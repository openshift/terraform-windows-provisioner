#!/bin/bash
# Terraform operations module

# Get WMCO namespace - uses configured value or auto-detects
function get_wmco_namespace() {
    local configured_namespace
    configured_namespace=$(get_config "WMCO_NAMESPACE" "")

    # If namespace is configured, verify it exists
    if [[ -n "$configured_namespace" ]]; then
        if oc get namespace "$configured_namespace" &>/dev/null; then
            echo "$configured_namespace"
            return 0
        else
            log "Warning: Configured namespace '$configured_namespace' not found. Attempting auto-detection..."
        fi
    fi

    # Auto-detect by finding WMCO deployment
    local detected_namespace
    detected_namespace=$(oc get deployment --all-namespaces -o=jsonpath="{.items[?(@.metadata.name=='windows-machine-config-operator')].metadata.namespace}" 2>/dev/null)

    if [[ -n "$detected_namespace" ]]; then
        echo "$detected_namespace"
        return 0
    fi

    # Return empty if not found
    return 1
}

# Handle templates directory setup
function handle_templates_dir() {
    local templates_dir="$1"
    local action="$2"
    local platform="$3"
    local script_dir="$(dirname "$(dirname "${BASH_SOURCE[0]}")")"

    if [[ "$action" == "apply" ]]; then
        if [[ -d "$templates_dir" ]]; then
            log "Warning: Directory ${templates_dir} already exists"
            log "This may contain Terraform state from a previous run"
            log "Do you want to remove it and start fresh? (yes/no)"
            read -p "Answer: " answer

            case $answer in
                "yes")
                    log "Removing existing directory: ${templates_dir}"
                    rm -rf "$templates_dir" || error "Failed to remove directory: ${templates_dir}"
                    mkdir -p "$templates_dir" || error "Failed to create directory: ${templates_dir}"
                    cp -R "${script_dir}/${platform}/." "$templates_dir" || error "Failed to copy templates"
                    ;;
                "no")
                    log "Using existing directory: ${templates_dir}"
                    log "Terraform will reuse existing state"
                    ;;
                *)
                    error "Invalid answer: ${answer}. Please answer 'yes' or 'no'"
                    ;;
            esac
        else
            log "Creating templates directory: ${templates_dir}"
            mkdir -p "$templates_dir" || error "Failed to create directory: ${templates_dir}"
            cp -R "${script_dir}/${platform}/." "$templates_dir" || error "Failed to copy templates"
        fi
    fi
}

# Create ConfigMap for Windows instances
function create_configmap() {
    local templates_dir="$1"
    local platform="$2"

    log "Creating ConfigMap for Windows instances..."

    local wmco_namespace
    wmco_namespace=$(get_wmco_namespace)

    if [[ -z "$wmco_namespace" ]]; then
        error "Failed to get WMCO namespace. Is the Windows Machine Config Operator installed?"
    fi

    log "Using WMCO namespace: $wmco_namespace"

    local config_file="${templates_dir}/byoh_cm.yaml"

    # Change to templates directory to run terraform output
    cd "$templates_dir" || error "Failed to change to templates directory: ${templates_dir}"

    # Create ConfigMap YAML
    cat > "$config_file" << EOF
kind: ConfigMap
apiVersion: v1
metadata:
  name: windows-instances
  namespace: ${wmco_namespace}
data:
EOF

    # Determine identifier type (IP or DNS/hostname) from configuration
    local identifier_type
    identifier_type=$(get_config "WMCO_IDENTIFIER_TYPE" "ip")

    log "ConfigMap identifier type: $identifier_type"

    local terraform_cmd="${TERRAFORM_BIN:-terraform}"
    local identifiers=""

    # Get identifiers based on configured type
    if [[ "$identifier_type" == "dns" ]]; then
        # Try to get DNS hostnames from Terraform output
        identifiers=$($terraform_cmd output -json instance_hostname 2>/dev/null | jq -r '.[]' 2>/dev/null)

        if [[ -z "$identifiers" ]]; then
            log "Warning: instance_hostname output not available in Terraform, falling back to IP addresses"
            identifier_type="ip"
            identifiers=$($terraform_cmd output -json instance_ip 2>/dev/null | jq -r '.[]')
        fi
    else
        # Default to IP addresses
        identifiers=$($terraform_cmd output -json instance_ip 2>/dev/null | jq -r '.[]')
    fi

    if [[ -z "$identifiers" ]]; then
        error "Failed to get instance identifiers from Terraform output"
    fi

    local username=$(get_user_name "$platform")

    log "Creating ConfigMap entries for identifiers: $(echo $identifiers | tr '\n' ' ')"

    for identifier in $identifiers; do
        # Remove quotes if present
        identifier="${identifier%\"}"
        identifier="${identifier#\"}"

        cat >> "$config_file" << EOF
  ${identifier}: |-
    username=${username}
EOF
    done

    log "ConfigMap file created: ${config_file}"

    # Apply ConfigMap
    if oc get configmap windows-instances -n "$wmco_namespace" &>/dev/null; then
        log "ConfigMap already exists, deleting and recreating..."
        oc delete configmap windows-instances -n "$wmco_namespace" || log "Warning: Failed to delete existing ConfigMap"
    fi

    oc create -f "$config_file" || error "Failed to create ConfigMap"

    log "ConfigMap created successfully"
}

# Run Terraform init
function terraform_init() {
    local templates_dir="$1"
    local terraform_cmd="${TERRAFORM_BIN:-terraform}"

    log "Initializing Terraform in: ${templates_dir}"

    cd "$templates_dir" || error "Failed to change to templates directory: ${templates_dir}"

    if ! $terraform_cmd init; then
        error "Terraform init failed"
    fi

    log "Terraform initialized successfully"
}

# Run Terraform apply
function terraform_apply() {
    local templates_dir="$1"
    local terraform_cmd="${TERRAFORM_BIN:-terraform}"

    log "Running Terraform apply (using terraform.auto.tfvars)..."

    cd "$templates_dir" || error "Failed to change to templates directory: ${templates_dir}"

    if ! $terraform_cmd apply --auto-approve; then
        error "Terraform apply failed"
    fi

    log "Terraform apply completed successfully"
}

# Run Terraform destroy
function terraform_destroy() {
    local templates_dir="$1"
    local terraform_cmd="${TERRAFORM_BIN:-terraform}"

    log "Running Terraform destroy (using terraform.auto.tfvars)..."

    cd "$templates_dir" || error "Failed to change to templates directory: ${templates_dir}"

    if ! $terraform_cmd destroy --auto-approve; then
        error "Terraform destroy failed"
    fi

    log "Terraform destroy completed successfully"
}

# Clean up templates directory
function cleanup_templates_dir() {
    local templates_dir="$1"

    if [[ -d "$templates_dir" ]]; then
        log "Removing templates directory: ${templates_dir}"
        rm -rf "$templates_dir" || error "Failed to remove directory: ${templates_dir}"
        log "Cleanup completed successfully"
    else
        log "Nothing to clean: ${templates_dir} does not exist"
    fi
}

# Delete ConfigMap
function delete_configmap() {
    local templates_dir="$1"

    log "Deleting ConfigMap..."

    local config_file="${templates_dir}/byoh_cm.yaml"

    if [[ ! -f "$config_file" ]]; then
        log "ConfigMap file not found: ${config_file}"
        return 0
    fi

    local wmco_namespace
    wmco_namespace=$(get_wmco_namespace)

    if [[ -n "$wmco_namespace" ]] && oc get configmap windows-instances -n "$wmco_namespace" &>/dev/null; then
        oc delete -f "$config_file" || log "Warning: Failed to delete ConfigMap"
        log "ConfigMap deleted successfully"
    else
        log "ConfigMap does not exist, skipping deletion"
    fi
}
