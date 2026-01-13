#!/bin/bash
# Configuration loading and management module
# Loads configuration from multiple sources with proper priority

# Configuration file locations
declare -r USER_CONFIG_FILE="${HOME}/.config/byoh-provisioner/config"
declare -r PROJECT_CONFIG_FILE="$(dirname "$(dirname "${BASH_SOURCE[0]}")")/configs/defaults.conf"

# Track which variables were set in environment before loading configs
# Using space-delimited string for bash 3.x compatibility (no associative arrays)
ENV_VARS_BEFORE_CONFIG=""

# Load configuration from file
# Arguments:
#   $1 - Configuration file path
function load_config_file() {
    local config_file="$1"

    if [[ -f "$config_file" ]]; then
        log "Loading configuration from: $config_file"
        # Source the file safely - only lines with valid KEY=VALUE format
        while IFS= read -r line; do
            # Skip comments and empty lines
            [[ "$line" =~ ^[[:space:]]*# ]] && continue
            [[ -z "$line" ]] && continue

            # Only process lines with = sign (valid KEY=VALUE format)
            [[ ! "$line" =~ = ]] && continue

            # Extract key and value
            key="${line%%=*}"
            value="${line#*=}"

            # Remove leading/trailing whitespace from key using sed
            key=$(echo "$key" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')

            # Skip if key is empty
            [[ -z "$key" ]] && continue

            # Remove quotes from value if present
            value="${value%\"}"
            value="${value#\"}"
            value="${value%\'}"
            value="${value#\'}"

            # Only export if not set in environment BEFORE config loading
            # This allows user config to override defaults, but environment to override everything
            if [[ ! " ${ENV_VARS_BEFORE_CONFIG} " =~ " ${key} " ]]; then
                export "$key=$value"
            fi
        done < "$config_file"
    fi
}

# Get configuration value with priority order
# Priority: Environment Variable > User Config > Project Config > Default
# Arguments:
#   $1 - Variable name
#   $2 - Default value (optional)
function get_config() {
    local var_name="$1"
    local default_value="${2:-}"

    # Check if already set as environment variable
    if [[ -n "${!var_name:-}" ]]; then
        echo "${!var_name}"
        return 0
    fi

    # Return default if provided
    if [[ -n "$default_value" ]]; then
        echo "$default_value"
        return 0
    fi

    # Return empty string if nothing found
    echo ""
}

# Load all configuration files in priority order
function load_all_configs() {
    # Capture environment variables before loading config files
    # These will have highest priority and won't be overwritten
    # Using space-delimited string for bash 3.x compatibility (no associative arrays)
    local config_vars=(
        "BYOH_LOG_LEVEL" "BYOH_TMP_DIR" "TERRAFORM_MIN_VERSION"
        "WINDOWS_CONTAINER_LOGS_PORT" "WMCO_NAMESPACE" "WMCO_IDENTIFIER_TYPE"
        "WINC_ADMIN_PASSWORD" "WINC_SSH_PUBLIC_KEY" "WINC_ADMIN_USERNAME"
        "AZURE_VM_EXTENSION_HANDLER_VERSION" "AZURE_2019_IMAGE_VERSION" "AZURE_2022_IMAGE_VERSION"
        "AZURE_WINDOWS_SKU" "AZURE_WINDOWS_IMAGE_VERSION"
        "AWS_INSTANCE_TYPE" "AWS_PROFILE" "AWS_WINDOWS_AMI" "AWS_REGION"
        "AZURE_INSTANCE_SIZE" "GCP_MACHINE_TYPE"
        "AWS_ROOT_VOLUME_SIZE" "AWS_ROOT_VOLUME_TYPE"
        "AZURE_DISK_SIZE_GB" "GCP_BOOT_DISK_SIZE_GB"
        "VSPHERE_WINDOWS_TEMPLATE" "NUTANIX_WINDOWS_IMAGE"
        "ENVIRONMENT_TAG" "MANAGED_BY_TAG"
    )

    for var in "${config_vars[@]}"; do
        if [[ -n "${!var:-}" ]]; then
            ENV_VARS_BEFORE_CONFIG="${ENV_VARS_BEFORE_CONFIG} ${var}"
        fi
    done

    # Load project defaults first
    if [[ -f "$PROJECT_CONFIG_FILE" ]]; then
        load_config_file "$PROJECT_CONFIG_FILE"
    fi

    # Load user config (overrides project defaults)
    if [[ -f "$USER_CONFIG_FILE" ]]; then
        load_config_file "$USER_CONFIG_FILE"
    fi

    # Configuration priority: Environment Variables > User Config > Project Config
    log "Configuration loaded successfully"
}

# Create default user config file
function create_user_config() {
    local config_dir="$(dirname "$USER_CONFIG_FILE")"

    if [[ ! -d "$config_dir" ]]; then
        mkdir -p "$config_dir" || error "Failed to create config directory: $config_dir"
    fi

    if [[ ! -f "$USER_CONFIG_FILE" ]]; then
        cat > "$USER_CONFIG_FILE" << 'EOF'
# BYOH Provisioner User Configuration
# This file is sourced by the provisioner and can override default settings

# Logging
# BYOH_LOG_LEVEL=INFO

# Terraform
# BYOH_TMP_DIR=/tmp/terraform_byoh

# Windows Credentials
# WINC_ADMIN_PASSWORD="YourSecurePassword"
# WINC_SSH_PUBLIC_KEY="ssh-rsa AAAA..."

# Windows Settings
# WINDOWS_ADMIN_USERNAME - Platform-specific (Azure: capi, Others: Administrator)
# WINDOWS_CONTAINER_LOGS_PORT=10250

# WMCO (Windows Machine Config Operator) Configuration
# WMCO_NAMESPACE=openshift-windows-machine-config-operator
# WMCO_IDENTIFIER_TYPE=ip  # Use 'ip' or 'dns' for ConfigMap identifiers

# Azure-specific
# AZURE_VM_EXTENSION_HANDLER_VERSION=1.9
# AZURE_2019_IMAGE_VERSION=latest
# AZURE_2022_IMAGE_VERSION=latest

# AWS Configuration
# AWS_PROFILE - For SAML/SSO, set to your profile name (e.g., "saml")
#               Leave empty for CI/CD using environment variables
# AWS_PROFILE=saml

# Instance Tags
# ENVIRONMENT_TAG=production
# MANAGED_BY_TAG=terraform
EOF
        chmod 600 "$USER_CONFIG_FILE"
        log "Created user configuration file: $USER_CONFIG_FILE"
    else
        log "User configuration file already exists: $USER_CONFIG_FILE"
    fi
}

# Validate configuration
function validate_config() {
    log "Validating configuration..."

    # Check for required credentials
    local winc_password=$(get_config "WINC_ADMIN_PASSWORD")
    local winc_ssh_key=$(get_config "WINC_SSH_PUBLIC_KEY")

    if [[ -z "$winc_password" ]]; then
        log "Warning: WINC_ADMIN_PASSWORD not set. This is required for Windows instances."
    fi

    if [[ -z "$winc_ssh_key" ]]; then
        log "Warning: WINC_SSH_PUBLIC_KEY not set. This is required for SSH access."
    fi

    return 0
}
