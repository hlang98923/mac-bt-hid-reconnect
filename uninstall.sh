#!/bin/bash
# Remove bt-hid-reconnect. Run with sudo.
set -euo pipefail

if (( EUID != 0 )); then
  echo "Run this with sudo: sudo $0" >&2
  exit 1
fi

systemctl disable --now bt-hid-reconnect.service 2>/dev/null || true
rm -f /etc/systemd/system/bt-hid-reconnect.service /usr/local/bin/bt-hid-reconnect
systemctl daemon-reload
echo "Removed."
