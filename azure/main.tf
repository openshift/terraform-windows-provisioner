terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 3.0.0"
    }
  }
  required_version = ">= 1.0.0"
}

# Provider configuration
# Authentication via environment variables:
# ARM_CLIENT_ID
# ARM_CLIENT_SECRET
# ARM_SUBSCRIPTION_ID
# ARM_TENANT_ID
provider "azurerm" {
  features {}
}

# Data sources
data "azurerm_resource_group" "winc_rg" {
  name = var.winc_resource_group
}

data "azurerm_subnet" "winc_subnet" {
  name                 = "${var.winc_resource_prefix}-worker-subnet"
  virtual_network_name = "${var.winc_resource_prefix}-vnet"
  resource_group_name  = var.winc_resource_group
}

data "azurerm_virtual_machine" "winc-machine-node" {
  name                = var.winc_machine_hostname
  resource_group_name = var.winc_resource_group
}

# Network Interface
resource "azurerm_network_interface" "winc-byoh-interface" {
  count               = var.winc_number_workers
  name                = "${var.winc_resource_prefix}-interface-${count.index}"
  location            = data.azurerm_resource_group.winc_rg.location
  resource_group_name = var.winc_resource_group

  ip_configuration {
    name                          = "internal"
    subnet_id                     = data.azurerm_subnet.winc_subnet.id
    private_ip_address_allocation = "Dynamic"
  }

  tags = {
    Name        = "${var.winc_instance_name}-${count.index}-nic"
    Environment = var.environment_tag
    ManagedBy   = var.managed_by_tag
  }
}

# Windows Virtual Machine
resource "azurerm_windows_virtual_machine" "win_server" {
  count               = var.winc_number_workers
  depends_on          = [azurerm_network_interface.winc-byoh-interface]
  name                = "${var.winc_instance_name}-${count.index}"
  resource_group_name = var.winc_resource_group
  location            = data.azurerm_resource_group.winc_rg.location
  size                = var.winc_instance_type
  admin_username      = var.admin_username
  admin_password      = var.admin_password
  
  network_interface_ids = [
    azurerm_network_interface.winc-byoh-interface[count.index].id
  ]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = var.winc_worker_sku
    version   = var.windows_image_version
  }

  tags = {
    Name        = "${var.winc_instance_name}-${count.index}"
    Environment = var.environment_tag
    ManagedBy   = var.managed_by_tag
  }

  lifecycle {
    create_before_destroy = true
  }
}

# VM Extension for Configuration
resource "azurerm_virtual_machine_extension" "configure-byoh" {
  count                = var.winc_number_workers
  depends_on           = [azurerm_windows_virtual_machine.win_server]
  name                 = "configure-byoh"
  virtual_machine_id   = azurerm_windows_virtual_machine.win_server[count.index].id
  publisher            = "Microsoft.Compute"
  type                 = "CustomScriptExtension"
  type_handler_version = var.vm_extension_handler_version

  protected_settings = jsonencode({
    commandToExecute = "powershell -command \"[System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String('${base64encode(data.template_file.windows-userdata[count.index].rendered)}')) | Out-File -filepath install.ps1\" && powershell -ExecutionPolicy Unrestricted -File install.ps1"
  })

  tags = {
    Name = "${var.winc_instance_name}-${count.index}-extension"
  }
}

# Outputs
output "instance_ip" {
  description = "Private IP addresses of the Windows instances"
  value       = azurerm_windows_virtual_machine.win_server[*].private_ip_address
}

output "instance_ids" {
  description = "IDs of the Windows instances"
  value       = azurerm_windows_virtual_machine.win_server[*].id
}

output "instance_hostname" {
  description = "Computer names of the Windows instances"
  value       = azurerm_windows_virtual_machine.win_server[*].computer_name
}