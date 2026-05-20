# WINC-1633: PTR record management for BYOH Windows nodes on vSphere.
# MAO creates PTR records for MachineSet VMs automatically, but BYOH nodes
# need them provisioned explicitly. Without PTR records, WMCO fails with
# "no such host" errors during reverse DNS lookups.
#
# Uses RFC 2136 dynamic DNS updates (BIND, Windows DNS Server, etc.).

provider "dns" {
  dynamic "update" {
    for_each = var.enable_ptr_records ? [1] : []
    content {
      server        = var.dns_server
      key_name      = var.dns_key_name
      key_algorithm = var.dns_key_algorithm
      key_secret    = var.dns_key_secret
    }
  }
}

resource "dns_ptr_record" "windows_ptr" {
  count = var.enable_ptr_records ? var.winc_number_workers : 0

  zone = var.dns_reverse_zone

  # Last two octets of the IP become the PTR record name (assumes /16 reverse zone)
  name = join(".", slice(
    reverse(split(".", vsphere_virtual_machine.win_server[count.index].default_ip_address)),
    0, 2
  ))

  ptr = "${vsphere_virtual_machine.win_server[count.index].name}.${var.dns_domain}."
  ttl = 300
}

resource "null_resource" "validate_ptr_records" {
  count = var.enable_ptr_records && var.validate_ptr_records ? var.winc_number_workers : 0

  provisioner "local-exec" {
    command = <<-EOT
      echo "Validating PTR record for ${vsphere_virtual_machine.win_server[count.index].default_ip_address}"
      sleep 10
      RESULT=$(nslookup ${vsphere_virtual_machine.win_server[count.index].default_ip_address} ${var.dns_server} 2>&1 | grep "name =")
      if [ -z "$RESULT" ]; then
        echo "ERROR: PTR record not found for ${vsphere_virtual_machine.win_server[count.index].default_ip_address}"
        exit 1
      else
        echo "SUCCESS: $RESULT"
      fi
    EOT
  }

  depends_on = [dns_ptr_record.windows_ptr]
}

output "ptr_records" {
  description = "PTR records created for BYOH Windows instances"
  value = var.enable_ptr_records ? [
    for i in range(var.winc_number_workers) : {
      ip   = vsphere_virtual_machine.win_server[i].default_ip_address
      fqdn = "${vsphere_virtual_machine.win_server[i].name}.${var.dns_domain}."
      ptr  = dns_ptr_record.windows_ptr[i].ptr
    }
  ] : []
}
