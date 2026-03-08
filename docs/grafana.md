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

Deployed via Helm with a values file at `playbooks/files/kube-prometheus-stack-values.yml`. The values file handles:

- Prometheus `serviceMonitorSelector: {}` — makes Prometheus pick up ALL ServiceMonitors across all namespaces, not just ones labelled for kube-prometheus-stack. Required for the blackbox and speedtest exporters to be scraped.
- Grafana dashboard provisioning via the grafana-sc-dashboard sidecar.

Grafana is accessible at `http://192.168.0.243`.

**Credentials:** username `admin`, password stored in ansible-vault (`vault_grafana_admin_password`).

Prometheus runs internally (no external IP) — it's only accessed by Grafana.

## Network monitoring extras

Two additional exporters are deployed by `deploy_network_monitoring.yml`:

### Blackbox Exporter

Probes remote targets and reports whether they're reachable and how long they take to respond. Runs every 60 seconds against:

| Target | Probe type |
|--------|-----------|
| `1.1.1.1` (Cloudflare DNS) | ICMP ping |
| `8.8.8.8` (Google DNS) | ICMP ping |
| `https://www.google.com` | HTTP 2xx |
| `https://1.1.1.1` (Cloudflare) | HTTP 2xx |

Key metrics: `probe_success` (1=up, 0=down), `probe_duration_seconds` (round-trip latency).

### Speedtest Exporter

Runs an Ookla speedtest every 5 minutes and exposes the results as Prometheus metrics. Each test takes ~30 seconds.

Key metrics: `speedtest_download_bits_per_second`, `speedtest_upload_bits_per_second`, `speedtest_ping_latency_milliseconds`, `speedtest_jitter_latency_milliseconds`.

## Dashboards

### Pre-built (shipped with kube-prometheus-stack)

Go to **Dashboards → Browse** on first login:

**Kubernetes dashboards**
- **Kubernetes / Compute Resources / Cluster** — overall CPU and memory usage across the cluster
- **Kubernetes / Compute Resources / Node** — per-node breakdown
- **Kubernetes / Compute Resources / Namespace** — per-namespace resource usage
- **Kubernetes / Compute Resources / Pod** — per-pod CPU/memory over time
- **Kubernetes / Persistent Volumes** — PVC usage (see how full your Longhorn volumes are)

**Node dashboards**
- **Node Exporter / Nodes** — full hardware metrics: CPU, disk I/O, network throughput, RAM, load

### Provisioned via ConfigMaps (auto-loaded, no import needed)

These dashboards are stored in `playbooks/files/dashboards/` and provisioned as ConfigMaps labelled `grafana_dashboard=1`. The Grafana sidecar picks them up automatically within ~30s of deploy.

- **Network Probes** — probe status (up/down), probe duration, and probe success over time for all blackbox targets
- **Internet Speed** — download/upload Mbps, ping, and jitter over time from speedtest results

### Community dashboards (downloaded from grafana.com at deploy time)

- **Node Exporter Full** (ID 1860) — comprehensive per-node metrics, more detailed than the built-in node dashboard
- **Kubernetes Cluster** (ID 7249) — cluster overview

## Where it sits in the architecture

```
Every node
    │
    ├── Node Exporter (hardware metrics: CPU, RAM, disk, network)
    └── k3s metrics endpoint
    │
    ▼
Prometheus (scrapes metrics every 30s, stores time-series data)
    ▲
    ├── Blackbox Exporter (internet ping + HTTP probes every 60s)
    └── Speedtest Exporter (bandwidth test every 5m)
    │
    ▼
Grafana (queries Prometheus, renders dashboards)
    │
    ▼
Browser → http://192.168.0.243
```

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

# Internet download speed (Mbps)
speedtest_download_bits_per_second / 1e6

# Probe success for all blackbox targets
probe_success
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
# All Node Exporter metrics
{job="node-exporter"}

# Blackbox probe metrics
{job=~"blackbox.*"}

# Speedtest metrics
{__name__=~"speedtest_.*"}

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
