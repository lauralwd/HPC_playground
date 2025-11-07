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
  
  # Set up proper permissions for slurm directories first
  sudo mkdir -p /var/spool/slurmctld /var/log/slurm
  sudo chown slurm:slurm /var/spool/slurmctld /var/log/slurm
  sudo chmod 755 /var/spool/slurmctld /var/log/slurm
  
  # Dynamic CPU configuration like the working example
  sudo sed -i "s/REPLACE_IT/$(nproc)/g" /etc/slurm/slurm.conf
  
  # Simple approach - use sudo service like the working example
  sudo service munge start
  sleep 3
  
  # Test Munge on controller
  echo "Testing Munge authentication on controller..."
  munge -n | unmunge || echo "Controller Munge test failed!"
  
  sudo service slurmctld start
  
  # Give slurmctld a moment to fully start
  sleep 5
  
  # Wait for slurmctld to be fully ready
  echo "Waiting for slurmctld to fully initialize..."
  for i in {1..30}; do
    if scontrol ping >/dev/null 2>&1; then
      echo "slurmctld is ready!"
      break
    else
      echo "Waiting for slurmctld initialization (attempt $i/30)..."
      sleep 2
    fi
  done
  
  # Check if slurmctld is actually running and listening
  echo "Checking slurmctld status..."
  sudo service slurmctld status || echo "slurmctld service status check failed"
  echo "Checking what slurmctld is actually listening on:"
  netstat -tlnp | grep 6817 || echo "Port 6817 not listening"
  echo "Checking all slurmctld listening ports:"
  netstat -tlnp | grep slurmctld || echo "No slurmctld ports found"
  
  # Test if the controller can talk to itself
  echo "Testing controller self-communication..."
  scontrol ping || echo "Controller self-ping failed"
  scontrol show config | grep -E "(ClusterName|ControlMachine|ControlAddr)" || echo "Config check failed"
  
  # Check slurmctld logs for any errors
  echo "Recent slurmctld log entries:"
  tail -10 /var/log/slurm/slurmctld.log 2>/dev/null || echo "No slurmctld logs found"
  
  # Start SSH daemon in foreground
  /usr/sbin/sshd -D
elif [ "$ROLE" = "compute" ]; then
  echo "Setting up slurmd daemon on compute node"
  
  # Set up proper permissions for slurm directories first
  sudo mkdir -p /var/spool/slurmd /var/log/slurm
  sudo chown slurm:slurm /var/spool/slurmd /var/log/slurm
  sudo chmod 755 /var/spool/slurmd /var/log/slurm
  
  # Dynamic CPU configuration like the working example
  sudo sed -i "s/REPLACE_IT/$(nproc)/g" /etc/slurm/slurm.conf
  
  # Simple approach - use sudo service like the working example
  sudo service munge start
  sleep 3
  
  # Debug: Show what CPU config was set
  echo "CPU configuration set to: $(nproc)"
  grep "CPUs=" /etc/slurm/slurm.conf | head -2
  
  # Wait for controller to be ready before starting slurmd
  echo "Waiting for controller to be available..."
  until ping -c 1 login >/dev/null 2>&1; do
    echo "Waiting for login node to be reachable..."
    sleep 2
  done
  
  # Test if slurmctld port is open
  until nc -z login 6817; do
    echo "Waiting for slurmctld to be ready on login:6817..."
    sleep 3
  done
  
  # Test Munge authentication
  echo "Testing Munge authentication..."
  munge -n | unmunge || echo "Munge test failed!"
  
  # Test communication with controller
  echo "Testing Slurm communication..."
  scontrol ping || echo "Scontrol ping failed"
  
  # Show Slurm version info for debugging
  echo "Slurm version information:"
  slurmd --version
  echo "Checking Slurm configuration..."
  scontrol show config | grep -E "(ClusterName|ControlMachine|ControlAddr|SlurmctldPort)" || echo "Failed to get config"
  echo "Trying to contact slurmctld directly..."
  scontrol show config | head -5 || echo "Cannot get slurmctld config"
  echo "Checking if we can resolve controller hostname..."
  nslookup login || echo "DNS resolution failed"
  getent hosts login || echo "Host resolution failed"
  
  # Test actual Slurm protocol communication
  echo "Testing Slurm protocol communication..."
  timeout 10 slurm_load_ctl_conf 2>&1 || echo "Slurm load config timeout or failed"
  
  # Check if there are any firewall or connection issues
  echo "Testing connection specifics..."
  nc -v -z login 6817 2>&1 | head -3
  telnet login 6817 </dev/null 2>&1 | head -5 || echo "Telnet test complete"
  
  echo "Controller is ready, starting slurmd..."
  sudo slurmd -N $(hostname) -D
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