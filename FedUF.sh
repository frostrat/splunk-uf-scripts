#!/bin/bash
# ============================================================
# FedUf.sh - Fedora 
# Installs Splunk Universal Forwarder, seeds UF admin user,
# monitors high-value logs if they exist, and forwards to
# SPLUNK_IP:9997 into index=linuxlogs.
# ============================================================

set -e

# ---------- 1) checks if running on root ----------
if [ "$EUID" -ne 0 ]; then
  echo "[ERROR] Run as root: sudo bash FedUf.sh"
  exit 1
fi

# ---------- 2) prompts for Splunk Enterprise IP ----------
read -r -p "Enter Splunk Enterprise (Indexer) IP: " SPLUNK_IP
if [ -z "$SPLUNK_IP" ]; then
  echo "[ERROR] Splunk IP cannot be empty."
  exit 1
fi

# ---------- 3) prompts fpr UF admin username/password ----------
read -r -p "Create a local Splunk UF admin username (example: admin): " SPLUNK_ADMIN_USER
if [ -z "$SPLUNK_ADMIN_USER" ]; then
  echo "[ERROR] Username cannot be empty."
  exit 1
fi

read -rs -p "Create a local Splunk UF admin password (input hidden): " SPLUNK_ADMIN_PASS
echo
read -rs -p "Confirm password: " SPLUNK_ADMIN_PASS_CONFIRM
echo
if [ "$SPLUNK_ADMIN_PASS" != "$SPLUNK_ADMIN_PASS_CONFIRM" ]; then
  echo "[ERROR] Passwords do not match."
  exit 1
fi

# ---------- 4) configure specifics before running! ----------
SPLUNK_HOME="/opt/splunkforwarder"
SPLUNK_REC_PORT="9997"
SPLUNK_INDEX="linuxlogs" #this was my specific index name. Change if not using the same name on your enterprise system. 

UF_PKG="splunkforwarder-<VERSION>-<BUILD_ID>-Linux-x86_64.tgz"
UF_URL="https://download.splunk.com/<YOUR_FORWARDER_DOWNLOAD_PATH>/${UF_PKG}"

# ---------- 5) download + install UF ----------
echo "[*] Downloading Splunk Universal Forwarder..."
cd /tmp
wget -q --show-progress -O "$UF_PKG" "$UF_URL"

echo "[*] Installing UF to /opt..."
tar -xzf "$UF_PKG" -C /opt

# ---------- 6) Seed admin user BEFORE first start ----------
echo "[*] Seeding UF admin user (user-seed.conf)..."
USERSEED_DIR="${SPLUNK_HOME}/etc/system/local"
mkdir -p "$USERSEED_DIR"

printf "%s\n" \
"[user_info]" \
"USERNAME = ${SPLUNK_ADMIN_USER}" \
"PASSWORD = ${SPLUNK_ADMIN_PASS}" \
> "${USERSEED_DIR}/user-seed.conf"

chmod 600 "${USERSEED_DIR}/user-seed.conf"

# ---------- 7) Start UF &&& accept license ----------
echo "[*] Starting UF and accepting license..."
"${SPLUNK_HOME}/bin/splunk" start --accept-license --answer-yes --no-prompt

# ---------- 8) Write inputs.conf (only monitors files that exist) ----------
echo "[*] Writing inputs.conf (Fedora 42) -> index=${SPLUNK_INDEX}..."
INPUTS_FILE="${SPLUNK_HOME}/etc/system/local/inputs.conf"

# Start clean
printf "%s\n" \
"# ========= CCDC Fedora 42 UF Inputs =========" \
"# Auto-add monitors only if file exists" \
"# Target index: ${SPLUNK_INDEX}" \
> "$INPUTS_FILE"

add_monitor_if_exists () {
  local path="$1"
  local st="$2"
  if [ -f "$path" ]; then
    printf "\n[monitor://%s]\ndisabled = false\nindex = %s\nsourcetype = %s\n" \
      "$path" "$SPLUNK_INDEX" "$st" >> "$INPUTS_FILE"
    echo "[OK] Monitoring $path"
  else
    echo "[SKIP] Missing $path"
  fi
}

# Auth/system (Fedora may have these if rsyslog is enabled)
add_monitor_if_exists "/var/log/secure" "linux_secure"
add_monitor_if_exists "/var/log/messages" "messages"

# Packages
add_monitor_if_exists "/var/log/dnf.log" "linux_dnf"

# Mail logs (if webmail stack installed)
add_monitor_if_exists "/var/log/maillog" "linux_mail"
add_monitor_if_exists "/var/log/mail.log" "linux_mail"

# Web logs (nginx or apache)
add_monitor_if_exists "/var/log/nginx/access.log" "nginx_access"
add_monitor_if_exists "/var/log/nginx/error.log"  "nginx_error"
add_monitor_if_exists "/var/log/httpd/access_log" "apache_access"
add_monitor_if_exists "/var/log/httpd/error_log"  "apache_error"

# Add default host setting-> host name should now be comp name vs enterprise ip
echo "" >> "$INPUTS_FILE"
echo "[default]" >> "$INPUTS_FILE"
echo "host = $(hostname)" >> "$INPUTS_FILE"


chmod 600 "$INPUTS_FILE"
echo "[OK] inputs.conf written"

# ---------- 9) Set forward server ----------
echo "[*] Setting forward-server to ${SPLUNK_IP}:${SPLUNK_REC_PORT}..."
"${SPLUNK_HOME}/bin/splunk" add forward-server "${SPLUNK_IP}:${SPLUNK_REC_PORT}" -auth "${SPLUNK_ADMIN_USER}:${SPLUNK_ADMIN_PASS}"

# ---------- 10) Enable boot-start (best effort since this has been an issue) ----------
echo "[*] Enabling boot-start..."
"${SPLUNK_HOME}/bin/splunk" enable boot-start || true

# ---------- 11) Restart UF ----------
echo "[*] Restarting UF..."
"${SPLUNK_HOME}/bin/splunk" restart

# ---------- 12) Status ----------
echo "[*] UF status:"
"${SPLUNK_HOME}/bin/splunk" status || true

echo "[DONE] Fedora UF installed and forwarding -> ${SPLUNK_IP}:${SPLUNK_REC_PORT} index=${SPLUNK_INDEX}"