# Prow CI Integration

This tool is integrated into OpenShift Prow CI via the step-registry in the [openshift/release](https://github.com/openshift/release) repository.

## Overview

The BYOH provisioner is available as reusable step-registry components that can be used in Prow CI workflows for Windows Container testing.

## Step-Registry Components

The integration is implemented in `openshift/release` at:

```
ci-operator/step-registry/
├── windows/byoh/provision/     # Provision Windows BYOH nodes
└── windows/byoh/destroy/       # Cleanup Windows BYOH nodes
```

## Usage in Workflows

### Basic Usage

Include the BYOH provisioning steps in your workflow:

```yaml
steps:
  - ref: windows-byoh-provision
  - ref: windows-e2e-operator-test-byoh  # Your tests here
  - ref: windows-byoh-destroy
```

### Configuration

Configure via environment variables:

```yaml
env:
  - name: WINC_ADMIN_PASSWORD
    valueFrom:
      secretKeyRef:
        name: windows-credentials
        key: admin-password
  - name: BYOH_INSTANCE_NAME
    value: "test-winc"
  - name: BYOH_NUM_WORKERS
    value: "2"
  - name: BYOH_WINDOWS_VERSION
    value: "2022"
```

## Existing Chains

BYOH provisioning is integrated into all Windows Container testing chains:

- `cucushift-installer-rehearse-aws-ipi-ovn-winc-provision`
- `cucushift-installer-rehearse-azure-ipi-ovn-winc-provision`
- `cucushift-installer-rehearse-gcp-ipi-ovn-winc-provision`
- `cucushift-installer-rehearse-vsphere-ipi-ovn-winc-provision`
- `cucushift-installer-rehearse-nutanix-ipi-ovn-winc-provision`
- `cucushift-installer-rehearse-aws-upi-ovn-winc-provision` (platform "none")

## Platform Support

All platforms are supported automatically:

| Platform | Support | Credential Source |
|----------|---------|-------------------|
| AWS | ✅ | `CLUSTER_PROFILE_DIR/.awscred` |
| Azure | ✅ | `CLUSTER_PROFILE_DIR/osServicePrincipal.json` |
| GCP | ✅ | `CLUSTER_PROFILE_DIR/gce.json` |
| vSphere | ✅ | Cluster secrets |
| Nutanix | ✅ | Cluster secrets |
| Platform "none" | ✅ | Local AWS credentials |

Credentials are automatically detected from the cluster profile provided by Prow.

## How It Works

### Provision Step

1. Detects the platform from the cluster infrastructure.
2. Loads the cloud credentials from the `CLUSTER_PROFILE_DIR` directory.
3. Extracts the Windows SSH key from the WMCO `cloud-private-key` secret.
4. Clones the terraform-windows-provisioner repository.
5. Runs provisioning via the `byoh.sh apply` command.
6. Exports the instance information to `${SHARED_DIR}` for WMCO tests.

### Destroy Step

1. Reads the work directory from provision step.
2. Runs the cleanup via `byoh.sh destroy` command.
3. Removes the temporary files.

## Integration with WMCO Tests

The provisioner exports instance information in the format expected by WMCO BYOH e2e tests:

```bash
${SHARED_DIR}/<ip>_windows_instance.txt:
  username: Administrator
```

This is compatible with existing `windows-e2e-operator-test-byoh` tests.

## Local Development

For local testing and development:

### Using Docker/Podman

```bash
# Build container image
make build

# Run locally with your cluster
podman run -it --rm \
  -v ~/.kube:/root/.kube:ro \
  -e KUBECONFIG=/root/.kube/config \
  -e WINC_ADMIN_PASSWORD='YourPassword' \
  quay.io/openshift/byoh-provisioner:latest \
  apply test 2
```

### Direct Script Usage

```bash
# Clone the repository
git clone https://github.com/openshift/terraform-windows-provisioner.git
cd terraform-windows-provisioner

# Set credentials
export WINC_ADMIN_PASSWORD="YourPassword123!"
export WINC_SSH_PUBLIC_KEY="$(cat ~/.ssh/id_rsa.pub)"

# Run provisioning
./byoh.sh apply test 2

# Run tests...

# Cleanup
./byoh.sh destroy test 2
```

## References

- **Step-Registry Source**: https://github.com/openshift/release/tree/master/ci-operator/step-registry/windows/byoh
- **Example Chains**: https://github.com/openshift/release/tree/master/ci-operator/step-registry/cucushift/installer/rehearse
- **Prow Documentation**: https://docs.prow.k8s.io/
- **OpenShift CI**: https://docs.ci.openshift.org/

## Contributing

To modify the Prow CI integration:

1. Make changes to the step-registry components in the `openshift/release` repository.
2. Test with the `/pj-rehearse` command.
3. Submit PR to `openshift/release` repository.

For changes to the provisioner itself:

1. Make changes in this repository.
2. The step-registry will automatically use the latest version from `main` branch.

## Support

- **Step-Registry Issues**: Create issues in [openshift/release](https://github.com/openshift/release/issues).
- **Provisioner Issues**: Create issues in [terraform-windows-provisioner](https://github.com/openshift/terraform-windows-provisioner/issues).
- **Slack**: `#forum-ocp-winc` or `#forum-ocp-testplatform`
