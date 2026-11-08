#!/bin/bash
# Prepares the server. Safe to run again.
set -euo pipefail
ROOT=/opt/asktala
COMPOSE_VERSION=v5.7.0
BUILDX_VERSION=v0.38.1

dnf install -y docker jq amazon-cloudwatch-agent
plugins=/usr/libexec/docker/cli-plugins
mkdir -p "$plugins"
if [ ! -x "$plugins/docker-compose" ]; then
  curl -fsSL -o "$plugins/docker-compose" \
    "https://github.com/docker/compose/releases/download/$COMPOSE_VERSION/docker-compose-linux-x86_64"
  chmod +x "$plugins/docker-compose"
fi
if [ ! -x "$plugins/docker-buildx" ]; then
  curl -fsSL -o "$plugins/docker-buildx" \
    "https://github.com/docker/buildx/releases/download/$BUILDX_VERSION/buildx-$BUILDX_VERSION.linux-amd64"
  chmod +x "$plugins/docker-buildx"
fi
systemctl enable --now docker

if [ ! -f /swapfile ]; then
  dd if=/dev/zero of=/swapfile bs=1M count=2048 status=none
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  echo '/swapfile none swap sw 0 0' >>/etc/fstab
fi

mkdir -p /var/log/asktala
touch /var/log/asktala/backup.log /var/log/asktala/eval.log
chmod +x "$ROOT"/ops/*.sh "$ROOT"/ops/*.py
cp "$ROOT"/ops/systemd/* /etc/systemd/system/
systemctl daemon-reload
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -s \
  -c "file:$ROOT/ops/cloudwatch-agent.json"
systemctl enable asktala.service
systemctl restart asktala.service
systemctl enable --now asktala-backup.timer asktala-eval.timer
