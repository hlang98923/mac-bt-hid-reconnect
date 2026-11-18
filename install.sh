#!/bin/bash
# Install bt-hid-reconnect as a system service. Run with sudo.
#   sudo ./install.sh          install on a supported Mac
#   sudo ./install.sh --force  install without the hardware check
set -euo pipefail

cd "$(dirname "$0")"

if (( EUID != 0 )); then
  echo "Run this with sudo: sudo $0 $*" >&2
  exit 1
fi

uart_bcm=false
for dev in /sys/class/bluetooth/hci*/device; do
  if [[ -e $dev/driver && $(basename "$(readlink -f "$dev/driver")") == "hci_uart_bcm" ]]; then
    uart_bcm=true
  fi
done
vendor=$(cat /sys/class/dmi/id/sys_vendor 2>/dev/null || true)

if [[ ${1:-} != "--force" ]] && ! { [[ $vendor == Apple* ]] && $uart_bcm; }; then
  echo "This machine is not a Mac with a Broadcom UART Bluetooth controller (hci_uart_bcm)," >&2
  echo "so it should not need this. Use --force to install anyway." >&2
  exit 1
fi

install -Dm755 bt-hid-reconnect /usr/local/bin/bt-hid-reconnect
install -Dm644 bt-hid-reconnect.service /etc/systemd/system/bt-hid-reconnect.service
systemctl daemon-reload
systemctl enable --now bt-hid-reconnect.service

echo "Installed. Follow it with: journalctl -fu bt-hid-reconnect"
