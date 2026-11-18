#!/bin/bash
# Remove the dynatrace-demo service from this VM. Run as: sudo bash uninstall.sh
set -euo pipefail
APP_NAME="dynatrace-demo"
[[ $EUID -eq 0 ]] || { echo "Please run as root: sudo bash $0" >&2; exit 1; }

systemctl disable --now "${APP_NAME}-loadgen" 2>/dev/null || true
systemctl disable --now "${APP_NAME}" 2>/dev/null || true
rm -f "/etc/systemd/system/${APP_NAME}.service" "/etc/default/${APP_NAME}"
rm -f "/etc/systemd/system/${APP_NAME}-loadgen.service" "/etc/default/${APP_NAME}-loadgen"
rm -rf "/var/lib/${APP_NAME}-loadgen"
rm -f /usr/local/bin/dtdemo-load
systemctl daemon-reload
rm -rf "/opt/${APP_NAME}"
userdel "${APP_NAME}" 2>/dev/null || true
echo "Removed ${APP_NAME}. Logs kept in /var/log/${APP_NAME} (delete manually if not needed)."
