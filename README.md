# BYOH Provisioner - Bring Your Own Host for Windows Nodes

The BYOH Provisioner is a tool for provisioning and managing Windows worker nodes across multiple cloud platforms. This project provides automated BYOH (Bring Your Own Host) Windows node deployment for Kubernetes/OpenShift clusters with support for AWS, Azure, GCP, vSphere, Nutanix, and bare metal environments.

All configuration is derived from your OpenShift cluster or provided via parameters.

## Features

- Multi-cloud support: AWS, Azure, GCP, vSphere, Nutanix, bare metal
- Generic bootstrap template: Single cross-platform Windows bootstrap script
- Automated credential management: Extraction from cluster secrets
- Modular architecture: Clean separation of concerns with library modules
- Configuration priority: Environment variables, user config, project config, defaults
- Platform auto-detection from cluster configuration
- Fully parameterized: Customize instance types, disk sizes, tags

## Prerequisites

- **Kubernetes/OpenShift Cluster** with exported KUBECONFIG and Linux worker nodes
- **Terraform** >= 1.0.0
- **oc** CLI tool
- **jq** for JSON processing
- **base64** command-line tool
- **Optional**: AWS CLI for automatic AMI discovery on AWS platform

## Quick Start

### 1. Install the Tool

```bash
git clone https://github.com/openshift/terraform-windows-provisioner.git
cd terraform-windows-provisioner
chmod +x byoh.sh
```

### 2. Configure Credentials (Optional)

The tool automatically:
- **Generates a secure random password** for Windows instances (if not provided)
- **Extracts SSH keys** from your cluster's `cloud-private-key` secret

Optionally customize credentials:

```bash
mkdir -p ~/.config/byoh-provisioner
cp configs/examples/defaults.conf.example ~/.config/byoh-provisioner/config
chmod 600 ~/.config/byoh-provisioner/config
```

Optional configuration:
- `WINC_ADMIN_PASSWORD`: Custom Windows password (auto-generated if not set)
- `WINC_SSH_PUBLIC_KEY`: Custom SSH public key (auto-extracted if not set)
- `WINC_ADMIN_USERNAME`: Administrator username (defaults: Azure=`capi`, Others=`Administrator`)

### 3. Deploy Windows Nodes

```bash
# Deploy 2 Windows Server 2022 nodes
./byoh.sh apply mywindows 2

# Deploy 4 Windows Server 2019 nodes
./byoh.sh apply mywindows 4 '' 2019
```

### 4. Destroy Windows Nodes When Done

```bash
./byoh.sh destroy mywindows 2
```

## Supported Platforms

| Platform | Status | Auto-Credentials | Notes |
|----------|--------|------------------|-------|
| **AWS** | Supported | Yes | Credentials from cluster secrets |
| **Azure** | Supported | Yes | Instance names limited to 13 chars |
| **GCP** | Supported | Yes | Service account integration |
| **vSphere** | Supported | Yes | Template-based provisioning |
| **Nutanix** | Supported | Yes | Prism Central integration |
| **Bare Metal** | Supported | Local AWS config | Uses AWS credentials |

## Usage

### Parameters

| Parameter | Description | Default | Required |
|-----------|-------------|---------|----------|
| `ACTION` | Operation (apply/destroy/arguments/configmap/clean/help) | apply | Yes |
| `NAME` | Base name for instances | byoh-winc | No |
| `NUM_WORKERS` | Number of workers | 2 | No |
| `FOLDER_SUFFIX` | Temporary folder suffix | "" | No |
| `WINDOWS_VERSION` | Windows Server version (2019/2022) | 2022 | No |

### Basic Commands

```bash
# Create instances
./byoh.sh apply [NAME] [NUM_WORKERS] [FOLDER_SUFFIX] [WINDOWS_VERSION]

# Destroy instances
./byoh.sh destroy [NAME] [NUM_WORKERS]

# Show Terraform arguments
./byoh.sh arguments [NAME] [NUM_WORKERS]

# Create/update ConfigMap only
./byoh.sh configmap

# Clean up temporary files
./byoh.sh clean

# Show help
./byoh.sh help
```

### Examples

```bash
# Single Windows 2019 instance
./byoh.sh apply myapp 1 '' 2019

# 4 Windows 2022 instances with custom name
./byoh.sh apply production-win 4

# Multiple deployments with suffixes
./byoh.sh apply test 2 '-env1'
./byoh.sh apply test 2 '-env2'

# Show what would be deployed without creating
./byoh.sh arguments myapp 2
```

## How It Works

### Intelligent Infrastructure Discovery

The provisioner uses **Linux worker nodes** as the source of truth for infrastructure configuration:

- **Network Configuration**: VPC, VNet, subnets, security groups from Linux machines
- **Region/Zone**: Automatically detected from existing Linux workers
- **Resource Groups**: Extracted from cluster credentials
- **No Windows MachineSet Required**: Works immediately with just Linux workers

### Image Selection Strategy

| Platform | Priority |
|----------|----------|
| **AWS** | User config `AWS_WINDOWS_AMI` → AWS API query (version-specific) → Windows MachineSet |
| **Azure** | User config `AZURE_WINDOWS_SKU` → Windows MachineSet → Default SKU (uses latest image) |
| **GCP** | Uses image family (always latest) |
| **vSphere** | User config `VSPHERE_WINDOWS_TEMPLATE` → Windows MachineSet → Error |
| **Nutanix** | User config `NUTANIX_WINDOWS_IMAGE` → Windows MachineSet → Error |

### Generic Bootstrap Template

All platforms use a single generic Windows bootstrap script located at `lib/windows-vm-bootstrap.tf`. Platform-specific directories contain symlinks to this generic template, ensuring consistent behavior across all cloud providers.

**Key features:**
- GCP's `sysprep-specialize-script-ps1` accepts `<powershell>` XML tags
- Single source of truth for Windows bootstrap logic
- Includes only the mandatory Administrator password fix
- Simplified maintenance (update one file, all platforms benefit)

## Configuration

### Configuration Priority

Configuration is loaded with the following priority (highest to lowest):

1. **Environment variables** (highest priority)
2. **User config file**: `~/.config/byoh-provisioner/config`
3. **Project config file**: `./configs/defaults.conf`
4. **Built-in defaults** (lowest priority)

### Required Configuration

**None!** All credentials are auto-generated or extracted from your cluster:
- Windows password: **Auto-generated** (cryptographically secure)
- SSH public key: **Auto-extracted** from cluster secrets
- Infrastructure config: **Auto-detected** from Linux worker nodes

### Optional Configuration

See [configs/examples/](configs/examples/) for platform-specific examples:

- `aws.conf.example` - AWS-specific settings
- `azure.conf.example` - Azure-specific settings (including image versions)
- `gcp.conf.example` - GCP-specific settings
- `vsphere.conf.example` - vSphere-specific settings
- `nutanix.conf.example` - Nutanix-specific settings

### Key Configuration Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `WMCO_NAMESPACE` | WMCO deployment namespace (can override auto-detection) | `openshift-windows-machine-config-operator` |
| `WMCO_IDENTIFIER_TYPE` | ConfigMap identifier type: `ip` (IP addresses) or `dns` (hostnames) | `ip` |
| `WINDOWS_ADMIN_USERNAME` | Windows administrator username | Platform-specific: Azure=`capi`, Others=`Administrator` |
| `WINDOWS_CONTAINER_LOGS_PORT` | Container logs port | 10250 |
| `AZURE_VM_EXTENSION_HANDLER_VERSION` | Azure VM extension version | 1.9 |
| `AZURE_2019_IMAGE_VERSION` | Azure Win 2019 image version | latest |
| `AZURE_2022_IMAGE_VERSION` | Azure Win 2022 image version | latest |
| `AWS_INSTANCE_TYPE` | AWS instance type | m5a.large |
| `AWS_WINDOWS_AMI` | AWS Windows AMI override | (auto-detected) |
| `AWS_ROOT_VOLUME_SIZE` | AWS root volume size (GB) | 120 |
| `ENVIRONMENT_TAG` | Environment tag for resources | production |
| `MANAGED_BY_TAG` | Managed-by tag for resources | terraform |

## Platform-Specific Notes

### AWS

- Credentials automatically extracted from cluster secrets
- AMI selection: User override → AWS API (version-specific) → MachineSet
- AWS CLI recommended for automatic version-specific AMI discovery
- Configurable instance types and volume sizes

### Azure

- **Instance names limited to 13 characters** (automatically truncated)
- Supports specific image versions or 'latest'
- **All 6 Azure variables auto-loaded from cluster secret**:
  - Auth: `ARM_CLIENT_ID`, `ARM_CLIENT_SECRET`, `ARM_SUBSCRIPTION_ID`, `ARM_TENANT_ID`
  - Infrastructure: `ARM_RESOURCE_PREFIX`, `ARM_RESOURCEGROUP`
- Works with credentials from environment variables (CI) or cluster secrets

### GCP

- Service account credentials from cluster secrets
- Zone and region auto-detected
- Supports custom machine types
- Bootstrap accepts `<powershell>` tags (enables generic template)

### vSphere

- Requires pre-configured Windows templates
- vCenter credentials from cluster secrets
- Template names: `Windows-Server-2019-Template`, `Windows-Server-2022-Template`

### Nutanix

- Requires pre-configured Windows images in Prism Central
- Cluster and subnet UUIDs auto-detected
- Image names: `Windows-Server-2019`, `Windows-Server-2022`

### Bare Metal (None)

- Uses AWS credentials from `~/.aws/config` and `~/.aws/credentials`
- Platform detected as "none"
- Provisions using AWS infrastructure

## Architecture

This project uses a modular architecture with separated concerns:

```
terraform-windows-provisioner/
├── byoh.sh                      # Main entry point
├── lib/                         # Library modules
│   ├── config.sh               # Configuration loading (bash 3.x compatible)
│   ├── credentials.sh          # Credential management
│   ├── platform.sh             # Platform detection & tfvars generation
│   ├── terraform.sh            # Terraform operations (cp -LR for symlinks)
│   ├── validation.sh           # Input validation
│   └── windows-vm-bootstrap.tf # Generic Windows bootstrap (all platforms)
├── configs/                    # Configuration files
│   ├── defaults.conf           # Default values
│   └── examples/               # Platform-specific examples
└── <platform>/                 # Platform-specific Terraform
    ├── aws/
    │   ├── main.tf
    │   ├── variables.tf
    │   └── windows-vm-bootstrap.tf → ../lib/windows-vm-bootstrap.tf
    ├── azure/
    │   ├── main.tf
    │   ├── variables.tf
    │   └── windows-vm-bootstrap.tf → ../lib/windows-vm-bootstrap.tf
    ├── gcp/
    │   ├── main.tf
    │   ├── variables.tf
    │   └── windows-vm-bootstrap.tf → ../lib/windows-vm-bootstrap.tf
    ├── vsphere/
    ├── nutanix/
    └── none/
```

## Troubleshooting

### Windows SSH Connectivity Issues

If WMCO cannot connect to Windows nodes with "unable to connect to Windows VM: timed out" errors, check the bootstrap logs.

**GCP - Check Serial Port Logs**:
```bash
# Check if Administrator password was configured
gcloud compute instances get-serial-port-output <vm-name> --zone <zone> | grep "Administrator account configured"

# Check if SSH services are running
gcloud compute instances get-serial-port-output <vm-name> --zone <zone> | grep -A5 "sshd"
```

**Azure - Check VM Boot Diagnostics**:
```bash
# Get VM status
az vm get-instance-view --name <vm-name> --resource-group <rg> --query "instanceView.statuses"

# Check extensions
az vm extension list --vm-name <vm-name> --resource-group <rg>
```

**Verify SSH from Bastion**:
```bash
bastion_host=$(oc get service --all-namespaces -l run=ssh-bastion -o go-template='{{ with (index (index .items 0).status.loadBalancer.ingress 0) }}{{ or .hostname .ip }}{{end}}')
ssh -i ~/.ssh/openshift-qe.pem -t -o StrictHostKeyChecking=no -o ProxyCommand="ssh -i ~/.ssh/openshift-qe.pem -A -o StrictHostKeyChecking=no -W %h:%p core@${bastion_host}" Administrator@<windows-ip> 'powershell'
```

### Check Cluster Credentials

```bash
oc get secret -n kube-system
oc get secret -n openshift-machine-api
```

### Verify Cluster Status

```bash
oc get clusterversion
oc get nodes
```

### View Terraform State

```bash
cd /tmp/terraform_byoh/<platform>
terraform show
terraform output
```

### Check ConfigMap

```bash
# Find WMCO namespace
oc get deployment --all-namespaces | grep windows-machine-config-operator

# View ConfigMap
oc get configmap windows-instances -n <wmco-namespace> -o yaml
```

### Enable Debug Logging

```bash
export BYOH_LOG_LEVEL=DEBUG
./byoh.sh apply myapp 2
```

## Contributing

We welcome contributions! Please:

1. Follow existing code style and patterns
2. Test changes on multiple platforms
3. Update documentation

## Security

For security issues, please see [SECURITY.md](SECURITY.md).

## License

Apache License 2.0. See [LICENSE](LICENSE) for details.

## Project Status

Version: 1.0.0

This is a vendor-neutral tool suitable for upstream use in OpenShift CI workflows.

## Support

- **Issues**: Report bugs or request features via [GitHub Issues](https://github.com/openshift/terraform-windows-provisioner/issues)
- **Documentation**: See [docs/](docs/) for comprehensive guides

## Acknowledgments

This project works with:
- OpenShift Windows Container Support
- Windows Machine Config Operator (WMCO)
- Kubernetes Windows node support

---
