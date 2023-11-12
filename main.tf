provider "aws" {
  region = "us-east-1"
}

#First we setup the ECS Cluster

resource "aws_ecs_cluster" "my_cluster" {
  name = "my-cluster"
}

# CREATE THE EXCECUTION ROLE ecs_instance_role
resource "aws_iam_role" "ecs_instance_role" {
  name = "ecs_instance_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = ["ec2.amazonaws.com", "ecs-tasks.amazonaws.com"]
        },
      },
    ],
  })
}

resource "aws_iam_instance_profile" "ecs_instance_profile" {
  name = "ecs_instance_profile"
  role = aws_iam_role.ecs_instance_role.name
}
#add permissions for EC2 Containers on ECS
resource "aws_iam_role_policy_attachment" "ecs_policy_attachment" {
  role       = aws_iam_role.ecs_instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}


# ECS needs autoscalling permissions to scale our EC2 instances
# otherwise the alarm trigger but dont scale
resource "aws_iam_policy" "ecs_autoscaling_policy" {
  name        = "ecs_autoscaling_policy"
  path        = "/"
  description = "A policy that allows ECS service to manage Auto Scaling of EC2 instances."

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = [
          "autoscaling:DescribeAutoScalingGroups",
          "autoscaling:DescribeAutoScalingInstances",
          "autoscaling:DescribeLaunchConfigurations",
          "autoscaling:DescribeScalingActivities",
          "autoscaling:DescribeScheduledActions",
          "autoscaling:SetDesiredCapacity",
          "autoscaling:TerminateInstanceInAutoScalingGroup",
          "autoscaling:UpdateAutoScalingGroup"
        ],
        Effect   = "Allow",
        Resource = "*"
      },
    ]
  })
}
# attach the role and policy
resource "aws_iam_role_policy_attachment" "ecs_autoscaling_policy_attachment" {
  role       = aws_iam_role.ecs_instance_role.name
  policy_arn = aws_iam_policy.ecs_autoscaling_policy.arn
}

# creation of a log group for ecs
resource "aws_cloudwatch_log_group" "ecs_log_group" {
  name              = "ecs-log-group"
  retention_in_days = 30
}

# define the task to run on EC2, with the execution w/ cpu and memory
resource "aws_ecs_task_definition" "hello_world" {
  family                   = "hello_world"
  network_mode             = "awsvpc"
  requires_compatibilities = ["EC2"]
  execution_role_arn       = aws_iam_role.ecs_instance_role.arn
  cpu                      = "256"
  memory                   = "256"

  # here I create a Flask application which on path / make a calculus and then return a string
  #and it has a /health path
  container_definitions = jsonencode([{
    name      = "hello_world",
    image     = "gnm3000/python-intensive:v7", # my image push to duckerhub public
    cpu       = 256,
    memory    = 256,
    essential = true,
    portMappings = [{
      containerPort = 8000, # this is the port that my docker python application is using,
      hostPort      = 8000     # this is because we want to run many containers on the same host
    }],

    logConfiguration = {
      logDriver = "awslogs",
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.ecs_log_group.name,
        "awslogs-region"        = "us-east-1",
        "awslogs-stream-prefix" = "ecs"
      }
    },
    "healthCheck" : {
      "command" : ["CMD-SHELL", "curl -f http://localhost:8000/health || exit 1"],
      "interval" : 10,
      "retries" : 5,
      "timeout" : 5
    }
  }])
}

# in the security group for the ecs task we allow port 8000.
resource "aws_security_group" "ecs_tasks_sg" {
  name        = "ecs-tasks-sg"
  description = "Allow inbound traffic to ECS tasks"
  vpc_id      = "vpc-07bda9d98a3314bc1"

  ingress {
    from_port   = 8000
    to_port     = 8000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

#the security group for the Aplication load balancer allow port 80.
resource "aws_security_group" "alb_sg2" {
  name        = "alb-sg2"
  description = "Security group for ALB"
  vpc_id      = "vpc-07bda9d98a3314bc1"

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}


# define an application load balancer for our ECS.
#Im using my default VPC and default public subnets.
resource "aws_lb" "ecs_alb" {
  name               = "ecs-alb"
  internal           = false
  load_balancer_type = "application"
  subnets            = ["subnet-058e23ab7532d95ae", "subnet-0c967e1d6fb86bd76"]
  security_groups    = [aws_security_group.alb_sg2.id]
}

# the listener is 80 because I want to receive HTTP requests.
# and forward to my target group.
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.ecs_alb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.ecs_tg.arn
  }
}

# a target group running on port 8000. 
# So incomming HTTP 80 requests are forwarded to my target group on port 8000
# and this is another healthcheck
resource "aws_lb_target_group" "ecs_tg" {
  name     = "ecs-tg"
  port     = 8000
  protocol = "HTTP"
  vpc_id   = "vpc-07bda9d98a3314bc1"
  target_type = "ip" 

  health_check {
    healthy_threshold   = 2
    unhealthy_threshold = 5
    timeout             = 10
    interval            = 15
    path                = "/health"
    matcher             = "200"
  }
}

# on my ECS service something I learn is when we use the Capacity provider which
# I added then I could deploy a simple ECS, dont need the launch type, because
# this is already define on the autoscaling group
#that why is commented and no needed
#define the load balancer too, 

#the capaacity provider strategy is what looks like the infrastructure underline
# we are goiing to use to deploy our container
#this on fargate is invisible

#so on this case, the weight is 1, because I dont have any other capacity provider,
#but I could use two for example, one using EC2 ondemand and other one
# using EC2 Spot. and for example, on is cheaper and other.
# base is how many container at min send to this provider.

resource "aws_ecs_service" "hello_world_service" {
  name            = "hello-world-service"
  cluster         = aws_ecs_cluster.my_cluster.id
  task_definition = aws_ecs_task_definition.hello_world.arn
  #launch_type     = "EC2"
  desired_count        = 1
  force_new_deployment = true
  network_configuration {
    subnets = ["subnet-058e23ab7532d95ae", "subnet-0c967e1d6fb86bd76"]
    security_groups = [aws_security_group.ecs_tasks_sg.id]
    #assign_public_ip = true # Set to false if you do not want to assign public IPs to your tasks
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.ecs_tg.arn
    container_name   = "hello_world"
    container_port   = 8000
  }
  capacity_provider_strategy {
    capacity_provider = aws_ecs_capacity_provider.ecs_capacity_provider.name
    weight            = 1
    base              = 1
  }

  depends_on = [
    aws_iam_role_policy_attachment.ecs_policy_attachment,
    aws_iam_instance_profile.ecs_instance_profile,
    aws_ecs_cluster_capacity_providers.my_cluster_capacity_providers,
  ]
}

#here I define the autoscaling for my ECS Service hello world. 
# I want to scale the DesiredCount for my service. At max only 2.

resource "aws_appautoscaling_target" "ecs_autoscale_target" {
  max_capacity       = 1
  min_capacity       = 1
  resource_id        = "service/my-cluster/hello-world-service"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
  depends_on = [aws_ecs_service.hello_world_service,
    aws_ecs_capacity_provider.ecs_capacity_provider
  ]
}
# I want to track the cpu utilization.
# So at average I want to mantain at only 2% the target, and scalein/out 60 seconds
# in this way I wanted see if the scalling was working properly.
resource "aws_appautoscaling_policy" "ecs_autoscale_policy" {
  name               = "ecs_cpu_utilization"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs_autoscale_target.resource_id
  scalable_dimension = aws_appautoscaling_target.ecs_autoscale_target.scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs_autoscale_target.service_namespace

  target_tracking_scaling_policy_configuration {
    target_value       = 70
    scale_in_cooldown  = 60
    scale_out_cooldown = 60

    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
  }
  depends_on = [aws_appautoscaling_target.ecs_autoscale_target]
}

#I had problems to know which ami_id to use, so I found this way to query dynamically
# the ami_id optimized for ECS in this case.
data "aws_ssm_parameter" "ecs_ami_id" {
  name = "/aws/service/ecs/optimized-ami/amazon-linux-2/recommended/image_id"
}


# define a new security group, with ALL ALL for ingress and egress.
#this is for our ec2 instances
resource "aws_security_group" "ecs_instance_sg2" {
  name        = "ecs-instance-sg2"
  description = "Security group for ECS instances"
  vpc_id      = "vpc-07bda9d98a3314bc1"

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

#this launch configuration I was reading is about define what are the specification for the
# ec2 instance we are going to launch
#this setup we use then on the autoscalling group to scale in/out.
# The iam_instance_profile has attached the ECS execution role.

resource "aws_launch_configuration" "ecs_launch_configuration2" {
  name_prefix          = "ecs-instance-"
  image_id             = data.aws_ssm_parameter.ecs_ami_id.value
  instance_type        = "t2.medium"
  iam_instance_profile = aws_iam_instance_profile.ecs_instance_profile.name
  security_groups      = [aws_security_group.ecs_instance_sg2.id]

  lifecycle {
    create_before_destroy = true
  }

  user_data = <<-EOF
                #!/bin/bash
                echo "ECS_CLUSTER=${aws_ecs_cluster.my_cluster.name}" >> /etc/ecs/ecs.config
                # prevent access to metadata
                echo "ECS_AWSVPC_BLOCK_IMDS=true" >> /etc/ecs/ecs.config
              EOF
}

# here define the autoscaling group for our ECS service.
# I want to launch max 3 taks.
#protect_from_scale_in allow to ECS scale in. => seted to true
#"To enable managed termination protection for a capacity provider, the Auto Scaling group must have instance protection from scale in enabled."

resource "aws_autoscaling_group" "ecs_autoscaling_group" {
  launch_configuration      = aws_launch_configuration.ecs_launch_configuration2.name
  min_size                  = 1
  max_size                  = 1
  desired_capacity          = 1
  health_check_grace_period = 30
  health_check_type         = "EC2"
  force_delete              = true
  #target_group_arns         = [aws_lb_target_group.ecs_tg.arn]
  vpc_zone_identifier       = ["subnet-058e23ab7532d95ae", "subnet-0c967e1d6fb86bd76"]
  protect_from_scale_in     = false
  tag {
    key                 = "Name"
    value               = "ECS Instance"
    propagate_at_launch = true
  }
}

# now we define finally the capacity provider for out autoscalling group.
# so at max I want until 3 EC2 running my containers.
resource "aws_ecs_capacity_provider" "ecs_capacity_provider" {
  name = "my-capacity-provider"

  auto_scaling_group_provider {
    auto_scaling_group_arn         = aws_autoscaling_group.ecs_autoscaling_group.arn
    managed_termination_protection = "DISABLED"

    managed_scaling {
      maximum_scaling_step_size = 3
      minimum_scaling_step_size = 1
      status                    = "ENABLED"
      target_capacity           = 100
    }
  }
}


# Then the capacity provider is attach to the cluster.
resource "aws_ecs_cluster_capacity_providers" "my_cluster_capacity_providers" {
  cluster_name       = aws_ecs_cluster.my_cluster.name
  capacity_providers = [aws_ecs_capacity_provider.ecs_capacity_provider.name]

  default_capacity_provider_strategy {
    capacity_provider = aws_ecs_capacity_provider.ecs_capacity_provider.name
    weight            = 1
    base              = 1
  }
}


# finally I want to know what is the URL for my public ALB.
output "alb_dns_name" {
  description = "The DNS name for the ALB"
  value       = aws_lb.ecs_alb.dns_name
}
