# FIPS 140-2 Support for Windows BYOH Instances

This document describes how to provision FIPS 140-2 enabled Windows instances for testing WMCO on FIPS-enabled OpenShift clusters.

## Overview

When `fips_enabled = true`, the provisioner will:
1. **Enable FIPS mode** on Windows via registry (`HKLM:\System\CurrentControlSet\Control\Lsa\FipsAlgorithmPolicy`)
2. **Configure SSH for FIPS-compliant algorithms** only (no curve25519, chacha20-poly1305, etc.)
3. **Configure SCHANNEL** for FIPS-compliant TLS

## Prerequisites

### 1. FIPS-Enabled OpenShift Cluster

Deploy a FIPS cluster using flexy or openshift-installer:

```bash
# Using flexy
cd flexy-templates/functionality-testing/aos-4_22/ipi-on-aws
flexy-deploy --profile versioned-installer-fips-winc-test

# Using openshift-installer
openshift-install create install-config
# Edit install-config.yaml and set: fips: true
openshift-install create cluster
```

### 2. RSA 4096 SSH Key (REQUIRED)

FIPS mode **does NOT support** curve25519 or ed25519 keys. You **MUST** use RSA 4096:

```bash
# Generate FIPS-compliant SSH key
ssh-keygen -t rsa -b 4096 -f ~/.ssh/fips-windows-key -N ""
```

**DO NOT use:**
- `ssh-keygen -t ed25519` ❌
- `ssh-keygen -t ecdsa` ❌
- `ssh-keygen -t rsa -b 2048` ❌ (too small for FIPS)

## Usage

### Enable FIPS Mode

Set the `fips_enabled` variable to `true`:

**Option 1: Configuration File** (Recommended)
```bash
# Add to ~/.config/byoh-provisioner/config
echo "FIPS_ENABLED=true" >> ~/.config/byoh-provisioner/config

# Or edit configs/defaults.conf in the repo
# FIPS_ENABLED=true

# Then provision normally
./byoh.sh apply my-fips-instance 2
```

**Option 2: Environment Variable**
```bash
export TF_VAR_fips_enabled=true
./byoh.sh apply my-fips-instance 2
```

**Option 3: Terraform Variable File**
```bash
# Create terraform.tfvars
cat > terraform.tfvars <<EOF
fips_enabled = true
EOF

terraform apply
```

**Option 4: Command Line**
```bash
terraform apply -var="fips_enabled=true"
```

### Complete Example (AWS)

**Using Configuration File:**
```bash
cd terraform-windows-provisioner

# Configure FIPS mode in config file
cat >> ~/.config/byoh-provisioner/config <<EOF
FIPS_ENABLED=true
WINC_SSH_PUBLIC_KEY=$(cat ~/.ssh/fips-windows-key.pub)
EOF

# Deploy Windows instances
./byoh.sh apply fips-test 2
```

**Using Environment Variables:**
```bash
cd terraform-windows-provisioner

# Set FIPS mode
export TF_VAR_fips_enabled=true

# Use RSA 4096 key
export WINC_SSH_PUBLIC_KEY=$(cat ~/.ssh/fips-windows-key.pub)

# Deploy Windows instances
./byoh.sh apply fips-test 2
```

### Verify FIPS is Enabled

After provisioning, SSH to the Windows instance:

```bash
ssh -i ~/.ssh/fips-windows-key Administrator@<instance-ip>
```

Check FIPS registry setting:

```powershell
Get-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\Lsa\FipsAlgorithmPolicy" -Name "Enabled"
```

Should output: `Enabled : 1`

Check SSH configuration:

```powershell
Get-Content C:\ProgramData\ssh\sshd_config | Select-String -Pattern "KexAlgorithms|Ciphers"
```

Should show only FIPS-approved algorithms.

## Testing with WMCO

### 1. Create windows-instances ConfigMap

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: windows-instances
  namespace: openshift-windows-machine-config-operator
data:
  10.0.1.50: |-
    username=Administrator
  10.0.1.51: |-
    username=Administrator
```

### 2. Create cloud-private-key Secret

Use your RSA 4096 private key:

```bash
oc create secret generic cloud-private-key \
  --from-file=private-key.pem=~/.ssh/fips-windows-key \
  -n openshift-windows-machine-config-operator
```

### 3. Deploy WMCO

```bash
oc create -f wmco-subscription.yaml
```

### 4. Monitor Logs

```bash
oc logs -f deployment/windows-machine-config-operator \
  -n openshift-windows-machine-config-operator
```

**Expected:**
- ✅ No `curve25519: use of X25519 is not allowed in FIPS 140-only mode` errors
- ✅ SSH connections succeed
- ✅ Windows nodes join cluster successfully

## Troubleshooting

### SSH Handshake Fails

**Error:** `curve25519: use of X25519 is not allowed in FIPS 140-only mode`

**Solution:** Ensure you're using RSA 4096 key, not curve25519/ed25519:

```bash
# Check key type
ssh-keygen -l -f ~/.ssh/fips-windows-key
# Should show: 4096 SHA256:... (RSA)
```

### WMCO Can't Connect

1. Verify FIPS mode is enabled on Windows instance
2. Check SSH config has FIPS algorithms
3. Verify RSA 4096 key is used
4. Check authorized_keys permissions

### Windows Node Won't Join

1. Check WMCO logs for errors
2. Verify cluster is in FIPS mode
3. Check network connectivity
4. Verify cloud-private-key secret has RSA 4096 key

## FIPS Algorithms Configured

### SSH Key Exchange
- diffie-hellman-group14-sha256
- diffie-hellman-group16-sha512
- diffie-hellman-group-exchange-sha256

### Host Key Algorithms
- ssh-rsa
- rsa-sha2-256
- rsa-sha2-512

### Ciphers
- aes128-ctr
- aes192-ctr
- aes256-ctr
- aes128-gcm@openssh.com
- aes256-gcm@openssh.com

### MACs
- hmac-sha2-256
- hmac-sha2-512

## Related Issues

- **OCPBUGS-69902**: WMCO curve25519 error in FIPS mode
- **OCPBUGS-74382**: SSH handshake FIPS compatibility

## References

- [NIST FIPS 140-2](https://csrc.nist.gov/publications/detail/fips/140/2/final)
- [Windows FIPS 140 Validation](https://learn.microsoft.com/en-us/windows/security/threat-protection/fips-140-validation)
- [OpenSSH FIPS Mode](https://www.openssh.com/fips.html)
