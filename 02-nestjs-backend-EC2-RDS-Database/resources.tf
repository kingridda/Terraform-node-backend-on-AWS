############################## LOCALS ################################
locals {
  common_tags = {
    BillingCode = var.billing_code_tag
    Environment = var.environment_tag
  }

}


######################## DATA ###################################################################

data "aws_availability_zones" "available" {}


data "aws_ami" "aws-linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn-ami-hvm*"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}


########################### RESOURCES  ######################################


# NETWORKING #
resource "aws_vpc" "vpc" {
  cidr_block           = var.network_address_space
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.vpc.id

}

resource "aws_subnet" "subnet1" {
  cidr_block              = var.subnet1_address_space
  vpc_id                  = aws_vpc.vpc.id
  map_public_ip_on_launch = "true"
  availability_zone       = data.aws_availability_zones.available.names[0]

}
resource "aws_subnet" "subnet2" {
  cidr_block              = var.subnet2_address_space
  vpc_id                  = aws_vpc.vpc.id
  map_public_ip_on_launch = "true"
  availability_zone       = data.aws_availability_zones.available.names[1]

}
resource "aws_subnet" "subnet3" {
  cidr_block              = var.subnet3_address_space
  vpc_id                  = aws_vpc.vpc.id
  map_public_ip_on_launch = "true"
  availability_zone       = data.aws_availability_zones.available.names[0]

}


####  DB SUBNET GROUP  necessary for database to work
##### NB: than 1 AZ  is required (at least 2 subnets in 2 diff AZ)
resource "aws_db_subnet_group" "mysql-subnet-group" {
  name       = "mysql-subnet-group"
  subnet_ids = [aws_subnet.subnet2.id, aws_subnet.subnet3.id]
}


# ROUTING #
resource "aws_route_table" "rtb" {
  vpc_id = aws_vpc.vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

}

resource "aws_route_table_association" "rta-subnet1" {
  subnet_id      = aws_subnet.subnet1.id
  route_table_id = aws_route_table.rtb.id
}

resource "aws_route_table_association" "rta-subnet2" {
  subnet_id      = aws_subnet.subnet2.id
  route_table_id = aws_route_table.rtb.id
}

resource "aws_route_table_association" "rta-subnet3" {
  subnet_id      = aws_subnet.subnet3.id
  route_table_id = aws_route_table.rtb.id
}

# SECURITY GROUPS #
resource "aws_security_group" "elb-sg" {
  name   = "nginx_server_elb_sg"
  vpc_id = aws_vpc.vpc.id

  #Allow HTTP from anywhere
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  #allow all outbound
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

}

#server Security group
resource "aws_security_group" "allow_ssh" {
  name        = "server_sg_002"
  description = "Allow HTTP and SSH ports for myserver"
  vpc_id      = aws_vpc.vpc.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = [var.network_address_space] #allow ingress only from VPC
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = -1
    cidr_blocks = ["0.0.0.0/0"]
  }
}

#DB security group
resource "aws_security_group" "allow-mysql" {
  name        = "db_sg_OO2"
  description = "allow-mysql"
  vpc_id      = aws_vpc.vpc.id

  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.allow_ssh.id]  #we allow access only from our instance's firewall (sg)
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    #self        = true
  }
  
}



# LOAD BALANCER #
resource "aws_elb" "web" {
  name = "server-nginx-elb"

  subnets         = [aws_subnet.subnet1.id]
  security_groups = [aws_security_group.elb-sg.id]
  instances       = [aws_instance.myserver.id]

  listener {
    instance_port     = 3000
    instance_protocol = "http"
    lb_port           = 80
    lb_protocol       = "http"
  }


}


#server instances

resource "aws_instance" "myserver" {
  ami                    = data.aws_ami.aws-linux.id
  instance_type          = "t2.micro"
  subnet_id              = aws_subnet.subnet1.id
  key_name               = var.key_name
  vpc_security_group_ids = [aws_security_group.allow_ssh.id]

  # connection block used by the external provisionner to connect to the instance 
  # as ssh and execute the script you gave it

  connection {
    type        = "ssh"
    host        = self.public_ip
    user        = "ec2-user"
    private_key = file(var.private_key_path)

  }

  provisioner "file" {
    source      = "mynestapp.zip"
    destination = "/tmp/mynestapp.zip"
  }

  # NB: check the node version 
  # NB: u cant run node as sudo if node isnt in usr/bin/ to that we create link to it in that folder
  # NB: sudo is needed to run on port 80
  # NB: still locking how to move folder from tmp
  provisioner "remote-exec" {
    inline = [
      "sudo yum update -y",
      "curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.34.0/install.sh | bash",
      ". ~/.nvm/nvm.sh",
      "nvm install 14.18.0",
      "cd /tmp",
      "unzip mynestapp.zip -d mynestapp",
      "cd mynestapp",
      "npm install -y",
      "export PORT=3000",
      "export DB_MYSQL_HOST=${aws_db_instance.default.address}",
      "npm run build",
      "npm install pm2 -g",
      "pm2 start dist/main.js"
    ]

  }
  
}



resource "aws_db_instance" "default" {
  identifier           = var.db_identifier
  allocated_storage    = 10
  engine               = "mysql"
  engine_version       = "5.7"
  instance_class       = "db.t2.micro"
  storage_type         = "gp2"

  name                 = var.db_name
  username             = var.db_user
  password             = var.db_password
  port                 = 3306
  parameter_group_name = aws_db_parameter_group.default.name


  vpc_security_group_ids = [aws_security_group.allow-mysql.id]
  db_subnet_group_name   = aws_db_subnet_group.mysql-subnet-group.name

  skip_final_snapshot  = true # NB: true == no final snapshot well be taken for the DB before its end/delete/destruction
  multi_az             = false
  publicly_accessible  = false


  # use these provisioners later to configure the shit
  # provisioner "file" {
  #   #nested connection
  #   connection {
  #     type        = "ssh"
  #     host        =  "${aws_instance.server.public_ip}"
  #     user        = "${var.AWS_INSTANCE_USERNAME}"
  #     private_key = "${file("${var.PATH_TO_PRIVATE_KEY}")}"
  #   }
  #   source      = "script.sql"
  #   destination = "/tmp/script.sql"
  # }

  # # remote-exec provesioner
  # provisioner "remote-exec" {
  #   #nested connection
  #   connection {
  #     type        = "ssh"
  #     host        = "${aws_instance.server.public_ip}"
  #     user        = "${var.AWS_INSTANCE_USERNAME}"
  #     private_key = "${file("${var.PATH_TO_PRIVATE_KEY}")}"
  #   }
  #   inline = [
  #     "sudo apt update",
  #     "echo Y | sudo apt-get install mysql-client",
  #     "mysql -u root -h ${aws_db_instance.mysql.address} -p${var.DB_PASSWORD} mydb < /tmp/script.sql",
  #     "exit",
  #     "exit"
  #   ]
  # }

}


### Used to Manage the MySQL configuration chatset and stuff
resource "aws_db_parameter_group" "default" {
  name        = "mysql-57-param-group"
  description = " parameter group for mysql5.7"
  family      = "mysql5.7"
  parameter {
    name  = "character_set_server"
    value = "utf8"
  }
  parameter {
    name  = "character_set_client"
    value = "utf8"
  }
}





