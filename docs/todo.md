# Dudlab Cluster — Backlog

Pending improvements, roughly in priority order. See also the original review in the commit history.

---

## Phase 2 — Next sprint

### Move Helm credentials out of `--set` flags

**Why:** Passwords passed as `--set` flags appear in `ps aux` output and Ansible logs. Vault encryption doesn't help here because the decrypted value is visible at deploy time.

**Fix:** For Grafana and Pi-hole, create a Kubernetes Secret in a separate task, then reference it in the Helm values file using `existingSecret`. The password never appears in process listings.

Files: `playbooks/deploy_grafana.yml`, `playbooks/deploy_pihole.yml`

---

### Longhorn off-cluster backups

**Why:** Longhorn replicates data across both nodes, but if both nodes fail (fire, theft, power event), all data is lost. Replication is high availability, not backup.

**Fix:** Pick a backup target — NFS share, Minio on a spare machine, or Backblaze B2 — and configure it in the Longhorn UI under **Settings → Backup**. Set a recurring backup schedule (weekly minimum).

Even one off-cluster backup destination makes recovery possible.

---

### Grafana alerting — node down + Longhorn volume degraded

**Why:** Currently, a node going down or a Longhorn volume becoming degraded requires manual discovery (checking the dashboards). No notification is sent.

**Suggested alerts:**
- Node unreachable for > 2 minutes → notify
- Longhorn volume in degraded state → notify
- Internet probe down for > 5 minutes → notify

**Fix:** In Grafana: **Alerting → Alert rules → New alert rule**. Set up a contact point (email or Discord webhook) under **Alerting → Contact points** first.

---

### Pi-hole Grafana integration

**Why:** Pi-hole metrics (queries/day, blocked %, blocklist size, top clients) would be useful in Grafana alongside the cluster metrics.

**Fix:** Deploy `ekofr/pihole-exporter` as a Deployment in the `monitoring` namespace, pointed at `http://192.168.0.241/admin/api.php`. Create a ServiceMonitor so Prometheus scrapes it. Import or write a Grafana dashboard for the metrics.

Depends on: Pi-hole confirmed working and stable.

---

## Phase 3 — When server-3 arrives

### HA control plane (3-node etcd)

**Why:** Currently k3s uses SQLite (single-node mode). If `dudley-server-1.local` dies, the k3s API goes down — `kubectl` stops working and no new pods can be scheduled.

**Fix:** k3s supports embedded etcd HA with 3 master nodes. Adding server-3 as a second master (and making server-1 + server-3 the HA pair) requires re-provisioning the cluster carefully.

This is a significant change — plan it separately before server-3 arrives.

---

### Assign static IPs to all nodes

**Why:** `dudley-server-2.local` uses DHCP. If its lease changes or mDNS is flaky, Ansible can't reach it. The `hosts.ini` has no IP for it, just the `.local` name.

**Fix:** Assign DHCP reservations by MAC address on the router for both servers. Add the IPs to `inventory/group_vars/all/vars.yml` and document them. Update `hosts.ini` to use IPs directly as fallback.

---

### GitHub Actions — ansible-lint on PR

**Why:** Pre-commit hooks only run locally. CI catches lint regressions for everyone and is a safety net when pushing from machines without pre-commit configured.

**Fix:** Add `.github/workflows/lint.yml` running `yamllint` + `ansible-lint` on every PR. No secrets needed — lint is syntax-only.

---

## Known architectural constraints (not bugs)

- **MetalLB L2 mode:** One node owns each VIP and responds to ARP. That node is a single point of failure for that service IP. Failover is automatic (~10s) but there's no visibility into which node currently owns which IP. This is a property of L2 mode, not a bug.

- **Single k3s master:** Until server-3 provides a second master, the k3s control plane has no HA. This is a known, documented constraint.

- **Longhorn UI unauthenticated:** The Longhorn UI at `192.168.0.244` has no built-in authentication. Acceptable on a trusted home network; worth adding a reverse proxy with basic auth if the network is ever shared.
