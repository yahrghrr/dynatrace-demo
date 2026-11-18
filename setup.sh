#!/bin/bash
# =============================================================
# setup.sh — Install Java 17 + Maven, build the app, install it
# as a systemd service that starts automatically on VM boot.
#
# Run from the project directory as:   sudo bash setup.sh
# Safe to re-run: it rebuilds and redeploys.
# Supports Ubuntu/Debian (apt) and RHEL/CentOS/Rocky/Alma/Amazon Linux (dnf/yum).
# =============================================================
set -euo pipefail

APP_NAME="dynatrace-demo"
APP_USER="dynatrace-demo"
INSTALL_DIR="/opt/${APP_NAME}"
LOG_DIR="/var/log/${APP_NAME}"
SERVICE_FILE="/etc/systemd/system/${APP_NAME}.service"
ENV_FILE="/etc/default/${APP_NAME}"
PORT="${PORT:-8080}"

if [[ $EUID -ne 0 ]]; then
  echo "Please run as root: sudo bash $0" >&2
  exit 1
fi

cd "$(dirname "$(readlink -f "$0")")"

echo "=============================="
echo "1. Installing Java 17 & Maven"
echo "=============================="
if command -v apt-get >/dev/null 2>&1; then
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y
  apt-get install -y openjdk-17-jdk-headless maven curl
elif command -v dnf >/dev/null 2>&1; then
  dnf install -y java-17-openjdk-devel maven curl
elif command -v yum >/dev/null 2>&1; then
  yum install -y java-17-openjdk-devel maven curl
else
  echo "Unsupported distro: install Java 17 and Maven manually, then re-run." >&2
  exit 1
fi
java -version
mvn -version

echo "=============================="
echo "2. Building the application"
echo "=============================="
mvn -B clean package -DskipTests
JAR="$(ls target/${APP_NAME}-*.jar | grep -v '\.original$' | head -n1)"

echo "=============================="
echo "3. Creating service user & directories"
echo "=============================="
if ! id "${APP_USER}" >/dev/null 2>&1; then
  useradd --system --no-create-home --shell /usr/sbin/nologin "${APP_USER}" 2>/dev/null \
    || useradd --system --no-create-home --shell /sbin/nologin "${APP_USER}"
fi
mkdir -p "${INSTALL_DIR}" "${LOG_DIR}"
install -m 0644 "${JAR}" "${INSTALL_DIR}/${APP_NAME}.jar"
install -m 0644 README.md "${INSTALL_DIR}/README.md" 2>/dev/null || true
chown -R "${APP_USER}:${APP_USER}" "${INSTALL_DIR}" "${LOG_DIR}"
chmod 0755 "${LOG_DIR}"

echo "=============================="
echo "4. Installing systemd service (auto-start on boot)"
echo "=============================="
install -m 0644 deploy/${APP_NAME}.service "${SERVICE_FILE}"
# Keep an existing env file so local edits survive redeploys
[[ -f "${ENV_FILE}" ]] || install -m 0644 deploy/${APP_NAME}.env "${ENV_FILE}"

systemctl daemon-reload
systemctl enable "${APP_NAME}"      # start on every boot
systemctl restart "${APP_NAME}"     # (re)start now

echo "=============================="
echo "5. Waiting for the app to come up"
echo "=============================="
for i in $(seq 1 60); do
  if curl -fs "http://localhost:${PORT}/normal" >/dev/null; then
    echo "App is UP after ${i}s"
    break
  fi
  sleep 1
  if [[ $i -eq 60 ]]; then
    echo "App did not respond within 60s. Check: journalctl -u ${APP_NAME} -n 100" >&2
    exit 1
  fi
done

IP="$(hostname -I 2>/dev/null | awk '{print $1}')"
echo "=============================="
echo "Done! ${APP_NAME} is running and enabled at boot."
echo ""
echo "  Status : systemctl status ${APP_NAME}"
echo "  Enabled: systemctl is-enabled ${APP_NAME}"
echo ""
echo "Test endpoints:"
echo "  curl http://localhost:${PORT}/normal"
echo "  curl http://localhost:${PORT}/error"
[[ -n "${IP}" ]] && echo "  (from another machine: http://${IP}:${PORT}/normal — open port ${PORT} in the firewall)"
echo ""
echo "Generate traffic:  bash scripts/trigger.sh"
echo ""
echo "Logs:"
echo "  tail -f ${LOG_DIR}/application.log"
echo "  journalctl -u ${APP_NAME} -f"
echo "=============================="
