# Dudlab Cluster

A home Kubernetes lab running on two (soon three) mini Dell PCs, managed entirely through Ansible from a Mac. The cluster runs a stack of self-hosted services for personal use — DNS ad-blocking, monitoring, persistent storage, and a management UI — with more apps planned.

## Hardware

| Host | Role | IP |
|------|------|----|
| `dudley-server-1.local` | k3s master | `192.168.0.38` |
| `dudley-server-2.local` | k3s worker | DHCP |
| `dudley-server-3.local` | k3s worker (coming soon) | — |

Both servers run Ubuntu Server. The Mac is the Ansible control node — nothing runs on it, it just issues commands over SSH.

## Services

| Service | What it does | URL |
|---------|-------------|-----|
| [MetalLB](docs/metallb.md) | Assigns real LAN IPs to Kubernetes services | — |
| [Longhorn](docs/longhorn.md) | Persistent storage across the cluster | `http://192.168.0.244` |
| [Portainer](docs/portainer.md) | Web UI for managing the cluster | `https://192.168.0.242:9443` |
| [Grafana + Prometheus](docs/grafana.md) | Monitoring and dashboards | `http://192.168.0.243` |
| [Pi-hole](docs/pihole.md) | Network-wide DNS ad-blocking | `http://192.168.0.241/admin` |

## Architecture Overview

```
                        Mac (control node)
                              │
                    ansible-playbook site.yml
                              │
              ┌───────────────┴───────────────┐
              │                               │
   dudley-server-1.local            dudley-server-2.local
   k3s master (192.168.0.38)        k3s worker
              │                               │
              └───────────── k3s ─────────────┘
                         Kubernetes cluster
                               │
                ┌──────────────┼──────────────┐
                │              │              │
            MetalLB        Longhorn      Services
         (LoadBalancer    (Persistent   (Pi-hole,
          IPs from LAN)    Storage)    Portainer,
                                        Grafana)
```

All services are deployed as Kubernetes workloads via Helm charts. MetalLB provides real IP addresses from a reserved block on the local network (`192.168.0.240–250`), so services are reachable directly without port-forwarding or NodePort gymnastics. Longhorn provides replicated persistent storage across both nodes so data survives a node restart.

## Repository Structure

```
dudlab-cluster/
├── ansible.cfg                    # Ansible config (inventory, vault script, collections path)
├── site.yml                       # Master playbook — runs everything in order
├── requirements.yml               # Ansible collection dependencies
├── Makefile                       # Common targets: deploy, lint, ping, install-deps
├── scripts/
│   └── vault-pass.sh              # Reads vault password from macOS Keychain
├── inventory/
│   ├── hosts.ini                  # Server inventory (master + workers)
│   └── group_vars/
│       └── all/
│           ├── vars.yml           # Cluster-wide variables, IPs, version pins
│           └── vault.yml          # Encrypted secrets (ansible-vault)
├── playbooks/
│   ├── install_packages.yml       # Base packages on all nodes
│   ├── setup_firewall.yml         # UFW rules for Kubernetes traffic
│   ├── provision_k3s.yml          # Install k3s master + join workers
│   ├── deploy_metallb.yml         # MetalLB load balancer
│   ├── deploy_longhorn.yml        # Longhorn persistent storage
│   ├── deploy_portainer.yml       # Portainer web UI
│   ├── deploy_grafana.yml         # Prometheus + Grafana monitoring
│   ├── deploy_network_monitoring.yml  # Blackbox exporter + speedtest exporter
│   ├── deploy_pihole.yml          # Pi-hole DNS ad-blocker
│   ├── ping.yml                   # Connectivity check
│   ├── update.yml                 # apt upgrade all nodes
│   └── files/
│       ├── kube-prometheus-stack-values.yml  # Helm values for Grafana/Prometheus
│       ├── blackbox-exporter-values.yml      # Probe targets config
│       ├── speedtest-exporter.yml            # k8s Deployment + ServiceMonitor
│       └── dashboards/
│           ├── network-probes.json           # Grafana dashboard: ping/HTTP probes
│           └── internet-speed.json           # Grafana dashboard: speedtest results
├── roles/
│   └── metallb/
│       └── files/
│           └── metallb-config.yaml  # IP pool + L2Advertisement config
└── docs/                          # Per-service documentation
```

## Getting Started

### Prerequisites

- Ansible installed on your Mac (`brew install ansible`)
- SSH key copied to all servers (`ssh-copy-id -i ~/.ssh/<key>.pub dudley@<host>`)
- `kubectl` installed locally (`brew install kubectl`)
- Vault password stored in macOS Keychain (see below)

### One-time setup

**Install Ansible collections** (required before first deploy):

```bash
make install-deps
```

**Store the vault password in macOS Keychain** (required for encrypted secrets):

```bash
make setup-vault
```

This stores the vault password under the key `dudlab-ansible-vault` in your Keychain. Ansible reads it automatically via `scripts/vault-pass.sh` — you never need to type it during deploys.

### Deploy

```bash
make deploy        # Full stack deploy (runs site.yml)
make ping          # Test connectivity to all nodes
make lint          # Run yamllint + ansible-lint
make update        # apt upgrade all nodes
```

### Individual playbooks

```bash
# Redeploy a single service
ansible-playbook playbooks/deploy_grafana.yml
ansible-playbook playbooks/deploy_pihole.yml
```

### Playbook run order (for fresh deploys)

`site.yml` runs these in order — each step depends on the ones before it:

```
install_packages → setup_firewall → provision_k3s → deploy_metallb
→ deploy_longhorn → deploy_portainer → deploy_grafana
→ deploy_network_monitoring → deploy_pihole
```

## Configuration

All IP addresses, cluster settings, and version pins live in `inventory/group_vars/all/vars.yml`:

```yaml
k3s_master_ip: 192.168.0.38
metallb_ip_pool: "192.168.0.240-192.168.0.250"

pihole_ip: "192.168.0.241"
portainer_ip: "192.168.0.242"
grafana_ip: "192.168.0.243"
longhorn_ip: "192.168.0.244"

# Version pins — lock the cluster to known-good versions
k3s_version: "v1.32.5+k3s1"
helm_version: "v3.20.0"
longhorn_chart_version: "1.11.0"
portainer_chart_version: "239.0.2"
kube_prometheus_stack_chart_version: "82.10.1"
blackbox_exporter_chart_version: "11.8.0"
pihole_chart_version: "2.35.0"
```

Sensitive values (passwords) live in `inventory/group_vars/all/vault.yml`, encrypted with ansible-vault.

To change a service IP, update the variable and redeploy that playbook. To update a version pin, verify against the live cluster first, then update and redeploy.

## Adding a Third Node

### 1. Set up the hostname on the new server

SSH into the new server and set its hostname so it's reachable as `dudley-server-3.local`:

```bash
sudo hostnamectl set-hostname dudley-server-3
```

Verify mDNS is working from your Mac:

```bash
ping dudley-server-3.local
```

If it doesn't resolve, install Avahi on the server (Ubuntu):

```bash
sudo apt install avahi-daemon
sudo systemctl enable --now avahi-daemon
```

### 2. Copy your SSH key

```bash
ssh-copy-id -i ~/.ssh/<key>.pub dudley@dudley-server-3.local
```

Verify you can connect without a password:

```bash
ssh dudley@dudley-server-3.local
```

### 3. Add it to the inventory

Uncomment the placeholder lines in `inventory/hosts.ini` — add the new node to both `k3s_worker_nodes` and `dudlab_cluster`:

```ini
[k3s_worker_nodes]
dudley-server-2.local ansible_user=dudley
dudley-server-3.local ansible_user=dudley

[dudlab_cluster]
dudley-server-1.local ansible_user=dudley
dudley-server-2.local ansible_user=dudley
dudley-server-3.local ansible_user=dudley
```

### 4. Run the playbooks

The worker join step in `provision_k3s.yml` is idempotent — it only acts on nodes where the k3s agent isn't already running, so existing nodes are unaffected:

```bash
ansible-playbook playbooks/install_packages.yml
ansible-playbook playbooks/setup_firewall.yml
ansible-playbook playbooks/provision_k3s.yml
```

Verify the new node joined:

```bash
kubectl get nodes
```

It will initially show `NotReady` while it pulls images, then transition to `Ready` within a minute or two.

Longhorn will automatically start scheduling volume replicas on the new node.

## Quick Reference

```bash
# Cluster status
kubectl get nodes
kubectl get pods -A

# Check service IPs
kubectl get svc -A | grep LoadBalancer

# Check storage
kubectl get pvc -A
kubectl get storageclass

# Restart a stuck service
kubectl rollout restart deployment <name> -n <namespace>

# Roll back a Helm release
helm rollback <release-name> -n <namespace>
```
