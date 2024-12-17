# BYOH Auto-provisioning Tool

Automates provisioning and management of BYOH Windows worker nodes in OpenShift clusters across multiple cloud providers.

## Prerequisites

- OpenShift Cluster with exported KUBECONFIG
- Terraform ≥ 1.0.0
- `oc` CLI tool
- `jq` for JSON processing
- Base64 command-line tool

## Supported Platforms

- **AWS**: Automated credential management via cluster secrets
- **Azure**: Native cloud integration with resource group support
- **GCP**: Google Cloud Platform with service account integration
- **vSphere**: VMware infrastructure support
- **Nutanix**: Prism Central managed infrastructure
- **Baremetal**: Non-cloud environments with AWS credentials

## Usage

Basic operations:
```bash
./byoh.sh [ACTION] [NAME] [NUM_WORKERS] [FOLDER_SUFFIX] [WINDOWS_VERSION]
```

Examples:
```bash
# Create 2 BYOH instances with Windows Server 2019
./byoh.sh apply byoh 2 '' 2019

# Create 4 instances with custom name
./byoh.sh apply my-byoh 4

# Create on Nutanix
./byoh.sh apply ntnx-byoh 2

# Multiple platform deployments
./byoh.sh apply byoh-winc 2 '-az2019'  # Azure 2019
./byoh.sh apply byoh-winc 2 '-az2022'  # Azure 2022

# Destroy instances
./byoh.sh destroy my-byoh 4

# Create/update ConfigMap only
./byoh.sh configmap
```

### Parameters

| Parameter | Description | Default | Required |
|-----------|-------------|---------|----------|
| ACTION | Operation (apply/destroy/arguments/configmap/clean/help) | apply | Yes |
| NAME | Base name for instances | byoh-winc | No |
| NUM_WORKERS | Number of workers | 2 | No |
| FOLDER_SUFFIX | Temporary folder suffix | "" | No |
| WINDOWS_VERSION | Windows Server version (2019/2022) | 2022 | No |

## Credential Configuration

The script requires two credentials for all platforms:
1. Windows administrator password
2. SSH public key for remote access

These can be provided in two ways:

### Environment Variables
```bash
# Set credentials via environment variables
export WINC_ADMIN_PASSWORD="YourSecurePassword123!"
export WINC_SSH_PUBLIC_KEY="ssh-rsa AAAA..."

# Then run the script
./byoh.sh apply
```

### Configuration File
Create a configuration file at `~/.config/winc/credentials`:
```bash
# Sample ~/.config/winc/credentials
WINC_ADMIN_PASSWORD="YourSecurePassword123!"
WINC_SSH_PUBLIC_KEY="$(cat ~/.ssh/id_rsa.pub)"
```

Secure the credentials file:
```bash
# Create directory and file with proper permissions
mkdir -p ~/.config/winc
touch ~/.config/winc/credentials
chmod 600 ~/.config/winc/credentials
```

The script will first check for environment variables, then fall back to the configuration file if necessary.

### Security Notes
- Keep your credentials file secure and readable only by you
- Regularly rotate passwords and SSH keys
- Never commit credentials to source control
- Use strong passwords that meet Windows complexity requirements
- Generate a dedicated SSH key pair for BYOH instances if desired

### Platform-Specific Notes

#### AWS
- Credentials automatically extracted from cluster secrets
- Uses 'Administrator' as default username
- SSH key-based authentication configured during provisioning
- All credentials managed through variables

#### Azure
- Instance names limited to 13 characters
- Uses 'Administrator' as default username
- SSH key-based authentication configured during provisioning
- Credentials and SSH keys provided through variables

#### GCP
- Credentials from service account in cluster secrets
- Uses 'Administrator' as default username
- SSH key-based authentication configured during provisioning
- Service account and SSH access managed through variables

#### Nutanix
- Requires Prism Central credentials from cluster secrets
- Pre-configured Windows image required
- SSH key-based authentication configured during provisioning
- Subnet configuration from machineset

#### vSphere
- vCenter credentials from cluster secrets
- Network and datastore permissions required
- Template-based provisioning
- SSH key-based authentication configured during provisioning

### Platform: None (Baremetal)

For baremetal deployments, the platform is detected as "none" and uses AWS credentials for provisioning.

#### Prerequisites
- AWS credentials configured in either:
  ```bash
  ~/.aws/config
  ~/.aws/credentials
  ```
- Valid AWS region access
- Permissions for EC2 instance creation

#### Configuration
The script will:
1. Detect platform as "none"
2. Verify AWS credential files existence
3. Use local worker node information for networking

#### Example Usage
```bash
# Create Windows 2022 instances
./byoh.sh apply byoh-metal 2

# Using Windows 2019
./byoh.sh apply byoh-metal 2 '' 2019
```

#### Credential Requirements
```bash
# ~/.aws/credentials format:
[default]
aws_access_key_id = YOUR_ACCESS_KEY
aws_secret_access_key = YOUR_SECRET_KEY

# ~/.aws/config format:
[default]
region = YOUR_AWS_REGION
```

## Cloud Provider Requirements

### AWS
- Credentials in cluster secrets or local AWS configuration
- Valid AMI access

### Azure
- Valid subscription and service principal
- Resource group access

### GCP
- Service account with compute permissions
- Valid project configuration

### Nutanix
- Prism Central access
- Pre-configured Windows image
- Configured subnet

### vSphere
- vCenter access
- Network and datastore permissions

## Troubleshooting

Check credentials:
```bash
oc get secret -n kube-system
oc get secret -n openshift-machine-api
```

Verify cluster status:
```bash
oc get clusterversion
```

Check cluster capacity:
```bash
oc get nodes
```

View Terraform logs:
```bash
cd /tmp/terraform_byoh/<platform>
terraform show
```

Check ConfigMap status:
```bash
oc get configmap windows-instances -n <wmco-namespace>
```
