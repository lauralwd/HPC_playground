# HPC Playground

This is Laura's simple HPC playground.
A set of docker images simulates a Slurm HPC environment connected via a docker network bridge.
Nextflow and conda are installed by default.
Users should submit a public ssh key to the sys-admin/teacher before spinning up the cluster.

The HPC playground consists of

- SSH login node with user accounts
- Slurm job queue and compute nodes
- Intra-node SSH connections (e.g., `ssh compute1`)
- Shared storage (`/shared`)
- Toy Nextflow pipeline

---

## 🧰 Quick start

### 1. Build & start the cluster

But first, make sure the munge folder has permissions 755

```bash
chmod 755 munge
docker compose up --build -d
```

Exposes SSH on port `2222` (mapped to the login node).

### 2. Login as a user

```bash
ssh -p 2222 alice@<your-nas-ip>
```

(Use the private key matching `users/keys/alice.pub`)

---

## 🧪 Test a job

From inside the login node (as `alice`):

```bash
cd
cp /opt/nextflow/pipelines/example.fastq .
cp /opt/nextflow/pipelines/linecount.nf .
nextflow run linecount.nf
```

To run a bash job with Slurm:

```bash
echo '#!/bin/bash
wc -l ~/example.fastq > ~/results/lines.txt' > job.sh
chmod +x job.sh

echo '#!/bin/bash
#SBATCH --job-name=count
#SBATCH --output=job.out
#SBATCH --ntasks=1
#SBATCH --mem=512M
#SBATCH --time=00:05:00
bash ~/job.sh' > run.slurm

sbatch run.slurm
```

Then check:

```bash
squeue -u alice
cat job.out
```

---

## 👥 Add new users

1. Add their line to `users/users.csv`:
   ```
   laura,1003,1003,keys/laura.pub
   ```
2. Place their public SSH key in `users/keys/laura.pub`
3. Run:
   ```bash
   docker compose restart login compute1 compute2 dtn
   ```

This will recreate the UNIX user accounts inside the containers with persistent home folders.

---

## 🧼 Reset between course runs

To clear homes and data:

```bash
docker compose down
rm -rf homes/* shared/*
```
Then rebuild:

```bash
docker compose up --build -d
```

---

## 🔐 Notes

- SSH between nodes works with no prompts due to `.ssh/config`
- Each user's `$HOME` is `/home/<user>` shared across all containers
- Shared folder: `/shared`
  - `/shared/data/` – staged input
  - `/shared/results/` – output (optional)
  - `/shared/uploads/` – DTN staging

---


## 🛠 Roadmap (optional future additions)

- Slurm accounting (`sacct`)
- Slurm Web UI (e.g. slurm-web)
- Per-user home quota enforcement
- JupyterHub or web terminals

---

## ⚠️ Known limitations

- **No user quotas**: Home folders are shared but not space-limited per user (you can monitor usage manually).
- **No authentication isolation**: All users are defined within containers. There is no integration with external authentication (e.g. LDAP).
- **No job accounting**: There is no job usage tracking (`sacct`) or fair-share scheduling. All jobs are treated equally.
- **Single-node login**: There is only one login node, and it does not balance users or connections.
- **No container security hardening**: Containers run services as root and are not secured for untrusted users. Do not expose to the public internet.
- **No persistent network identity**: Hostnames are stable, but IPs may change unless reserved via Compose networking.
- **Limited performance realism**: All nodes run on the same physical NAS with limited CPU. This is for training, not benchmarking.
- **No graphical tools or remote desktops**: SSH is the only access method. No X11, Jupyter, or web GUIs are pre-installed.
- **No SLURM mail notifications**: Email alerts for job start/end/fail are not configured.