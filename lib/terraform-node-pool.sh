# Create node pool ConfigMap for test isolation
# This allows tests to allocate nodes individually instead of using all nodes at once
function create_node_pool_configmap() {
    local templates_dir="$1"
    local platform="$2"

    log "Creating node pool ConfigMap for Windows instances..."

    local wmco_namespace
    wmco_namespace=$(get_wmco_namespace)

    if [[ -z "$wmco_namespace" ]]; then
        error "Failed to get WMCO namespace. Is the Windows Machine Config Operator installed?"
    fi

    log "Using WMCO namespace: $wmco_namespace"

    local config_file="${templates_dir}/byoh_node_pool_cm.yaml"

    # Change to templates directory to run terraform output
    cd "$templates_dir" || error "Failed to change to templates directory: ${templates_dir}"

    # Determine identifier type (IP or DNS/hostname) from configuration
    local identifier_type
    identifier_type=$(get_config "WMCO_IDENTIFIER_TYPE" "ip")

    log "Node pool identifier type: $identifier_type"

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
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    log "Creating node pool entries for identifiers: $(echo $identifiers | tr '\n' ' ')"

    # Create ConfigMap YAML header
    cat > "$config_file" << EOF
kind: ConfigMap
apiVersion: v1
metadata:
  name: windows-node-pool
  namespace: ${wmco_namespace}
data:
EOF

    # Add each node to the pool with available status
    for identifier in $identifiers; do
        # Remove quotes if present
        identifier="${identifier%\"}"
        identifier="${identifier#\"}"

        # Node pool entry format
        cat >> "$config_file" << EOF
  ${identifier}: |
    status: available
    username: ${username}
    address-type: ${identifier_type}
    platform: ${platform}
    test-id:
    allocated-at:
    last-updated: ${timestamp}
EOF
    done

    log "Node pool ConfigMap file created: ${config_file}"

    # Apply or patch ConfigMap
    if oc get configmap windows-node-pool -n "$wmco_namespace" &>/dev/null; then
        log "Node pool ConfigMap already exists, patching with new entries..."

        # Extract and update each entry
        for identifier in $identifiers; do
            identifier="${identifier%\"}"
            identifier="${identifier#\"}"

            # Check if entry already exists
            local existing_status
            existing_status=$(oc get configmap windows-node-pool -n "$wmco_namespace" -o jsonpath="{.data['${identifier}']}" 2>/dev/null | grep "^status:" | awk '{print $2}')

            # Only add if not already in pool, or if status is unavailable
            if [[ -z "$existing_status" ]] || [[ "$existing_status" == "unavailable" ]]; then
                log "Adding/updating node pool entry: ${identifier}"

                # Use strategic merge patch to add/update entry
                local entry_data="status: available
username: ${username}
address-type: ${identifier_type}
platform: ${platform}
test-id:
allocated-at:
last-updated: ${timestamp}"

                oc patch configmap windows-node-pool -n "$wmco_namespace" \
                    --type merge \
                    -p "{\"data\":{\"${identifier}\":\"${entry_data}\"}}" \
                    || error "Failed to patch node pool ConfigMap for ${identifier}"
            else
                log "Node ${identifier} already in pool with status: ${existing_status}"
            fi
        done

        log "Node pool ConfigMap updated successfully"
    else
        log "Node pool ConfigMap does not exist, creating new one..."
        oc create -f "$config_file" || error "Failed to create node pool ConfigMap"
        log "Node pool ConfigMap created successfully"
    fi

    log "Node pool ready with $(echo $identifiers | wc -w) nodes"
}

# Delete node pool ConfigMap
function delete_node_pool_configmap() {
    local templates_dir="$1"

    log "Removing nodes from node pool ConfigMap..."

    local wmco_namespace
    wmco_namespace=$(get_wmco_namespace)

    if [[ -z "$wmco_namespace" ]]; then
        log "Warning: Failed to get WMCO namespace, skipping node pool cleanup"
        return 0
    fi

    # Check if node pool exists
    if ! oc get configmap windows-node-pool -n "$wmco_namespace" &>/dev/null; then
        log "Node pool ConfigMap does not exist, nothing to clean"
        return 0
    fi

    # Change to templates directory to run terraform output
    cd "$templates_dir" || error "Failed to change to templates directory: ${templates_dir}"

    local terraform_cmd="${TERRAFORM_BIN:-terraform}"
    local identifiers=""

    # Try to get identifiers from Terraform output (may fail if already destroyed)
    local identifier_type
    identifier_type=$(get_config "WMCO_IDENTIFIER_TYPE" "ip")

    if [[ "$identifier_type" == "dns" ]]; then
        identifiers=$($terraform_cmd output -json instance_hostname 2>/dev/null | jq -r '.[]' 2>/dev/null)
    fi

    if [[ -z "$identifiers" ]]; then
        identifiers=$($terraform_cmd output -json instance_ip 2>/dev/null | jq -r '.[]' 2>/dev/null)
    fi

    if [[ -z "$identifiers" ]]; then
        log "Warning: Could not get identifiers from Terraform, node pool entries will remain"
        log "You may need to manually clean the node pool ConfigMap"
        return 0
    fi

    # Remove each node from the pool
    for identifier in $identifiers; do
        identifier="${identifier%\"}"
        identifier="${identifier#\"}"

        log "Removing ${identifier} from node pool"

        # Use JSON patch to remove the entry
        oc patch configmap windows-node-pool -n "$wmco_namespace" \
            --type=json \
            -p="[{\"op\": \"remove\", \"path\": \"/data/${identifier}\"}]" \
            2>/dev/null || log "Warning: Failed to remove ${identifier} from node pool (may not exist)"
    done

    log "Nodes removed from pool successfully"
}
