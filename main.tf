terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
      profile = "SECUREIQ" # Specify the AWS profile to use}
    }
  }

  # This block configures the backend for storing the Terraform state.
  # Uncomment and configure the backend block below if you want to use S3 for state management.
  backend "s3" {
    bucket       = "multivendor-project-terraform-state-20250607"
    key          = "MULTIVENDOR-PROJECT/terraform.tfstate"
    region       = "ap-south-1" # Specify the AWS region where the S3 bucket is located
    use_lockfile = true
  }
}

provider "aws" {
  region = var.region
  #profile = "UDPERSONAL"
}

#crating VPC

resource "aws_vpc" "my_vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = merge(var.common_tags, {
    Name = var.vpc_name
  })

}


resource "aws_subnet" "all_subnets" {
  for_each                = var.subnet_configs
  vpc_id                  = aws_vpc.my_vpc.id
  cidr_block              = each.value.cidr_block
  availability_zone       = var.availability_zone
  map_public_ip_on_launch = each.value.auto_assign_public_ip
  tags = merge(var.common_tags, {
    Name   = each.key          # The subnet's specific name
    Vendor = each.value.vendor #gets the vendor name from the name defined in the variable object vendor

  })
}

#Creating elastic network interface from variable
resource "aws_network_interface" "multi_interfaces" {
  for_each          = var.network_interface_configs
  subnet_id         = aws_subnet.all_subnets[each.value.subnet_key].id
  private_ip        = cidrhost(aws_subnet.all_subnets[each.value.subnet_key].cidr_block, each.value.private_ip_suffix)
  security_groups   = [aws_security_group.instance_sg.id]
  source_dest_check = false # Often disabled for multi-homed instances like firewalls

  tags = merge(var.common_tags, {
    Name   = each.key          # The subnet's specific name
    Vendor = each.value.vendor #gets the vendor name from the name defined in the variable object vendor

  })
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
    cidr_blocks = ["0.0.0.0/0"] # Allow SSH from anywhere,
  }

  ingress {
    from_port   = 3389
    to_port     = 3389
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # Allow RDP from anywhere,
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1" # Allow all outbound traffic
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.common_tags, {
    Name = "MULTIVENDOR-INSTANCE-SG"
  })
}

# Creating an EC2 instance using the latest Ubuntu Jammy image
data "aws_ami" "victim_ubuntu" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }
}



# Creating an EC2 instance using the latest Ubuntu Noble (24.04 LTS) image
data "aws_ami" "ubuntu_noble" {
  owners      = ["099720109477"]
  most_recent = false            
  filter {
    name   = "image-id"
    values = ["ami-020cba7c55df1f615"] 
  }
}
# Instance creation for Ubuntu VMs with multiple ENIs
resource "aws_instance" "ubuntu_victim_instances" {
  for_each      = var.instance_configs # Iterate over instance configurations
  ami           = data.aws_ami.ubuntu_noble.id
  instance_type = each.value.instance_type
  key_name      = var.key_pair_name

  # Attach network interfaces dynamically based on instance config
  dynamic "network_interface" {
    for_each = each.value.network_interfaces_keys # Iterate through ENI keys for this instance
    content {
      network_interface_id = aws_network_interface.multi_interfaces[network_interface.value].id
      # Use the 'is_primary' flag from the network_interface_configs variable
      # Device index 0 is always the primary, others follow.
      # If `is_primary` is true, it's device_index 0, otherwise it's 1, 2, ...
      #device_index = var.network_interface_configs[network_interface.value].is_primary ? 0 : index(each.value.network_interfaces_keys, network_interface.value) + 1
      device_index = var.network_interface_configs[network_interface.value].is_primary ? 0 : 1
    }
  }
  tags = merge(var.common_tags, {
    Name   = each.key          # The instance's specific name
    Vendor = each.value.vendor # gets the vendor name from the instance config
  })
}