# Portainer

## What it is

Portainer is a web-based management UI for container environments. In dudlab it connects to the k3s Kubernetes cluster and gives you a point-and-click interface for everything you'd otherwise do with `kubectl` on the command line.

## Why Portainer

| Alternative | Trade-off |
|-------------|-----------|
| **kubectl only** | Fully capable but command-line only — no visual overview, no quick inspection |
| **k9s** | Excellent TUI (terminal UI), fast, but still terminal-only |
| **Lens / OpenLens** | Full-featured desktop IDE for Kubernetes — more powerful than Portainer but runs on your Mac, not the cluster |
| **Headlamp** | Newer open-source option, lighter than Lens, web-based |
| **Kubernetes Dashboard** | Official k8s UI, minimal and harder to set up auth for |

Portainer CE (Community Edition) was chosen because it's free, installs easily via Helm, has a clean UI, and is good enough for a homelab where you mostly want visibility rather than GitOps-level management.

## Setup in dudlab

Deployed via Helm:

```bash
helm upgrade --install portainer portainer/portainer \
  --namespace portainer \
  --set service.type=LoadBalancer \
  --set service.loadBalancerIP=192.168.0.242
```

Accessible at `https://192.168.0.242:9443` (self-signed cert, you'll get a browser warning — accept it).

### First login

Portainer has a **5-minute window** after startup to set an admin password. If you miss it, the instance locks for security. To reset:

```bash
kubectl rollout restart deployment portainer -n portainer
```

Then immediately navigate to the UI and set your password.

## Where it sits in the architecture

Portainer sits outside the core stack — removing it wouldn't affect any other service. It talks directly to the Kubernetes API (via its service account) to read and manage cluster resources.

```
Browser → https://192.168.0.242:9443
    │
    ▼
Portainer pod
    │
    ▼
Kubernetes API (kubectl equivalent)
    │
    ▼
Cluster resources (pods, deployments, services, etc.)
```

## What you can do with it

### Dashboard

The home screen shows cluster health at a glance: node count, running containers, image count, volume count. Click through to any resource.

### Namespaces

Browse by namespace — `monitoring`, `longhorn-system`, `pihole`, `portainer`, `metallb-system`. Useful for understanding what's running where without writing `kubectl get pods -A`.

### Workloads

- View all **Deployments, DaemonSets, StatefulSets**
- See pod status, replica counts, restart history
- Restart a deployment with one click
- Scale up/down replicas

### Pod inspection

- View live **logs** from any pod — no need for `kubectl logs`
- Open a **shell** into a running container (`kubectl exec` equivalent)
- See environment variables, resource limits, mounted volumes

### Services and networking

- See all Services and their ClusterIP / NodePort / LoadBalancer IPs
- Confirm MetalLB has assigned the right external IPs

### Storage

- Browse PersistentVolumeClaims and PersistentVolumes
- See which pods are using which volumes

### Application deployment (advanced)

Portainer can deploy new applications via:
- **Manifests** — paste or upload a YAML file
- **Helm charts** — search and deploy from public repos
- **GitOps** — link a Git repo and auto-sync on push (paid feature in CE is limited)

For dudlab, we deploy everything via Ansible, so Portainer is primarily used for **inspection and debugging** rather than deployment.

## Useful for debugging

When something isn't working, Portainer is often faster than the command line for finding the problem:

1. Go to **Namespaces → (namespace) → Workloads**
2. Find the deployment that's unhealthy (red indicator)
3. Click through to the pod
4. Check **Logs** for error messages
5. Check **Events** on the pod for Kubernetes-level issues (image pull failures, scheduling errors, etc.)
