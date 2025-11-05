# HPC Playground - AI Coding Assistant Instructions

## Project Overview
This is a containerized HPC (High Performance Computing) simulation environment using Docker Compose to replicate a Slurm cluster. It provides an educational/testing platform with login nodes, compute nodes, and shared storage.

## Architecture
- **4 Container Types**: `login` (controller/SSH gateway), `compute1`/`compute2` (worker nodes), `dtn` (data transfer node)
- **Shared Volumes**: `/home` (user directories), `/shared` (cluster storage), `/etc/munge` (authentication keys)
- **Network**: Custom bridge network `172.25.0.0/16` for inter-node communication
- **Entry Points**: All containers use `entrypoint.sh` with role-based startup (`controller`, `compute`, `dtn`)

## Key Files & Structure
- `docker-compose.yml`: Service definitions with volume mounts and dependencies
- `Dockerfile`: Multi-target build (base → controller/compute/dtn variants)
- `entrypoint.sh`: Container initialization script handling Munge auth + role-specific daemons
- `slurm/conf/slurm.conf`: Cluster configuration (2 compute nodes, debug partition)
- `users/users.csv`: User account definitions (username,uid,gid,pubkey_path)
- `nextflow/pipelines/`: Example workflows for testing

## Critical Workflows

### Starting the Environment
```bash
chmod 755 munge  # Required before first run
docker compose up --build -d
```

### User Management
1. Add line to `users/users.csv`: `username,uid,gid,keyfile.pub`
2. Place SSH public key in `users/` directory
3. Restart containers: `docker compose restart login compute1 compute2 dtn`

### Testing Jobs
SSH access: `ssh -p 2424 user@localhost` (port 2424 → login container)
- Slurm commands: `squeue`, `sbatch`, `sinfo`
- Nextflow testing: Copy from `/opt/nextflow/pipelines/` to user home

## Development Patterns

### Container Role System
- `entrypoint.sh` uses `$1` parameter to determine container behavior
- Login node: runs `slurmctld` + `sshd`
- Compute nodes: run `slurmd` daemon only
- DTN node: file transfer service (moves `/shared/uploads/*` → `/shared/data/`)

### Volume Mount Strategy
All containers share:
- User homes at `/home` (persistent across restarts)
- Cluster storage at `/shared` (data/uploads/results)
- Configuration files mounted read-only from host

### Authentication Flow
- Munge keys generated on first login node startup
- SSH keys bootstrapped only on login node (`USER_BOOTSTRAP=1`)
- Inter-node SSH configured for passwordless access

## Integration Points
- **Slurm**: Login node is controller, compute nodes are workers
- **Nextflow**: Pre-installed with example pipelines in `/opt/nextflow/pipelines/`
- **Networking**: Hostnames match container names for inter-node communication
- **Storage**: `/shared` provides cluster-wide filesystem simulation

## Debugging Commands
- Check cluster status: `sinfo`, `squeue`
- Container logs: `docker compose logs [service]`
- Reset environment: `docker compose down && rm -rf homes/* shared/*`
- Munge issues: Check `/etc/munge/munge.key` permissions (400, munge:munge)
- Common Munge fix: `docker compose down && sudo rm -rf munge/munge.key && docker compose up --build -d`
- Slurm config permissions: `chmod 644 slurm/conf/slurm.conf` on host if permission errors

## Limitations to Remember
- No quotas, accounting, or security hardening
- Single login node, no load balancing
- All containers run on same host (no real distributed computing)
- No external auth integration (LDAP/AD)