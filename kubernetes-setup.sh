#!/bin/bash
#
# -------------------------------------------------------------------
# Script Name:   kubernetes-setup.sh
# Description:   Provisions and configures Kubernetes control plane
#                and worker nodes on Ubuntu-based systems.
#
# Usage:         ./kubernetes-setup.sh [cp|worker]
#
# Arguments:
#   cp       Set up the Kubernetes control plane node
#   worker   Join a node as a Kubernetes worker
#
# Requirements:
#   - Must be run with sudo or as root
#   - Compatible with Ubuntu 20.04 / 22.04
#   - Internet connection for package installation
#
# Author:        Avi Avila
# Created:       2025-04-03
# Updated:       2025-04-05
# License:       GNU General Public License v3.0
# -------------------------------------------------------------------

# Log Handling File
LOG_FILE="/var/log/k8s_provisioning.log"

# Function to log Messages
echo_log () {
    local LOG_LEVEL="$1"
    shift
    local MESSAGE="$@"
    echo "$(date +'%Y-%m-%d %H:%M:%S')" [$LOG_LEVEL] $MESSAGE | tee -a "$LOG_FILE"
}

# Function to display usage help
show_help() {
    cat <<EOF
Usage: sudo ./k8s_provision.sh <node_type> <hostname> [k8s_version] [pod_cidr]

Arguments:
  --node_type       Type of node to provision: "cp" for Control Plane or "worker" for Worker Node (default: cp)
  --hostname        Desired hostname for the node (default: k8s-master-node)
  --k8s_version     Optional: Kubernetes version to install (default: v1.31)
  --pod_cidr        Optional: Pod network CIDR (default: 192.168.0.0/16)

  --join            The IP address and port number used by the Master Node found in the k8s_provisioning.log file (172.)
  --token           The Token value found in the k8s_provisioning.log file
  --discovery-token The CA-Cert-Hash value found the the k8s_provisioning.log file

Examples:
  sudo ./kubernetes-setup.sh --node_type cp --hostname my-k8s-m-node
  sudo ./kubernetes-setup.sh --node_type cp --hostname my-k8s-cp-node --k8s_version 1.32 --pod_cidr 10.244.0.0/16
  sudo ./kubernetes-setup.sh --node_type worker --hostname k8s-worker-node-1 --join 172.168.222.222 --token 294iru.f3m1vbsxc9wve8q --discovery-token sha256:48edadccfc47...f8
EOF
    exit 0
}

# Default values
NODE_TYPE="cp"
HOSTNAME="k8s-master-node"
K8S_VERSION="1.31"
POD_CIDR="192.168.0.0/16"
JOIN=""
TOKEN=""
DISCOVERY_TOKEN=""

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --node_type)
            NODE_TYPE="$2"
            shift 2
            ;;
        --hostname)
            HOSTNAME="$2"
            shift 2
            ;;
        --k8s_version)
            K8S_VERSION="$2"
            shift 2
            ;;
        --pod_cidr)
            POD_CIDR="$2"
            shift 2
            ;;
        --join)
            JOIN="$2"
            shift 2
            ;;
        --token)
            TOKEN="$2"
            shift 2
            ;;
        --discovery-token)
            DISCOVERY_TOKEN="$2"
            shift 2
            ;;
        --help|-h)
            show_help
            ;;
        *)
            echo_log "ERROR" "Unknown option: $1"
            show_help
            ;;
    esac
done

# Function to check Ubuntu version
check_ubuntu_version() {
    local SUPPORTED_VERSIONS=("20.04" "22.04" "24.04")
    local UBUNTU_VERSION=$(lsb_release -rs)
    
    if [[ ! " ${SUPPORTED_VERSIONS[@]} " =~ " ${UBUNTU_VERSION} " ]]; then
        echo_log "ERROR" "Unsupported Ubuntu version: $UBUNTU_VERSION. Supported versions: ${SUPPORTED_VERSIONS[*]}"
        exit 1
    fi
    echo_log "INFO" "Detected Ubuntu version: $UBUNTU_VERSION"
}

# Function to configure hostname
configure_hostname() {
    local HOSTNAME="$1"
    
    if [[ -z "$HOSTNAME" ]]; then
        echo_log "ERROR" "Hostname not provided. Usage: $0 <hostname>"
        exit 1
    fi
    
    echo_log "INFO" "Setting hostname to $HOSTNAME"
    hostnamectl set-hostname "$HOSTNAME"
}

# Function to disable swap
disable_swap() {
    echo_log "INFO" "Disabling swap..."
    swapoff -a || true
    sed -i '/swap/d' /etc/fstab
}

# Load Containerd Modules 
containerd_modules() {
    echo_log "INFO" "Loading Containerd Modules"
    sudo modprobe overlay
    sudo modprobe br_netfilter

    cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf > /dev/null
overlay
br_netfilter
EOF
    
    echo_log "INFO" "Containerd modules loaded successfully."
}

# Config k8s IPv4
k8s_networking() {
        local CONFIG_FILE="/etc/sysctl.d/k8s.conf"

    echo_log "INFO" "Configuring Kubernetes networking settings in $CONFIG_FILE..."

    cat <<EOF | tee "$CONFIG_FILE" > /dev/null
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward = 1
EOF

    sysctl --system || { echo_log "ERROR" "Failed to apply sysctl settings."; exit 1; }

    echo_log "INFO" "Kubernetes networking settings applied successfully."
}

# Check for system packages
update_system() {
    echo_log "INFO" "Updating system packages..."
    sudo apt update && sudo apt upgrade -y || { echo_log "ERROR" "Failed to update system."; exit 1; }
}

# Install Docker and Config Containerd
install_docker() {
    echo_log "INFO" "Installing Docker"
    sudo apt install docker.io -y
    sudo systemctl enable docker
    sudo mkdir /etc/containerd
    sudo sh -c "containerd config default > /etc/containerd/config.toml"
    sudo sed -i 's/ SystemdCgroup = false/ SystemdCgroup = true/' /etc/containerd/config.toml
    sudo systemctl restart containerd.service
    echo_log "INFO" "Docker Installed and Containerd Configured"
}

# Install k8s Components
install_k8s_tools() {
    local K8S_VERSION="$K8S_VERSION"
    echo_log "INFO" "Installing Kubernetes required tools (Version: $K8S_VERSION)..."
    sudo apt-get install curl ca-certificates apt-transport-https -y
    curl -fsSL https://pkgs.k8s.io/core:/stable:/v$K8S_VERSION/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
    echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v$K8S_VERSION/deb/ /" | sudo tee /etc/apt/sources.list.d/kubernetes.list
    sudo apt update
    sudo apt install kubelet kubeadm kubectl -y
    echo_log "INFO" "Installed Kubelet, Kubeadm and Kubectl successfully"
}

join_master() {
    echo_log "INFO" "Joining Master Node.."
    sudo kubeadm join $JOIN --token $TOKEN --discovery-token-ca-cert-hash $DISCOVERY_TOKEN
    echo_log "INFO" "Successfully Joined Master Node.."
}

wait_for_api_server() {
    echo_log "INFO" "Waiting for Kubernetes API server to become available..."

    for i in {1..150}; do  # 150 loops × 2 seconds = 300 seconds (5 minutes)
        if kubectl version --short &>/dev/null; then
            echo_log "INFO" "Kubernetes API server is responsive."
            return 0
        fi
        sleep 2
    done

    echo_log "ERROR" "Kubernetes API server did not become ready within 5 minutes."
    exit 1
}

# CP Node Actions Below

# Function to determine node type
select_node_type() {
    if [[ $NODE_TYPE == "cp" ]]; then
        echo_log "INFO" "Provisioning a Control Plane Node."
        initialize_control_plane
        setup_k8s_user
        install_calico_plugin        
    elif [[ "$NODE_TYPE" == "worker" ]]; then
        echo_log "INFO" "Provisioning a Worker Node."
        if [[ -z "$JOIN" || -z "$TOKEN" || -z "$DISCOVERY_TOKEN" ]]; then
            echo_log "ERROR" "--join, --token and --discovery-token are required."
            show_help
            exit 1
        fi
        join_master
    else
        echo_log "ERROR" "Invalid node type specified. Use 'cp' for Control Plane or 'worker' for Worker Node."
        exit 1
    fi
}

# Init k8s (Master Node)
initialize_control_plane() {
    local POD_CIDR=$POD_CIDR
    echo_log "INFO" "Initializing Kubernetes control plane with CIDR: $POD_CIDR..."

    kubeadm init --pod-network-cidr=$POD_CIDR 2>&1 | tee -a "$LOG_FILE"

    if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
        echo_log "ERROR" "Control plane initialization failed."
        exit 1
    fi

    echo_log "INFO" "Kubernetes control plane initialized successfully."
    echo_log "INFO" "NOTE: Save the 'kubeadm join' command above to add new worker nodes."
}


# Ask user to switch to regular user
setup_k8s_user() {
    local K8S_USER="${SUDO_USER:-$(whoami)}"

    echo_log "INFO" "Configuring Kubernetes access for user: $K8S_USER"

    if [[ "$K8S_USER" == "root" ]]; then
        echo_log "INFO" "Running as root. Exporting admin.conf for KUBECONFIG."
        export KUBECONFIG=/etc/kubernetes/admin.conf
        echo "export KUBECONFIG=/etc/kubernetes/admin.conf" >> /root/.bashrc
        echo "export KUBECONFIG=/etc/kubernetes/admin.conf" >> /root/.profile
    else
        local HOME_DIR=$(eval echo ~$K8S_USER)
        if [[ -z "$HOME_DIR" || ! -d "$HOME_DIR" ]]; then
            echo_log "ERROR" "Home directory for user $K8S_USER not found!"
            exit 1
        fi

        mkdir -p "$HOME_DIR/.kube"
        sudo cp -i /etc/kubernetes/admin.conf "$HOME_DIR/.kube/config"
        sudo chown $(id -u $K8S_USER):$(id -g $K8S_USER) "$HOME_DIR/.kube/config"

        echo_log "INFO" "Kubernetes configuration set up for $K8S_USER."
    fi
}

# Install Calico Plugin
install_calico_plugin() {
    local POD_CIDR=$POD_CIDR

    wait_for_api_server
    echo_log "INFO" "Installing Calico network plugin using Calico operator..."
    kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.28.0/manifests/tigera-operator.yaml || {
        echo_log "ERROR" "Failed to apply Calico operator manifest."; exit 1;
    }

    curl -O https://raw.githubusercontent.com/projectcalico/calico/v3.28.0/manifests/custom-resources.yaml || {
        echo_log "ERROR" "Failed to download custom-resources.yaml."; exit 1;
    }

    sed -i "s|cidr: 192\.168\.0\.0/16|cidr: \"$POD_CIDR\"|g" custom-resources.yaml || {
        echo_log "ERROR" "Failed to update CIDR in custom-resources.yaml."; exit 1;
    }

    kubectl create -f custom-resources.yaml || {
        echo_log "ERROR" "Failed to apply Calico custom resources."; exit 1;
    }

    echo_log "INFO" "Calico network plugin installed successfully."
}

# Ask user to run script on Worker Node and copy the kubeadm join cmd



# Main script execution
if [[ "$1" == "--help" || "$1" == "-h" ]]; then
    show_help
fi

# Functions required for both Master Node and Worker Nodes
check_ubuntu_version
configure_hostname "$HOSTNAME"
disable_swap
containerd_modules
k8s_networking
update_system
install_docker
install_k8s_tools "$K8S_VERSION"

# Fucntion Required for Master Node only / Worker Join
select_node_type "$NODE_TYPE"
