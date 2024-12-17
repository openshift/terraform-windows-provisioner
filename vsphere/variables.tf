# Instance name for the newly created Windows VM
variable winc_instance_name {
    type = string
}

# Hostname for one of the already existing cluster worker VM nodes
variable winc_machine_hostname {
    type = string
}

# vSphere template name
variable winc_vsphere_template {
    type = string
}

# vSphere datacenter
variable winc_datacenter {
    type = string
}

# vSphere datastore
variable winc_datastore {
    type = string
}

# vSphere network
variable winc_network {
    type = string
}

# vSphere resource pool
variable winc_resource_pool {
    type = string
}

# Number of BYOH worker instances
variable winc_number_workers {
    type = number
    default = 2
}

# vSphere authentication variables
variable vsphere_user {
    type        = string
    description = "vSphere username"
}

variable vsphere_password {
    type        = string
    description = "vSphere password"
    sensitive   = true
}

variable vsphere_server {
    type        = string
    description = "vSphere server hostname"
}

# Windows administrator username
variable admin_username {
    type        = string
    default     = "Administrator"
    description = "Administrator username for Windows instances"
}

# Windows administrator password
variable admin_password {
    type        = string
    sensitive   = true
    description = "Administrator password for Windows instances"
}

# SSH public key for remote access
variable ssh_public_key {
    type        = string
    description = "SSH public key for remote access to Windows instances"
}
