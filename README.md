# mac-bt-hid-reconnect

Keeps Bluetooth mice and keyboards connected on Intel Macs whose Broadcom Bluetooth chip sits on a UART (serial) line and runs on Linux without its patch firmware. Tested on an iMac19,1 (27-inch 5K, 2019) running Omarchy with a Logitech MX Master 3S.

## Do you need this?

You probably do if all of these are true:

- `cat /sys/class/dmi/id/sys_vendor` prints `Apple Inc.`
- `basename "$(readlink -f /sys/class/bluetooth/hci0/device/driver)"` prints `hci_uart_bcm`
- `journalctl -k -b | grep -i 'patch file not found'` shows `BCM: firmware Patch file not found, tried: 'brcm/BCM.hcd'`
- a paired mouse or keyboard stops working now and then and does not come back on its own

## What goes wrong

Linux has no patch firmware for this chip (on the iMac19,1, a BCM4364B0 that reports itself as `Ekans Olympic (MFG)`), so it stays in manufacturing mode on its ROM. In that state:

- it returns malformed advertising reports (`unknown advertising packet type: 0x11 / 0x81 / ...` in the kernel log), which the kernel drops. BlueZ's background auto-connect for bonded LE devices therefore never fires, so a mouse that drops stays gone.
- a targeted `bluetoothctl connect` alone often hears nothing either. On the test iMac, two minutes of connect attempts failed while the mouse was being moved. The mouse came back within a second once an LE scan ran at the same time, and this happened both times it was tried.
- a link can die while BlueZ still reports `Connected: yes`.

## What this does

A small loop (`bt-hid-reconnect`, run by systemd) does this every 2 seconds:

1. It lists paired devices that are **trusted**, **not blocked**, and offer HID: HID over GATT (`0x1812`) or classic HID (`0x1124`).
2. For each one, it checks whether the kernel has an input device for it. It matches on the device's Bluetooth address (the input device's `Uniq`), not on its name. The kernel names a Logitech mouse either `MX Master 3S` or `Logitech MX Master 3S` depending on timing, and matching on the name tears down working links.
3. If the device is missing, it opens a targeted connect with an LE scan running alongside it. Scanning only happens while a device is missing.
4. If BlueZ says `Connected: yes` but there is still no input device after 20 seconds, it drops the stale link and connects again.
5. If connects keep failing with `InProgress`, it power-cycles the adapter once. That is the only thing that clears this BlueZ state.

It leaves Bluetooth alone when you turned it off: when the adapter is rfkill-blocked or powered off, it does nothing and never powers the adapter back on.

## Install

```bash
git clone https://github.com/hlang98923/mac-bt-hid-reconnect.git
cd mac-bt-hid-reconnect
sudo ./install.sh
```

The installer refuses to run unless the machine is an Apple Mac with an `hci_uart_bcm` controller. Use `sudo ./install.sh --force` to skip that check. It installs `/usr/local/bin/bt-hid-reconnect` and enables `bt-hid-reconnect.service`.

Watch it work:

```bash
journalctl -fu bt-hid-reconnect
```

Remove it:

```bash
sudo ./uninstall.sh
```

To stop it reconnecting one particular device, untrust that device: `bluetoothctl untrust <address>`.

## What it can't fix

- **It recovers from drops; it doesn't prevent them.** The chip still runs without firmware, so links still drop. Most devices only advertise when touched, so after a drop the device comes back when you move or click it, usually within a second or two.
- **It scans while a device is missing.** If a trusted mouse stays switched off for hours, the loop scans that whole time. Bluetooth and Wi-Fi share one chip, so this might cost some Wi-Fi throughput. Untrust devices you leave off.
- **The real fix is firmware plus driver work.** macOS ships this chip's patch as Intel HEX (`/usr/share/firmware/bluetooth/BCM4364B0-*.hex`). [MrHogun/imac-a2115-linux](https://github.com/MrHogun/imac-a2115-linux#bluetooth--not-solved) converted it to `.hcd`: the chip accepts the patch and then stops answering (`failed to write update baudrate (-110)`), because `hci_uart_bcm` can't follow the UART speed change on this machine. Until that driver work is done, this loop is the practical fix.

## Tests

```bash
tests/run.sh
```

The tests run the loop for one pass against a fake `bluetoothctl` and check which commands it ran: name-independent matching, ignored devices, rfkill and power-off handling, the stale-link grace period, the scan, and the `InProgress` recovery. No Bluetooth hardware is needed.

## License

MIT
