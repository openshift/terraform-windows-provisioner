#!/bin/bash

# Script configuration and validation
set -euo pipefail

# Default values and input validation
declare -r SCRIPT_VERSION="1.0.0"
declare -r SUPPORTED_ACTIONS=("apply" "destroy" "arguments" "configmap" "clean" "help")
declare -r SUPPORTED_PLATFORMS=("aws" "gcp" "azure" "vsphere" "nutanix" "none")
declare -r SUPPORTED_WIN_VERSIONS=("2019" "2022")

# Script parameters with defaults
action="${1:-apply}"
byoh_name="${2:-byoh-winc}"
num_byoh="${3:-2}"
tmp_folder_suffix="${4:-}"
win_version="${5:-2022}"

# Helper functions
function log() {
    echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')] $*"
}

function error() {
    log "ERROR: $*" >&2
    exit 1
}

function show_help() {
    cat << EOF
BYOH Script (Bring Your Own Host) - Version ${SCRIPT_VERSION}

Usage: 
    ./byoh.sh [ACTION] [NAME] [NUM_WORKERS] [FOLDER_SUFFIX] [WINDOWS_VERSION]

Actions:
    apply     - Create Windows instances and configure them (default)
    destroy   - Remove Windows instances and clean up resources
    arguments - Show Terraform arguments that would be used
    configmap - Create/update ConfigMap for Windows instances
    clean     - Remove temporary directories and files
    help      - Show this help message

Parameters:
    NAME            Name prefix for BYOH instances, will append -0, -1, etc.
                   Default: "byoh-winc"
    
    NUM_WORKERS    Number of Windows worker nodes to create
                   Default: 2
    
    FOLDER_SUFFIX  Suffix to append to the temporary folder
                   Useful for running multiple instances
                   Default: "" (empty)
    
    WINDOWS_VERSION Windows Server version to use
                   Accepted: 2019, 2022
                   Default: 2022

Supported Platforms:
    - AWS
    - GCP
    - Azure
    - vSphere
    - Nutanix
    - None (baremetal)

Examples:
    # Create single Windows 2019 instance
    ./byoh.sh apply byoh 1 '' 2019

    # Create 4 Windows 2022 instances
    ./byoh.sh apply winc-byoh 4 ''

    # Multiple platform-specific runs
    ./byoh.sh apply byoh-winc 2 '-az2019'    # Azure 2019
    ./byoh.sh apply byoh-winc 2 '-az2022'    # Azure 2022

Notes:
    - Requires OpenShift cluster with proper credentials configured
    - Requires Terraform installed locally
    - Platform is auto-detected from cluster configuration
    - Credentials are automatically exported from cluster secrets

For more information, see: https://github.com/openshift/terraform-windows-provisioner
EOF
}

function validate_inputs() {
    # First validate action as it doesn't depend on platform
    if [[ ! " ${SUPPORTED_ACTIONS[*]} " =~ " ${action} " ]]; then
        error "Unsupported action: ${action}. Supported actions: ${SUPPORTED_ACTIONS[*]}"
    fi

    # Early return for help action
    if [[ "${action}" == "help" ]]; then
        return 0
    fi

    # Skip these validations for certain actions
    if [[ "${action}" != "clean" && "${action}" != "arguments" ]]; then
        # Validate Windows version
        if [[ ! " ${SUPPORTED_WIN_VERSIONS[*]} " =~ " ${win_version} " ]]; then
            error "Unsupported Windows version: ${win_version}. Supported versions: ${SUPPORTED_WIN_VERSIONS[*]}"
        fi

        # Validate number of workers
        if ! [[ "$num_byoh" =~ ^[0-9]+$ ]] || [ "$num_byoh" -lt 1 ]; then
            error "Number of workers must be a positive integer, got: ${num_byoh}"
        fi

        # Validate instance name is not empty
        if [[ -z "$byoh_name" ]]; then
            error "Instance name cannot be empty"
        fi
    fi

    return 0
}

function validate_platform_specific() {
    # Azure-specific validations
    if [[ "$platform" == "azure" ]]; then
        if [[ ${#byoh_name} > 13 ]]; then
            log "Warning: Azure instance names longer than 13 characters will be truncated"
            byoh_name="${byoh_name:0:13}"
        fi
    fi
}

function get_platform() {
    local platform
    platform=$(oc get infrastructure cluster -o=jsonpath="{.status.platformStatus.type}" 2>/dev/null | tr '[:upper:]' '[:lower:]')
    if [[ ! " ${SUPPORTED_PLATFORMS[@]} " =~ " ${platform} " ]]; then
        error "Platform ${platform} not supported. Supported platforms: ${SUPPORTED_PLATFORMS[*]}"
    fi
    echo "$platform"
}

function export_credentials() {
    log "Exporting credentials for platform: $platform"
    
    case $platform in
        "aws")
            AWS_ACCESS_KEY=$(oc -n kube-system get secret aws-creds -o=jsonpath='{.data.aws_access_key_id}' | base64 -d)
            AWS_SECRET_ACCESS_KEY=$(oc -n kube-system get secret aws-creds -o=jsonpath='{.data.aws_secret_access_key}' | base64 -d)
            export AWS_ACCESS_KEY AWS_SECRET_ACCESS_KEY
            ;;
        "gcp")
            GOOGLE_CREDENTIALS=$(oc -n openshift-machine-api get secret gcp-cloud-credentials -o=jsonpath='{.data.service_account\.json}' | base64 -d)
            export GOOGLE_CREDENTIALS
            ;;
        "azure")
            local creds
            creds=$(oc -n kube-system get secret azure-credentials -o json)
            ARM_CLIENT_ID=$(echo "$creds" | jq -r '.data.azure_client_id' | base64 -d)
            ARM_CLIENT_SECRET=$(echo "$creds" | jq -r '.data.azure_client_secret' | base64 -d)
            ARM_SUBSCRIPTION_ID=$(echo "$creds" | jq -r '.data.azure_subscription_id' | base64 -d)
            ARM_TENANT_ID=$(echo "$creds" | jq -r '.data.azure_tenant_id' | base64 -d)
            ARM_RESOURCE_PREFIX=$(echo "$creds" | jq -r '.data.azure_resource_prefix' | base64 -d)
            ARM_RESOURCEGROUP=$(echo "$creds" | jq -r '.data.azure_resourcegroup' | base64 -d)
            export ARM_CLIENT_ID ARM_CLIENT_SECRET ARM_SUBSCRIPTION_ID ARM_TENANT_ID ARM_RESOURCE_PREFIX ARM_RESOURCEGROUP
            ;;
        "vsphere")
            VSPHERE_USER=$(oc -n kube-system get secret vsphere-creds -o=jsonpath='{.data.vcenter\.username}' | base64 -d)
            VSPHERE_PASSWORD=$(oc -n kube-system get secret vsphere-creds -o=jsonpath='{.data.vcenter\.password}' | base64 -d)
            VSPHERE_SERVER=$(oc -n kube-system get secret vsphere-creds -o=jsonpath='{.data.vcenter\.server}' | base64 -d)
            export VSPHERE_USER VSPHERE_PASSWORD VSPHERE_SERVER
            ;;
        "nutanix")
            local nutanix_creds
            nutanix_creds=$(oc -n openshift-machine-api get secret nutanix-credentials -o=jsonpath='{.data.credentials}' | base64 -d)
            NUTANIX_USERNAME=$(echo "$nutanix_creds" | jq -r '.[0].data.prismCentral.username')
            NUTANIX_PASSWORD=$(echo "$nutanix_creds" | jq -r '.[0].data.prismCentral.password')
            export NUTANIX_USERNAME NUTANIX_PASSWORD
            ;;
        "none")
            if [[ ! -f $HOME/.aws/config || ! -f $HOME/.aws/credentials ]]; then
                error "Can't load AWS user credentials. Configure your AWS account following: https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-files.html"
            fi
            ;;
        *)
            error "Platform ${platform} not supported. Aborting execution."
            ;;
    esac

    # Verify credentials were exported successfully
    if [[ $? -ne 0 ]]; then
        error "Failed to export credentials for platform: $platform"
    fi

    log "Successfully exported credentials for platform: $platform"
}

function create_configmap() {
    local templates_dir="$1"
    local wmco_namespace
    
    wmco_namespace=$(oc get deployment --all-namespaces -o=jsonpath="{.items[?(@.metadata.name=='windows-machine-config-operator')].metadata.namespace}")
    [[ -z "$wmco_namespace" ]] && error "Failed to get WMCO namespace"

    local config_file="${templates_dir}/byoh_cm.yaml"
    
    # Create ConfigMap with error handling
    {
        cat << EOF > "$config_file"
kind: ConfigMap
apiVersion: v1
metadata:
  name: windows-instances
  namespace: ${wmco_namespace}
data:
$(
    for ip in $(terraform output --json instance_ip | jq -c '.[]'); do
        echo -e "  ${ip}: |-\n    username=$(get_user_name)"
    done
)
EOF
    } || error "Failed to create ConfigMap file"

    oc create -f "$config_file" || error "Failed to apply ConfigMap"
}

# Main execution
function main() {
    validate_inputs
    
    platform=$(get_platform)
    log "Detected platform: $platform"
    
    validate_platform_specific
    
    export_credentials

    tmp_dir="/tmp/terraform_byoh/"
    templates_dir="${tmp_dir}${platform}${tmp_folder_suffix}"

    case "$action" in
        "apply")
            handle_templates_dir "$templates_dir" "apply"
            export_credentials
            cd "$templates_dir" || error "Failed to change to templates directory"
            terraform init || error "Terraform init failed"
            terraform apply --auto-approve $(get_terraform_arguments) || error "Terraform apply failed"
            create_configmap "$templates_dir"
            log "Successfully applied and configured Windows instances"
            ;;

        "destroy")
            if [[ ! -d "$templates_dir" ]]; then
                error "Directory ${templates_dir} not found. Did you run ./byoh.sh apply first?"
            fi

            # Delete the configmap if exists
            if [[ -e "${templates_dir}/byoh_cm.yaml" ]]; then
                wmco_namespace=$(oc get deployment --all-namespaces -o=jsonpath="{.items[?(@.metadata.name=='windows-machine-config-operator')].metadata.namespace}")
                if oc get cm windows-instances -n "${wmco_namespace}" &>/dev/null; then
                    oc delete -f "${templates_dir}/byoh_cm.yaml" || log "Warning: Failed to delete ConfigMap"
                fi
            fi

            export_credentials
            cd "$templates_dir" || error "Failed to change to templates directory"
            terraform destroy --auto-approve $(get_terraform_arguments) || error "Terraform destroy failed"
            
            rm -rf "$templates_dir"
            log "Successfully destroyed Windows instances and cleaned up resources"
            ;;

        "configmap")
            create_configmap "$templates_dir"
            log "Successfully created ConfigMap"
            ;;

        "clean")
            if [[ -d "$templates_dir" ]]; then
                rm -rf "$templates_dir"
                log "Successfully cleaned up directory: $templates_dir"
            else
                log "Nothing to clean: $templates_dir does not exist"
            fi
            ;;

        "arguments")
            terraform_args=$(get_terraform_arguments)
            echo "$terraform_args"
            log "Successfully retrieved Terraform arguments"
            ;;

        "help")
            show_help
            ;;

        *)
            error "Unsupported action: ${action}. Use: apply, destroy, arguments, clean, configmap, or help"
            ;;
    esac
}

# Execute main with error handling
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    trap 'error "Script failed on line $LINENO"' ERR
    main "$@"
fi