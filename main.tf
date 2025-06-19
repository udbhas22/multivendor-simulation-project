terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
      #profile = "SECUREIQ" # Specify the AWS profile to use}
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
    values = ["ami-0d1b5a8c13042c939"] 
  }
}
# Instance creation for Ubuntu VMs with multiple ENIs
resource "aws_instance" "ubuntu_victim_instances" {
  for_each      = var.instance_configs # Iterate over instance configurations
  ami           = data.aws_ami.ubuntu_noble.id
  instance_type = each.value.instance_type
  key_name      = var.sshkey_name

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

# Creating eip for management instance
resource "aws_eip" "management_eip" {
  domain = "vpc"
  tags = merge(var.common_tags, {
    Name = "MANAGEMENT-UBUNTU-EIP"
  })
}

# eip association for management instance
resource "aws_eip_association" "management_eip_association" {
  #instance_id   = aws_instance.ubuntu_victim_instances["MANAGEMENT-UBUNTU-PRIMARY"].id
  network_interface_id = aws_network_interface.multi_interfaces["MANAGEMENT-UBUNTU-PRIMARY-ENI"].id
  allocation_id = aws_eip.management_eip.id
  allow_reassociation = true

}

# Cration of internet gateway
resource "aws_internet_gateway" "my_igw" {
  vpc_id = aws_vpc.my_vpc.id

  tags = merge(var.common_tags, {
    Name = "MULTIVENDOR-IGW"
  })
}

# --- Route Table and Association for Management Subnet ---

# Create a custom route table for the management subnet
resource "aws_route_table" "management_route_table" {
  vpc_id = aws_vpc.my_vpc.id

  tags = merge(var.common_tags, {
    Name = "MANAGEMENT-ROUTE-TABLE"
  })
}

# Add a default route (0.0.0.0/0) to the Internet Gateway in the management route table
resource "aws_route" "management_internet_route" {
  route_table_id         = aws_route_table.management_route_table.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.my_igw.id
}

# Associate the MANAGEMENT-SUBNET with the new management route table
resource "aws_route_table_association" "management_subnet_association" {
  subnet_id      = aws_subnet.all_subnets["MANAGEMENT-SUBNET"].id
  route_table_id = aws_route_table.management_route_table.id
}
# Key Pair for SSH access
resource "tls_private_key" "ssh_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
  
}
resource "aws_key_pair" "mykey" {
  key_name   = var.sshkey_name
  public_key = tls_private_key.ssh_key.public_key_openssh
  tags = merge(var.common_tags, {
    Name = var.sshkey_name
    Vendor = "ALL"
  })
}
#Output for the SSH Key Pair 
# output "private_key_pem" {
#   value     = tls_private_key.ssh_key.private_key_pem
#   sensitive = true
# }

# output "save_private_key_to_file" {
#   value = "Run this command to save the key: \nterraform output -raw private_key_pem > mykey.pem && chmod 400 mykey.pem"
# }

resource "local_file" "ssh_key_file" { 
  content  = tls_private_key.ssh_key.private_key_pem
  filename = "${path.module}/mykey.pem"
  file_permission = "0400" # Set file permissions to read-only for the owner
}

