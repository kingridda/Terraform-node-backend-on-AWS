# NestJS on AWS EC2 and ELB using Terraform

NestJS app on:

- 1 EC2 AWS with linux AMI

- Elastic Load Balancer

- Costumized VPC with 1 public subnets

## Create the infrastructure
```
terraform init
terraform validate
terraform plan -out myplan.tfplan
terraform apply "myplan.tfplan"
```

## Destroy 
```
terraform destroy
```
