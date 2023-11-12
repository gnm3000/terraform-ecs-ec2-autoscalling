
# terraform project with ECS and EC2 autoscaling

Look this PR related with the version using awsvpc network mode [PR Open awsvpc support](https://github.com/gnm3000/terraform-ecs-ec2-autoscalling/pull/1)


Alternative to terraform is possible to use AWS CDK Python 

```
terraform init
```

![image](https://github.com/gnm3000/terraform-ecs-ec2-autoscalling/assets/1533217/0eee4bb2-12c1-445f-8bcd-7572ab77131d)


```
terraform plan
```

![image](https://github.com/gnm3000/terraform-ecs-ec2-autoscalling/assets/1533217/299e82d5-708a-4e2b-87c9-1504ec8331bc)


```
terraform apply
```
In total we apply the 21 resource, I apply twice.
![image](https://github.com/gnm3000/terraform-ecs-ec2-autoscalling/assets/1533217/feac88ff-fd1f-46c3-8512-1426ed89bb31)


Then we go to the ALB url

![image](https://github.com/gnm3000/terraform-ecs-ec2-autoscalling/assets/1533217/6e397aab-102e-4a23-9fcf-915b066cfc32)

My Cluster =>
![image](https://github.com/gnm3000/terraform-ecs-ec2-autoscalling/assets/1533217/b05ffe7a-a959-4f79-a5bb-a132b7a49985)

My tasks =>

![image](https://github.com/gnm3000/terraform-ecs-ec2-autoscalling/assets/1533217/66992c2b-9ff4-40b0-8f53-f972a3ee77d9)



The autoscalling set DesiredCount to 2 because the threshold is so low, but this means its working

![image](https://github.com/gnm3000/terraform-ecs-ec2-autoscalling/assets/1533217/ef73c900-3b62-42cc-9c78-d794fe48c900)

The capacity provider and containers instances

![image](https://github.com/gnm3000/terraform-ecs-ec2-autoscalling/assets/1533217/b0447994-ac67-4b36-b733-05e017d8a3f0)



```
terraform destroy
```

![image](https://github.com/gnm3000/terraform-ecs-ec2-autoscalling/assets/1533217/49824722-4843-4235-8fa9-f9da0c0bf656)

![image](https://github.com/gnm3000/terraform-ecs-ec2-autoscalling/assets/1533217/3d8b2596-4dcf-450e-8e0b-794ad27463e7)


