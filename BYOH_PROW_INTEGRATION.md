# BYOH Node Pool Integration for Prow CI

## Problem Statement

WC-BYOH tests in `openshift-tests-private` were originally designed to work with ephemeral MachineSets created during test execution. When attempting to use persistent terraform-provisioned BYOH nodes in Prow CI, we encountered architectural incompatibilities:

### What Breaks With Direct ConfigMap Approach

**Current approach** (creates `windows-instances` ConfigMap):
1. Terraform provisions 2 persistent Windows VMs (byoh-0, byoh-1)
2. Creates `windows-instances` ConfigMap with both nodes
3. WMCO configures both nodes
4. Test runs and **deletes the entire ConfigMap** during cleanup
5. WMCO deconfigures **ALL BYOH nodes** on the cluster
6. Next test starts but nodes still reconfiguring → **FAIL**

**Result**: Cascade failures, flaky tests, regression from stable state.

## Solution: Node Pool Integration

The `openshift-tests-private` repository already has a **node pool system** (since ~2024) that allows tests to:
- Allocate ONE node at a time from a shared pool
- Use the node for testing
- Release it back to the pool when done
- **Never delete the ConfigMap globally**

### How It Works

**New approach** (creates `windows-node-pool` ConfigMap):
1. Terraform provisions 2 persistent Windows VMs
2. Creates `windows-node-pool` ConfigMap with both nodes marked `available`
3. Test 1 allocates byoh-0 from pool → creates temporary `windows-instances` with only byoh-0
4. Test 1 completes → releases byoh-0 back to pool
5. Test 2 allocates byoh-1 from pool → creates temporary `windows-instances` with only byoh-1
6. Tests never interfere with each other ✅

## Implementation

### Node Pool ConfigMap Format

```yaml
kind: ConfigMap
apiVersion: v1
metadata:
  name: windows-node-pool
  namespace: openshift-windows-machine-config-operator
data:
  192.168.221.179: |
    status: available
    username: Administrator
    address-type: ip
    platform: vsphere
    test-id:
    allocated-at:
    last-updated: 2026-03-31T12:00:00Z
  192.168.221.181: |
    status: available
    username: Administrator
    address-type: ip
    platform: vsphere
    test-id:
    allocated-at:
    last-updated: 2026-03-31T12:00:00Z
```

### Usage

#### Create Node Pool (instead of windows-instances)

```bash
# Set environment variable to use node pool mode
export USE_NODE_POOL=true

# Provision nodes and create node pool ConfigMap
./byoh.sh apply

# Or create/update just the node pool ConfigMap
./byoh.sh configmap
```

#### Destroy Nodes and Clean Pool

```bash
# Removes nodes from pool and destroys VMs
export USE_NODE_POOL=true
./byoh.sh destroy
```

### Test Integration

No changes needed in `openshift-tests-private`! The existing `setBYOH()` function already:

1. Checks if node pool exists: `isNodePoolEnabled(oc)`
2. Allocates one node: `allocateNodeFromPool(oc, testID, platform, addressType)`
3. Creates temporary `windows-instances` ConfigMap with ONLY that node
4. Waits for node to be Ready
5. Test runs
6. Cleanup releases node: `releaseNodeToPool(oc, nodeAddress, false)`

**File**: `test/extended/winc/utils.go`, lines 1307-1391

## Prow Integration

### Step 1: Update Prow Job Definition

In `ci-operator/config/openshift/release/openshift-release-master-*.yaml`:

```yaml
- as: windows-byoh-provision
  commands: |
    # Enable node pool mode for test isolation
    export USE_NODE_POOL=true

    # Rest of provisioning logic...
    ./byoh.sh apply
  ...
```

### Step 2: Update Cleanup Step

```yaml
- as: windows-byoh-cleanup
  commands: |
    export USE_NODE_POOL=true
    ./byoh.sh destroy
  ...
```

### No Changes Needed To:
- Test code in `openshift-tests-private`
- WMCO configuration
- Node provisioning logic (just ConfigMap format changes)

## Benefits

✅ **Test Isolation**: Each test gets its own node, can't interfere with others
✅ **No Global Deconfiguration**: Node pool preserves all nodes
✅ **Faster Tests**: Nodes stay configured, just reallocate between tests
✅ **Existing Code**: Uses production node pool system already in use
✅ **Clean Architecture**: Tests work identically in Jenkins (MachineSets) and Prow (node pool)

## Migration Path

### Phase 1: Terraform-Windows-Provisioner (This PR)
- ✅ Add `create_node_pool_configmap()` function
- ✅ Add `delete_node_pool_configmap()` function
- ✅ Add `USE_NODE_POOL` environment variable support
- ✅ Update `byoh.sh` to support both modes

### Phase 2: Release Repository
- Update Prow job definitions to set `USE_NODE_POOL=true`
- Test on vSphere and Azure platforms
- Monitor for regressions

### Phase 3: Validation
- Run full WC-BYOH test suite with node pool
- Verify all 5 tests pass consistently
- Compare timing vs MachineSet approach

## Backwards Compatibility

The default behavior remains unchanged (creates `windows-instances` ConfigMap). Node pool mode is opt-in via `USE_NODE_POOL=true`. This allows gradual migration and easy rollback if issues are discovered.

## Related Issues

- **WINC-1835**: Node pool integration for terraform-provisioned nodes
- **WINC-1837**: Original attempt at direct terraform detection (closed due to architectural issues)
- **PR #29631**: Closed PR that attempted to bypass node pool (caused regression)

## Testing

### Local Testing

```bash
# 1. Provision with node pool
export USE_NODE_POOL=true
./byoh.sh apply

# 2. Verify node pool created
oc get configmap windows-node-pool -n openshift-windows-machine-config-operator -o yaml

# 3. Run one BYOH test to verify allocation works
oc get configmap windows-instances -n openshift-windows-machine-config-operator
# Should show ONLY the allocated node

# 4. After test completes, verify node released
oc get configmap windows-node-pool -n openshift-windows-machine-config-operator -o yaml
# Should show node back to "available" status

# 5. Clean up
./byoh.sh destroy
```

### Expected Behavior

**Before test:**
- `windows-node-pool` exists with 2 available nodes
- `windows-instances` does NOT exist

**During test:**
- `windows-node-pool` shows 1 in-use, 1 available
- `windows-instances` exists with ONLY the in-use node

**After test:**
- `windows-node-pool` shows 2 available nodes again
- `windows-instances` deleted by test cleanup

## Future Enhancements

1. **Pool Statistics**: Add pool-available, pool-in-use counters to ConfigMap metadata
2. **Health Checks**: Automatically mark nodes unavailable if NotReady
3. **Lease Timeouts**: Auto-release nodes if test hangs
4. **Multi-Platform**: Support mixed pools (vSphere + Azure nodes)

## References

- Node pool implementation: `openshift-tests-private/test/extended/winc/utils.go:2697-3263`
- Test usage: `openshift-tests-private/test/extended/winc/winc.go` (setBYOH calls)
- Architecture discussion: PR #29631 closing comment
