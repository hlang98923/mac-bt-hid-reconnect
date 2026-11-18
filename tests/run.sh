#!/bin/bash
# Run bt-hid-reconnect for one pass against a fake bluetoothctl and check what it did.
#   tests/run.sh
set -u

ROOT=$(cd "$(dirname "$0")/.." && pwd)
MAC=DF:EF:A2:67:98:30
MAC2=C0:11:22:33:44:55
HOG=00001812-0000-1000-8000-00805f9b34fb
CLASSIC_HID=00001124-0000-1000-8000-00805f9b34fb
AUDIO=0000110b-0000-1000-8000-00805f9b34fb
pass=0
fail=0

setup() {
  T=$(mktemp -d)
  mkdir -p "$T/bin" "$T/rfkill/rfkill0"
  echo bluetooth >"$T/rfkill/rfkill0/type"
  echo 0 >"$T/rfkill/rfkill0/soft"
  echo 0 >"$T/rfkill/rfkill0/hard"
  echo yes >"$T/powered"
  : >"$T/paired"
  : >"$T/calls"
  : >"$T/input"

  # The fake bluetoothctl logs every call and answers from files in $T
  cat >"$T/bin/bluetoothctl" <<EOF
#!/bin/bash
echo "\$*" >>"$T/calls"
case \$1 in
  show) echo "Controller 38:F9:D3:D6:67:F7 (public)"; echo "	Powered: \$(<"$T/powered")" ;;
  devices) cat "$T/paired" ;;
  info) cat "$T/info_\$2" 2>/dev/null ;;
  connect) cat "$T/connect_\$2" 2>/dev/null || echo "Failed to connect: org.bluez.Error.Failed" ;;
  power|disconnect) echo "Changing \$* succeeded" ;;
esac
EOF
  # No real waiting in tests
  printf '#!/bin/bash\nexit 0\n' >"$T/bin/sleep"
  chmod +x "$T/bin/bluetoothctl" "$T/bin/sleep"
}

pair() {  # mac trusted blocked connected uuid
  # bluetoothctl colours this line even into a pipe; keep the escape codes in
  printf '\033[1;30mDevice %s Some Device\033[0m\n' "$1" >>"$T/paired"
  printf 'Device %s (random)\n\tTrusted: %s\n\tBlocked: %s\n\tConnected: %s\n\tUUID: Something (%s)\n' \
    "$1" "$2" "$3" "$4" "$5" >"$T/info_$1"
}

input_device() {  # mac name
  printf 'I: Bus=0005 Vendor=046d Product=b034 Version=0006\nN: Name="%s"\nU: Uniq=%s\n\n' \
    "$2" "${1,,}" >>"$T/input"
}

run() {
  PATH="$T/bin:$PATH" \
    BT_HID_RECONNECT_INPUT_DEVICES="$T/input" \
    BT_HID_RECONNECT_RFKILL_DIR="$T/rfkill" \
    BT_HID_RECONNECT_ONESHOT=1 \
    "$@" "$ROOT/bt-hid-reconnect" >"$T/out" 2>&1
}

called() {
  grep -qxF -- "$1" "$T/calls"
}

check() {  # description, then a command that must succeed
  local what=$1
  shift
  if "$@"; then
    pass=$(( pass + 1 ))
  else
    fail=$(( fail + 1 ))
    echo "FAIL: $what"
    echo "  calls: $(tr '\n' '|' <"$T/calls")"
    echo "  output: $(tr '\n' '|' <"$T/out")"
  fi
}

not() {
  ! "$@"
}

setup; pair $MAC yes no no $HOG; input_device $MAC "Logitech MX Master 3S"; run env
check "present device is left alone" not called "connect $MAC"
check "no scan while every device is present" not called "--timeout 45 scan le"

setup; pair $MAC yes no no $HOG; input_device $MAC "MX Master 3S"; run env
check "device is matched by address, not by name" not called "connect $MAC"
check "a present device is never disconnected" not called "disconnect $MAC"

setup; pair $MAC yes no no $HOG; run env
check "missing LE HID device gets a connect" called "connect $MAC"
check "an LE scan runs alongside the connect" called "--timeout 45 scan le"
check "a failed connect is logged" grep -q "still missing (Failed to connect: org.bluez.Error.Failed)" "$T/out"

setup; pair $MAC yes no no $CLASSIC_HID; run env
check "missing classic HID device gets a connect" called "connect $MAC"

setup; pair $MAC yes no no $HOG; echo "Connection successful" >"$T/connect_$MAC"; run env
check "a successful connect is logged" grep -q "$MAC: reconnected" "$T/out"

setup; pair $MAC no no no $HOG; run env
check "untrusted device is ignored" not called "connect $MAC"

setup; pair $MAC yes yes no $HOG; run env
check "blocked device is ignored" not called "connect $MAC"

setup; pair $MAC yes no no $AUDIO; run env
check "non-HID device is ignored" not called "connect $MAC"

setup; pair $MAC yes no no $HOG; echo 1 >"$T/rfkill/rfkill0/soft"; run env
check "rfkill soft block: no bluetoothctl calls at all" test ! -s "$T/calls"

setup; pair $MAC yes no no $HOG; echo no >"$T/powered"; run env
check "powered-off adapter: no connect" not called "connect $MAC"
check "powered-off adapter: never powered back on" not called "power on"

setup; pair $MAC yes no yes $HOG; run env
check "fresh link with no input device yet: no disconnect inside the grace period" not called "disconnect $MAC"
check "fresh link with no input device yet: no connect inside the grace period" not called "connect $MAC"

setup; pair $MAC yes no yes $HOG; run env BT_HID_RECONNECT_STALE_GRACE=0
check "stale link past the grace period is dropped" called "disconnect $MAC"
check "stale link past the grace period is reconnected" called "connect $MAC"

setup; pair $MAC yes no no $HOG; pair $MAC2 yes no no $HOG
echo "Failed to connect: org.bluez.Error.InProgress" >"$T/connect_$MAC"
echo "Failed to connect: org.bluez.Error.InProgress" >"$T/connect_$MAC2"
run env
check "two InProgress results power the adapter off" called "power off"
check "two InProgress results power the adapter back on" called "power on"

setup; pair $MAC yes no no $HOG; pair $MAC2 yes no no $HOG; input_device $MAC "MX Master 3S"; run env
check "with two devices, only the missing one gets a connect" called "connect $MAC2"
check "with two devices, the present one is left alone" not called "connect $MAC"

echo "$pass passed, $fail failed"
(( fail == 0 ))
