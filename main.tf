terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

    # This block configures the backend for storing the Terraform state.
    # Uncomment and configure the backend block below if you want to use S3 for state management.
    backend "s3" {
    bucket         = "udbhas-terraform-state-20250607"
    key            = "${var.project_name}/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "UDBHAS-TERRAFORM-STATE-LOCK"
    }
}

provider "aws" {
  region = var.region
  profile = "UDPERSONAL"
}

#crating VPC

resource "aws_vpc" "my_vpc" {
  cidr_block = var.vpc_cidr
  enable_dns_support = true
  enable_dns_hostnames = true
  tags = merge(var.common_tags, {
    Name = var.vpc_name # The subnet's specific name
    # You could add other subnet-specific tags here if needed
  })
    
  } 


resource "aws_subnet" "all_subnets" {
  for_each          = var.subnet_configs
  vpc_id            = aws_vpc.main.id
  cidr_block        = each.value.cidr_block
  availability_zone = var.availability_zone
  map_public_ip_on_launch = each.value.auto_assign_public_ip
  tags = merge(var.common_tags, {
    Name = each.key # The subnet's specific name
    # You could add other subnet-specific tags here if needed
  })
}