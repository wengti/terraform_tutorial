# 0. Initial setup
terraform {
    required_providers {
      aws = {
        source = "hashicorp/aws"
        version = "~> 6.0"
      }
    }
}

provider "aws" {
    region = "us-east-1"
}

# 1. Create vpc
resource "aws_vpc" "prod_vpc" {
    cidr_block = "10.0.0.0/16"
    tags = {
        Name = "production_vpc"
    }
}

# 2. Create Internet Gateway
resource "aws_internet_gateway" "gw" {
    vpc_id = aws_vpc.prod_vpc.id
    tags = {
        Name = "production_gw"
    }
}

# 3. Create Route Table
resource "aws_route_table" "rt" {
  vpc_id = aws_vpc.prod_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }

  route {
    ipv6_cidr_block        = "::/0"
    gateway_id = aws_internet_gateway.gw.id
  }

  tags = {
    Name = "production_rt"
  }
}

# 4. Create VPC subnet
variable "subnet_prefix" {
    description = "A list of variables used to setup the multiple subnet"
    # default
    # type
} # terraform will first look for terraform.tfvars to fill in the value.
# Else, it will prompt the user to enter a value on `terraform apply`
# Else, it will use the default value listed
# You can use terraform apply -var-file example.tfvars so you can save variables in a different file name


resource "aws_subnet" "prod_subnet_1" {
  vpc_id     = aws_vpc.prod_vpc.id
  cidr_block = var.subnet_prefix[0].cidr_block
  availability_zone = "us-east-1a"

  tags = {
    Name = var.subnet_prefix[0].name
  }
}

resource "aws_subnet" "dev_subnet_1" {
    vpc_id = aws_vpc.prod_vpc.id
    cidr_block = var.subnet_prefix[1].cidr_block
    availability_zone = "us-east-1a"

    tags = {
        Name = var.subnet_prefix[1].name
    }
}

# 5. Associate subnet with route table
resource "aws_route_table_association" "rta_subnet_1" {
  subnet_id      = aws_subnet.prod_subnet_1.id
  route_table_id = aws_route_table.rt.id
}

# 6. Create security group to control inbound and outbound traffic
resource "aws_security_group" "allow_web" {
  name        = "allow_web"
  description = "Allow web inbound traffic and all outbound traffic"
  vpc_id      = aws_vpc.prod_vpc.id

  tags = {
    Name = "allow_web"
  }
}

resource "aws_vpc_security_group_ingress_rule" "allow_web_ipv4" {
  security_group_id = aws_security_group.allow_web.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "allow_web_ipv6" {
  security_group_id = aws_security_group.allow_web.id
  cidr_ipv6         = "::/0"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "allow_http_ipv4" {
  security_group_id = aws_security_group.allow_web.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "allow_http_ipv6" {
  security_group_id = aws_security_group.allow_web.id
  cidr_ipv6         = "::/0"
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "allow_ssh_ipv4" {
  security_group_id = aws_security_group.allow_web.id
  cidr_ipv4         = "211.24.221.117/32" # Only this IP address can access SSH
  from_port         = 22
  to_port           = 22
  ip_protocol       = "tcp"
}


resource "aws_vpc_security_group_egress_rule" "allow_all_traffic_ipv4" {
  security_group_id = aws_security_group.allow_web.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1" # semantically equivalent to all ports
}

resource "aws_vpc_security_group_egress_rule" "allow_all_traffic_ipv6" {
  security_group_id = aws_security_group.allow_web.id
  cidr_ipv6         = "::/0"
  ip_protocol       = "-1" # semantically equivalent to all ports
}

#7. Create a network interface for the subnet
resource "aws_network_interface" "web_server_nic" {
  subnet_id       = aws_subnet.prod_subnet_1.id
  private_ips     = ["10.0.1.50"]
  security_groups = [aws_security_group.allow_web.id]
}

# 8. Elastic IP Resource
resource "aws_eip" "one" {
  domain                    = "vpc"
  network_interface         = aws_network_interface.web_server_nic.id
  associate_with_private_ip = "10.0.1.50"
  depends_on = [ aws_internet_gateway.gw ]
}

output "server_public_ip" {
    value = aws_eip.one.public_ip
} # This value will be displayed when run terraform output

# 9. Create an ec2 instance
resource "aws_instance" "prod_instance" {
    ami = "ami-0b6d9d3d33ba97d99"
    instance_type = "t3.micro"
    key_name = "terraform_access_key"

    primary_network_interface {
      network_interface_id = aws_network_interface.web_server_nic.id
    }

    user_data = <<-EOF
                #!/bin/bash
                sudo apt update -y
                sudo apt install apache2 -y
                sudo systemctl start apache2
                sudo bash -c 'echo your very first web server > /var/www/html/index.html'
                EOF

    depends_on = [ aws_eip.one ]

    tags = {
        Name = "web_server"
    }
}