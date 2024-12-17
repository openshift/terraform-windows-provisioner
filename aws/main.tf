terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.27"
    }
  }

  # It's a good practice to specify minimum Terraform version
  required_version = ">= 1.0.0"
}

# Configure the AWS Provider
provider "aws" {
  region = var.winc_region

  # Credentials are handled via environment variables:
  # AWS_ACCESS_KEY_ID
  # AWS_SECRET_ACCESS_KEY
}

# Data source for existing worker node information
data "aws_instance" "winc-machine-node" {
  filter {
    name    = "private-dns-name"
    values  = [var.winc_machine_hostname]
  }
  
  filter {
    name   = "tag:kubernetes.io/cluster/${var.winc_cluster_name}"
    values = ["owned"]
  }
}

# Windows Server instances
resource "aws_instance" "win_server" {
  count                = var.winc_number_workers
  ami                  = var.winc_worker_ami
  instance_type        = var.winc_instance_type
  ebs_optimized        = false
  
  # Network configuration
  subnet_id            = data.aws_instance.winc-machine-node.subnet_id
  security_groups      = data.aws_instance.winc-machine-node.vpc_security_group_ids
  
  # IAM configuration
  iam_instance_profile = data.aws_instance.winc-machine-node.iam_instance_profile
  
  # Instance initialization
  user_data           = data.template_file.windows-userdata[count.index].rendered

  # Storage configuration
  root_block_device {
    volume_size = var.root_volume_size
    volume_type = var.root_volume_type

    tags = {
      Name = "${var.winc_instance_name}-${count.index}-root"
    }
  }

  # Instance tags
  tags = {
    Name = "${var.winc_instance_name}-${count.index}"
    "kubernetes.io/cluster/${var.winc_cluster_name}" = "owned"
    Environment = var.environment_tag
    ManagedBy   = var.managed_by_tag
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Outputs
output "instance_ip" {
  description = "Private IP addresses of the Windows instances"
  value       = aws_instance.win_server[*].private_ip
}

output "instance_ids" {
  description = "IDs of the Windows instances"
  value       = aws_instance.win_server[*].id
}

output "instance_hostname" {
  description = "Private DNS hostnames of the Windows instances"
  value       = aws_instance.win_server[*].private_dns
}