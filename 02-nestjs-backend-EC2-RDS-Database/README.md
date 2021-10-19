# NestJS on AWS EC2, RDS Database and ELB using Terraform

Infrastructure:

- Elastic Load Balancer

- EC2 AWS linux AMI

- Costumized VPC with 1 public subnets (for EC2) and 2 private subnets (for RDS)

- 1 EC2 instances 

- RDS MySQL Database 

PS: We export PORT and DB_MYSQL_HOST as environment variables If you want to change them export them :p

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

## Useful commands:

```
# ssh to the instance and check database connection using:

mysql --host=hosturl --user=root --password=rootrootroot db_test_00001
```
