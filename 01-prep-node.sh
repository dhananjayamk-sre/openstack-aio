#!/usr/bin/env bash
# OpenStack all-in-one (Ubuntu 24.04) — system preparation
# Run as: sudo ./01-prep-ubuntu.sh
# Creates stack user and installs base packages for DevStack

set -e

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

echo "[*] Creating stack user for DevStack..."
if ! getent passwd stack >/dev/null; then
  useradd -s /bin/bash -d /opt/stack -m stack
  chmod 755 /opt/stack
  echo "stack ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/stack
  chmod 440 /etc/sudoers.d/stack
  echo "[+] User stack created. Home: /opt/stack"
else
  echo "[.] User stack already exists."
fi

echo "[*] Done. Next steps:"
echo "    1. Configure static IP: sudo ./02-configure-network.sh"
echo "    2. Switch to stack user: sudo su - stack"
echo "    3. Run DevStack install: ./03-devstack-install.sh  (from repo copy in /opt/stack)"
