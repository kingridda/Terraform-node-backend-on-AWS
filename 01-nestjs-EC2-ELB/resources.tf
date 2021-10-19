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
    cidr_blocks = [var.network_address_space]
    #allow ingress only from VPC
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = -1
    cidr_blocks = ["0.0.0.0/0"]
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
      "export PORT=80",
      "npm run build",
      "npm install pm2 -g",
      "pm2 start dist/main.js"
    ]

  }
  
}




