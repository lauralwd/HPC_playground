# Shared base image
FROM ubuntu:24.04 AS base

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      openssh-server \
      slurm-wlm \
      munge \
      libmunge2 \
      nfs-common \
      curl \
      ca-certificates \
      python3 \
      openjdk-17-jre-headless \
      procps \
      vim \
      rsync && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Ensure munge user exists with proper setup
RUN if ! id munge &>/dev/null; then \
        useradd --system --home-dir /var/lib/munge --shell /bin/false munge; \
    fi && \
    mkdir -p /var/lib/munge /var/log/munge /var/run/munge && \
    chown munge:munge /var/lib/munge /var/log/munge /var/run/munge

RUN mkdir /var/run/sshd

# Install Nextflow
RUN curl -sSL https://get.nextflow.io | bash && \
    mv nextflow /usr/local/bin/nextflow && \
    chmod +x /usr/local/bin/nextflow

# Add entrypoint script
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

EXPOSE 22

# Controller target
FROM base AS controller
RUN mkdir -p /var/spool/slurmctld && chown -R slurm:slurm /var/spool/slurmctld

# Compute target
FROM base AS compute
RUN mkdir -p /var/spool/slurmd && chown -R slurm:slurm /var/spool/slurmd

# DTN target
FROM base AS dtn