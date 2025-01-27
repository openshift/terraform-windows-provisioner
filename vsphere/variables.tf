# Instance name for the newly created Windows VM
variable winc_instance_name {
    type = string
}

variable winc_vsphere_template {
    type = string
    default = ""
}

variable "winc_network" {
  type    = string
  default = ""
}

variable "winc_resource_pool" {
  type    = string
  default = ""
}

# Number of BYOH worker instances
variable winc_number_workers {
  description = "Number of Windows BYOH workers to create"
  type		= number
  default	= 2
}

variable "vsphere_user" {
  description = "vSphere username"
  type        = string
}

variable "vsphere_password" {
  description = "vSphere password"
  type        = string
}

variable "vsphere_server" {
  description = "vSphere server address"
  type        = string
}

