# Kubernetes Cluster Script


### Intro
Spin up a Kubernetes Control Plane with ease and quickly with this script. Once you provision a server in whatever CSP of our choice, you can copy this repo and run this script to get your control plane up and running. The script also helps get Worker nodes setup so you can join the CP with ease.

This Bash script automates the provisioning of Kubernetes Control Plane (cp) and Worker Nodes on supported Ubuntu systems (20.04, 22.04, and 24.04). It performs essential steps including hostname configuration, system updates, Docker/containerd setup, Kubernetes installation, and cluster initialization or joining.

### Requirments

* Able to SSH into the server(s)
* A Minimum of 2 vCPU & 2GB RAM (For CP and/or Worker)
* A Minimum of 8GB of Disk Space (AWS Default)


### Capatiable with the following Ubuntu versions

* Ubuntu 24.04
* Ubuntu 22.04
* Ubuntu 20.04


## ✅ Features

- Supports provisioning of:
  - **Control Plane (cp)** nodes
  - **Worker nodes**
- Automatically:
  - Validates Ubuntu version
  - Configures hostname
  - Disables swap
  - Loads containerd modules
  - Applies Kubernetes networking settings
  - Installs Docker & containerd
  - Installs Kubernetes tools (`kubelet`, `kubeadm`, `kubectl`)
  - Initializes or joins the cluster
  - Configures Calico as the network plugin (for cp)
  - Logs all operations to `/var/log/k8s_provisioning.log`

---

## ⚙️ Prerequisites

- Script must have execute permissions:
  ```bash
  chmod +x kubernetes-setup.sh
  ```

---

## 🚀 Usage

```bash
./kubernetes-setup.sh [OPTIONS]
```

### ✅ Common Arguments

| Argument            | Description                                                    | Default              |
|---------------------|----------------------------------------------------------------|----------------------|
| `--node_type`       | Node type: `cp` (Control Plane) or `worker`                    | `cp`                 |
| `--hostname`        | Hostname for the node                                          | `k8s-master-node`    |
| `--k8s_version`     | Kubernetes version (e.g., `1.31`)                              | `1.31`              |
| `--pod_cidr`        | Pod CIDR for networking                                        | `192.168.0.0/16`     |
| `--join`            | Master node IP and port (Required for worker nodes)            | *None*               |
| `--token`           | Token for joining the cluster (Required for worker nodes)      | *None*               |
| `--discovery-token` | CA Cert Hash (Required for worker nodes)                       | *None*               |
| `--help`, `-h`      | Show help and usage                                            |                      |


---

## 🧠 Examples

### 🛠 Provision a Control Plane Node

```bash
./kubernetes-setup.sh --node_type cp --hostname my-cp-node
```

Or with custom Kubernetes version and Pod CIDR:

```bash
./kubernetes-setup.sh --node_type cp --hostname my-cp-node --k8s_version v1.32 --pod_cidr 10.244.0.0/16
```

---

### 🔗 Provision a Worker Node (Join Existing Cluster)

First, retrieve the join command from the control plane node log at `/var/log/k8s_provisioning.log`, then:

```bash
./kubernetes-setup.sh \
  --node_type worker \
  --hostname worker-node-1 \
  --join 172.32.95.160:6443 \
  --token <your-token> \
  --discovery-token <sha256:your-discovery-token>
```

---

## 📝 Notes

- On control plane initialization, the script will output a `kubeadm join` command. Save it to use for joining worker nodes.
- The script assumes you are running as a user or with `sudo` permissions.
- The script logs everything to: `/var/log/k8s_provisioning.log`
- Ensure your system has access to Kubernetes repositories and GitHub URLs for the Calico manifests.
- Ensure Networking / Firewall rules are updated to allow communication between nodes

---

## 🧩 Troubleshooting

- Ensure network connectivity to download Calico manifests.
- Check the log file `/var/log/k8s_provisioning.log` for any error messages.
- Ensure you are using a supported Ubuntu version (20.04, 22.04, or 24.04).
- Check Network Routing in your Subnet
- Check Firewall Rules (NSG's / SG's) to Allow Kubernetes Traffic

---

## 👨‍💻 Author

Created by Avi Avila  
For provisioning K8s clusters in production and lab environments.