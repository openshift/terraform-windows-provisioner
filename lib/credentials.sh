#!/bin/bash
# Credential management module
# Handles loading credentials from multiple sources

# Generate a cryptographically secure random password
# Azure requires 3 out of 4: lowercase, uppercase, digit, special character
# Password must be 8-123 characters
function generate_random_password() {
    # Generate a base64 string and extract characters to ensure all types are present
    local base=$(openssl rand -base64 32 | tr -dc 'a-zA-Z0-9')

    # Ensure we have at least one of each required type
    local lower="abc"
    local upper="XYZ"
    local digit="123"
    local special="!@#"

    # Combine: 3 lowercase + 3 uppercase + 3 digits + 3 special + 12 random = 24 chars total
    echo "${lower}${upper}${digit}${special}${base:0:12}"
}

# Generate random instance name suffix
function generate_random_suffix() {
    echo "$(dd if=/dev/urandom bs=1 count=50 2>/dev/null | tr -dc 'a-z0-9' | head -c 5)"
}

# Get Windows admin username based on platform
# Arguments:
#   $1 - Platform name (aws, azure, gcp, vsphere, nutanix, none)
# Returns: Default username for the platform (user can override via WINC_ADMIN_USERNAME)
function get_windows_admin_username() {
    local platform="$1"

    # Check if user has explicitly set a username
    local user_defined=$(get_config "WINC_ADMIN_USERNAME")
    if [[ -n "$user_defined" ]]; then
        echo "$user_defined"
        return 0
    fi

    # Return platform-specific default
    if [[ "$platform" == "azure" ]]; then
        echo "capi"
    else
        echo "Administrator"
    fi
}

# Extract SSH public key from cloud-private-key secret
function get_ssh_public_key_from_secret() {
    local wmco_namespace
    wmco_namespace=$(get_wmco_namespace)

    if [[ -z "$wmco_namespace" ]]; then
        log "Warning: WMCO namespace not found. Cannot extract SSH public key from cloud-private-key secret."
        return 1
    fi

    log "Extracting SSH public key from cloud-private-key secret in namespace: $wmco_namespace"

    # Get the private key from the secret
    local private_key=$(oc get secret cloud-private-key -n "$wmco_namespace" -o jsonpath='{.data.private-key\.pem}' 2>/dev/null | base64 -d)

    if [[ -z "$private_key" ]]; then
        log "Warning: cloud-private-key secret not found in namespace $wmco_namespace"
        return 1
    fi

    # Extract the public key from the private key using ssh-keygen
    # Write to temp file to avoid stdin permission issues
    local temp_key_file=$(mktemp)
    echo "$private_key" > "$temp_key_file"
    chmod 600 "$temp_key_file"

    local public_key=$(ssh-keygen -y -f "$temp_key_file" 2>/dev/null)
    rm -f "$temp_key_file"

    if [[ -z "$public_key" ]]; then
        log "Warning: Failed to extract public key from private key"
        return 1
    fi

    echo "$public_key"
    return 0
}

# Validate SSH public key format and length
# Returns 0 if valid, 1 if invalid
function validate_ssh_public_key() {
    local key="$1"

    # Check if key is empty
    [[ -z "$key" ]] && return 1

    # Check if key starts with a valid type (ssh-rsa, ssh-ed25519, ecdsa-sha2-nistp256, etc.)
    [[ ! "$key" =~ ^(ssh-rsa|ssh-ed25519|ecdsa-sha2-nistp) ]] && return 1

    # Check minimum length (ssh-rsa keys should be at least 200 chars, typically 400-600)
    # A truncated key would be much shorter
    if [[ "$key" =~ ^ssh-rsa ]]; then
        [[ ${#key} -lt 200 ]] && return 1
    fi

    # Valid
    return 0
}

# Extract SSH public key from MachineConfig
# For platforms using Ignition (GCP, etc.) where SSH keys are in MachineConfig
# Returns the SSH public key on success, exits with 1 on failure
function get_ssh_public_key_from_machineconfig() {
    log "Attempting to extract SSH public key from MachineConfig..."

    # Try common MachineConfig names for worker SSH keys
    local machineconfig=$(oc get machineconfig -o name 2>/dev/null | grep -E '(worker-ssh|99-worker-ssh|ssh)' | head -1)

    if [[ -z "$machineconfig" ]]; then
        log "No SSH-related MachineConfig found"
        return 1
    fi

    log "Found MachineConfig: $machineconfig"

    # Extract SSH key from MachineConfig (Ignition format)
    local ssh_key=$(oc get "$machineconfig" -o jsonpath='{.spec.config.passwd.users[?(@.name=="core")].sshAuthorizedKeys[0]}' 2>/dev/null)

    if [[ -z "$ssh_key" ]]; then
        log "No SSH public key found in MachineConfig"
        return 1
    fi

    # Validate before returning to catch truncated keys
    if ! validate_ssh_public_key "$ssh_key"; then
        log "Warning: Extracted SSH key from MachineConfig is invalid or truncated (length: ${#ssh_key} chars)"
        return 1
    fi

    echo "$ssh_key"
    return 0
}

# Extract SSH public key from Linux MachineSet userdata
# For platforms using cloud-init (AWS, Azure) where SSH keys are embedded in userdata
# Returns the SSH public key on success, exits with 1 on failure
function get_ssh_public_key_from_machineset() {
    log "Attempting to extract SSH public key from Linux MachineSet userdata..."

    # Find LINUX (worker) MachineSet - NOT Windows!
    # WMCO uses the same SSH key for Windows nodes that's in Linux worker userdata
    local machineset=$(oc get machineset -n openshift-machine-api -o name 2>/dev/null | grep -i worker | grep -v windows | head -1)

    if [[ -z "$machineset" ]]; then
        log "No Linux MachineSet found (platform may be UPI/none)"
        return 1
    fi

    log "Found MachineSet: $machineset"

    # Get userdata secret name
    local userdata_secret=$(oc get "$machineset" -n openshift-machine-api -o jsonpath='{.spec.template.spec.providerSpec.value.userDataSecret.name}' 2>/dev/null)

    if [[ -z "$userdata_secret" ]]; then
        log "No userdata secret found in MachineSet (platform may not use MachineSets)"
        return 1
    fi

    # Extract and decode userdata
    local userdata=$(oc get secret "$userdata_secret" -n openshift-machine-api -o jsonpath='{.data.userData}' 2>/dev/null | base64 -d)

    if [[ -z "$userdata" ]]; then
        log "Failed to extract userdata from secret"
        return 1
    fi

    # Extract SSH public key from userdata (supports ssh-rsa, ssh-ed25519, ecdsa-sha2)
    local ssh_key=$(echo "$userdata" | grep -oP '(ssh-rsa|ssh-ed25519|ecdsa-sha2-nistp[0-9]+) [A-Za-z0-9+/=]+' | head -1)

    if [[ -z "$ssh_key" ]]; then
        log "No SSH public key found in MachineSet userdata"
        return 1
    fi

    # Validate before returning to catch truncated keys
    if ! validate_ssh_public_key "$ssh_key"; then
        log "Warning: Extracted SSH key from MachineSet is invalid or truncated (length: ${#ssh_key} chars)"
        return 1
    fi

    echo "$ssh_key"
    return 0
}

# Load Windows credentials from environment or config file
function load_windows_credentials() {
    local winc_password=$(get_config "WINC_ADMIN_PASSWORD")
    local winc_ssh_key=$(get_config "WINC_SSH_PUBLIC_KEY")

    if [[ -z "$winc_password" || -z "$winc_ssh_key" ]]; then
        log "Windows credentials not found in environment or config file"
        log "Checking legacy credentials file..."

        # Check legacy credentials file for backward compatibility
        local legacy_creds_file="${HOME}/.config/winc/credentials"
        if [[ -f "$legacy_creds_file" ]]; then
            log "Loading credentials from legacy file: $legacy_creds_file"
            source "$legacy_creds_file"
            winc_password=$(get_config "WINC_ADMIN_PASSWORD")
            winc_ssh_key=$(get_config "WINC_SSH_PUBLIC_KEY")
        fi
    fi

    # If password is still not set, auto-generate one
    if [[ -z "$winc_password" ]]; then
        log "WINC_ADMIN_PASSWORD not set. Generating random password..."
        winc_password=$(generate_random_password)
        log "Random password generated. It will be displayed at the end of provisioning."
    fi

    # SSH Key Loading Priority:
    # 1. User-provided (env/config) - allows override
    # 2. WMCO cloud-private-key secret (DEFAULT - the ONLY key that matters!)
    #
    # Why not MachineSet/MachineConfig?
    # - Those keys are for Linux nodes and may differ from WMCO's key
    # - WMCO always uses cloud-private-key secret for Windows SSH authentication
    # - We must use the same key WMCO uses, not the Linux node keys

    local ssh_key_source=""

    # Priority 1: Validate user-provided SSH key if one was found
    if [[ -n "$winc_ssh_key" ]]; then
        if ! validate_ssh_public_key "$winc_ssh_key"; then
            log "Warning: User-provided WINC_SSH_PUBLIC_KEY is invalid or truncated (length: ${#winc_ssh_key} chars)"
            log "This can happen if the config file has line breaks in the SSH key"
            log "Falling back to automatic SSH key extraction..."
            winc_ssh_key=""  # Clear the invalid key
        else
            # Verify user-provided key matches WMCO cloud-private-key secret
            log "User-provided SSH key found. Verifying against WMCO cloud-private-key secret..."
            local wmco_ssh_key=$(get_ssh_public_key_from_secret || true)

            if [[ -n "$wmco_ssh_key" ]]; then
                if [[ "$winc_ssh_key" == "$wmco_ssh_key" ]]; then
                    log "✅ User-provided SSH key matches WMCO cloud-private-key secret"
                    ssh_key_source="user config/environment (verified against WMCO)"
                else
                    log "⚠️  WARNING: User-provided SSH key DOES NOT MATCH WMCO cloud-private-key secret!"
                    log "User key fingerprint:"
                    echo "$winc_ssh_key" | ssh-keygen -lf - 2>/dev/null | sed 's/^/  /' || log "  (unable to generate fingerprint)"
                    log "WMCO key fingerprint:"
                    echo "$wmco_ssh_key" | ssh-keygen -lf - 2>/dev/null | sed 's/^/  /' || log "  (unable to generate fingerprint)"
                    log ""
                    log "This WILL cause BYOH nodes to fail to join the cluster!"
                    log "WMCO will not be able to SSH to the instances using the configured authorized_keys."
                    log ""
                    log "Recommendation: Use WMCO's cloud-private-key automatically (this is the only key that will work)"
                    log "Using WMCO cloud-private-key secret automatically..."
                    winc_ssh_key="$wmco_ssh_key"
                    ssh_key_source="WMCO cloud-private-key secret (auto-selected due to mismatch)"
                fi
            else
                log "Unable to extract WMCO key for verification. Using user-provided key without verification."
                ssh_key_source="user config/environment (unverified)"
            fi
        fi
    fi

    # Priority 2 (DEFAULT): Extract public key from WMCO's cloud-private-key secret
    # This is the definitive source - WMCO uses this private key for SSH authentication
    if [[ -z "$winc_ssh_key" ]]; then
        log "Extracting SSH public key from WMCO cloud-private-key secret..."
        winc_ssh_key=$(get_ssh_public_key_from_secret || true)

        if [[ -n "$winc_ssh_key" ]]; then
            ssh_key_source="WMCO cloud-private-key secret"
            log "Successfully extracted SSH key from ${ssh_key_source} (length: ${#winc_ssh_key} chars)"
        fi
    fi

    # Validate SSH key is loaded (password is now optional - auto-generated if missing)
    if [[ -z "$winc_ssh_key" ]]; then
        error "WINC_SSH_PUBLIC_KEY is required but not set. Please set it via environment variable, config file, or ensure cloud-private-key secret exists in WMCO namespace."
    fi

    # Final validation of the SSH key
    if ! validate_ssh_public_key "$winc_ssh_key"; then
        error "WINC_SSH_PUBLIC_KEY is invalid. Please check the format and ensure it's a complete SSH public key."
    fi

    # Export for use in Terraform
    export WINC_ADMIN_PASSWORD="$winc_password"
    export WINC_SSH_PUBLIC_KEY="$winc_ssh_key"

    log "Windows credentials loaded successfully"
    log "SSH public key validated (${#winc_ssh_key} characters)"
}

# Export cloud provider credentials from cluster secrets
function export_cloud_credentials() {
    local platform="$1"

    log "Exporting cloud credentials for platform: $platform"

    case $platform in
        "aws")
            export_aws_credentials
            ;;
        "gcp")
            export_gcp_credentials
            ;;
        "azure")
            export_azure_credentials
            ;;
        "vsphere")
            export_vsphere_credentials
            ;;
        "nutanix")
            export_nutanix_credentials
            ;;
        "none")
            # Platform "none": Trust that AWS credentials are configured
            # Terraform AWS provider will auto-discover credentials from environment
            log "Platform 'none' - AWS credentials will be auto-discovered by Terraform"
            ;;
        *)
            error "Platform ${platform} not supported for credential export"
            ;;
    esac

    log "Cloud credentials exported successfully for platform: $platform"
}

# AWS credential export
function export_aws_credentials() {
    if [[ -z "${AWS_ACCESS_KEY:-}" ]] || [[ -z "${AWS_SECRET_ACCESS_KEY:-}" ]]; then
        log "AWS credentials not in environment, attempting to load from cluster secrets..."

        local aws_key=$(oc -n kube-system get secret aws-creds -o=jsonpath='{.data.aws_access_key_id}' 2>/dev/null | base64 -d)
        local aws_secret=$(oc -n kube-system get secret aws-creds -o=jsonpath='{.data.aws_secret_access_key}' 2>/dev/null | base64 -d)

        if [[ -z "$aws_key" ]] || [[ -z "$aws_secret" ]]; then
            error "Failed to load AWS credentials from cluster secrets"
        fi

        export AWS_ACCESS_KEY_ID="$aws_key"
        export AWS_SECRET_ACCESS_KEY="$aws_secret"
    fi
}

# GCP credential export
function export_gcp_credentials() {
    if [[ -z "${GOOGLE_CREDENTIALS:-}" ]]; then
        log "GCP credentials not in environment, attempting to load from cluster secrets..."

        local gcp_creds=$(oc -n openshift-machine-api get secret gcp-cloud-credentials -o=jsonpath='{.data.service_account\.json}' 2>/dev/null | base64 -d)

        if [[ -z "$gcp_creds" ]]; then
            error "Failed to load GCP credentials from cluster secrets"
        fi

        export GOOGLE_CREDENTIALS="$gcp_creds"
    fi
}

# Azure credential export
function export_azure_credentials() {
    if [[ -z "${ARM_CLIENT_ID:-}" ]] || [[ -z "${ARM_CLIENT_SECRET:-}" ]]; then
        log "Azure credentials not in environment, attempting to load from cluster secrets..."

        local creds=$(oc -n kube-system get secret azure-credentials -o json 2>/dev/null)

        if [[ -z "$creds" ]]; then
            error "Failed to load Azure credentials from cluster secrets"
        fi

        local client_id=$(echo "$creds" | jq -r '.data.azure_client_id' | base64 -d)
        local client_secret=$(echo "$creds" | jq -r '.data.azure_client_secret' | base64 -d)
        local subscription_id=$(echo "$creds" | jq -r '.data.azure_subscription_id' | base64 -d)
        local tenant_id=$(echo "$creds" | jq -r '.data.azure_tenant_id' | base64 -d)
        local resource_prefix=$(echo "$creds" | jq -r '.data.azure_resource_prefix' | base64 -d)
        local resourcegroup=$(echo "$creds" | jq -r '.data.azure_resourcegroup' | base64 -d)

        export ARM_CLIENT_ID="$client_id"
        export ARM_CLIENT_SECRET="$client_secret"
        export ARM_SUBSCRIPTION_ID="$subscription_id"
        export ARM_TENANT_ID="$tenant_id"
        export ARM_RESOURCE_PREFIX="$resource_prefix"
        export ARM_RESOURCEGROUP="$resourcegroup"
    fi

    # Ensure all 6 required variables are set
    # If any are missing (e.g., when credentials come from CI environment), load from secret
    local missing_vars=()
    [[ -z "${ARM_CLIENT_ID:-}" ]] && missing_vars+=("ARM_CLIENT_ID")
    [[ -z "${ARM_CLIENT_SECRET:-}" ]] && missing_vars+=("ARM_CLIENT_SECRET")
    [[ -z "${ARM_SUBSCRIPTION_ID:-}" ]] && missing_vars+=("ARM_SUBSCRIPTION_ID")
    [[ -z "${ARM_TENANT_ID:-}" ]] && missing_vars+=("ARM_TENANT_ID")
    [[ -z "${ARM_RESOURCE_PREFIX:-}" ]] && missing_vars+=("ARM_RESOURCE_PREFIX")
    [[ -z "${ARM_RESOURCEGROUP:-}" ]] && missing_vars+=("ARM_RESOURCEGROUP")

    if [[ ${#missing_vars[@]} -gt 0 ]]; then
        log "Missing Azure variables: ${missing_vars[*]}, loading from cluster secret..."

        [[ -z "${ARM_CLIENT_ID:-}" ]] && export ARM_CLIENT_ID=$(oc -n kube-system get secret azure-credentials -o=jsonpath='{.data.azure_client_id}' 2>/dev/null | base64 -d || echo "")
        [[ -z "${ARM_CLIENT_SECRET:-}" ]] && export ARM_CLIENT_SECRET=$(oc -n kube-system get secret azure-credentials -o=jsonpath='{.data.azure_client_secret}' 2>/dev/null | base64 -d || echo "")
        [[ -z "${ARM_SUBSCRIPTION_ID:-}" ]] && export ARM_SUBSCRIPTION_ID=$(oc -n kube-system get secret azure-credentials -o=jsonpath='{.data.azure_subscription_id}' 2>/dev/null | base64 -d || echo "")
        [[ -z "${ARM_TENANT_ID:-}" ]] && export ARM_TENANT_ID=$(oc -n kube-system get secret azure-credentials -o=jsonpath='{.data.azure_tenant_id}' 2>/dev/null | base64 -d || echo "")
        [[ -z "${ARM_RESOURCE_PREFIX:-}" ]] && export ARM_RESOURCE_PREFIX=$(oc -n kube-system get secret azure-credentials -o=jsonpath='{.data.azure_resource_prefix}' 2>/dev/null | base64 -d || echo "")
        [[ -z "${ARM_RESOURCEGROUP:-}" ]] && export ARM_RESOURCEGROUP=$(oc -n kube-system get secret azure-credentials -o=jsonpath='{.data.azure_resourcegroup}' 2>/dev/null | base64 -d || echo "")

        # Verify all required variables are now set
        if [[ -z "${ARM_CLIENT_ID:-}" ]] || [[ -z "${ARM_CLIENT_SECRET:-}" ]] || [[ -z "${ARM_SUBSCRIPTION_ID:-}" ]] || \
           [[ -z "${ARM_TENANT_ID:-}" ]] || [[ -z "${ARM_RESOURCE_PREFIX:-}" ]] || [[ -z "${ARM_RESOURCEGROUP:-}" ]]; then
            error "Failed to load all required Azure credentials from cluster secret. Ensure azure-credentials secret exists in kube-system namespace with all required fields."
        fi

        log "Successfully loaded all Azure credentials: ARM_CLIENT_ID, ARM_CLIENT_SECRET, ARM_SUBSCRIPTION_ID, ARM_TENANT_ID, ARM_RESOURCE_PREFIX, ARM_RESOURCEGROUP"
    fi
}

# vSphere credential export
function export_vsphere_credentials() {
    if [[ -z "${VSPHERE_USER:-}" ]] || [[ -z "${VSPHERE_PASSWORD:-}" ]] || [[ -z "${VSPHERE_SERVER:-}" ]]; then
        log "vSphere credentials not in environment, attempting to load from cluster secrets..."

        # Get vSphere server from Windows machineset
        local vsphere_server=$(oc get machineset.machine.openshift.io -n openshift-machine-api -o=jsonpath="{.items[?(@.spec.template.metadata.labels.machine\.openshift\.io\/os-id=='Windows')].spec.template.spec.providerSpec.value.workspace.server}" 2>/dev/null)

        if [[ -z "$vsphere_server" ]]; then
            error "Failed to get vSphere server from Windows machineset. Ensure Windows machineset exists."
        fi

        log "Found vSphere server from machineset: $vsphere_server"

        # Escape dots for jsonpath (replace . with \.)
        local vsphere_server_escaped=$(echo "${vsphere_server}" | sed 's/\./\\./g')

        # Get credentials using the server name as the key prefix
        local vsphere_user=$(oc -n kube-system get secret vsphere-creds -o=jsonpath="{.data.${vsphere_server_escaped}\.username}" 2>/dev/null | base64 -d)
        local vsphere_password=$(oc -n kube-system get secret vsphere-creds -o=jsonpath="{.data.${vsphere_server_escaped}\.password}" 2>/dev/null | base64 -d)

        if [[ -z "$vsphere_user" ]] || [[ -z "$vsphere_password" ]]; then
            error "Failed to load vSphere credentials from cluster secrets. Expected keys: ${vsphere_server}.username and ${vsphere_server}.password"
        fi

        export VSPHERE_USER="$vsphere_user"
        export VSPHERE_PASSWORD="$vsphere_password"
        export VSPHERE_SERVER="$vsphere_server"

        log "Successfully loaded vSphere credentials for server: $vsphere_server"
    fi
}

# Nutanix credential export
function export_nutanix_credentials() {
    if [[ -z "${NUTANIX_USERNAME:-}" ]] || [[ -z "${NUTANIX_PASSWORD:-}" ]]; then
        log "Nutanix credentials not in environment, attempting to load from cluster secrets..."

        local nutanix_creds=$(oc -n openshift-machine-api get secret nutanix-credentials -o=jsonpath='{.data.credentials}' 2>/dev/null | base64 -d)

        if [[ -z "$nutanix_creds" ]]; then
            error "Failed to load Nutanix credentials from cluster secrets"
        fi

        local nutanix_user=$(echo "$nutanix_creds" | jq -r '.[0].data.prismCentral.username')
        local nutanix_pass=$(echo "$nutanix_creds" | jq -r '.[0].data.prismCentral.password')

        export NUTANIX_USERNAME="$nutanix_user"
        export NUTANIX_PASSWORD="$nutanix_pass"
    fi
}

# Validate AWS credentials for "none" platform (UPI/baremetal)
# Supports multiple authentication methods for different CI/CD environments
function validate_aws_local_credentials() {
    # Method 1: Check for AWS profile with shared credentials file (CI systems like Jenkins)
    if [[ -n "${AWS_PROFILE:-}" ]] && [[ -n "${AWS_SHARED_CREDENTIALS_FILE:-}" ]]; then
        log "AWS credentials configured via profile '${AWS_PROFILE}' with shared credentials file"
        # Ensure they're exported for Terraform
        export AWS_PROFILE
        export AWS_SHARED_CREDENTIALS_FILE
        return 0
    fi

    # Method 2: Check if credentials are in environment variables (direct credentials)
    if [[ -n "${AWS_ACCESS_KEY_ID:-}" ]] && [[ -n "${AWS_SECRET_ACCESS_KEY:-}" ]]; then
        log "AWS credentials found in environment variables"

        # Check for session token (needed for SAML/STS temporary credentials)
        if [[ -n "${AWS_SESSION_TOKEN:-}" ]]; then
            log "AWS session token found (temporary/SAML credentials)"
        elif [[ -n "${AWS_SECURITY_TOKEN:-}" ]]; then
            log "AWS security token found (temporary/SAML credentials)"
            # Some tools use AWS_SESSION_TOKEN, ensure both are set
            export AWS_SESSION_TOKEN="${AWS_SECURITY_TOKEN}"
        fi

        return 0
    fi

    # Method 3: Check for AWS profile with default credentials file
    if [[ -n "${AWS_PROFILE:-}" ]] && [[ -f "$HOME/.aws/credentials" ]]; then
        log "AWS credentials configured via profile '${AWS_PROFILE}' with ~/.aws/credentials"
        export AWS_PROFILE
        return 0
    fi

    # Method 4: Check for default AWS credentials file
    if [[ -f "$HOME/.aws/credentials" ]]; then
        log "AWS credentials will be read from ~/.aws/credentials by Terraform"
        return 0
    fi

    # No valid credentials found
    error "AWS credentials not found. For platform 'none' (UPI/baremetal), you must configure one of:
  1. AWS Profile: Set AWS_PROFILE and AWS_SHARED_CREDENTIALS_FILE (or use ~/.aws/credentials)
  2. Environment variables: AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, and AWS_SESSION_TOKEN (if using SAML/temporary credentials)
  3. AWS CLI: Run 'aws configure' to set up ~/.aws/credentials

See: https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-files.html"
}
