# Bootstrapping PowerShell Script
data "template_file" "windows-userdata" {
  template = <<EOF
<powershell>
# Ensure the Administrator account is enabled
$UserAccount = Get-LocalUser -Name "Administrator"
if( ($UserAccount -ne $null) -and (!$UserAccount.Enabled) ) {
    function Get-RandomPassword {
        Add-Type -AssemblyName 'System.Web'
        return [System.Web.Security.Membership]::GeneratePassword(16, 2)
    }

    $password = ConvertTo-SecureString (Get-RandomPassword) -asplaintext -force
    $UserAccount | Set-LocalUser -Password $password
    $UserAccount | Enable-LocalUser
}

# Install OpenSSH Server
Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0

# Configure firewall for container logs
$firewallRuleName = "ContainerLogsPort"
$containerLogsPort = "10250"
New-NetFirewallRule -DisplayName $firewallRuleName -Direction Inbound -Action Allow -Protocol TCP -LocalPort $containerLogsPort -EdgeTraversalPolicy Allow

# Ensure the SSH service is enabled and started
Set-Service -Name sshd -StartupType 'Automatic'
Start-Service sshd

# Configure SSH settings
$sshdConfigFilePath = "$env:ProgramData\ssh\sshd_config"
$pubKeyConf = (Get-Content -path $sshdConfigFilePath) -replace '#PubkeyAuthentication yes','PubkeyAuthentication yes'
$pubKeyConf | Set-Content -Path $sshdConfigFilePath
$passwordConf = (Get-Content -path $sshdConfigFilePath) -replace '#PasswordAuthentication yes','PasswordAuthentication yes'
$passwordConf | Set-Content -Path $sshdConfigFilePath

# Set up authorized keys
$authorizedKeyFilePath = "$env:ProgramData\ssh\administrators_authorized_keys"
New-Item -Force -Path $authorizedKeyFilePath
echo "${var.ssh_public_key}" | Out-File $authorizedKeyFilePath -Encoding ascii

# Set proper ACLs on the authorized keys file
$acl = Get-Acl $authorizedKeyFilePath
$acl.SetAccessRuleProtection($true, $false)
$administratorsRule = New-Object system.security.accesscontrol.filesystemaccessrule("Administrators","FullControl","Allow")
$systemRule = New-Object system.security.accesscontrol.filesystemaccessrule("SYSTEM","FullControl","Allow")
$acl.SetAccessRule($administratorsRule)
$acl.SetAccessRule($systemRule)
$acl | Set-Acl

# Restart the SSH service to apply changes
Restart-Service sshd
</powershell>
<persist>true</persist>
EOF
}

