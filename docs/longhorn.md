# Longhorn

## What it is

Longhorn is a distributed block storage system for Kubernetes. It provides persistent volumes that survive pod restarts, rescheduling, and node failures — things that Kubernetes doesn't handle by default (pods are stateless; if a pod moves to a different node, it loses access to any local disk data).

Longhorn stores data across multiple nodes as replicas, so if one node goes down, your data is still accessible from another.

## Why Longhorn

| Alternative | Trade-off |
|-------------|-----------|
| **local-path (k3s default)** | Simple, fast, but data is tied to a single node — no redundancy, no failover |
| **NFS share** | Works, but requires separate NFS server; single point of failure unless that's also HA |
| **Rook/Ceph** | More powerful (object + block + file storage), but heavyweight — overkill for a 2-node homelab |
| **OpenEBS** | Similar to Longhorn, slightly more complex setup |

Longhorn was chosen because it's lightweight, has a clean web UI, integrates well with Helm, and is designed exactly for this use case — small bare-metal clusters that need replicated storage without a lot of operational overhead.

## How it works

When a pod requests a `PersistentVolumeClaim` (PVC), Longhorn:

1. Creates a volume and distributes replica copies across nodes (default: 2 replicas)
2. Presents that volume to the pod as a standard block device
3. Keeps replicas in sync as data is written
4. If a node goes offline, the volume remains accessible from the surviving replica
5. When the node comes back, Longhorn rebuilds the replica automatically

From a pod's perspective, it's just a disk — the replication is completely transparent.

## Setup in dudlab

Longhorn is deployed via Helm with two key settings:

```bash
helm upgrade --install longhorn longhorn/longhorn \
  --namespace longhorn-system \
  --set defaultSettings.defaultReplicaCount=2
```

- **2 replicas** — each volume gets one copy on server-1 and one on server-2. With 2 nodes this is the maximum useful replica count.
- **Default StorageClass** — after install, `local-path` (the k3s default) is demoted and Longhorn becomes the default. Any PVC that doesn't specify a storage class gets Longhorn automatically.

The Longhorn UI is exposed via a LoadBalancer service at `http://192.168.0.244`.

## Where it sits in the architecture

Longhorn is the storage layer that stateful services depend on. Pi-hole uses a Longhorn PVC to persist its blocklist and configuration. Any future apps (finance tracker, etc.) that need a database will also use Longhorn.

```
Pod requests PersistentVolumeClaim
    │
    ▼
Longhorn creates volume (2 replicas)
    ├── Replica on server-1  (/var/lib/longhorn/...)
    └── Replica on server-2  (/var/lib/longhorn/...)
    │
    ▼
Pod mounts volume as /data (or wherever)
```

## What you can do with it

### Longhorn UI (`http://192.168.0.244`)

- **Volumes** — see all PVCs, their replica status, which nodes they're on
- **Nodes** — see storage capacity and disk usage per node
- **Backups** — configure S3 or NFS backup targets and take snapshots
- **Settings** — tweak defaults like replica count, storage reservation, backup schedule

### Useful commands

```bash
# See all persistent volume claims across the cluster
kubectl get pvc -A

# See the underlying Longhorn volumes
kubectl get volumes -n longhorn-system

# Check StorageClass (Longhorn should be default)
kubectl get storageclass

# Describe a specific PVC
kubectl describe pvc <name> -n <namespace>
```

### Requesting storage from a pod (example)

Any deployment or StatefulSet can request Longhorn storage:

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: my-app-data
  namespace: my-app
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: longhorn
  resources:
    requests:
      storage: 5Gi
```

Then mount it in a pod:

```yaml
volumes:
  - name: data
    persistentVolumeClaim:
      claimName: my-app-data
containers:
  - name: app
    volumeMounts:
      - name: data
        mountPath: /data
```

## Degraded volumes

A volume shows as "Degraded" when one replica is out of sync (e.g. a node was offline during a write, or a node had network issues during initial provisioning). This doesn't mean data is lost — the healthy replica is still serving the volume. Longhorn will automatically rebuild the degraded replica once the node is back and healthy.

You can trigger a manual rebuild from the UI: **Volumes → (volume name) → Replicas → Rebuild**.

## Backups (future)

Longhorn supports snapshot and backup to:
- S3 (AWS, Backblaze B2, MinIO)
- NFS

This isn't configured yet. Worth setting up once the cluster is stable — particularly for Pi-hole's blocklist config and any future app databases.
