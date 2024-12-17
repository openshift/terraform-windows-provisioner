# Bootstrapping PowerShell Script
data "template_file" "windows-userdata" {
  count    = "${var.winc_number_workers}"
  template = <<EOF
<powershell>
# Rename Machine
Rename-Computer -NewName "${var.winc_instance_name}-${count.index}" -Force;
# Setup SSH access
$authorizedKeyConf = "$env:ProgramData\ssh\administrators_authorized_keys"
$authorizedKeyFolder = Split-Path -Path $authorizedKeyConf
if (!(Test-Path $authorizedKeyFolder))
{
  New-Item -path $authorizedKeyFolder  -ItemType Directory
}
Write-Output "${var.ssh_public_key}" | Out-File -FilePath $authorizedKeyConf -Encoding ascii
# SSH service startup type
Set-Service -Name ssh-agent -StartupType 'Automatic'
Set-Service -Name sshd -StartupType 'Automatic'
# start service
Start-Service ssh-agent
Start-Service sshd
# configure key based-authentication
$sshdConfigFilePath = "$env:ProgramData\ssh\sshd_config"
$pubKeyConf = (Get-Content -path $sshdConfigFilePath) -replace '#PubkeyAuthentication yes','PubkeyAuthentication yes'
$pubKeyConf | Set-Content -Path $sshdConfigFilePath
$passwordConf = (Get-Content -path $sshdConfigFilePath) -replace '#PasswordAuthentication yes','PasswordAuthentication yes'
$passwordConf | Set-Content -Path $sshdConfigFilePath
# create key file in configuration

$acl = Get-Acl $authorizedKeyConf
# disable inheritance
$acl.SetAccessRuleProtection($true, $false)
# set full control for Administrators
$administratorsRule = New-Object system.security.accesscontrol.filesystemaccessrule("Administrators","FullControl","Allow")
$acl.SetAccessRule($administratorsRule)
# set full control for SYSTEM
$systemRule = New-Object system.security.accesscontrol.filesystemaccessrule("SYSTEM","FullControl","Allow")
$acl.SetAccessRule($systemRule)
# apply file acl
$acl | Set-Acl
# restart service
Restart-Service sshd
# success
# Firewall Rules
New-NetFirewallRule -DisplayName "ContainerLogsPort" -LocalPort 10250 -Enabled True -Direction Inbound -Protocol TCP -Action Allow -EdgeTraversalPolicy Allow
# Install Docker
Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force
# configure repository policy
Set-PSRepository PSGallery -InstallationPolicy Trusted
# install module with provider
Install-Module -Name DockerMsftProvider -Repository PSGallery -Force
# install docker package
Install-Package -Name docker -ProviderName DockerMsftProvider -Force

# Restart
shutdown -r -t 10;
</powershell>
EOF
}