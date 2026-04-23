#!/usr/bin/env bash
#
# Check that the OS is hardened and ready for OpenStack AIO deployment.
# Run on the server: ./scripts/03-check-os-hardening.sh
# Some checks need root; run with sudo for full report.
# Uses set +e so all checks run (diagnostic tool, not strict automation).
#
set +e

PASS=0
WARN=0
FAIL=0

check_pass() { echo "[PASS] $*"; PASS=$((PASS+1)); }
check_warn() { echo "[WARN] $*"; WARN=$((WARN+1)); }
check_fail() { echo "[FAIL] $*"; FAIL=$((FAIL+1)); }

echo "=== OS hardening & OpenStack AIO readiness check ==="
echo ""

# --- OpenStack AIO requirements ---

# 1. Memory (AIO needs at least 8–16 GB RAM)
MEM=$(free -g | awk '/^Mem:/ {print $2}')
if [[ -n "$MEM" && "$MEM" -ge 8 ]]; then
  check_pass "Memory: ${MEM}GB RAM (min 8GB for AIO)"
else
  check_fail "Memory: ${MEM:-?}GB detected — minimum 8GB required for OpenStack AIO"
fi

# 2. CPU virtualization (needed for Nova / KVM)
if grep -qE '(vmx|svm)' /proc/cpuinfo 2>/dev/null; then
  check_pass "CPU: Virtualization (vmx/svm) supported for Nova"
else
  check_warn "CPU: Virtualization not detected — Nova instances may not run"
fi

# 3. KVM kernel module (Nova actually uses KVM)
if lsmod 2>/dev/null | awk '{print $1}' | grep -qx "kvm"; then
  check_pass "CPU: KVM kernel module loaded"
else
  check_warn "CPU: KVM module not loaded (modprobe kvm_intel or kvm_amd)"
fi

# 4. Disk space (root filesystem)
DISK_KB=$(df -k / 2>/dev/null | awk 'NR==2 {print $4}')
DISK_GB=$((DISK_KB / 1024 / 1024))
if [[ -n "$DISK_KB" && "$DISK_GB" -ge 50 ]]; then
  check_pass "Disk: ${DISK_GB}GB free on / (recommend 100GB+ for lab)"
else
  check_warn "Disk: ${DISK_GB:-?}GB free on / — recommend 100GB+ for OpenStack AIO"
fi

# 5. Kernel modules (OpenStack/container networking)
for mod in br_netfilter overlay; do
  if lsmod 2>/dev/null | awk '{print $1}' | grep -qx "$mod"; then
    check_pass "Kernel module: $mod loaded"
  else
    check_warn "Kernel module: $mod not loaded (may be required for Neutron/containers)"
  fi
done

# 6. Bridge networking sysctl (container networking)
if sysctl -n net.bridge.bridge-nf-call-iptables 2>/dev/null | grep -q 1; then
  check_pass "Bridge sysctl: net.bridge.bridge-nf-call-iptables=1"
else
  check_warn "Bridge sysctl: set net.bridge.bridge-nf-call-iptables=1 for container networking"
fi

# 7. Docker (required for Kolla)
if command -v docker &>/dev/null; then
  if systemctl is-active --quiet docker 2>/dev/null; then
    check_pass "Docker: installed and running"
  else
    check_warn "Docker: installed but not running (systemctl start docker)"
  fi
  if docker info 2>/dev/null | grep -q "overlay2"; then
    check_pass "Docker: storage driver overlay2"
  else
    check_warn "Docker: storage driver not overlay2 (recommended)"
  fi
else
  check_warn "Docker: not installed (required for Kolla OpenStack)"
fi

# 8. Python version (Kolla/Ansible need modern Python)
PY_VER=$(python3 -c 'import sys; print(sys.version_info.major*10+sys.version_info.minor)' 2>/dev/null)
if [[ -n "$PY_VER" && "$PY_VER" -ge 38 ]]; then
  check_pass "Python3: version OK ($(python3 --version 2>/dev/null || echo "$PY_VER"))"
else
  check_fail "Python3 too old or missing (need 3.8+)"
fi

# 9. Swap (can hurt OpenStack performance)
SWAP=$(swapon --show 2>/dev/null)
if [[ -z "$SWAP" ]]; then
  check_pass "Swap: disabled (recommended for OpenStack)"
else
  check_warn "Swap: enabled — consider disabling for OpenStack performance"
fi

# 10. Hostname resolution (many deployments fail without this)
if hostname -f &>/dev/null && [[ -n "$(hostname -f 2>/dev/null)" ]]; then
  check_pass "Hostname: $(hostname -f) resolves"
else
  check_fail "Hostname resolution broken — fix /etc/hosts and hostname"
fi

# 11. Network interfaces (UP)
if ip -br addr 2>/dev/null | grep -q UP; then
  check_pass "Network: Interfaces UP detected"
else
  check_fail "No network interface in UP state"
fi

# 12. DNS resolution
if ping -c1 -W2 archive.ubuntu.com &>/dev/null; then
  check_pass "DNS: resolution working"
else
  check_fail "DNS resolution failed (e.g. ping archive.ubuntu.com)"
fi

# 13. Common OpenStack ports already in use
if command -v ss &>/dev/null; then
  for p in 80 443 3306 5672 5000; do
    if ss -tuln | grep -q ":$p "; then
      check_warn "Ports: $p already in use (may conflict with OpenStack services)"
    fi
  done
fi

# 14. MTU check (important for Neutron)
MTU=$(ip link show 2>/dev/null | awk '/mtu/ {print $5; exit}')
if [[ -n "$MTU" && "$MTU" -ge 1500 ]]; then
  check_pass "Network: MTU $MTU"
elif [[ -n "$MTU" ]]; then
  check_warn "Network: MTU $MTU detected — recommended 1500+ for Neutron"
fi

# --- Hardening checks ---

# 15. NTP (chrony) running
if systemctl is-active --quiet chrony 2>/dev/null || [[ -n "$(pgrep -x chronyd 2>/dev/null)" ]]; then
  check_pass "NTP (chrony) is running"
else
  if [[ $EUID -eq 0 ]]; then
    check_fail "NTP (chrony) not running — install/start: sudo systemctl enable chrony && sudo systemctl start chrony"
  else
    check_warn "NTP (chrony) status unknown (run with sudo for full check)"
  fi
fi

# 16. SSH server present and using Protocol 2
if [[ -f /etc/ssh/sshd_config ]]; then
  if grep -qE '^Protocol\s+2' /etc/ssh/sshd_config 2>/dev/null || ! grep -qE '^Protocol' /etc/ssh/sshd_config; then
    check_pass "SSH: Protocol 2 (or default)"
  else
    check_fail "SSH: Set Protocol 2 in /etc/ssh/sshd_config"
  fi
  if grep -qE '^PermitRootLogin\s+(no|prohibit-password)' /etc/ssh/sshd_config 2>/dev/null; then
    check_pass "SSH: PermitRootLogin restricted (no or prohibit-password)"
  else
    check_warn "SSH: Consider PermitRootLogin no or prohibit-password in /etc/ssh/sshd_config"
  fi
else
  check_warn "SSH: /etc/ssh/sshd_config not found"
fi

# 17. Locale
if [[ "${LANG:-}" == *"UTF-8"* ]] || grep -qE '^LANG=.*UTF-8' /etc/default/locale 2>/dev/null; then
  check_pass "Locale: UTF-8 set (LANG=$LANG)"
else
  check_warn "Locale: Set LANG=en_US.UTF-8 (e.g. in /etc/default/locale)"
fi

# 4. Pending security updates (needs apt)
if command -v apt-get &>/dev/null; then
  UPDATES=$(apt-get -s dist-upgrade 2>/dev/null | grep -cE '^Inst' || true)
  SEC_UPDATES=$(apt-get -s dist-upgrade 2>/dev/null | grep -i security | grep -cE '^Inst' || true)
  if [[ "${SEC_UPDATES:-0}" -gt 0 ]]; then
    check_warn "Updates: $SEC_UPDATES security update(s) pending — run: sudo apt update && sudo apt upgrade -y"
  elif [[ "${UPDATES:-0}" -gt 0 ]]; then
    check_warn "Updates: $UPDATES non-security update(s) pending"
  else
    check_pass "Updates: No pending upgrades"
  fi
else
  check_warn "Updates: apt not found, skip"
fi

# 5. Sudo / NOPASSWD for deploy user (optional but needed for Ansible)
DEPLOY_USER="${SUDO_USER:-$USER}"
if [[ -n "$DEPLOY_USER" && "$DEPLOY_USER" != "root" ]]; then
  if sudo -n true 2>/dev/null; then
    check_pass "Sudo: $DEPLOY_USER can run sudo without password (Ansible-ready)"
  else
    if [[ $EUID -eq 0 ]]; then
      check_warn "Sudo: $DEPLOY_USER may need NOPASSWD for Ansible — see PRE_DEPLOYMENT_CHECKLIST Section 2.8"
    else
      check_warn "Sudo: Ensure $DEPLOY_USER has NOPASSWD for Ansible"
    fi
  fi
fi

# 6. SSH authorized_keys for deploy user
if [[ -n "$DEPLOY_USER" && "$DEPLOY_USER" != "root" ]]; then
  AUTH_KEYS=$(eval echo "~$DEPLOY_USER/.ssh/authorized_keys" 2>/dev/null)
  if [[ -f "$AUTH_KEYS" && -s "$AUTH_KEYS" ]]; then
    check_pass "SSH keys: authorized_keys present for $DEPLOY_USER"
  else
    check_warn "SSH keys: Add keys to ~$DEPLOY_USER/.ssh/authorized_keys for key-based login"
  fi
fi

# 7. Static IP (informational)
if command -v ip &>/dev/null; then
  PRIMARY_IP=$(ip -o -4 route get 8.8.8.8 2>/dev/null | sed -n 's/.*src \([0-9.]*\).*/\1/p')
  if [[ -n "$PRIMARY_IP" ]]; then
    check_pass "Network: Primary IP $PRIMARY_IP (static recommended for OpenStack)"
  fi
fi

# 8. Firewall (informational — OpenStack often uses custom rules or disables)
if command -v ufw &>/dev/null; then
  if sudo ufw status 2>/dev/null | grep -q "Status: active"; then
    check_pass "Firewall: UFW is active"
  else
    check_warn "Firewall: UFW not active (acceptable for lab; for production consider enabling with allowed ports)"
  fi
else
  check_warn "Firewall: UFW not installed (optional)"
fi

# 9. Unattended-upgrades (optional security)
if dpkg -l unattended-upgrades &>/dev/null 2>&1; then
  check_pass "Auto-updates: unattended-upgrades installed"
else
  check_warn "Auto-updates: Consider installing unattended-upgrades for security patches"
fi

echo ""
echo "--- Summary ---"
echo "PASS: $PASS   WARN: $WARN   FAIL: $FAIL"
if [[ $FAIL -gt 0 ]]; then
  echo "Action: Fix [FAIL] items before OpenStack deployment."
  exit 2
elif [[ $WARN -gt 0 ]]; then
  echo "Action: Review [WARN] items; you can proceed but hardening is recommended."
  exit 0
else
  echo "All set: OS hardening checks passed. Safe to proceed with OpenStack AIO deployment."
  exit 0
fi
