#!/usr/bin/env bash
#
# install.sh - Deployment Utility for OCI Adaptive CPU Load Balancer
# Usage:
#   sudo ./install.sh              # Install, harden, enable, and verify
#   sudo ./install.sh --uninstall  # Stop, disable, and cleanly remove all artifacts

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

SERVICE_USER="ociburner"
SERVICE_GROUP="ociburner"
BIN_BALANCER="/usr/local/bin/oci-cpu-balancer"
BIN_WATCHDOG="/usr/local/bin/oci-cpu-watchdog"
CONF_FILE="/etc/oci-cpu-balancer.conf"
STATE_DIR="/var/lib/oci-cpu-balancer"
UNIT_DIR="/etc/systemd/system"

log_info()  { echo -e "\033[1;32m[INFO]\033[0m  $*"; }
log_warn()  { echo -e "\033[1;33m[WARN]\033[0m  $*"; }
log_error() { echo -e "\033[1;31m[ERROR]\033[0m $*" >&2; }

require_root() {
    if [[ "${EUID}" -ne 0 ]]; then
        log_error "This script must be executed as root (use sudo)."
        exit 1
    fi
}

validate_files() {
    log_info "Checking for required repository files..."
    local required_files=(
        "oci-cpu-balancer"
        "oci-cpu-watchdog"
        "oci-cpu-balancer.conf"
        "oci-cpu-balancer.service"
        "oci-cpu-watchdog.service"
        "oci-cpu-watchdog.timer"
    )
    for f in "${required_files[@]}"; do
        if [[ ! -f "${REPO_DIR}/${f}" ]]; then
            log_error "Missing required file: ${f} in ${REPO_DIR}"
            exit 1
        fi
    done
}

uninstall_all() {
    require_root
    log_info "Starting uninstallation of OCI CPU Balancer & Watchdog..."

    systemctl stop oci-cpu-balancer.service oci-cpu-watchdog.timer oci-cpu-watchdog.service 2>/dev/null || true
    systemctl disable oci-cpu-balancer.service oci-cpu-watchdog.timer 2>/dev/null || true

    rm -f "${UNIT_DIR}/oci-cpu-balancer.service" \
          "${UNIT_DIR}/oci-cpu-watchdog.service" \
          "${UNIT_DIR}/oci-cpu-watchdog.timer"

    systemctl daemon-reload
    systemctl reset-failed 2>/dev/null || true

    rm -f "${BIN_BALANCER}" "${BIN_WATCHDOG}" "${CONF_FILE}"
    rm -rf "${STATE_DIR}"

    if id "${SERVICE_USER}" >/dev/null 2>&1; then
        userdel "${SERVICE_USER}" 2>/dev/null || true
        log_info "Removed system user '${SERVICE_USER}'."
    fi

    log_info "Uninstallation complete. System restored to clean state."
    exit 0
}

if [[ "${1:-}" == "--uninstall" ]]; then
    uninstall_all
fi

require_root
validate_files

# 1. Create dedicated system user and group
if ! getent group "${SERVICE_GROUP}" >/dev/null; then
    groupadd --system "${SERVICE_GROUP}"
    log_info "Created system group '${SERVICE_GROUP}'."
fi

if ! id "${SERVICE_USER}" >/dev/null 2>&1; then
    useradd --system \
        --gid "${SERVICE_GROUP}" \
        --no-create-home \
        --home-dir /nonexistent \
        --shell /usr/sbin/nologin \
        --comment "OCI Adaptive CPU Load Balancer" \
        "${SERVICE_USER}"
    log_info "Created locked-down system user '${SERVICE_USER}'."
fi

# 2. Create state directory with 0750 permissions
mkdir -p "${STATE_DIR}"
chown "root:${SERVICE_GROUP}" "${STATE_DIR}"
chmod 0750 "${STATE_DIR}"
log_info "Configured state directory ${STATE_DIR} (0750)."

# 3. Install Configuration File
if [[ ! -f "${CONF_FILE}" ]]; then
    cp "${REPO_DIR}/oci-cpu-balancer.conf" "${CONF_FILE}"
    log_info "Installed default configuration to ${CONF_FILE}."
else
    log_info "Existing ${CONF_FILE} found; preserving current settings."
fi
chown "root:${SERVICE_GROUP}" "${CONF_FILE}"
chmod 0640 "${CONF_FILE}"

# 4. Install Binaries
cp "${REPO_DIR}/oci-cpu-balancer" "${BIN_BALANCER}"
cp "${REPO_DIR}/oci-cpu-watchdog" "${BIN_WATCHDOG}"
chown "root:${SERVICE_GROUP}" "${BIN_BALANCER}"
chmod 0750 "${BIN_BALANCER}"
chown root:root "${BIN_WATCHDOG}"
chmod 0750 "${BIN_WATCHDOG}"
log_info "Installed daemon and watchdog scripts to /usr/local/bin/."

# 5. Install Systemd Units
cp "${REPO_DIR}/oci-cpu-balancer.service" "${UNIT_DIR}/"
cp "${REPO_DIR}/oci-cpu-watchdog.service" "${UNIT_DIR}/"
cp "${REPO_DIR}/oci-cpu-watchdog.timer" "${UNIT_DIR}/"
chmod 0644 "${UNIT_DIR}/oci-cpu-balancer.service" \
           "${UNIT_DIR}/oci-cpu-watchdog.service" \
           "${UNIT_DIR}/oci-cpu-watchdog.timer"
log_info "Installed systemd units."

# 6. Reload, Enable, and Start Services
systemctl daemon-reload
systemctl enable --now oci-cpu-balancer.service
systemctl enable --now oci-cpu-watchdog.timer

sleep 2

# 7. Post-Deployment Verification
log_info "Verifying deployment status and memory constraints..."
if systemctl is-active --quiet oci-cpu-balancer.service; then
    MEM_BYTES="$(systemctl show -p MemoryCurrent --value oci-cpu-balancer.service)"
    MEM_MB="$(awk "BEGIN {printf \"%.2f\", ${MEM_BYTES:-0} / 1048576}")"
    log_info "oci-cpu-balancer.service is ACTIVE (Current RSS/Memory: ${MEM_MB} MB / 20.00 MB limit)."
else
    log_error "oci-cpu-balancer.service failed to start. Check: journalctl -u oci-cpu-balancer.service"
    exit 1
fi

if systemctl is-active --quiet oci-cpu-watchdog.timer; then
    log_info "oci-cpu-watchdog.timer is ACTIVE."
else
    log_error "oci-cpu-watchdog.timer failed to start."
    exit 1
fi

log_info "Installation completed successfully."
