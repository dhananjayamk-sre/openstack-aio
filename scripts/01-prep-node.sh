#!/usr/bin/env bash
# DevStack AIO (Ubuntu 24.04) — system preparation
# Usage: sudo ./01-prep-ubuntu.sh

set -euo pipefail

echo "[*] Updating system..."
export DEBIAN_FRONTEND=noninteractive
apt-get -qq update
apt-get -y upgrade

echo "[*] Installing base packages..."
apt-get -y install \
  git \
  sudo \
  bridge-utils \
  python3-pip \
  python3-venv \
  net-tools \
  curl \
  ca-certificates

echo "[*] Creating 'stack' user..."
if ! id "stack" &>/dev/null; then
  useradd -s /bin/bash -d /opt/stack -m stack
  chmod 755 /opt/stack
  echo "stack ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/stack
  chmod 440 /etc/sudoers.d/stack
  echo "[+] User 'stack' created"
else
  echo "[.] User 'stack' already exists"
fi

echo "[*] Done."
echo "Next:"
echo "  - Configure network: ./02-configure-network.sh"
echo "  - Switch user: sudo su - stack"
echo "  - Install DevStack: ./03-devstack-install.sh"
