data "template_file" "windows-userdata" {
  count    = "${var.winc_number_workers}"
  template = <<EOF
<powershell>
# Rename Machine
Rename-Computer -NewName "${var.winc_instance_name}-${count.index}" -Force;

# Initial user setup
if((Get-LocalUser | Where-Object {$_.Name -eq "${var.admin_username}"}) -eq $null) {
    $password = ConvertTo-SecureString "${var.admin_password}" -AsPlainText -Force
    New-LocalUser -Name "${var.admin_username}" -Password $password -PasswordNeverExpires
    Add-LocalGroupMember -Group "Administrators" -Member "${var.admin_username}"
}

# Setup SSH access
$authorizedKeyConf = "$env:ProgramData\ssh\administrators_authorized_keys"
$authorizedKeyFolder = Split-Path -Path $authorizedKeyConf
if (!(Test-Path $authorizedKeyFolder)) {
  New-Item -path $authorizedKeyFolder -ItemType Directory
}
Write-Output "${var.ssh_public_key}" | Out-File -FilePath $authorizedKeyConf -Encoding ascii
Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0

# SSH service configuration
Set-Service -Name ssh-agent -StartupType 'Automatic'
Set-Service -Name sshd -StartupType 'Automatic'
Start-Service ssh-agent
Start-Service sshd

# Configure SSH authentication
$sshdConfigFilePath = "$env:ProgramData\ssh\sshd_config"
$pubKeyConf = (Get-Content -path $sshdConfigFilePath) -replace '#PubkeyAuthentication yes','PubkeyAuthentication yes'
$pubKeyConf | Set-Content -Path $sshdConfigFilePath
$passwordConf = (Get-Content -path $sshdConfigFilePath) -replace '#PasswordAuthentication yes','PasswordAuthentication yes'
$passwordConf | Set-Content -Path $sshdConfigFilePath

# Configure SSH key permissions
$acl = Get-Acl $authorizedKeyConf
$acl.SetAccessRuleProtection($true, $false)
$administratorsRule = New-Object system.security.accesscontrol.filesystemaccessrule("Administrators","FullControl","Allow")
$acl.SetAccessRule($administratorsRule)
$systemRule = New-Object system.security.accesscontrol.filesystemaccessrule("SYSTEM","FullControl","Allow")
$acl.SetAccessRule($systemRule)
$acl | Set-Acl

# Restart SSH service
Restart-Service sshd

# Configure Firewall
New-NetFirewallRule -DisplayName "ContainerLogsPort" -LocalPort 10250 -Enabled True -Direction Inbound -Protocol TCP -Action Allow -EdgeTraversalPolicy Allow

# Install Docker
Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force
Set-PSRepository PSGallery -InstallationPolicy Trusted
Install-Module -Name DockerMsftProvider -Repository PSGallery -Force
Install-Package -Name docker -ProviderName DockerMsftProvider -Force

# Restart system
shutdown -r -t 10;
</powershell>
EOF
}