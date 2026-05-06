#!/bin/bash
# OpenStack Project Network Factory (v2) – production-ready.
# Creates projects if missing, public network once, per-project private net + router,
# default security group rules (SSH, ICMP), and per-project quotas (FinOps).
#
# Usage:
#   export OS_CLIENT_CONFIG_FILE=/etc/kolla/clouds.yaml
#   export OS_CLOUD=kolla-admin
#   ./03-create-networks.sh
#
# Optional env: EXTERNAL_NET_NAME, EXTERNAL_PHYSICAL, EXTERNAL_SUBNET, EXTERNAL_GATEWAY,
#   EXTERNAL_ALLOCATION_START/END, PROJECTS (default "admin demo"), DNS_NAMESERVER

set -e

EXTERNAL_NET_NAME="${EXTERNAL_NET_NAME:-public}"
EXTERNAL_PHYSICAL="${EXTERNAL_PHYSICAL:-physnet1}"
EXTERNAL_SUBNET="${EXTERNAL_SUBNET:-192.168.1.0/24}"
EXTERNAL_GATEWAY="${EXTERNAL_GATEWAY:-192.168.1.1}"
EXTERNAL_ALLOCATION_START="${EXTERNAL_ALLOCATION_START:-192.168.1.200}"
EXTERNAL_ALLOCATION_END="${EXTERNAL_ALLOCATION_END:-192.168.1.254}"

PROJECTS="${PROJECTS:-admin demo}"
DNS_NAMESERVER="${DNS_NAMESERVER:-8.8.8.8}"

echo "=== OpenStack Project Network Factory ==="

# Ensure projects exist
for proj in $PROJECTS; do
  if ! openstack project show "$proj" &>/dev/null; then
    echo "Creating project $proj"
    openstack project create "$proj"
  fi
done

# External network
if ! openstack network show "$EXTERNAL_NET_NAME" &>/dev/null; then
  openstack network create \
    --external \
    --provider-network-type flat \
    --provider-physical-network "$EXTERNAL_PHYSICAL" \
    --share \
    "$EXTERNAL_NET_NAME"
fi

# External subnet
EXT_SUBNET_NAME="${EXTERNAL_NET_NAME}-subnet"

if ! openstack subnet show "$EXT_SUBNET_NAME" &>/dev/null; then
  openstack subnet create \
    --network "$EXTERNAL_NET_NAME" \
    --subnet-range "$EXTERNAL_SUBNET" \
    --gateway "$EXTERNAL_GATEWAY" \
    --allocation-pool start="$EXTERNAL_ALLOCATION_START",end="$EXTERNAL_ALLOCATION_END" \
    --no-dhcp \
    "$EXT_SUBNET_NAME"
fi

# Per project
n=0
for proj in $PROJECTS; do
  n=$((n+1))

  priv_net="private-${proj}"
  priv_subnet="private-${proj}-subnet"
  router="router-${proj}"
  cidr="10.0.${n}.0/24"

  if ! openstack network show "$priv_net" &>/dev/null; then
    echo "Setting up network for $proj"

    openstack network create --project "$proj" "$priv_net"

    openstack subnet create \
      --project "$proj" \
      --network "$priv_net" \
      --subnet-range "$cidr" \
      --dns-nameserver "$DNS_NAMESERVER" \
      "$priv_subnet"

    openstack router create --project "$proj" "$router"

    openstack router add subnet "$router" "$priv_subnet"

    openstack router set --external-gateway "$EXTERNAL_NET_NAME" "$router"
  fi

  # Security rules (default SG: SSH + ICMP)
  openstack security group rule create \
    --project "$proj" --proto tcp --dst-port 22 default 2>/dev/null || true

  openstack security group rule create \
    --project "$proj" --proto icmp default 2>/dev/null || true

  # Quotas (FinOps)
  openstack quota set --cores 20 --ram 51200 --instances 20 "$proj"

done

echo "Done."
