#!/bin/bash

# BYOH Provisioner - Bring Your Own Host for Windows Nodes
# A generic, configurable tool for provisioning Windows nodes across multiple cloud platforms
#
# Usage: ./byoh.sh [ACTION] [NAME] [NUM_WORKERS] [FOLDER_SUFFIX] [WINDOWS_VERSION]
#
# For more information, run: ./byoh.sh help

set -euo pipefail

# Script metadata
declare -r SCRIPT_VERSION="1.0.0"
declare -r SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load library modules
source "${SCRIPT_DIR}/lib/config.sh"
source "${SCRIPT_DIR}/lib/credentials.sh"
source "${SCRIPT_DIR}/lib/platform.sh"
source "${SCRIPT_DIR}/lib/validation.sh"
source "${SCRIPT_DIR}/lib/terraform.sh"

# Helper functions
function log() {
    echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')] $*" >&2
}

function error() {
    log "ERROR: $*" >&2
    exit 1
}

function show_help() {
    cat << 'EOF'
BYOH Provisioner - Bring Your Own Host for Windows Nodes

Usage:
    ./byoh.sh [ACTION] [NAME] [NUM_WORKERS] [FOLDER_SUFFIX] [WINDOWS_VERSION]

Actions:
    apply       - Create Windows instances and configure them (default)
    destroy     - Remove Windows instances and clean up resources
    arguments   - Show Terraform arguments that would be used
    configmap   - Create/update ConfigMap for Windows instances
    clean       - Remove temporary directories and files
    help        - Show this help message

Parameters:
    NAME            Name prefix for BYOH instances, will append -0, -1, etc.
                    Default: "byoh-winc"

    NUM_WORKERS     Number of Windows worker nodes to create
                    Default: 2

    FOLDER_SUFFIX   Suffix to append to the temporary folder
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
    ./byoh.sh apply winc-byoh 4

    # Multiple platform-specific runs
    ./byoh.sh apply byoh-winc 2 '-az2019'    # Azure 2019
    ./byoh.sh apply byoh-winc 2 '-az2022'    # Azure 2022

    # Show Terraform arguments without applying
    ./byoh.sh arguments byoh-winc 2

    # Destroy instances
    ./byoh.sh destroy byoh-winc 2

Configuration:
    Configuration can be provided via:
    1. Environment variables (highest priority)
    2. User config file: ~/.config/byoh-provisioner/config
    3. Project config file: ./configs/defaults.conf
    4. Built-in defaults (lowest priority)

    Key configuration variables:
    - WINC_ADMIN_PASSWORD: Windows administrator password (required)
    - WINC_SSH_PUBLIC_KEY: SSH public key for remote access (required)
    - WINDOWS_ADMIN_USERNAME: Windows username (default: Administrator)
    - AZURE_VM_EXTENSION_HANDLER_VERSION: Azure VM extension version
    - ENVIRONMENT_TAG: Environment tag for resources

    To create a user config file:
        mkdir -p ~/.config/byoh-provisioner
        cp configs/examples/defaults.conf.example ~/.config/byoh-provisioner/config
        chmod 600 ~/.config/byoh-provisioner/config
        # Edit the file with your credentials

Prerequisites:
    - OpenShift cluster with KUBECONFIG exported
    - Terraform >= 1.0.0
    - oc CLI tool
    - jq for JSON processing
    - base64 command-line tool

Notes:
    - Platform is auto-detected from cluster configuration
    - Cloud credentials are automatically extracted from cluster secrets
    - Windows credentials must be provided via config or environment variables

For more information:
    - GitHub: https://github.com/your-org/terraform-windows-provisioner
    - Documentation: ./docs/

EOF
}

# Parse command line arguments
action="${1:-apply}"
byoh_name="${2:-byoh-winc}"
num_byoh="${3:-2}"
tmp_folder_suffix="${4:-}"
win_version="${5:-2022}"

# Main execution
function main() {
    log "BYOH Provisioner v${SCRIPT_VERSION}"

    # Show help and exit
    if [[ "$action" == "help" ]]; then
        show_help
        exit 0
    fi

    # Load configuration
    log "Loading configuration..."
    load_all_configs

    # Validate inputs
    validate_inputs "$action" "$byoh_name" "$num_byoh" "$win_version"

    # Skip platform detection and prerequisites for clean action
    if [[ "$action" == "clean" ]]; then
        local tmp_dir="$(get_config 'BYOH_TMP_DIR' '/tmp/terraform_byoh')"
        local templates_dir="${tmp_dir}/*${tmp_folder_suffix}"

        log "Cleaning up directories matching: ${templates_dir}"
        rm -rf ${templates_dir}
        log "Cleanup completed"
        exit 0
    fi

    # Validate prerequisites
    validate_prerequisites

    # Detect platform
    local platform
    platform=$(get_platform)
    log "Detected platform: $platform"

    # Platform-specific validation
    validate_platform_requirements "$platform" "$byoh_name"

    # Setup templates directory
    local tmp_dir="$(get_config 'BYOH_TMP_DIR' '/tmp/terraform_byoh')"
    local templates_dir="${tmp_dir}${platform}${tmp_folder_suffix}"

    # Load Windows credentials
    if [[ "$action" != "arguments" ]]; then
        load_windows_credentials
    fi

    # Export cloud provider credentials
    if [[ "$action" == "apply" || "$action" == "destroy" || "$action" == "configmap" ]]; then
        export_cloud_credentials "$platform"
    fi

    # Execute action
    case "$action" in
        "apply")
            log "Starting provisioning workflow..."
            handle_templates_dir "$templates_dir" "apply" "$platform"
            terraform_init "$templates_dir"

            # Write tfvars file for the platform
            case "$platform" in
                "aws")
                    write_aws_tfvars "$templates_dir" "$byoh_name" "$num_byoh" "$win_version"
                    ;;
                "gcp")
                    write_gcp_tfvars "$templates_dir" "$byoh_name" "$num_byoh"
                    ;;
                "azure")
                    write_azure_tfvars "$templates_dir" "$byoh_name" "$num_byoh" "$win_version"
                    ;;
                "vsphere")
                    write_vsphere_tfvars "$templates_dir" "$byoh_name" "$num_byoh" "$win_version"
                    ;;
                "nutanix")
                    write_nutanix_tfvars "$templates_dir" "$byoh_name" "$num_byoh" "$win_version"
                    ;;
                "none")
                    write_none_tfvars "$templates_dir" "$byoh_name" "$num_byoh"
                    ;;
                *)
                    error "Unsupported platform: ${platform}"
                    ;;
            esac

            terraform_apply "$templates_dir"

            # Create ConfigMap unless explicitly skipped
            if [[ "$(get_config 'SKIP_CONFIGMAP_CREATION' 'false')" != "true" ]]; then
                create_configmap "$templates_dir" "$platform"
                log "Provisioning completed successfully!"
                log "Windows instances are ready and registered with WMCO"
            else
                log "Provisioning completed successfully!"
                log "ConfigMap creation skipped (SKIP_CONFIGMAP_CREATION=true)"
                log "Run './byoh.sh configmap' to create ConfigMap manually"
            fi
            ;;

        "destroy")
            log "Starting destruction workflow..."
            if [[ ! -d "$templates_dir" ]]; then
                error "Directory ${templates_dir} not found. Did you run ./byoh.sh apply first?"
            fi

            # Check if terraform state file exists
            if [[ ! -f "${templates_dir}/terraform.tfstate" ]]; then
                log "WARNING: terraform.tfstate not found. Terraform may not have anything to destroy."
            fi

            # Regenerate minimal tfvars for destroy (terraform needs vars defined, but values aren't used)
            case $platform in
                "aws")
                    write_aws_tfvars "$templates_dir" "$byoh_name" "$num_byoh" "$win_version" "true"
                    ;;
                *)
                    # Other platforms don't need special handling
                    ;;
            esac

            delete_configmap "$templates_dir"
            terraform_destroy "$templates_dir"
            cleanup_templates_dir "$templates_dir"
            log "Destruction completed successfully!"
            ;;

        "configmap")
            log "Creating/updating ConfigMap..."
            if [[ ! -d "$templates_dir" ]]; then
                error "Directory ${templates_dir} not found. Did you run ./byoh.sh apply first?"
            fi
            create_configmap "$templates_dir" "$platform"
            log "ConfigMap created/updated successfully!"
            ;;

        "arguments")
            log "Terraform arguments for ${platform}:"
            echo "$terraform_args"
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
