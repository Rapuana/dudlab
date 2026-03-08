# MetalLB

## What it is

MetalLB is a load balancer for bare-metal Kubernetes clusters. In cloud environments (AWS, GCP, Azure), when you create a Kubernetes `Service` of type `LoadBalancer`, the cloud provider automatically provisions an external IP and routes traffic to your pods. On bare metal, that mechanism doesn't exist — without MetalLB, `LoadBalancer` services stay in `<pending>` state indefinitely.

MetalLB fills that gap by managing a pool of IPs from your local network and assigning them to services on demand, making them reachable like any other device on the LAN.

## Why MetalLB

| Alternative | Why not chosen |
|-------------|---------------|
| **NodePort** | Exposes services on a random port (30000–32767) — ugly URLs, no standard ports |
| **Host networking** | Bypasses Kubernetes networking entirely, loses isolation |
| **Ingress only** | Works for HTTP/HTTPS but not DNS (UDP), which Pi-hole needs |
| **k3s built-in ServiceLB (Klipper)** | Simpler but binds one service per node — less flexible, doesn't support IP sharing |

MetalLB is the standard solution for this problem in homelab k3s setups.

## How it works in dudlab

MetalLB runs in **L2 (Layer 2) mode**. This means:

1. You define an IP pool — a range of addresses reserved on your LAN (`192.168.0.240–250`)
2. When a service requests a `LoadBalancer` IP, MetalLB picks one from the pool and assigns it
3. The node hosting that service responds to ARP requests for that IP, making it appear as a regular device on the network
4. Your router doesn't need any special configuration — it just sees ARP like any other device

No BGP router or special network hardware required.

## Configuration

**IP pool** (`roles/metallb/files/metallb-config.yaml`):

```yaml
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: default-pool
  namespace: metallb-system
spec:
  addresses:
    - 192.168.0.240-192.168.0.250
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: default
  namespace: metallb-system
```

The `L2Advertisement` tells MetalLB to use ARP (Layer 2) to advertise IPs — no additional config needed.

**IP assignments** (`inventory/group_vars/all.yml`):

```yaml
metallb_ip_pool: "192.168.0.240-192.168.0.250"
pihole_ip: "192.168.0.241"
portainer_ip: "192.168.0.242"
grafana_ip: "192.168.0.243"
longhorn_ip: "192.168.0.244"
```

IPs `245–250` are currently unassigned, reserved for future services.

## IP sharing

Pi-hole needs three LoadBalancer services on the same IP (web UI, DNS TCP, DNS UDP). MetalLB supports this via the `allow-shared-ip` annotation — services with the same annotation value share the IP, but must use different ports/protocols:

```yaml
metallb.universe.tf/allow-shared-ip: pihole
```

Without this annotation, MetalLB only assigns the IP to the first service that requests it and leaves the others pending.

## Where it sits in the architecture

MetalLB is pure infrastructure — it has no UI and nothing to log in to. It's the invisible layer that makes everything else work. Every service with a fixed IP in the cluster is using MetalLB to get it.

```
Service (type: LoadBalancer, loadBalancerIP: 192.168.0.241)
    │
    ▼
MetalLB assigns 192.168.0.241 from the pool
    │
    ▼
Node responds to ARP for 192.168.0.241
    │
    ▼
Browser hits http://192.168.0.241 → traffic reaches the pod
```

## Useful commands

```bash
# See what IPs have been assigned
kubectl get svc -A | grep LoadBalancer

# Check MetalLB is running
kubectl get pods -n metallb-system

# Inspect the IP pool
kubectl get ipaddresspool -n metallb-system

# See which node is handling a given IP (L2 mode only)
kubectl get l2advertisements -n metallb-system
```

## Version note

MetalLB v0.15.2 merged the webhook server into the controller pod. If you see documentation referencing a `metallb-webhook-server` deployment, it's out of date — only `controller` and `speaker` pods exist in v0.15+.
