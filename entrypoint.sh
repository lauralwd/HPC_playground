#!/bin/bash
set -e

ROLE="$1"
shift

# generate munge key on login node ONLY if it doesn't exist yet

if [[ "$ROLE" == "controller" && ! -f /etc/munge/munge.key ]]; then
    echo "Generating new MUNGE key on controller..."
    # Ensure munge directory exists and has correct ownership
    echo ' create dir /etc/munge'
    mkdir -p /etc/munge
    chown munge:munge /etc/munge
    chmod 700 /etc/munge
    
    # Generate the key as root, then fix ownership
    echo 'generate key'
    /usr/sbin/mungekey
    
    # Set correct permissions on the key file
    echo 'set key rights'
    chown munge:munge /etc/munge/munge.key
    chmod 400 /etc/munge/munge.key
    echo "MUNGE key created."
elif [[ ! -f /etc/munge/munge.key ]]; then
    echo "Waiting for controller to generate MUNGE key..."
    # Wait for the key to be available (shared volume)
    while [[ ! -f /etc/munge/munge.key ]]; do
        sleep 1
    done
    echo "MUNGE key found, proceeding..."
fi

# Start munge
mkdir -p /var/run/munge
chown munge:munge /var/run/munge
chmod 755 /var/run/munge

# Start munge daemon
service munge start || /etc/init.d/munge start || true

# Create users
# if [ -f /etc/hpc/users.csv ]; then
#   echo "Setting up user accounts from users.csv..."
#   while IFS=, read -r username uid gid pubkey_path; do
#       # Create user if missing
#       if id "$username" &>/dev/null; then
#           echo "User $username already exists"
#       else
#           echo "Creating user $username"
#           useradd -m -u "$uid" -g "$gid" -s /bin/bash "$username"
#       fi

#       home_dir="/home/$username"
#       ssh_dir="$home_dir/.ssh"

#       mkdir -p "$ssh_dir"

#       # Only bootstrap SSH keys and config from login node
#       if [[ "$USER_BOOTSTRAP" == "1" ]]; then
#           echo "Setting up SSH key and config for $username"

#           if [ -f "$pubkey_path" ] ; then
#             cp "$pubkey_path" "$ssh_dir/authorized_keys"
#             chmod 600 "$ssh_dir/authorized_keys"
#           fi

#           # Generate minimal .ssh/config
#           cat > "$ssh_dir/config" <<EOF
#   Host compute1
#       HostName compute1
#       User $username
#       StrictHostKeyChecking no

#   Host compute2
#       HostName compute2
#       User $username
#       StrictHostKeyChecking no

#   Host dtn
#       HostName dtn
#       User $username
#       StrictHostKeyChecking no
#   EOF

#           chmod 600 "$ssh_dir/config"
#       fi

#       chmod 700 "$ssh_dir"
#       chown -R "$uid:$gid" "$home_dir"

#   done < /opt/users/users.csv
# fi

# Role-specific startup

chsh -s /bin/bash slurm

if [ "$ROLE" = "controller" ]; then
  echo "Setting up slurmctld daemon on controller" 
  # Wait a bit for munge to be fully ready
  sleep 2
  slurmctld -D &
  /usr/sbin/sshd -D
elif [ "$ROLE" = "compute" ]; then
  echo "Setting up slurmd daemon on compute node"
  # Wait for controller to be ready and munge to start
  sleep 5
  # Test connectivity to controller
  until ping -c 1 login >/dev/null 2>&1; do
    echo "Waiting for login node to be reachable..."
    sleep 2
  done
  su slurm -c "slurmd -D"
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