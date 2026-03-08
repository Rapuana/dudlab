# Pi-hole

## What it is

Pi-hole is a network-wide DNS ad-blocker. Instead of blocking ads at the browser level (like uBlock Origin), Pi-hole blocks them at the DNS level — before the request even leaves your network. Any device on your LAN that uses Pi-hole as its DNS server gets ad-blocking automatically, including phones, smart TVs, and anything else that can't run a browser extension.

It works by maintaining blocklists of known ad, tracking, and telemetry domains. When a device tries to look up `ads.doubleclick.net`, Pi-hole returns nothing (or `0.0.0.0`) instead of the real IP, so the ad never loads.

## Why Pi-hole

| Alternative | Trade-off |
|-------------|-----------|
| **Browser extensions (uBlock Origin)** | Per-device, per-browser only — doesn't cover apps, phones, smart TVs |
| **AdGuard Home** | Very similar feature set, arguably better UI; Pi-hole has larger community and more blocklists |
| **DNS over HTTPS providers (NextDNS, Cloudflare)** | Cloud-based, easy to set up, but your DNS queries go to a third party |
| **Unbound (recursive resolver)** | Pairs well with Pi-hole for full DNS privacy, no third-party resolver needed |

Pi-hole is the most established self-hosted DNS ad-blocker with the largest community and widest blocklist ecosystem.

## How it works

```
Device requests: "what is the IP of ads.doubleclick.net?"
    │
    ▼
Pi-hole DNS server (192.168.0.241)
    │
    ├── Is this domain on the blocklist?
    │   ├── YES → return NXDOMAIN (blocked)
    │   └── NO → forward to upstream DNS (e.g. 8.8.8.8) → return real IP
    │
    ▼
Device either gets the IP (allowed) or nothing (blocked)
```

Pi-hole acts as a forwarding DNS resolver — it doesn't resolve domains itself, it passes allowed queries upstream to a real resolver (Google DNS, Cloudflare, etc.).

## Setup in dudlab

Pi-hole is deployed via Helm on Kubernetes. It runs three LoadBalancer services all sharing `192.168.0.241`:

| Service | Protocol | Port | Purpose |
|---------|----------|------|---------|
| `pihole-web` | TCP | 80, 443 | Admin web UI |
| `pihole-dns-tcp` | TCP | 53 | DNS (large responses, zone transfers) |
| `pihole-dns-udp` | UDP | 53 | DNS (standard queries) |

All three share the same IP via MetalLB's `allow-shared-ip` annotation.

Pi-hole's blocklist database and configuration are stored on a Longhorn PVC — so they persist across pod restarts and node failovers.

**Admin UI:** `http://192.168.0.241/admin`
**Password:** `dudlab-pihole` (change this after first login)

## Activating network-wide ad-blocking

Pi-hole does nothing until you point devices at it. There are two ways:

### Option 1: Router-level (recommended)

Set your router's DNS server to `192.168.0.241`. Every device on the network automatically uses Pi-hole without any per-device configuration.

How to do this varies by router:
- **Most home routers**: LAN settings → DHCP settings → DNS server → set to `192.168.0.241`
- Some routers call it "Primary DNS" in the WAN or LAN section

Once set, new DHCP leases will pick it up. Existing devices may need to renew their lease (`ipconfig /release && /renew` on Windows, reconnect on phone) or wait for the lease to expire.

### Option 2: Per-device

Set DNS manually on individual devices:
- iPhone/iPad: Settings → Wi-Fi → (network) → Configure DNS → Manual → `192.168.0.241`
- Mac: System Settings → Network → (interface) → DNS → `192.168.0.241`
- Android: varies by version, often under Private DNS or network settings

### Verifying it works

After pointing a device at Pi-hole, check the Pi-hole dashboard — you should see queries appearing in real time under **Dashboard → Queries**. You can also test from the command line:

```bash
# Should return 0.0.0.0 or NXDOMAIN if blocked
nslookup ads.doubleclick.net 192.168.0.241

# Should return a real IP
nslookup google.com 192.168.0.241
```

## What you can do with it

### Admin UI (`http://192.168.0.241/admin`)

**Dashboard**
- Live query graph — see DNS traffic across your network in real time
- Top blocked domains — what's being blocked most
- Top clients — which devices are making the most DNS queries
- Query log — searchable history of every DNS request

**Blocklists**
- Go to **Group Management → Adlists** to add more blocklists
- Recommended lists:
  - `https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts` (default, general purpose)
  - `https://raw.githubusercontent.com/PolishFiltersTeam/KADhosts/master/KADhosts.txt` (Polish-specific)
  - OISD (https://oisd.nl) — well-maintained, low false positives

**Whitelist / Blacklist**
- If something is broken after enabling Pi-hole, a legitimate domain is probably blocked
- **Group Management → Domains** → add to whitelist
- Check **Query Log** to find what's being blocked for a specific device

**Custom DNS (local DNS entries)**
- Go to **Local DNS → DNS Records**
- Add entries like `dudley-server-1.local → 192.168.0.38`
- This lets you use hostnames instead of IPs for local services

**Clients**
- See per-device statistics — how many queries, how many blocked
- Name devices by MAC address so they appear with friendly names instead of IPs

### Useful commands

```bash
# Check Pi-hole pod is running
kubectl get pods -n pihole

# Check all three services have their IP
kubectl get svc -n pihole

# View Pi-hole logs
kubectl logs -n pihole -l app=pihole -f

# Check the PVC (blocklist storage)
kubectl get pvc -n pihole
```

## Where it sits in the architecture

```
All LAN devices
    │
    │  DNS queries (port 53)
    ▼
Pi-hole (192.168.0.241)
    │
    ├── Blocked → NXDOMAIN returned immediately
    │
    └── Allowed → upstream DNS (8.8.8.8)
                    │
                    ▼
              Real IP returned to device
```

Pi-hole depends on:
- **MetalLB** — to get and share `192.168.0.241` across its three services
- **Longhorn** — for persistent storage of blocklists and config

## Keeping blocklists updated

By default Pi-hole updates blocklists via a cron job (`pihole -g`) every week. You can trigger a manual update from the UI: **Tools → Update Gravity**.

After adding new adlists in the UI, run Update Gravity to download and apply them.
