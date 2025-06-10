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
    key            = "MULTIVENDOR-PROJECT/terraform.tfstate"
    region         = "us-east-1"
    use_lockfile = true
    }
}

provider "aws" {
  region = var.region
  #profile = "UDPERSONAL"
}

#crating VPC

resource "aws_vpc" "my_vpc" {
  cidr_block = var.vpc_cidr
  enable_dns_support = true
  enable_dns_hostnames = true
  tags = merge(var.common_tags, {
    Name = var.vpc_name 
  })
    
  } 


resource "aws_subnet" "all_subnets" {
  for_each          = var.subnet_configs
  vpc_id            = aws_vpc.my_vpc.id
  cidr_block        = each.value.cidr_block
  availability_zone = var.availability_zone
  map_public_ip_on_launch = each.value.auto_assign_public_ip
  tags = merge(var.common_tags, {
    Name = each.key # The subnet's specific name
    Vendor = each.value.vendor #gets the vendor name from the name defined in the variable object vendor
    
  })
}

#Creating elastic network interface from variable
resource "aws_network_interface" "multi_interfaces" {
  for_each           = var.network_interface_configs
  subnet_id          = aws_subnet.network_subnets[each.value.subnet_key].id
  private_ip         = cidrhost(aws_subnet.network_subnets[each.value.subnet_key].cidr_block, each.value.private_ip_suffix)
  security_groups    = [aws_security_group.instance_sg.id]
  source_dest_check  = false # Often disabled for multi-homed instances like firewalls

  tags = {
    Name = each.key
  }
}
#Creating security group
resource "aws_security_group" "instance_sg" {
  name        = "MULTIVENDOR-INSTANCE-SG"
  description = "Security group for instances in the MULTIVENDOR project"
  vpc_id      = aws_vpc.my_vpc.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0/0"] # Allow SSH from anywhere,
  }

  ingress {
    from_port   = 3389
    to_port     = 3389
    protocol    = "tcp"
    cidr_blocks = ["0.0.0/0"] # Allow RDP from anywhere,
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1" # Allow all outbound traffic
    cidr_blocks = ["0.0.0/0"]
  } 

  tags = merge(var.common_tags, {
    Name = "MULTIVENDOR-INSTANCE-SG"
  })
}

