# BYOH Provisioner - Bring Your Own Host for Windows Nodes

The BYOH Provisioner is a generic, configurable tool for provisioning and managing Windows worker nodes across multiple cloud platforms. This project provides automated BYOH (Bring Your Own Host) Windows node deployment for Kubernetes/OpenShift clusters with support for AWS, Azure, GCP, vSphere, Nutanix, and bare metal environments.

**Note:** This tool is vendor-neutral and contains no hardcoded values. All configuration is derived from your OpenShift cluster or provided via parameters.

## Features

- **Multi-Cloud Support**: Deploy Windows nodes on AWS, Azure, GCP, vSphere, Nutanix, or bare metal
- **Zero Hardcoded Values**: All configuration via files, environment variables, or auto-detection
- **Modular Architecture**: Clean separation of concerns with library modules
- **Flexible Configuration**: Multi-source configuration with priority ordering
- **Automated Credential Management**: Seamless integration with cluster secrets
- **Comprehensive Documentation**: Detailed guides for all platforms
- **Fully Parameterized**: Customize instance types, disk sizes, tags, and more

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
git clone https://github.com/<your-org>/terraform-windows-provisioner.git
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
| **AWS** | ✅ Supported | Yes | Credentials from cluster secrets |
| **Azure** | ✅ Supported | Yes | Instance names limited to 13 chars |
| **GCP** | ✅ Supported | Yes | Service account integration |
| **vSphere** | ✅ Supported | Yes | Template-based provisioning |
| **Nutanix** | ✅ Supported | Yes | Prism Central integration |
| **Bare Metal** | ✅ Supported | Local AWS config | Uses AWS credentials |

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
| **AWS** | Windows MachineSet → AWS API query → User config `AWS_WINDOWS_AMI` |
| **Azure** | User config `AZURE_WINDOWS_SKU` → Windows MachineSet → Default SKU (uses latest image) |
| **GCP** | Uses image family (always latest) |
| **vSphere** | User config `VSPHERE_WINDOWS_TEMPLATE` → Windows MachineSet → Error |
| **Nutanix** | User config `NUTANIX_WINDOWS_IMAGE` → Windows MachineSet → Error |

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
| `AWS_ROOT_VOLUME_SIZE` | AWS root volume size (GB) | 120 |
| `ENVIRONMENT_TAG` | Environment tag for resources | production |
| `MANAGED_BY_TAG` | Managed-by tag for resources | terraform |

**Configuration Priority (highest to lowest)**:
1. **Environment Variables** - Set via `export` or inline (e.g., `WMCO_IDENTIFIER_TYPE=dns ./byoh.sh apply`)
2. **User Config File** - `~/.config/byoh-provisioner/config` (personal overrides)
3. **Project Config File** - `configs/defaults.conf` (team-wide defaults)
4. **Built-in Defaults** - Hardcoded fallback values

**Notes:**
- `WMCO_NAMESPACE` is auto-detected by searching for the `windows-machine-config-operator` deployment. Override via environment variable or config file if using a custom namespace.
- `WMCO_IDENTIFIER_TYPE` controls how instances are identified in the ConfigMap. Set to `dns` for DNS hostnames or `ip` (default) for IP addresses. Useful for automation tests or environments requiring DNS-based identification.

**Example: Using DNS identifiers instead of IP addresses**
```bash
# Method 1: Environment variable (highest priority)
export WMCO_IDENTIFIER_TYPE=dns
./byoh.sh apply mywindows 2

# Method 2: User config file (overrides project defaults)
echo "WMCO_IDENTIFIER_TYPE=dns" >> ~/.config/byoh-provisioner/config
./byoh.sh apply mywindows 2

# Method 3: Inline environment variable
WMCO_IDENTIFIER_TYPE=dns ./byoh.sh apply mywindows 2
```

## Platform-Specific Notes

### AWS

- Credentials automatically extracted from cluster secrets
- Supports custom AMI selection
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
├── byoh.sh                 # Main entry point
├── lib/                    # Library modules
│   ├── config.sh          # Configuration loading
│   ├── credentials.sh     # Credential management
│   ├── platform.sh        # Platform detection & config
│   ├── terraform.sh       # Terraform operations
│   └── validation.sh      # Input validation
├── configs/               # Configuration files
│   ├── defaults.conf      # Default values
│   └── examples/          # Platform-specific examples
└── platforms/             # Platform-specific Terraform
    ├── aws/
    ├── azure/
    ├── gcp/
    ├── vsphere/
    ├── nutanix/
    └── none/
```

## Troubleshooting

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

We welcome contributions! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for details on:

- Code of conduct
- Development setup
- Pull request process
- Testing requirements

## Security

For security issues, please see [SECURITY.md](SECURITY.md).

## License

Apache License 2.0. See [LICENSE](LICENSE) for details.

## Project Status

Version: 1.0.0

This is a production-ready, vendor-neutral project suitable for upstream use.

## Support

- **Issues**: Report bugs or request features via [GitHub Issues](https://github.com/openshift/terraform-windows-provisioner/issues)
- **Documentation**: See [docs/](docs/) for comprehensive guides
- **Examples**: See [configs/examples/](configs/examples/) for configuration examples

## Acknowledgments

This project is designed to work seamlessly with:
- OpenShift Windows Container Support
- Windows Machine Config Operator (WMCO)
- Kubernetes Windows node support

## Roadmap

- [ ] Additional cloud platform support
- [ ] Enhanced monitoring and metrics
- [ ] Integration tests for all platforms
- [ ] Helm chart for Kubernetes deployment
- [ ] Web UI for configuration

---

