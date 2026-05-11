# Backup

A Docker-based backup orchestration system that uses Kopia to snapshot service data from source servers to a central backup server.

## Language

**Service**:
A named, independently-backupable unit consisting of one Docker container and one or more data paths.
_Avoid_: app, workload, target

**Path**:
A file or directory inside the backup client container to be snapshotted. Can be a Docker volume mount or bind mount — no distinction.
_Avoid_: volume, mount point

**Client**:
A Docker container running on a source server that connects to the Server, snapshots Service data, and manages container stop/start lifecycle.
_Avoid_: agent, runner

**Server**:
A Docker container running on the backup machine that hosts the Kopia repository, authenticates Clients, and optionally serves the web UI.
_Avoid_: backend, target, destination

**Mode**:
A per-Service setting that determines container behavior during snapshot. `stop` halts the container before snapshot and restarts after. `live` snapshots while the container runs.
_Avoid_: strategy, backup type

**Retention**:
A per-Path policy defining how many snapshots to keep across time intervals (daily, weekly, monthly). Defaults to Service-level retention if not specified on the Path.
_Avoid_: rotation, cleanup policy

**Restore**:
A manual, user-initiated operation that retrieves a specific snapshot to a target path. No automatic container stop — user handles the full workflow.
_Avoid_: recovery

## Relationships

- A **Client** connects to exactly one **Server** via password authentication
- A **Server** accepts connections from one or more **Clients**
- A **Client** manages one or more **Services** defined in its config file
- A **Service** has exactly one **Mode** (stop or live)
- A **Service** has one or more **Paths**, each with its own **Retention** (or inherited from Service)
- A **Service** optionally references a Docker container by name; if omitted, **Mode** is implicitly `live`
- **Paths** within a **Service** are snapshotted sequentially
- **Services** are processed sequentially (no grouped stops across Services)

## Example dialogue

> **Dev:** "When a **Client** snapshots a **Service** with `mode: stop`, what happens to the container?"
> **Domain expert:** "The **Client** stops the container by name, snapshots all **Paths** for that **Service**, then starts it again. If stop fails, the snapshot is aborted. If start fails after snapshot, the **Client** retries and sends a failure email."

> **Dev:** "Can a **Service** exist without a container?"
> **Domain expert:** "Yes. If no container is specified, **Mode** is always `live` — we just snapshot the **Paths** without touching any container."

> **Dev:** "Who handles scheduling?"
> **Domain expert:** "Kopia. We configure what to back up and the **Retention** policies. Kopia's built-in scheduler decides when."

## Flagged ambiguities

- "volume" was used interchangeably for Docker volumes and backup paths — resolved: use **Path** in this context, since it can be a volume mount, bind mount, or single file.
- "service" could mean Docker Compose service or our backup concept — resolved: **Service** in this context always means the backup unit, not the Docker Compose service definition.
