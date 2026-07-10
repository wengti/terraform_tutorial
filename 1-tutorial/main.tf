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

resource "aws_instance" "instance_1" {
    ami = "ami-0b6d9d3d33ba97d99"
    instance_type = "t3.micro"
}

resource "aws_vpc" "vpc_1" {
    cidr_block = "10.0.0.0/16"
    tags = {
        Name = "production"
    }
}

resource "aws_subnet" "subnet_1" {
    vpc_id = aws_vpc.vpc_1.id
    cidr_block = "10.0.1.0/24"
    tags = {
        Name = "production-subnet"
    }
}