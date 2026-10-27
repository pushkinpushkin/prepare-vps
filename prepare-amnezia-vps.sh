#!/usr/bin/env bash
# Ubuntu 24.04 LTS VPS preparation for AmneziaVPN.
# No SSH authentication changes, firewall policy changes, Docker installation,
# automatic reboot, or IP forwarding changes.
set -Eeuo pipefail
export DEBIAN_FRONTEND=noninteractive

log() { printf '\n[%s] %s\n' "$(date -u +'%Y-%m-%d %H:%M:%S UTC')" "$*"; }
WARNINGS=0
warn() { printf 'WARNING: %s\n' "$*" >&2; WARNINGS=$((WARNINGS + 1)); }
# Resource thresholds: official minima use decimal GB; free-space warnings are conservative estimates.
check_resources() {
  local mem_total mem_available swap_total disk_total disk_available cpu virt
  mem_total=$(awk '/^MemTotal:/ {print $2 * 1024}' /proc/meminfo | cut -d. -f1)
  mem_available=$(awk '/^MemAvailable:/ {print $2 * 1024}' /proc/meminfo | cut -d. -f1)
  swap_total=$(awk '/^SwapTotal:/ {print $2 * 1024}' /proc/meminfo | cut -d. -f1)
  disk_total=$(df -B1 --output=size / | tail -1 | tr -d ' ')
  disk_available=$(df -B1 --output=avail / | tail -1 | tr -d ' ')
  cpu=$(nproc)
  virt=$(systemd-detect-virt 2>/dev/null || true)
  printf 'RAM: total %s MiB, available %s MiB; swap %s MiB\n' \
    "$((mem_total/1048576))" "$((mem_available/1048576))" "$((swap_total/1048576))"
  printf 'Disk /: total %s MiB, available %s MiB; CPU: %s; virtualization: %s\n' \
    "$((disk_total/1048576))" "$((disk_available/1048576))" "$cpu" "${virt:-unknown}"
  (( mem_total >= 1000000000 )) || warn 'RAM below official Amnezia minimum of 1 GB (swap does not replace RAM).'
  (( mem_available >= 268435456 )) || warn 'Available RAM below 256 MiB; installations may fail under load (practical warning, not official limit).'
  (( disk_total >= 10000000000 )) || warn 'Disk total below official Amnezia minimum of 10 GB; installation may fail even if free space looks sufficient.'
  (( disk_available >= 3221225472 )) || warn 'Free space below 3 GiB; Docker image downloads may exhaust disk (practical warning, not official limit).'
  (( disk_available >= 2147483648 )) || warn 'Free space below 2 GiB; high risk of running out during installation (practical warning).'
  (( cpu >= 1 )) || warn 'No CPU cores detected.'
  [[ "$virt" == 'kvm' ]] || warn "Amnezia officially requires KVM virtualization; detected: ${virt:-unknown}"
}

fail() { echo "ERROR: $*" >&2; exit 1; }
trap 'echo "ERROR on line $LINENO (exit $?). Inspect output above." >&2' ERR

[[ "${EUID}" -eq 0 ]] || fail 'Run as root: sudo bash prepare-amnezia-vps.sh'
[[ -r /etc/os-release ]] || fail 'Cannot identify operating system'
# shellcheck disable=SC1091
source /etc/os-release
[[ "${ID:-}" == 'ubuntu' && "${VERSION_ID:-}" == '24.04' ]] || fail 'This script supports Ubuntu 24.04 only'
[[ "$(uname -m)" == 'x86_64' ]] || fail 'This script is designed for x86_64 VPS'
command -v apt-get >/dev/null || fail 'apt-get not found'

log '0/6: Check VPS resources before updates'
check_resources

log '1/6: Update installed packages (no automatic reboot)'
apt-get update
apt-get -y upgrade

log '2/6: Install unattended-upgrades and Fail2ban dependencies'
apt-get install -y unattended-upgrades fail2ban python3-systemd

log '3/6: Configure daily security updates without automatic reboot'
cat > /etc/apt/apt.conf.d/90-vps-security <<'APTCONF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
Unattended-Upgrade::Automatic-Reboot "false";
APTCONF
# Ubuntu packages may ship 20auto-upgrades; drop-in 90-vps-security takes precedence.

log '4/6: Configure SSH brute-force protection'
mkdir -p /etc/fail2ban/jail.d
cat > /etc/fail2ban/jail.d/sshd.local <<'JAIL'
[sshd]
enabled = true
backend = systemd
maxretry = 5
findtime = 10m
bantime = 1h
JAIL
fail2ban-client -t
systemctl enable fail2ban
systemctl restart fail2ban
# Wait for service socket readiness, avoiding the immediate post-restart race.
ready=0
for i in $(seq 1 15); do
  if fail2ban-client status sshd >/dev/null 2>&1; then ready=1; break; fi
  sleep 1
done
[[ "$ready" == 1 ]] || fail 'Fail2ban sshd jail did not become ready; see journalctl -u fail2ban'

log '5/6: Clean downloaded APT package archives only'
apt-get clean
# Do not autoremove kernels automatically on a small VPS.

log '6/6: Validate installation'
[[ "$(systemctl is-active fail2ban)" == 'active' ]] || fail 'Fail2ban is not running'
[[ "$(systemctl is-enabled fail2ban)" == 'enabled' ]] || fail 'Fail2ban is not enabled at boot'
fail2ban-client status sshd
[[ "$(apt-config shell APT_UPDATE APT::Periodic::Update-Package-Lists | awk -F "'" '/APT_UPDATE=/ {print $2}')" == '1' ]] || fail 'Daily APT index updates not enabled'
[[ "$(apt-config shell APT_UNATTENDED APT::Periodic::Unattended-Upgrade | awk -F "'" '/APT_UNATTENDED=/ {print $2}')" == '1' ]] || fail 'Unattended upgrades not enabled'
[[ "$(apt-config shell REBOOT Unattended-Upgrade::Automatic-Reboot | awk -F "'" '/REBOOT=/ {print $2}')" == 'false' ]] || fail 'Automatic reboot not disabled'
systemctl is-active ssh >/dev/null || fail 'SSH service is not active'
echo '--- SSH listening sockets ---'
ss -tlnp | grep -E '(^State|sshd|:22[[:space:]])' || true
echo '--- Resource checks after updates and cleanup ---'
check_resources
df -h /
echo '--- Kernel ---'
uname -r
if [[ -f /var/run/reboot-required ]]; then
  echo 'REBOOT REQUIRED: reboot manually when safe, then reconnect over SSH.'
else
  echo 'No reboot required flag detected.'
fi
echo '--- Status ---'
echo 'PASS: Packages upgraded, unattended-upgrades configured, Fail2ban sshd jail active, APT cache cleaned.'
if (( WARNINGS > 0 )); then
  printf 'WARN: %s resource warning(s) across pre/post checks. Review WARNING lines before installing Amnezia.\n' "$WARNINGS"
else
  echo 'PASS: Resource checks found no threshold warnings (not a guarantee of Amnezia installation).'
fi
echo 'Unchanged: SSH authentication, firewall, Docker, IP forwarding, reboot policy of current session.'
