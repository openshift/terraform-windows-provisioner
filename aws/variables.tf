# Instance name for the newly created Windows VM
variable winc_instance_name {
    type = string
}

# VM's image ami to used for the byoh instance
variable winc_worker_ami {
    type = string
}

# Hostname for one of the already existing cluster VM nodes
# You can get this info with: oc get nodes -l node-role.kubernetes.io/worker --no-headers
variable winc_machine_hostname {
    type = string
}

# New instance type
variable winc_instance_type {
    type = string
    default = "m5a.large"
}

# AWS Region
variable winc_region {
    type = string
}

# Number of BYOH worker instances
variable winc_number_workers {
    type = number
    default = 2
}

# Cluster name used to tag the AWS BYOH instance
variable winc_cluster_name {
    type = string
}

# Windows administrator username
variable admin_username {
    type        = string
    default     = "Administrator"
    description = "Administrator username for Windows instances"
}

# Windows administrator password
variable admin_password {
    type      = string
    sensitive = true
    description = "Administrator password for Windows instances"
}

# SSH public key for remote access
variable ssh_public_key {
    type = string
    description = "SSH public key for remote access to Windows instances"
}

# Root volume size (GB)
variable root_volume_size {
    type    = number
    default = 120
    description = "Root volume size in GB"
}

# Root volume type
variable root_volume_type {
    type    = string
    default = "gp2"
    description = "Root volume type (gp2, gp3, io1, etc.)"
}

# Environment tag
variable environment_tag {
    type    = string
    default = "production"
    description = "Environment tag for resources"
}

# Managed by tag
variable managed_by_tag {
    type    = string
    default = "terraform"
    description = "Managed by tag for resources"
}

# Container logs port
variable container_logs_port {
    type    = number
    default = 10250
    description = "Container logs port for firewall rule"
}
