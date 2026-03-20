#!/bin/bash
# ============================================================
# UbuUF.sh
# Ubuntu 24 UF install + config.
# Sends logs to Splunk index: linuxlogs
# Forwards to <SPLUNK_IP>:9997
# ============================================================

set -e

# ---------- 1) root check, run as root! ----------
if [ "$EUID" -ne 0 ]; then
  echo "[ERROR] Run as root: sudo bash UbuUF.sh"
  exit 1
fi

# ---------- 2) Prompt for Splunk Enterprise IP ----------
echo "Enter Splunk Enterprise (Indexer) IP:"
read -r SPLUNK_IP
if [ -z "$SPLUNK_IP" ]; then
  echo "[ERROR] Splunk IP cannot be empty."
  exit 1
fi

# ---------- 3) prompt for UF admin username/password ----------
echo "Create a local Splunk UF admin username (example: admin):"
read -r SPLUNK_ADMIN_USER
if [ -z "$SPLUNK_ADMIN_USER" ]; then
  echo "[ERROR] Username cannot be empty."
  exit 1
fi

echo "Create a local Splunk UF admin password (input hidden):"
read -rs SPLUNK_ADMIN_PASS
echo
echo "Confirm password:"
read -rs SPLUNK_ADMIN_PASS_CONFIRM
echo
if [ "$SPLUNK_ADMIN_PASS" != "$SPLUNK_ADMIN_PASS_CONFIRM" ]; then
  echo "[ERROR] Passwords do not match."
  exit 1
fi

# ---------- 4) UF package- change this before running! ----------
UF_PKG="splunkforwarder-<VERSION>-<BUILD_ID>-Linux-x86_64.tgz"
UF_URL="https://download.splunk.com/<YOUR_FORWARDER_DOWNLOAD_PATH>/${UF_PKG}"
SPLUNK_HOME="/opt/splunkforwarder"
SPLUNK_REC_PORT="9997" #make sure this receiving port on the splunk indexer(enterprise) is added !

# ---------- 4.1) MAKE SURE THIS IS ALREADY CREATED!: linuxlogs ----------
SPLUNK_INDEX="linuxlogs" # this was my specific index name. Change if not using the same name on your enterprise system.

# ---------- 5) Download &&&&& ----------
echo "[*] Downloading Splunk Universal Forwarder..."
cd /tmp
wget -q --show-progress -O "$UF_PKG" "$UF_URL"

# ---------- 6)&&&& Install UF ----------
echo "[*] Installing UF to /opt..."
tar -xzf "$UF_PKG" -C /opt

# ---------- 7) Seed admin user BEFORE first start !!!---------
echo "[*] Seeding UF admin user (user-seed.conf)..."
USERSEED_DIR="$SPLUNK_HOME/etc/system/local"
USERSEED_FILE="$USERSEED_DIR/user-seed.conf"
mkdir -p "$USERSEED_DIR"

cat > "$USERSEED_FILE" <<EOF
[user_info]
USERNAME = $SPLUNK_ADMIN_USER
PASSWORD = $SPLUNK_ADMIN_PASS
EOF
chmod 600 "$USERSEED_FILE"

# ---------- 8) Start UF && accept license ----------
echo "[*] Starting UF and accepting license..."
"$SPLUNK_HOME/bin/splunk" start --accept-license --answer-yes --no-prompt

# ---------- 9) Configure log inputs ----------
echo "[*] Writing inputs.conf (Ubuntu 24) → index=${SPLUNK_INDEX}..."
INPUTS_FILE="$SPLUNK_HOME/etc/system/local/inputs.conf"

# feel free to change these monitors, either here or in inputs.conf after running.
# if you're not seeing logs come in, check if these paths exist on your system.
# had no issues on ubuntu CLI installs but sometimes inputs.conf won't get created on ubuntu desktop.

cat > "$INPUTS_FILE" <<EOF
# ========= CCDC Ubuntu 24 UF Inputs =========
# All data goes to index: ${SPLUNK_INDEX}

# Auth (SSH, sudo)
[monitor:///var/log/auth.log]   
disabled = false
index = ${SPLUNK_INDEX}
sourcetype = linux_auth

# System log
[monitor:///var/log/syslog]
disabled = false
index = ${SPLUNK_INDEX}
sourcetype = syslog
EOF

# Optional high-value logs if present
if [ -f /var/log/kern.log ]; then
  cat >> "$INPUTS_FILE" <<EOF

# Kernel log (optional)
[monitor:///var/log/kern.log]
disabled = false
index = ${SPLUNK_INDEX}
sourcetype = linux_kern
EOF
fi

if [ -f /var/log/ufw.log ]; then
  cat >> "$INPUTS_FILE" <<EOF

# UFW firewall log (optional)
[monitor:///var/log/ufw.log]
disabled = false
index = ${SPLUNK_INDEX}
sourcetype = linux_ufw
EOF
fi

if [ -f /var/log/mail.log ]; then
  cat >> "$INPUTS_FILE" <<EOF

# Mail log (optional)
[monitor:///var/log/mail.log]
disabled = false
index = ${SPLUNK_INDEX}
sourcetype = linux_mail
EOF
fi

chmod 600 "$INPUTS_FILE"
echo "[OK] inputs.conf written"

# ---------- 10) Point UF to Splunk Enterprise receiver ----------
echo "[*] Setting forward-server to ${SPLUNK_IP}:${SPLUNK_REC_PORT}..."
"$SPLUNK_HOME/bin/splunk" add forward-server "${SPLUNK_IP}:${SPLUNK_REC_PORT}" \
  -auth "${SPLUNK_ADMIN_USER}:${SPLUNK_ADMIN_PASS}"

# ---------- 11) Enable boot-start (best effort) dont panic if this breaks----------
echo "[*] Enabling boot-start..."
"$SPLUNK_HOME/bin/splunk" enable boot-start || true

# ---------- 12) Restart UF ----------
echo "[*] Restarting UF..."
"$SPLUNK_HOME/bin/splunk" restart

# ---------- 13) Status ----------
echo "[*] UF status:"
"$SPLUNK_HOME/bin/splunk" status || true

echo "[DONE] Ubuntu 24 UF forwarding to ${SPLUNK_IP}:${SPLUNK_REC_PORT} with index=${SPLUNK_INDEX}"