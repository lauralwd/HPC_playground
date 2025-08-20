#!/bin/bash
set -e

ROLE="$1"
shift

# Start munge
if [ -f /etc/munge/munge.key ]; then
  chown munge:munge /etc/munge/munge.key
  chmod 400 /etc/munge/munge.key
fi
mkdir -p /var/run/munge
chown munge:munge /var/run/munge
service munge start || /etc/init.d/munge start || true

# Create users
if [ -f /etc/hpc/users.csv ]; then
  while IFS=, read -r user uid gid keypath; do
    [[ "$user" =~ ^#.*$ ]] && continue
    home_dir="/home/$user"
    groupadd -g "$gid" "$user" || true
    useradd -M -u "$uid" -g "$gid" -s /bin/bash -d "$home_dir" "$user" || true
    mkdir -p "$home_dir/.ssh" "$home_dir/results"
    if [ -f "/etc/hpc/$keypath" ]; then
      cat "/etc/hpc/$keypath" > "$home_dir/.ssh/authorized_keys"
    fi
    # SSH config for intra-node SSH
    cat <<EOF > "$home_dir/.ssh/config"
Host compute1 compute2 dtn login
  StrictHostKeyChecking no
  UserKnownHostsFile=/dev/null
EOF
    chown -R "$user:$gid" "$home_dir"
    chmod 700 "$home_dir/.ssh"
    chmod 600 "$home_dir/.ssh/authorized_keys" "$home_dir/.ssh/config"
  done < /etc/hpc/users.csv
fi

# Role-specific startup
if [ "$ROLE" = "controller" ]; then
  su - slurm -c "slurmctld"
  /usr/sbin/sshd -D
elif [ "$ROLE" = "compute" ]; then
  su - slurm -c "slurmd"
  tail -f /dev/null
elif [ "$ROLE" = "dtn" ]; then
  mkdir -p /shared/uploads /shared/data
  while true; do
    mv /shared/uploads/* /shared/data/ 2>/dev/null || true
    sleep 5
  done
else
  echo "Unknown role: $ROLE"
  exit 1
fi