#!/bin/bash
# Platform detection and configuration module

# Supported platforms
declare -ra SUPPORTED_PLATFORMS=("aws" "gcp" "azure" "vsphere" "nutanix" "none")

# Detect platform from cluster
function get_platform() {
    local platform

    platform=$(oc get infrastructure cluster -o=jsonpath="{.status.platformStatus.type}" 2>/dev/null | tr '[:upper:]' '[:lower:]')

    if [[ -z "$platform" ]]; then
        error "Failed to detect platform from cluster"
    fi

    if [[ ! " ${SUPPORTED_PLATFORMS[@]} " =~ " ${platform} " ]]; then
        error "Platform ${platform} not supported. Supported platforms: ${SUPPORTED_PLATFORMS[*]}"
    fi

    echo "$platform"
}

# Get platform-specific username
function get_user_name() {
    local platform="$1"

    case $platform in
        "aws"|"gcp"|"vsphere"|"none"|"nutanix")
            echo "$(get_config 'WINDOWS_ADMIN_USERNAME' 'Administrator')"
            ;;
        "azure")
            echo "$(get_config 'WINDOWS_ADMIN_USERNAME' 'capi')"
            ;;
        *)
            error "Platform ${platform} not supported for username resolution"
            ;;
    esac
}

# Get Terraform arguments for platform
function get_terraform_arguments() {
    local platform="$1"
    local byoh_name="$2"
    local num_byoh="$3"
    local win_version="$4"

    local terraform_args=""

    case $platform in
        "aws")
            terraform_args=$(get_aws_terraform_args "$byoh_name" "$num_byoh")
            ;;
        "gcp")
            terraform_args=$(get_gcp_terraform_args "$byoh_name" "$num_byoh")
            ;;
        "azure")
            terraform_args=$(get_azure_terraform_args "$byoh_name" "$num_byoh" "$win_version")
            ;;
        "vsphere")
            terraform_args=$(get_vsphere_terraform_args "$byoh_name" "$num_byoh" "$win_version")
            ;;
        "nutanix")
            terraform_args=$(get_nutanix_terraform_args "$byoh_name" "$num_byoh" "$win_version")
            ;;
        "none")
            terraform_args=$(get_none_terraform_args "$byoh_name" "$num_byoh")
            ;;
        *)
            error "Platform ${platform} not supported for Terraform arguments"
            ;;
    esac

    echo "$terraform_args"
}

# Write AWS Terraform variables to tfvars file
function write_aws_tfvars() {
    local templates_dir="$1"
    local byoh_name="$2"
    local num_byoh="$3"
    local win_version="${4:-2022}"
    local skip_ami_lookup="${5:-false}"  # Set to true for destroy operations

    local tfvars_file="${templates_dir}/terraform.auto.tfvars"

    # Get hostname from Linux worker nodes (always available)
    local win_machine_hostname=$(oc get nodes -l "node-role.kubernetes.io/worker,windowsmachineconfig.openshift.io/byoh!=true" -o=jsonpath="{.items[0].status.addresses[?(@.type=='Hostname')].address}")

    # Get infrastructure config from Linux Machine API (always available)
    local linux_machine_spec=$(oc get machines -n openshift-machine-api -l machine.openshift.io/cluster-api-machine-role=worker -o=jsonpath='{.items[0].spec}')
    local region=$(echo "$linux_machine_spec" | jq -r '.providerSpec.value.placement.region')
    local cluster_name=$(oc get machines -n openshift-machine-api -l machine.openshift.io/cluster-api-machine-role=worker -o=jsonpath='{.items[0].metadata.labels.machine\.openshift\.io/cluster-api-cluster}')

    # Get Windows AMI (skip for destroy operations - not needed, just use dummy)
    local windows_ami=""
    if [[ "$skip_ami_lookup" == "true" ]]; then
        log "Skipping AMI lookup for destroy operation (using dummy value)"
        windows_ami="ami-dummy-not-used-for-destroy"
    else
        log "Requested Windows version: ${win_version}"

        # Check user override first to allow version-specific AMI selection
        windows_ami=$(get_config "AWS_WINDOWS_AMI" "")
        if [[ -n "$windows_ami" ]]; then
            log "Using user-configured AMI: ${windows_ami}"
        fi

        # If no user override, try AWS API query for specific version
        if [[ -z "$windows_ami" ]]; then
            log "Querying AWS API for Windows Server ${win_version} AMI in region ${region}..."

            if command -v aws &> /dev/null; then
                local image_pattern="Windows_Server-${win_version}-English-Full-Base"
                log "Search pattern: ${image_pattern}*"

                # Add timeout to prevent hanging (30 seconds)
                windows_ami=$(PYTHONWARNINGS='ignore::DeprecationWarning' timeout 30s aws ec2 describe-images \
                    --filters "Name=name,Values=${image_pattern}*" \
                    --region "${region}" \
                    --query 'sort_by(Images, &CreationDate)[-1].[ImageId]' \
                    --output text 2>/dev/null || echo "")

                if [[ -n "$windows_ami" && "$windows_ami" != "None" ]]; then
                    log "Selected Windows ${win_version} AMI: ${windows_ami}"
                else
                    log "AWS API query failed or timed out"
                    windows_ami=""
                fi
            else
                log "AWS CLI not available"
            fi
        fi

        # Fallback to MachineSet AMI if AWS CLI not available or failed
        if [[ -z "$windows_ami" ]]; then
            log "AWS CLI query failed. Attempting to get AMI from Windows MachineSet..."
            windows_ami=$(oc get machineset.machine.openshift.io -n openshift-machine-api -o=jsonpath="{.items[?(@.spec.template.metadata.labels.machine\.openshift\.io\/os-id=='Windows')].spec.template.spec.providerSpec.value.ami.id}" 2>/dev/null)

            if [[ -n "$windows_ami" ]]; then
                log "Found Windows AMI from MachineSet: ${windows_ami}"
            fi
        fi

        # Final error if nothing works
        if [[ -z "$windows_ami" ]]; then
            error "Windows AMI not found. Please either:
  1. Install AWS CLI for automatic AMI discovery, OR
  2. Set AWS_WINDOWS_AMI in your configuration, OR
  3. Create a Windows MachineSet"
        fi
    fi

    # Get configuration values
    local admin_username=$(get_user_name "aws")
    local admin_password=$(get_config "WINC_ADMIN_PASSWORD")
    local ssh_key=$(get_config "WINC_SSH_PUBLIC_KEY")
    local instance_type=$(get_config "AWS_INSTANCE_TYPE" "m5a.large")
    local volume_size=$(get_config "AWS_ROOT_VOLUME_SIZE" "120")
    local volume_type=$(get_config "AWS_ROOT_VOLUME_TYPE" "gp2")
    local env_tag=$(get_config "ENVIRONMENT_TAG" "production")
    local managed_by=$(get_config "MANAGED_BY_TAG" "terraform")
    local container_port=$(get_config "WINDOWS_CONTAINER_LOGS_PORT" "10250")
    local fips_enabled=$(get_config "FIPS_ENABLED" "false")

    cat > "${tfvars_file}" << EOF
# Auto-generated Terraform variables for AWS
winc_number_workers   = ${num_byoh}
winc_machine_hostname = "${win_machine_hostname}"
winc_instance_name    = "${byoh_name}"
winc_worker_ami       = "${windows_ami}"
winc_cluster_name     = "${cluster_name}"
winc_region           = "${region}"
winc_instance_type    = "${instance_type}"
admin_username        = "${admin_username}"
admin_password        = "${admin_password}"
ssh_public_key        = "${ssh_key}"
root_volume_size      = ${volume_size}
root_volume_type      = "${volume_type}"
environment_tag       = "${env_tag}"
managed_by_tag        = "${managed_by}"
container_logs_port   = ${container_port}
fips_enabled          = ${fips_enabled}
EOF
}

# Write GCP Terraform variables to tfvars file
function write_gcp_tfvars() {
    local templates_dir="$1"
    local byoh_name="$2"
    local num_byoh="$3"

    local tfvars_file="${templates_dir}/terraform.auto.tfvars"

    # Get hostname from Linux worker nodes (always available)
    local win_machine_hostname=$(oc get nodes -l "node-role.kubernetes.io/worker,windowsmachineconfig.openshift.io/byoh!=true" -o=jsonpath="{.items[0].status.addresses[?(@.type=='Hostname')].address}" | cut -d "." -f1)

    # Get infrastructure config from Linux Machine API (always available)
    local zone=$(oc get machines -n openshift-machine-api -l machine.openshift.io/cluster-api-machine-role=worker -o=jsonpath='{.items[0].metadata.labels.machine\.openshift\.io/zone}')
    local region=$(oc get infrastructure cluster -o=jsonpath="{.status.platformStatus.gcp.region}")
    local project=$(oc get infrastructure cluster -o=jsonpath="{.status.platformStatus.gcp.projectID}")

    # Get configuration values
    local admin_password=$(get_config "WINC_ADMIN_PASSWORD")
    local ssh_key=$(get_config "WINC_SSH_PUBLIC_KEY")
    local instance_type=$(get_config "GCP_INSTANCE_TYPE" "n1-standard-4")
    local win_version=$(get_config "GCP_WINDOWS_VERSION" "windows-2022-core")
    local admin_username=$(get_config "GCP_ADMIN_USERNAME" "Administrator")
    local fips_enabled=$(get_config "FIPS_ENABLED" "false")

    cat > "${tfvars_file}" << EOF
# Auto-generated Terraform variables for GCP
winc_number_workers   = ${num_byoh}
winc_machine_hostname = "${win_machine_hostname}"
winc_instance_name    = "${byoh_name}"
winc_zone             = "${zone}"
winc_region           = "${region}"
winc_project          = "${project}"
winc_instance_type    = "${instance_type}"
winc_win_version      = "${win_version}"
admin_username        = "${admin_username}"
admin_password        = "${admin_password}"
ssh_public_key        = "${ssh_key}"
fips_enabled          = ${fips_enabled}
EOF
}

# Write Azure Terraform variables to tfvars file
function write_azure_tfvars() {
    local templates_dir="$1"
    local byoh_name="$2"
    local num_byoh="$3"
    local win_version="${4:-2022}"

    local tfvars_file="${templates_dir}/terraform.auto.tfvars"

    # Azure computer name can't take more than 15 characters
    if [[ ${#byoh_name} -gt 13 ]]; then
        log "Warning: Azure instance names longer than 13 characters will be truncated"
        byoh_name="${byoh_name:0:13}"
    fi

    # Get hostname from Linux worker nodes (always available)
    local win_machine_hostname=$(oc get nodes -l "node-role.kubernetes.io/worker,windowsmachineconfig.openshift.io/byoh!=true" -o=jsonpath="{.items[0].metadata.name}")

    # Get infrastructure config from credentials (set by export_azure_credentials)
    local resource_group="${ARM_RESOURCEGROUP}"
    local resource_prefix="${ARM_RESOURCE_PREFIX}"

    # Get Windows SKU (priority: User Config > MachineSet > Default based on version)
    local sku=$(get_config "AZURE_WINDOWS_SKU" "")

    if [[ -z "$sku" ]]; then
        sku=$(oc get machineset.machine.openshift.io -n openshift-machine-api -o=jsonpath="{.items[?(@.spec.template.metadata.labels.machine\.openshift\.io\/os-id=='Windows')].spec.template.spec.providerSpec.value.image.sku}" 2>/dev/null)
    fi

    if [[ -z "$sku" ]]; then
        log "Using default SKU for Windows Server ${win_version}"
        sku="${win_version}-Datacenter-smalldisk"
    fi

    # Get admin username (use platform default: capi for Azure)
    local admin_username=$(get_user_name "azure")

    # Get configuration values
    local admin_password=$(get_config "WINC_ADMIN_PASSWORD")
    local ssh_key=$(get_config "WINC_SSH_PUBLIC_KEY")
    local instance_type=$(get_config "AZURE_INSTANCE_SIZE" "Standard_D2s_v3")
    local vm_extension_version=$(get_config "AZURE_VM_EXTENSION_HANDLER_VERSION" "1.9")
    local env_tag=$(get_config "ENVIRONMENT_TAG" "production")
    local managed_by=$(get_config "MANAGED_BY_TAG" "terraform")
    local container_port=$(get_config "WINDOWS_CONTAINER_LOGS_PORT" "10250")
    local fips_enabled=$(get_config "FIPS_ENABLED" "false")

    # Get image version (priority: User Config > MachineSet > Default "latest")
    local image_version=$(get_config "AZURE_WINDOWS_IMAGE_VERSION" "")

    if [[ -z "$image_version" ]]; then
        image_version=$(oc get machineset.machine.openshift.io -n openshift-machine-api -o=jsonpath="{.items[?(@.spec.template.metadata.labels.machine\.openshift\.io\/os-id=='Windows')].spec.template.spec.providerSpec.value.image.version}" 2>/dev/null)
    fi

    if [[ -z "$image_version" ]]; then
        log "Using default image version: latest"
        image_version="latest"
    fi

    cat > "${tfvars_file}" << EOF
# Auto-generated Terraform variables for Azure
winc_number_workers           = ${num_byoh}
winc_machine_hostname         = "${win_machine_hostname}"
winc_instance_name            = "${byoh_name}"
winc_resource_group           = "${resource_group}"
winc_resource_prefix          = "${resource_prefix}"
winc_worker_sku               = "${sku}"
winc_instance_type            = "${instance_type}"
admin_username                = "${admin_username}"
admin_password                = "${admin_password}"
ssh_public_key                = "${ssh_key}"
vm_extension_handler_version  = "${vm_extension_version}"
windows_image_version         = "${image_version}"
environment_tag               = "${env_tag}"
managed_by_tag                = "${managed_by}"
container_logs_port           = ${container_port}
fips_enabled                  = ${fips_enabled}
EOF
}

# Write vSphere Terraform variables to tfvars file
function write_vsphere_tfvars() {
    local templates_dir="$1"
    local byoh_name="$2"
    local num_byoh="$3"
    local win_version="${4:-2022}"

    local tfvars_file="${templates_dir}/terraform.auto.tfvars"

    # Get hostname from Linux worker nodes (always available)
    local win_machine_hostname=$(oc get nodes -l "node-role.kubernetes.io/worker,windowsmachineconfig.openshift.io/byoh!=true" -o=jsonpath="{.items[0].metadata.name}")

    # Get infrastructure config from Linux Machine API (always available)
    local linux_machine_spec=$(oc get machines -n openshift-machine-api -l machine.openshift.io/cluster-api-machine-role=worker -o=jsonpath='{.items[0].spec.providerSpec.value}')
    local datacenter=$(echo "$linux_machine_spec" | jq -r '.workspace.datacenter')
    local datastore=$(echo "$linux_machine_spec" | jq -r '.workspace.datastore')
    local network=$(echo "$linux_machine_spec" | jq -r '.network.devices[0].networkName')
    local resource_pool=$(echo "$linux_machine_spec" | jq -r '.workspace.resourcePool')

    # Get Windows template (priority: User Config > MachineSet > Error)
    local template=$(get_config "VSPHERE_WINDOWS_TEMPLATE" "")

    if [[ -z "$template" ]]; then
        template=$(oc get machineset.machine.openshift.io -n openshift-machine-api -o=jsonpath="{.items[?(@.spec.template.metadata.labels.machine\.openshift\.io\/os-id=='Windows')].spec.template.spec.providerSpec.value.template}" 2>/dev/null)
    fi

    if [[ -z "$template" ]]; then
        error "vSphere Windows template not found. Please either:
  1. Create a Windows MachineSet, OR
  2. Set VSPHERE_WINDOWS_TEMPLATE in your configuration"
    fi

    local admin_username=$(get_user_name "vsphere")
    local admin_password=$(get_config "WINC_ADMIN_PASSWORD")
    local ssh_key=$(get_config "WINC_SSH_PUBLIC_KEY")
    local fips_enabled=$(get_config "FIPS_ENABLED" "false")

    cat > "${tfvars_file}" << EOF
# Auto-generated Terraform variables for vSphere
winc_number_workers   = ${num_byoh}
winc_machine_hostname = "${win_machine_hostname}"
winc_instance_name    = "${byoh_name}"
winc_vsphere_template = "${template}"
winc_datacenter       = "${datacenter}"
winc_datastore        = "${datastore}"
winc_network          = "${network}"
winc_resource_pool    = "${resource_pool}"
vsphere_user          = "${VSPHERE_USER}"
vsphere_password      = "${VSPHERE_PASSWORD}"
vsphere_server        = "${VSPHERE_SERVER}"
admin_username        = "${admin_username}"
admin_password        = "${admin_password}"
ssh_public_key        = "${ssh_key}"
fips_enabled          = ${fips_enabled}
EOF
}

# Write Nutanix Terraform variables to tfvars file
function write_nutanix_tfvars() {
    local templates_dir="$1"
    local byoh_name="$2"
    local num_byoh="$3"
    local win_version="${4:-2022}"

    local tfvars_file="${templates_dir}/terraform.auto.tfvars"

    # Get hostname from Linux worker nodes (always available)
    local win_machine_hostname=$(oc get nodes -l "node-role.kubernetes.io/worker,windowsmachineconfig.openshift.io/byoh!=true" -o=jsonpath="{.items[0].metadata.name}")

    # Get infrastructure config from Linux Machine API (always available)
    local linux_machine_spec=$(oc get machines -n openshift-machine-api -l machine.openshift.io/cluster-api-machine-role=worker -o=jsonpath='{.items[0].spec.providerSpec.value}')
    local cluster_uuid=$(echo "$linux_machine_spec" | jq -r '.cluster.uuid')
    local subnet_uuid=$(echo "$linux_machine_spec" | jq -r '.subnets[0].uuid')

    # Extract Prism Central endpoint from cloud-provider-config
    local prism_endpoint=$(oc get cm cloud-provider-config -n openshift-config -o jsonpath='{.data.config}' | jq -r '.prismCentral.address')
    local prism_port=$(oc get cm cloud-provider-config -n openshift-config -o jsonpath='{.data.config}' | jq -r '.prismCentral.port')

    # Get Windows image (priority: User Config > MachineSet > Error)
    local image_name=$(get_config "NUTANIX_WINDOWS_IMAGE" "")

    if [[ -z "$image_name" ]]; then
        image_name=$(oc get machineset.machine.openshift.io -n openshift-machine-api -o=jsonpath="{.items[?(@.spec.template.metadata.labels.machine\.openshift\.io\/os-id=='Windows')].spec.template.spec.providerSpec.value.image.name}" 2>/dev/null)
    fi

    if [[ -z "$image_name" ]]; then
        error "Nutanix Windows image not found. Please either:
  1. Create a Windows MachineSet, OR
  2. Set NUTANIX_WINDOWS_IMAGE in your configuration"
    fi

    local admin_username=$(get_user_name "nutanix")
    local admin_password=$(get_config "WINC_ADMIN_PASSWORD")
    local ssh_key=$(get_config "WINC_SSH_PUBLIC_KEY")
    local fips_enabled=$(get_config "FIPS_ENABLED" "false")

    cat > "${tfvars_file}" << EOF
# Auto-generated Terraform variables for Nutanix
winc_number_workers   = ${num_byoh}
winc_machine_hostname = "${win_machine_hostname}"
winc_instance_name    = "${byoh_name}"
winc_cluster_uuid     = "${cluster_uuid}"
subnet_uuid           = "${subnet_uuid}"
primary_windows_image = "${image_name}"
nutanix_endpoint      = "${prism_endpoint}"
nutanix_port          = ${prism_port}
nutanix_username      = "${NUTANIX_USERNAME}"
nutanix_password      = "${NUTANIX_PASSWORD}"
admin_username        = "${admin_username}"
admin_password        = "${admin_password}"
ssh_public_key        = "${ssh_key}"
fips_enabled          = ${fips_enabled}
EOF
}

# Write "none" platform Terraform variables to tfvars file
function write_none_tfvars() {
    local templates_dir="$1"
    local byoh_name="$2"
    local num_byoh="$3"
    local win_version="${4:-2022}"

    local tfvars_file="${templates_dir}/terraform.auto.tfvars"

    # Get Linux node information for platform "none" (UPI/baremetal on AWS)
    local linux_node=$(oc get nodes -l "node-role.kubernetes.io/worker,windowsmachineconfig.openshift.io/byoh!=true" -o=jsonpath="{.items[0].status.addresses[?(@.type=='Hostname')].address}")

    # Construct full DNS name or resolve it via nslookup
    local win_machine_hostname
    local region
    if [[ -n "${AWS_REGION:-}" ]]; then
        # Use AWS_REGION if set
        region="${AWS_REGION}"
        win_machine_hostname="${linux_node}.${region}.compute.internal"
    else
        # Otherwise, resolve via nslookup
        local ip_linux_node=$(oc get node ${linux_node} -o=jsonpath="{.status.addresses[?(@.type=='InternalIP')].address}")
        win_machine_hostname=$(oc debug node/${linux_node} -- nslookup ${ip_linux_node} 2>/dev/null | grep -oP 'name = \K[^.]*.*' | sed 's/\.$//')
        region=$(echo "${win_machine_hostname}" | cut -d "." -f2)
    fi

    local admin_username=$(get_user_name "none")
    local admin_password=$(get_config "WINC_ADMIN_PASSWORD")
    local ssh_key=$(get_config "WINC_SSH_PUBLIC_KEY")
    local instance_type=$(get_config "AWS_INSTANCE_TYPE" "m5a.large")
    local fips_enabled=$(get_config "FIPS_ENABLED" "false")

    cat > "${tfvars_file}" << EOF
# Auto-generated Terraform variables for none/baremetal platform
# AWS credentials are automatically discovered via AWS SDK from:
# - AWS_SHARED_CREDENTIALS_FILE + AWS_PROFILE (Jenkins/flexy)
# - ~/.aws/credentials (local development)
# - Environment variables (CI/CD)
winc_number_workers   = ${num_byoh}
winc_machine_hostname = "${win_machine_hostname}"
winc_instance_name    = "${byoh_name}"
winc_region           = "${region}"
winc_version          = "${win_version}"
winc_instance_type    = "${instance_type}"
admin_username        = "${admin_username}"
admin_password        = "${admin_password}"
ssh_public_key        = "${ssh_key}"
fips_enabled          = ${fips_enabled}
EOF
}

# GCP Terraform arguments
function get_gcp_terraform_args() {
    local byoh_name="$1"
    local num_byoh="$2"

    local win_machine_hostname=$(oc get nodes -l "node-role.kubernetes.io/worker,windowsmachineconfig.openshift.io/byoh!=true" -o=jsonpath="{.items[0].status.addresses[?(@.type=='Hostname')].address}" | cut -d "." -f1)
    local zone=$(oc get machine.machine.openshift.io -n openshift-machine-api -o=jsonpath="{.items[0].metadata.labels.machine\.openshift\.io\/zone}")
    local region=$(oc get infrastructure cluster -o=jsonpath="{.status.platformStatus.gcp.region}")
    local admin_password=$(get_config "WINC_ADMIN_PASSWORD")
    local ssh_key=$(get_config "WINC_SSH_PUBLIC_KEY")

    echo "--var winc_number_workers=${num_byoh} --var winc_machine_hostname=${win_machine_hostname} --var winc_instance_name=${byoh_name} --var winc_zone=${zone} --var winc_region=${region} --var admin_password='${admin_password}' --var ssh_public_key='${ssh_key}'"
}

# Azure Terraform arguments
function get_azure_terraform_args() {
    local byoh_name="$1"
    local num_byoh="$2"
    local win_version="$3"

    # Azure computer name can't take more than 15 characters
    if [[ ${#byoh_name} -gt 13 ]]; then
        log "Warning: Azure instance names longer than 13 characters will be truncated"
        byoh_name="${byoh_name:0:13}"
    fi

    local win_machine_hostname=$(oc get nodes -l "node-role.kubernetes.io/worker,windowsmachineconfig.openshift.io/byoh!=true" -o=jsonpath="{.items[0].metadata.name}")
    local resource_group="${ARM_RESOURCEGROUP}"
    local resource_prefix="${ARM_RESOURCE_PREFIX}"
    local sku="2022-datacenter-smalldisk"

    if [[ "$win_version" == "2019" ]]; then
        sku="2019-datacenter-smalldisk"
    fi

    # Get configuration values
    local admin_username=$(get_user_name "azure")
    local admin_password=$(get_config "WINC_ADMIN_PASSWORD")
    local ssh_key=$(get_config "WINC_SSH_PUBLIC_KEY")
    local instance_type=$(get_config "AZURE_INSTANCE_SIZE" "Standard_D2s_v3")
    local vm_extension_version=$(get_config "AZURE_VM_EXTENSION_HANDLER_VERSION" "1.9")
    local env_tag=$(get_config "ENVIRONMENT_TAG" "production")
    local managed_by=$(get_config "MANAGED_BY_TAG" "terraform")
    local container_port=$(get_config "WINDOWS_CONTAINER_LOGS_PORT" "10250")

    # Get image version (priority: User Config > MachineSet > Default "latest")
    local image_version=$(get_config "AZURE_WINDOWS_IMAGE_VERSION" "")

    if [[ -z "$image_version" ]]; then
        image_version=$(oc get machineset.machine.openshift.io -n openshift-machine-api -o=jsonpath="{.items[?(@.spec.template.metadata.labels.machine\.openshift\.io\/os-id=='Windows')].spec.template.spec.providerSpec.value.image.version}" 2>/dev/null)
    fi

    if [[ -z "$image_version" ]]; then
        log "Using default image version: latest"
        image_version="latest"
    fi

    echo "--var winc_number_workers=${num_byoh} --var winc_machine_hostname=${win_machine_hostname} --var winc_instance_name=${byoh_name} --var winc_resource_group=${resource_group} --var winc_resource_prefix=${resource_prefix} --var winc_worker_sku=${sku} --var winc_instance_type='${instance_type}' --var admin_username='${admin_username}' --var admin_password='${admin_password}' --var ssh_public_key='${ssh_key}' --var vm_extension_handler_version='${vm_extension_version}' --var windows_image_version='${image_version}' --var environment_tag='${env_tag}' --var managed_by_tag='${managed_by}' --var container_logs_port=${container_port}"
}

# vSphere Terraform arguments
function get_vsphere_terraform_args() {
    local byoh_name="$1"
    local num_byoh="$2"
    local win_version="$3"

    local win_machine_hostname=$(oc get nodes -l "node-role.kubernetes.io/worker,windowsmachineconfig.openshift.io/byoh!=true" -o=jsonpath="{.items[0].metadata.name}")

    # Get template from Windows machineset
    local template=$(oc get machineset.machine.openshift.io -n openshift-machine-api -o=jsonpath="{.items[?(@.spec.template.metadata.labels.machine\.openshift\.io\/os-id=='Windows')].spec.template.spec.providerSpec.value.template}")

    local datacenter=$(oc get machineset.machine.openshift.io -n openshift-machine-api -o=jsonpath="{.items[?(@.spec.template.metadata.labels.machine\.openshift\.io\/os-id=='Windows')].spec.template.spec.providerSpec.value.workspace.datacenter}")
    local datastore=$(oc get machineset.machine.openshift.io -n openshift-machine-api -o=jsonpath="{.items[?(@.spec.template.metadata.labels.machine\.openshift\.io\/os-id=='Windows')].spec.template.spec.providerSpec.value.workspace.datastore}")
    local network=$(oc get machineset.machine.openshift.io -n openshift-machine-api -o=jsonpath="{.items[?(@.spec.template.metadata.labels.machine\.openshift\.io\/os-id=='Windows')].spec.template.spec.providerSpec.value.network.devices[0].networkName}")
    local resource_pool=$(oc get machineset.machine.openshift.io -n openshift-machine-api -o=jsonpath="{.items[?(@.spec.template.metadata.labels.machine\.openshift\.io\/os-id=='Windows')].spec.template.spec.providerSpec.value.workspace.resourcePool}")

    # If resourcePool is empty in Windows machineset, fall back to first available machineset
    if [[ -z "$resource_pool" ]]; then
        resource_pool=$(oc get machineset.machine.openshift.io -n openshift-machine-api -o=jsonpath="{.items[0].spec.template.spec.providerSpec.value.workspace.resourcePool}")
    fi

    local admin_username=$(get_user_name "vsphere")
    local admin_password=$(get_config "WINC_ADMIN_PASSWORD")
    local ssh_key=$(get_config "WINC_SSH_PUBLIC_KEY")

    echo "--var winc_number_workers=${num_byoh} --var winc_machine_hostname=${win_machine_hostname} --var winc_instance_name=${byoh_name} --var winc_vsphere_template=${template} --var winc_datacenter=${datacenter} --var winc_datastore=${datastore} --var winc_network=${network} --var winc_resource_pool=${resource_pool} --var vsphere_user=${VSPHERE_USER} --var vsphere_password=${VSPHERE_PASSWORD} --var vsphere_server=${VSPHERE_SERVER} --var admin_username='${admin_username}' --var admin_password='${admin_password}' --var ssh_public_key='${ssh_key}'"
}

# Nutanix Terraform arguments
function get_nutanix_terraform_args() {
    local byoh_name="$1"
    local num_byoh="$2"
    local win_version="$3"

    local win_machine_hostname=$(oc get nodes -l "node-role.kubernetes.io/worker,windowsmachineconfig.openshift.io/byoh!=true" -o=jsonpath="{.items[0].metadata.name}")
    local cluster_uuid=$(oc get machineset.machine.openshift.io -n openshift-machine-api -o=jsonpath="{.items[?(@.spec.template.metadata.labels.machine\.openshift\.io\/os-id=='Windows')].spec.template.spec.providerSpec.value.cluster.uuid}")
    local subnet_uuid=$(oc get machineset.machine.openshift.io -n openshift-machine-api -o=jsonpath="{.items[?(@.spec.template.metadata.labels.machine\.openshift\.io\/os-id=='Windows')].spec.template.spec.providerSpec.value.subnets[0].uuid}")
    local image_name="Windows-Server-${win_version}"
    local admin_password=$(get_config "WINC_ADMIN_PASSWORD")
    local ssh_key=$(get_config "WINC_SSH_PUBLIC_KEY")

    echo "--var winc_number_workers=${num_byoh} --var winc_machine_hostname=${win_machine_hostname} --var winc_instance_name=${byoh_name} --var winc_cluster_uuid=${cluster_uuid} --var winc_subnet_uuid=${subnet_uuid} --var winc_image_name=${image_name} --var admin_password='${admin_password}' --var ssh_public_key='${ssh_key}'"
}

# None (Baremetal) Terraform arguments
function get_none_terraform_args() {
    local byoh_name="$1"
    local num_byoh="$2"

    local win_machine_hostname=$(oc get nodes -l "node-role.kubernetes.io/worker" -o=jsonpath="{.items[0].status.addresses[?(@.type=='Hostname')].address}")
    local region=$(get_config "AWS_DEFAULT_REGION" "us-east-1")
    local admin_password=$(get_config "WINC_ADMIN_PASSWORD")
    local ssh_key=$(get_config "WINC_SSH_PUBLIC_KEY")

    echo "--var winc_number_workers=${num_byoh} --var winc_machine_hostname=${win_machine_hostname} --var winc_instance_name=${byoh_name} --var winc_region=${region} --var admin_password='${admin_password}' --var ssh_public_key='${ssh_key}'"
}
