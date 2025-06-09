variable "region" {
  description = "value of the region where the resources will be created"
  type        = string
    default     = "us-east-1"
}

variable "common_tags" {
  description = "Common tags to apply to all resources."
  type        = map(string)
  default = {
    Project = "MULTIVENDOR-PROJECT"
    Name   = "LAB"
    Vendor = "ALL"
  }
}

variable "vpc_name" {
  description = "Name of the VPC"
  type        = string
  default     = "MULTIVENDOR-VPC"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "172.16.0.0/16"
}

variable "availability_zone" {
  description = "availability zones in the region"
  type        = string
  default     = "us-east-1a"
}

# Subnet Variables
variable "subnet_configs" {
  description = "A map of subnet configurations including name and CIDR."
  type = map(object({
    cidr_block             = string
    auto_assign_public_ip = bool
    vendor = string
  }))
  default = {
    "PUBLIC-SUBNET" = {
      cidr_block             = "172.16.5.0/24"
      auto_assign_public_ip = false # Overridden by elastic IP for target server
      vendor = "ALL"
    },
    "MANAGEMENT-SUBNET" = {
      cidr_block             = "172.16.10.0/24"
      auto_assign_public_ip = false
      vendor = "ALL"
    },
    "VENDOR1-SUBNET" = {
      cidr_block             = "172.16.101.0/24"
      auto_assign_public_ip = false
      vendor = "VENDOR1"
    },
    "VENDOR2-SUBNET" = {
      cidr_block             = "172.16.102.0/24"
      auto_assign_public_ip = false
      vendor = "VENDOR2"
    },
    "VENDOR3-SUBNET" = {
      cidr_block             = "172.16.103.0/24"
      auto_assign_public_ip = false # One subnet had this set to Yes
      vendor = "VENDOR3"
    }
  }
}
