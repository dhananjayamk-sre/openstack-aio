#!/bin/bash
# OpenStack All-in-One: Node preparation (run on Dell R620 AFTER OS install)
# Recommended: Ubuntu 22.04 LTS (24.04 + Kolla-Ansible can hit Galaxy cert_file / Python 3.12 errors)
# Run: sudo ./01-prep-node.sh

set -e
echo "=== OpenStack AIO – Node prep (Dell R620) ==="

# Optional: set hostname (uncomment and set)
# hostnamectl set-hostname openstack-aio

apt-get update
apt-get install -y git python3-dev libffi-dev gcc libssl-dev python3-venv

echo ""
echo "Network interfaces (use these in globals.yml):"
ip -br link show | grep -v '^lo'
echo ""
echo "Prepared. Next: run 02-deploy-kolla-aio.sh (or 02-deploy-devstack-aio.sh)"
