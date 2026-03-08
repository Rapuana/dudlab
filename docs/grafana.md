# Grafana + Prometheus

## What it is

The monitoring stack is deployed as `kube-prometheus-stack`, a Helm chart that bundles three components:

- **Prometheus** — collects and stores metrics from the cluster (time-series database)
- **Grafana** — visualises those metrics as dashboards
- **Node Exporter** — runs on every node and exposes hardware metrics (CPU, RAM, disk, network)
- **kube-state-metrics** — exposes Kubernetes object state as metrics (pod counts, deployment health, etc.)

Together they give you a complete picture of what the cluster is doing and how healthy it is.

## Why this stack

| Alternative | Trade-off |
|-------------|-----------|
| **Netdata** | Easier setup, lower resource use, but less flexible and Kubernetes-native |
| **InfluxDB + Telegraf + Grafana** | More flexibility but three separate tools to manage |
| **Datadog / New Relic** | Excellent but cloud SaaS, not self-hosted |
| **VictoriaMetrics** | More efficient than Prometheus at scale, but more complex |
| **Loki stack (logs)** | Complements this stack for log aggregation — worth adding later |

`kube-prometheus-stack` is the de-facto standard for Kubernetes monitoring. The Helm chart wires everything together automatically — Prometheus scrapes the right endpoints, Grafana is pre-configured with data sources, and a large set of dashboards are included out of the box.

## Setup in dudlab

Deployed via Helm:

```bash
helm upgrade --install kube-prometheus-stack \
  prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --set grafana.service.type=LoadBalancer \
  --set grafana.service.loadBalancerIP=192.168.0.243 \
  --set grafana.adminPassword=dudlab-admin
```

Grafana is accessible at `http://192.168.0.243`.

**Default credentials:**
- Username: `admin`
- Password: `dudlab-admin` — change this after first login

Prometheus runs internally (no external IP) — it's only accessed by Grafana.

## Where it sits in the architecture

```
Every node
    │
    ├── Node Exporter (hardware metrics: CPU, RAM, disk, network)
    └── k3s metrics endpoint
    │
    ▼
Prometheus (scrapes metrics every 30s, stores time-series data)
    │
    ▼
Grafana (queries Prometheus, renders dashboards)
    │
    ▼
Browser → http://192.168.0.243
```

kube-state-metrics also feeds Prometheus with cluster-level data (how many pods are running, are deployments healthy, etc.).

## What you can see out of the box

The Helm chart installs a full set of pre-built dashboards. On first login, go to **Dashboards → Browse**:

### Kubernetes dashboards
- **Kubernetes / Compute Resources / Cluster** — overall CPU and memory usage across the cluster
- **Kubernetes / Compute Resources / Node** — per-node breakdown
- **Kubernetes / Compute Resources / Namespace** — per-namespace resource usage (useful for seeing what Pi-hole vs Longhorn vs monitoring is consuming)
- **Kubernetes / Compute Resources / Pod** — per-pod CPU/memory over time
- **Kubernetes / Persistent Volumes** — PVC usage (see how full your Longhorn volumes are)

### Node dashboards
- **Node Exporter / Nodes** — full hardware metrics: CPU temperature (if available), disk I/O, network throughput, RAM usage

### Kubernetes state dashboards
- **Kubernetes / API server** — API server request rates and latencies
- **Kubernetes / Kubelet** — node agent health

## What you can do with it

### Creating custom dashboards

Go to **Dashboards → New Dashboard → Add visualization**.

Grafana uses PromQL (Prometheus Query Language) to pull data. Some useful queries:

```promql
# CPU usage per node (percentage)
100 - (avg by (instance) (irate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)

# RAM usage per node
node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes * 100

# Disk usage on /
(node_filesystem_size_bytes{mountpoint="/"} - node_filesystem_avail_bytes{mountpoint="/"})
  / node_filesystem_size_bytes{mountpoint="/"}  * 100

# Network traffic in (bytes/sec)
irate(node_network_receive_bytes_total{device="eth0"}[5m])

# Number of running pods
sum(kube_pod_status_phase{phase="Running"})
```

### Alerts

Grafana supports alerting — send a notification when something crosses a threshold. Integrations include:

- Email
- Slack
- Telegram
- PagerDuty
- Webhooks

Example: alert when a node's RAM usage exceeds 90% for more than 5 minutes.

To set up: **Alerting → Alert rules → New alert rule**, then set a contact point under **Alerting → Contact points**.

### Exploring raw metrics

Go to **Explore** (compass icon in the sidebar), select the Prometheus data source, and run PromQL queries directly. Useful for finding out what metrics are available:

```promql
# List all metrics exported by Node Exporter
{job="node-exporter"}

# Find metrics about a specific pod
{pod=~"pihole.*"}
```

### Checking Longhorn storage health via metrics

Longhorn exports metrics to Prometheus automatically. You can query:

```promql
# Longhorn volume capacity
longhorn_volume_capacity_bytes

# Longhorn volume actual size used
longhorn_volume_actual_size_bytes
```

## Adding Loki for logs (future)

The natural next addition is Loki — Grafana's log aggregation system. It works like Prometheus but for logs instead of metrics, and integrates directly into the Grafana UI so you can correlate logs and metrics on the same dashboard.

Install via: `helm install loki grafana/loki-stack --namespace monitoring`
