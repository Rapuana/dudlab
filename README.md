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
├── ansible.cfg                    # Ansible config (inventory path, python interpreter)
├── site.yml                       # Master playbook — runs everything in order
├── inventory/
│   ├── hosts.ini                  # Server inventory (master + workers)
│   └── group_vars/
│       └── all.yml                # Cluster-wide variables (IPs, pool ranges)
├── playbooks/
│   ├── install_packages.yml       # Base packages on all nodes
│   ├── setup_firewall.yml         # UFW rules for Kubernetes traffic
│   ├── provision_k3s.yml          # Install k3s master + join workers
│   ├── deploy_metallb.yml         # MetalLB load balancer
│   ├── deploy_longhorn.yml        # Longhorn persistent storage
│   ├── deploy_portainer.yml       # Portainer web UI
│   ├── deploy_grafana.yml         # Prometheus + Grafana monitoring
│   ├── deploy_pihole.yml          # Pi-hole DNS ad-blocker
│   ├── ping.yml                   # Connectivity check
│   └── update.yml                 # apt upgrade all nodes
├── roles/
│   └── metallb/
│       └── files/
│           └── metallb-config.yaml  # IP pool + L2Advertisement config
└── docs/                          # Per-service documentation
```

## Deployment

### Prerequisites

- Ansible installed on your Mac (`brew install ansible`)
- SSH key copied to all servers (`ssh-copy-id -i ~/.ssh/<key>.pub dudley@<host>`)
- `kubectl` installed locally (`brew install kubectl`)

### Full stack deploy

```bash
ansible-playbook site.yml
```

Runs all playbooks in order. Safe to re-run — all steps are idempotent.

### Individual playbooks

```bash
# Check connectivity first
ansible-playbook playbooks/ping.yml

# Update all servers
ansible-playbook playbooks/update.yml

# Redeploy a single service
ansible-playbook playbooks/deploy_pihole.yml
```

### Playbook run order (for fresh deploys)

Longhorn must be deployed before Pi-hole, since Pi-hole uses Longhorn for persistent storage.

```
install_packages → setup_firewall → provision_k3s → deploy_metallb
→ deploy_longhorn → deploy_portainer → deploy_grafana → deploy_pihole
```

## Configuration

All IP addresses and cluster settings live in `inventory/group_vars/all.yml`:

```yaml
k3s_master_ip: 192.168.0.38
metallb_ip_pool: "192.168.0.240-192.168.0.250"

pihole_ip: "192.168.0.241"
portainer_ip: "192.168.0.242"
grafana_ip: "192.168.0.243"
longhorn_ip: "192.168.0.244"
```

To change a service IP, update the variable here and redeploy that playbook.

## Adding a Third Node

When the third server arrives:

1. Uncomment the placeholder in `inventory/hosts.ini`
2. Copy your SSH key to the new server
3. Run `ansible-playbook playbooks/install_packages.yml` to configure it
4. Run `ansible-playbook playbooks/setup_firewall.yml`
5. Run `ansible-playbook playbooks/provision_k3s.yml` — the worker join step is idempotent, it will only act on nodes where the agent isn't already running

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
```
