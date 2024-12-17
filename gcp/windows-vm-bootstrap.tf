# Bootstrapping PowerShell Script
data "template_file" "windows-userdata" {
  template = <<EOF
<powershell>
function Get-RandomPassword {
    Add-Type -AssemblyName 'System.Web'
    return [System.Web.Security.Membership]::GeneratePassword(16, 2)
}

# Check if the capi user exists, this will be the case on Azure, and will be used instead of Administrator
if((Get-LocalUser | Where-Object {$_.Name -eq "${var.admin_username}"}) -eq $null) {
    # The user doesn't exist, ensure the Administrator account is enabled if it exists
    # If neither users exist, an error will be written to the console, but the script will still continue
    $UserAccount = Get-LocalUser -Name "Administrator"
    if( ($UserAccount -ne $null) -and (!$UserAccount.Enabled) ) {
        $password = ConvertTo-SecureString "${var.admin_password}" -asplaintext -force
        $UserAccount | Set-LocalUser -Password $password
        $UserAccount | Enable-LocalUser
    }
}

# Install and configure OpenSSH Server
Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0

# Configure firewall
$firewallRuleName = "ContainerLogsPort"
$containerLogsPort = "10250"
New-NetFirewallRule -DisplayName $firewallRuleName -Direction Inbound -Action Allow -Protocol TCP -LocalPort $containerLogsPort -EdgeTraversalPolicy Allow

# Configure SSH service
Set-Service -Name sshd -StartupType 'Automatic'
Start-Service sshd

# Configure SSH authentication
$pubKeyConf = (Get-Content -path C:\ProgramData\ssh\sshd_config) -replace '#PubkeyAuthentication yes','PubkeyAuthentication yes'
$pubKeyConf | Set-Content -Path C:\ProgramData\ssh\sshd_config
$passwordConf = (Get-Content -path C:\ProgramData\ssh\sshd_config) -replace '#PasswordAuthentication yes','PasswordAuthentication yes'
$passwordConf | Set-Content -Path C:\ProgramData\ssh\sshd_config

# Setup authorized keys
$authorizedKeyFilePath = "$env:ProgramData\ssh\administrators_authorized_keys"
New-Item -Force $authorizedKeyFilePath
echo "${var.ssh_public_key}" | Out-File $authorizedKeyFilePath -Encoding ascii

# Configure authorized keys file permissions
$acl = Get-Acl C:\ProgramData\ssh\administrators_authorized_keys
$acl.SetAccessRuleProtection($true, $false)
$administratorsRule = New-Object system.security.accesscontrol.filesystemaccessrule("Administrators","FullControl","Allow")
$systemRule = New-Object system.security.accesscontrol.filesystemaccessrule("SYSTEM","FullControl","Allow")
$acl.SetAccessRule($administratorsRule)
$acl.SetAccessRule($systemRule)
$acl | Set-Acl

# Restart SSH service to apply changes
Restart-Service sshd
</powershell>
<persist>true</persist>
EOF
}