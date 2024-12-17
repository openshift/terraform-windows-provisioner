# Resource group used
variable winc_resource_group {
    type = string
}

# Resource prefix. Prefix used in all resources
variable winc_resource_prefix {
    type = string
}

# Hostname for one of the already existing cluster worker VM nodes
# You can get this info with: oc get nodes -l node-role.kubernetes.io/worker --no-headers
variable winc_machine_hostname {
    type = string
}

# Instance name assigned to the byoh instance
variable winc_instance_name {
    type = string
}

# Number of BYOH worker instances
variable winc_number_workers {
    type = number
    default = 2
}

# Instance type for the byoh instance
variable winc_instance_type {
    type = string
    default = "Standard_D2s_v3"
}

# Windows SKU (e.g., 2019-datacenter-smalldisk, 2022-datacenter-smalldisk)
variable winc_worker_sku {
    type = string
}

# Windows administrator username
variable admin_username {
    type = string
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

# Azure VM extension handler version
variable vm_extension_handler_version {
    type    = string
    default = "1.9"
    description = "Azure VM extension type handler version"
}

# Windows image version (optional - defaults to 'latest')
variable windows_image_version {
    type    = string
    default = "latest"
    description = "Specific Windows image version or 'latest' for most recent"
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
