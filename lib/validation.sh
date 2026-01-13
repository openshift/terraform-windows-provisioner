#!/bin/bash
# Input validation module

# Supported actions and versions
declare -ra SUPPORTED_ACTIONS=("apply" "destroy" "arguments" "configmap" "clean" "help")
declare -ra SUPPORTED_WIN_VERSIONS=("2019" "2022")

# Validate action parameter
function validate_action() {
    local action="$1"

    if [[ ! " ${SUPPORTED_ACTIONS[@]} " =~ " ${action} " ]]; then
        error "Unsupported action: ${action}. Supported actions: ${SUPPORTED_ACTIONS[*]}"
    fi
}

# Validate Windows version
function validate_windows_version() {
    local version="$1"

    if [[ ! " ${SUPPORTED_WIN_VERSIONS[@]} " =~ " ${version} " ]]; then
        error "Unsupported Windows version: ${version}. Supported versions: ${SUPPORTED_WIN_VERSIONS[*]}"
    fi
}

# Validate number of workers
function validate_num_workers() {
    local num_workers="$1"

    if ! [[ "$num_workers" =~ ^[0-9]+$ ]] || [ "$num_workers" -lt 1 ]; then
        error "Number of workers must be a positive integer, got: ${num_workers}"
    fi
}

# Validate instance name
function validate_instance_name() {
    local name="$1"

    if [[ -z "$name" ]]; then
        error "Instance name cannot be empty"
    fi

    # Check for invalid characters
    if [[ ! "$name" =~ ^[a-zA-Z0-9-]+$ ]]; then
        error "Instance name can only contain alphanumeric characters and hyphens, got: ${name}"
    fi
}

# Validate platform-specific requirements
function validate_platform_requirements() {
    local platform="$1"
    local byoh_name="$2"

    case $platform in
        "azure")
            # Azure instance names limited to 13 characters (we add -0, -1 suffix)
            if [[ ${#byoh_name} -gt 13 ]]; then
                log "Warning: Azure instance names longer than 13 characters will be truncated to ${byoh_name:0:13}"
            fi
            ;;
        "vsphere")
            # Validate vSphere environment
            log "Validating vSphere requirements..."
            ;;
        "nutanix")
            # Validate Nutanix environment
            log "Validating Nutanix requirements..."
            ;;
    esac
}

# Validate all inputs
function validate_inputs() {
    local action="$1"
    local byoh_name="$2"
    local num_byoh="$3"
    local win_version="$4"

    # Always validate action
    validate_action "$action"

    # Return early for actions that don't need other validations
    if [[ "$action" == "help" || "$action" == "clean" ]]; then
        return 0
    fi

    # Validate other inputs
    if [[ "$action" != "arguments" ]]; then
        validate_windows_version "$win_version"
        validate_num_workers "$num_byoh"
        validate_instance_name "$byoh_name"
    fi

    return 0
}

# Validate prerequisites (tools and access)
function validate_prerequisites() {
    log "Validating prerequisites..."

    # Use TERRAFORM_BIN environment variable or default to 'terraform'
    local terraform_cmd="${TERRAFORM_BIN:-terraform}"

    # Check for required tools
    local required_tools=("$terraform_cmd" "oc" "jq" "base64")

    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            error "Required tool '${tool}' is not installed. Please install it and try again."
        fi
    done

    # Check Terraform version
    local tf_version=$($terraform_cmd version -json 2>/dev/null | jq -r '.terraform_version' 2>/dev/null || echo "unknown")
    log "Terraform command: $terraform_cmd"
    log "Terraform version: $tf_version"

    # Check cluster access
    if ! oc whoami &> /dev/null; then
        error "Cannot access OpenShift cluster. Please ensure KUBECONFIG is set and you are logged in."
    fi

    local current_user=$(oc whoami)
    log "Connected to cluster as: $current_user"

    log "Prerequisites validated successfully"
}
