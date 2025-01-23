data "template_file" "windows-userdata" {
  count    = var.winc_number_workers
  template = <<EOF
<powershell>
# Rename Machine
Rename-Computer -NewName "${var.winc_instance_name}-${count.index}" -Force

# Set up SSH public key authentication
$authorizedKeyConf = "$env:ProgramData\ssh\administrators_authorized_keys"
$authorizedKeyFolder = Split-Path -Path $authorizedKeyConf
if (!(Test-Path $authorizedKeyFolder)) {
    New-Item -Path $authorizedKeyFolder -ItemType Directory
}
Write-Output "${var.ssh_public_key}" | Out-File -FilePath $authorizedKeyConf -Encoding ascii

# Install and configure OpenSSH
Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
Set-Service -Name ssh-agent -StartupType 'Automatic'
Set-Service -Name sshd -StartupType 'Automatic'
Start-Service ssh-agent
Start-Service sshd

# Configure SSH to allow key-based authentication
$sshdConfigFilePath = "$env:ProgramData\ssh\sshd_config"
(Get-Content -Path $sshdConfigFilePath) -replace '#PubkeyAuthentication yes','PubkeyAuthentication yes' | Set-Content -Path $sshdConfigFilePath
(Get-Content -Path $sshdConfigFilePath) -replace '#PasswordAuthentication yes','PasswordAuthentication yes' | Set-Content -Path $sshdConfigFilePath

# Set ACL for administrators_authorized_keys
$acl = Get-Acl $authorizedKeyConf
$acl.SetAccessRuleProtection($true, $false)
$administratorsRule = New-Object system.security.accesscontrol.filesystemaccessrule("Administrators","FullControl","Allow")
$systemRule = New-Object system.security.accesscontrol.filesystemaccessrule("SYSTEM","FullControl","Allow")
$acl.SetAccessRule($administratorsRule)
$acl.SetAccessRule($systemRule)
$acl | Set-Acl

# Restart the SSH service
Restart-Service sshd
</powershell>
EOF

  vars = {
    ssh_public_key = var.ssh_public_key
  }
}

