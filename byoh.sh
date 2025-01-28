#!/bin/bash
# BYOH provisioning script
# $1 : action to perform (apply, destroy, arguments, configmap, clean). Default: apply
# $2 : name for the BYOH instances (default: byoh-winc)
# $3 : number of BYOH workers (default: 2)
# $4 : temporary folder suffix (optional)
# $5 : Windows Server version (2019 or 2022, default: 2022)

set -euo pipefail

# Input arguments and defaults
action="${1:-apply}"
byoh_name="${2:-byoh-winc}"
num_byoh="${3:-2}"
tmp_folder_suffix="${4:-}"
win_version="${5:-2022}"

platform=$(oc get infrastructure cluster -o=jsonpath="{.status.platformStatus.type}" | tr '[:upper:]' '[:lower:]')

# Check SSH_PUBLIC_KEY for required platforms
case $platform in
  "aws"|"azure"|"gcp")
    if [ -z "${SSH_PUBLIC_KEY:-}" ]; then
      echo "ERROR: SSH_PUBLIC_KEY environment variable is not set. Please provide the SSH public key."
      exit 1
    fi
    ;;
  "vsphere"|"nutanix"|"none")
    SSH_PUBLIC_KEY=""
    ;;
  *)
    echo "ERROR: Unsupported platform: $platform"
    exit 1
    ;;
esac

# Export cloud provider credentials
function export_credentials() {
    case $platform in
        "aws")
            AWS_ACCESS_KEY=$(oc -n kube-system get secret aws-creds -o=jsonpath={.data.aws_access_key_id} | base64 -d)
            AWS_SECRET_ACCESS_KEY=$(oc -n kube-system get secret aws-creds -o=jsonpath={.data.aws_secret_access_key} | base64 -d)
            export AWS_ACCESS_KEY AWS_SECRET_ACCESS_KEY
            ;;
        "gcp")
            GOOGLE_CREDENTIALS=$(oc -n openshift-machine-api get secret gcp-cloud-credentials -o=jsonpath='{.data.service_account\.json}' | base64 -d)
            export GOOGLE_CREDENTIALS
            ;;
        "azure")
            ARM_CLIENT_ID=$(oc -n kube-system get secret azure-credentials -o=jsonpath={.data.azure_client_id} | base64 -d)
            ARM_CLIENT_SECRET=$(oc -n kube-system get secret azure-credentials -o=jsonpath={.data.azure_client_secret} | base64 -d)
            ARM_SUBSCRIPTION_ID=$(oc -n kube-system get secret azure-credentials -o=jsonpath={.data.azure_subscription_id} | base64 -d)
            ARM_TENANT_ID=$(oc -n kube-system get secret azure-credentials -o=jsonpath={.data.azure_tenant_id} | base64 -d)
            ARM_RESOURCE_PREFIX=$(oc -n kube-system get secret azure-credentials -o=jsonpath={.data.azure_resource_prefix} | base64 -d)
            ARM_RESOURCEGROUP=$(oc -n kube-system get secret azure-credentials -o=jsonpath={.data.azure_resourcegroup} | base64 -d)
            export ARM_CLIENT_ID ARM_CLIENT_SECRET ARM_SUBSCRIPTION_ID ARM_TENANT_ID ARM_RESOURCE_PREFIX ARM_RESOURCEGROUP
            ;;
        "vsphere")
		    # Fetch all keys dynamically
			SECRET_DATA=$(oc -n kube-system get secret vsphere-creds -o=json | jq -r '.data')
			# Extract the username, password, and server dynamically
			VSPHERE_USER=$(echo "$SECRET_DATA" | jq -r 'to_entries[] | select(.key | test("\\.username$")) | .value' | base64 -d)
            VSPHERE_PASSWORD=$(echo "$SECRET_DATA" | jq -r 'to_entries[] | select(.key | test("\\.password$")) | .value' | base64 -d)
			VSPHERE_SERVER=$(oc get machineset -n openshift-machine-api winworker -o=jsonpath='{.spec.template.spec.providerSpec.value.workspace.server}')	
            export TF_VAR_vsphere_user="$VSPHERE_USER"
            export TF_VAR_vsphere_password="$VSPHERE_PASSWORD"
            export TF_VAR_vsphere_server="$VSPHERE_SERVER" 
            ;;
        "nutanix")
            NUTANIX_CREDS=$(oc -n openshift-machine-api get secret nutanix-credentials -o=jsonpath='{.data.credentials}' | base64 -d)
            NUTANIX_USERNAME=$(echo $NUTANIX_CREDS | jq -r '.[0].data.prismCentral.username')
            NUTANIX_PASSWORD=$(echo $NUTANIX_CREDS | jq -r '.[0].data.prismCentral.password')
            export NUTANIX_USERNAME NUTANIX_PASSWORD
            ;;
        "none")
            if ([ ! -f $HOME/.aws/config ] || [ ! -f $HOME/.aws/credentials ])
            then
                echo "ERROR: Can't load AWS user credentials" >&2
                echo "ERROR: Configure your AWS account following: https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-files.html" >&2
                exit 1
            fi
            ;;
        *)
            echo "ERROR: Platform ${platform} not supported. Aborting execution." >&2
            exit 1
            ;;
    esac
}

# Call the function to export credentials
export_credentials
echo "Credentials exported successfully. Proceeding with the script..."

# Fetch parameters dynamically or use fallback values
function fetch_vsphere_params() {
  windowsTemplate=$(oc get machineset -n openshift-machine-api -o=json | \
    jq -r '.items[] | select(.spec.template.metadata.labels["machine.openshift.io/os-id"]=="Windows") | .spec.template.spec.providerSpec.value.template' || echo "")

  datacenterName=$(oc get machineset -n openshift-machine-api -o=json | \
    jq -r '.items[] | select(.spec.template.metadata.labels["machine.openshift.io/os-id"]=="Windows") | .spec.template.spec.providerSpec.value.workspace.datacenter' || echo "")

  networkName=$(oc get machineset -n openshift-machine-api -o=json | \
    jq -r '.items[] | select(.spec.template.metadata.labels["machine.openshift.io/os-id"]=="Windows") | .spec.template.spec.providerSpec.value.network.devices[0].networkName' || echo "")

  datastoreName=$(oc get machineset -n openshift-machine-api -o=json | \
    jq -r '.items[] | select(.spec.template.metadata.labels["machine.openshift.io/os-id"]=="Windows") | .spec.template.spec.providerSpec.value.workspace.datastore' || echo "")

  resourcePool="${TF_VAR_vsphere_resource_pool:-/DEVQEdatacenter/host/DEVQEcluster/Resources}"

  # Validate resource pool
  if [ -z "$resourcePool" ]; then
    echo "ERROR: vsphere_resource_pool is not set and no default value is available. Aborting."
    exit 1
  fi

  # Validate fetched parameters
  if [ -z "$windowsTemplate" ] || [ -z "$datacenterName" ] || [ -z "$networkName" ] || [ -z "$datastoreName" ] || [ -z "$resourcePool" ]; then
    echo "ERROR: One or more required parameters are missing!"
    exit 1
  fi
}

# Generate Terraform arguments dynamically
function get_terraform_arguments() {
  terraform_args=()
  terraform_args+=("--var=winc_number_workers=${num_byoh:-1}")
  case $platform in
    "aws")
      winMachineHostname=$(oc get nodes -l "node-role.kubernetes.io/worker,windowsmachineconfig.openshift.io/byoh!=true" -o=jsonpath="{.items[0].status.addresses[?(@.type=='Hostname')].address}")
      windowsAmi=$(oc get machineset.machine.openshift.io -n openshift-machine-api -o=jsonpath="{.items[?(@.spec.template.metadata.labels.machine\\.openshift\\.io/os-id=='Windows')].spec.template.spec.providerSpec.value.ami.id}")
      clusterName=$(oc get machineset.machine.openshift.io -n openshift-machine-api -o=jsonpath="{.items[?(@.spec.template.metadata.labels.machine\\.openshift\\.io/os-id=='Windows')].metadata.labels.machine\\.openshift\\.io/cluster-api-cluster}")
      region=$(oc get infrastructure cluster -o=jsonpath="{.status.platformStatus.aws.region}")
      terraform_args+=(
        --var "winc_machine_hostname=${winMachineHostname}"
        --var "winc_instance_name=${byoh_name}"
        --var "winc_worker_ami=${windowsAmi}"
        --var "winc_cluster_name=${clusterName}"
        --var "winc_region=${region}"
        --var "ssh_public_key=${SSH_PUBLIC_KEY}"
      )
      ;;

    "azure")
      winMachineHostname=$(oc get nodes -l "node-role.kubernetes.io/worker,windowsmachineconfig.openshift.io/byoh!=true" -o=jsonpath="{.items[0].status.addresses[?(@.type=='Hostname')].address}")
      windowsSku=$(oc get machineset.machine.openshift.io -n openshift-machine-api -o=jsonpath="{.items[?(@.spec.template.metadata.labels.machine\\.openshift\\.io/os-id=='Windows')].spec.template.spec.providerSpec.value.image.sku}")
      terraform_args+=(
        --var "winc_machine_hostname=${winMachineHostname}"
        --var "winc_instance_name=${byoh_name}"
        --var "winc_worker_sku=${windowsSku}"
        --var "ssh_public_key=${SSH_PUBLIC_KEY}"
      )
      ;;

    "gcp")
      winMachineHostname=$(oc get nodes -l "node-role.kubernetes.io/worker,windowsmachineconfig.openshift.io/byoh!=true" -o=jsonpath="{.items[0].status.addresses[?(@.type=='Hostname')].address}" | cut -d '.' -f1)
      zone=$(oc get machine.machine.openshift.io -n openshift-machine-api -o=jsonpath="{.items[0].metadata.labels.machine\\.openshift\\.io/zone}")
      region=$(oc get infrastructure cluster -o=jsonpath="{.status.platformStatus.gcp.region}")
      terraform_args+=(
        --var "winc_machine_hostname=${winMachineHostname}"
        --var "winc_instance_name=${byoh_name}"
        --var "winc_zone=${zone}"
        --var "winc_region=${region}"
        --var "ssh_public_key=${SSH_PUBLIC_KEY}"
      )
      ;;

    "vsphere")
      fetch_vsphere_params
      terraform_args+=(
        "--var=winc_instance_name=${byoh_name}"
        "--var=vsphere_template=${windowsTemplate}"
        "--var=vsphere_datacenter=${datacenterName}"
        "--var=vsphere_network=${networkName}"
        "--var=vsphere_datastore=${datastoreName}"
        "--var=vsphere_resource_pool=${resourcePool}"
		"--var=instance_name=${byoh_name}"
		"--var=vsphere_server=${VSPHERE_SERVER}"
      )
      ;;
    *)
      echo "ERROR: Unsupported platform: $platform"
      exit 1
      ;;
  esac

  printf '%s\n' "${terraform_args[@]}" 
}



tmp_dir="/tmp/terraform_byoh/"
templates_dir="${tmp_dir}${platform}${tmp_folder_suffix}"

# Ensure the templates directory exists
mkdir -p "${templates_dir}"

function get_user_name() {
	case $platform in
		"aws"|"gcp"|"vsphere"|"none"|"nutanix")
			echo "Administrator"
			;;
		"azure")
			echo "capi"
			;;
		*)
			echo "ERROR: Platform ${platform} not supported. Aborting execution."
            exit 1
			;;
	esac
}


case $action in

	"apply")
		if [ -d $templates_dir ]
		then
			echo "The directory $templates_dir already exists, do you want to get rid of its content?(yes or no)"
			read -p "Answer: " answer
			case $answer in
				"yes")
					rm -r $templates_dir
					cp -R ./$platform $templates_dir
					;;
				"no")
					echo "Terraform apply will be re-executed using templates located in ${templates_dir}"
					;;
				"*")
					echo "ERROR: Unsupported answer ${answer}, write 'yes' or 'no'. Aborting execution."
            		exit 1
					;;
			esac
		else
			mkdir -p $tmp_dir
			cp -R ./$platform $templates_dir
		fi
		export_credentials
		cd $templates_dir
		terraform init
		echo "Terraform args: " + $(get_terraform_arguments)
		readarray -t terraform_args < <(get_terraform_arguments)
		# Debugging: Safely print arguments
		echo "Terraform args:"
		for arg in "${terraform_args[@]}"; do
		  echo "  $arg"
		done
		# Apply with proper var syntax
		echo "Number of workers passed to Terraform: $num_byoh"
		terraform apply --auto-approve "${terraform_args[@]}"

	    # Create configmap and apply it (follows to apply)
		if [ ! -d $templates_dir ]
		then
			echo "ERROR: Directory ${templates_dir} not created. Did you run ./byoh.sh apply first?"
            exit 1
		fi

		wmco_namespace=$(oc get deployment --all-namespaces -o=jsonpath="{.items[?(@.metadata.name=='windows-machine-config-operator')].metadata.namespace}")
		cd $templates_dir
		cat << EOF  > byoh_cm.yaml
kind: ConfigMap
apiVersion: v1
metadata:
  name: windows-instances
  namespace: ${wmco_namespace}
data:
$(
	for ip in $(terraform output --json instance_ip | jq -c '.[]')
	do
		echo -e "  ${ip}: |-\n    username=$(get_user_name)"
	done
)
EOF
		oc create -f "${templates_dir/byoh_cm.yaml}"

		;;
	"configmap")
	# Create configmap and apply it (in case you need to relaunch it)
		if [ ! -d $templates_dir ]
		then
			echo "ERROR: Directory ${templates_dir} not created. Did you run ./byoh.sh apply first?"
            exit 1
		fi

		wmco_namespace=$(oc get deployment --all-namespaces -o=jsonpath="{.items[?(@.metadata.name=='windows-machine-config-operator')].metadata.namespace}")
		cd $templates_dir
		cat << EOF  > byoh_cm.yaml
kind: ConfigMap
apiVersion: v1
metadata:
  name: windows-instances
  namespace: ${wmco_namespace}
data:
$(
	for ip in $(terraform output --json instance_ip | jq -c '.[]')
	do
		echo -e "  ${ip}: |-\n    username=$(get_user_name)"
	done
)
EOF
		oc create -f "${templates_dir/byoh_cm.yaml}"
		;;
	"destroy")
		if [ ! -d $templates_dir ]
		then
			echo "ERROR: Directory ${templates_dir} not created. Did you run ./byoh.sh apply first?"
            exit 1
		fi

		# Delete the configmap if exists
		if [ -e "${templates_dir/byoh_cm.yaml}" ]
		then
		    wmco_namespace=$(oc get deployment --all-namespaces -o=jsonpath="{.items[?(@.metadata.name=='windows-machine-config-operator')].metadata.namespace}")
			if oc get cm windows-instances -n ${wmco_namespace}
			then
				oc delete -f "${templates_dir/byoh_cm.yaml}"
			fi
		fi
		export_credentials
		cd $templates_dir
		readarray -t terraform_args < <(get_terraform_arguments)
		# Add winc_number_workers for all platforms
		echo "Terraform args:"
	    for arg in "${terraform_args[@]}"; do
    	    echo "  $arg"
    	done
    	terraform destroy --auto-approve "${terraform_args[@]}"		
		
		rm -r $templates_dir
		;;
	"clean")
		rm -r $templates_dir
		;;
	"arguments")
		echo $(get_terraform_arguments)
		;;
	"help")
		echo "
		$1: action to perform, it could be 'apply', 'destroy', 'arguments', 'configmap', 'clean'. Default: 'apply'
		$2: name for the byoh instances, it will append a number. Default: \"byoh-winc\"
		$3: number of byoh workers. If no argument is passed default number of byoh nodes = 2
		$4: suffix to append to the folder created. This is useful when you have already run the script once
		$5: windows server version to use in BYOH nodes. Accepted: 2019 or 2022

		Example for BYOH: ./byoh.sh apply byoh 1 '' 2019
		Example for others: ./byoh.sh apply winc-byoh 4 ''
		Example if multiple runs of same cloud provider: 
		   * Azure 2019: ./byoh.sh apply byoh-winc 2 '-az2019'
		   * Azure 2022: ./byoh.sh apply byoh-winc 2 '-az2022'
		"
		;;
	*)
		echo "ERROR: Option ${action} not supported. Use: apply, destroy, arguments, clean, configmap"
    	exit 1
		;;
esac

