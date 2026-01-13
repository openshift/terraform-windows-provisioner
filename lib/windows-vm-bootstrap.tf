# Generic Windows BYOH Bootstrap Script
# Works across all platforms: AWS, GCP, Azure, vSphere, Nutanix

data "template_file" "windows-userdata" {
  count    = "${var.winc_number_workers}"
  template = <<EOF
<powershell>
# Rename Machine (required for AWS, Azure, Nutanix; optional for GCP)
Rename-Computer -NewName "${var.winc_instance_name}-${count.index}" -Force

function Get-RandomPassword {
    Add-Type -AssemblyName 'System.Web'
    return [System.Web.Security.Membership]::GeneratePassword(16, 2)
}

# MANDATORY: Configure Administrator account for OpenSSH authentication
# OpenSSH on Windows requires valid password to generate Windows security token (LogonUser API)
# Without this, SSH authentication fails with "unable to generate token" error
# PasswordNeverExpires prevents mysterious failures after Windows password expiration (default 42 days)
$UserAccount = Get-LocalUser -Name "${var.admin_username}" -ErrorAction SilentlyContinue
if ($UserAccount -ne $null) {
    $password = ConvertTo-SecureString "${var.admin_password}" -AsPlainText -Force
    $UserAccount | Set-LocalUser -Password $password -PasswordNeverExpires $true
    if (!$UserAccount.Enabled) {
        $UserAccount | Enable-LocalUser
    }
    Write-Output "User account ${var.admin_username} configured for SSH authentication"
} else {
    Write-Output "WARNING: User account ${var.admin_username} not found"
}

# Setup SSH authorized keys
$authorizedKeyConf = "$env:ProgramData\ssh\administrators_authorized_keys"
$authorizedKeyFolder = Split-Path -Path $authorizedKeyConf
if (!(Test-Path $authorizedKeyFolder)) {
    New-Item -path $authorizedKeyFolder -ItemType Directory
}
Write-Output "${var.ssh_public_key}" | Out-File -FilePath $authorizedKeyConf -Encoding ascii

# Install and configure OpenSSH Server
Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0

# Start sshd service
Set-Service -Name sshd -StartupType 'Automatic'
Start-Service sshd

# Configure sshd_config - Enable both password and key authentication
$sshdConfigFilePath = "$env:ProgramData\ssh\sshd_config"
$sshConfig = Get-Content -path $sshdConfigFilePath
$sshConfig = $sshConfig -replace '#PubkeyAuthentication yes','PubkeyAuthentication yes'
$sshConfig = $sshConfig -replace '#PasswordAuthentication yes','PasswordAuthentication yes'
$sshConfig = $sshConfig -replace 'PasswordAuthentication no','PasswordAuthentication yes'
$sshConfig | Set-Content -Path $sshdConfigFilePath

# Configure authorized keys file permissions
$acl = Get-Acl $authorizedKeyConf
# Disable inheritance
$acl.SetAccessRuleProtection($true, $false)
# Set full control for Administrators
$administratorsRule = New-Object system.security.accesscontrol.filesystemaccessrule("Administrators","FullControl","Allow")
$acl.SetAccessRule($administratorsRule)
# Set full control for SYSTEM
$systemRule = New-Object system.security.accesscontrol.filesystemaccessrule("SYSTEM","FullControl","Allow")
$acl.SetAccessRule($systemRule)
# Apply file ACL
$acl | Set-Acl

# Restart SSH service to apply configuration changes
Restart-Service sshd

# Configure Firewall
New-NetFirewallRule -DisplayName "ContainerLogsPort" -LocalPort ${var.container_logs_port} -Enabled True -Direction Inbound -Protocol TCP -Action Allow -EdgeTraversalPolicy Allow

Write-Output "Windows BYOH bootstrap completed successfully"
</powershell>
EOF
}
