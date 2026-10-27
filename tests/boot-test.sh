# Boots a NixOS image the way SmartOS's bhyve boots one, and checks that
# cloud-init configured it from the NoCloud CIDATA disk.
#
# Like bhyve: UEFI with no saved boot entries (so the image must boot from
# the removable-media path), a virtio boot disk larger than the image, a
# virtio NIC, and a 16 MiB FAT16 disk labelled CIDATA holding the files
# vmadm writes (tests/cidata, in the format of smartos-live's
# src/vm/node_modules/cloudinit/nocloud.js).
#
# Usage: boot-test [IMAGE]
#   IMAGE is a qcow2 file, or a directory holding one; by default the
#   flake's image. Needs OVMF_CODE, OVMF_VARS and CIDATA in the environment,
#   which the flake app sets.

image=${1:-$DEFAULT_IMAGE}
if [ -d "$image" ]; then
  image=$(find -L "$image" -maxdepth 1 -name '*.qcow2' | head -n 1)
fi
if [ ! -f "$image" ]; then
  echo "boot-test: no qcow2 image at '${1:-$DEFAULT_IMAGE}'" >&2
  exit 2
fi

work=$(mktemp -d "${TMPDIR:-/tmp}/boot-test.XXXXXX")
cleanup() {
  if [ -f "$work/qemu.pid" ]; then
    kill "$(cat "$work/qemu.pid")" 2>/dev/null || true
  fi
  if [ -n "${KEEP_WORK:-}" ]; then
    echo "boot-test: kept $work"
  else
    rm -rf "$work"
  fi
}
trap cleanup EXIT

hostname=nixos-smartos-test
address=10.0.2.20
port=$(shuf -i 20000-40000 -n 1)

ssh-keygen -q -t ed25519 -N '' -C boot-test -f "$work/key"
key=$(cat "$work/key.pub")

# The boot disk: an overlay on the image, grown to 8 GiB so the test can
# see cloud-init and NixOS grow the root filesystem to fill it.
qemu-img create -q -f qcow2 -F qcow2 -b "$(realpath "$image")" "$work/disk.qcow2" 8G

mkdir "$work/cidata"
cp "$CIDATA/meta-data" "$CIDATA/network-config" "$work/cidata/"
sed "s|@SSH_KEY@|$key|" "$CIDATA/user-data" > "$work/cidata/user-data"
truncate -s 16M "$work/cidata.img"
mkfs.vfat -F 16 -n CIDATA "$work/cidata.img" > /dev/null
mcopy -i "$work/cidata.img" "$work/cidata/meta-data" "$work/cidata/user-data" \
  "$work/cidata/network-config" ::

cp "$OVMF_VARS" "$work/vars.fd"
chmod u+w "$work/vars.fd"

qemu-system-x86_64 \
  -machine q35,accel=kvm -cpu host -m 2048 -smp 2 \
  -display none -serial "file:$work/serial.log" \
  -drive if=pflash,format=raw,readonly=on,file="$OVMF_CODE" \
  -drive if=pflash,format=raw,file="$work/vars.fd" \
  -drive if=virtio,format=qcow2,file="$work/disk.qcow2" \
  -drive if=virtio,format=raw,file="$work/cidata.img" \
  -netdev "user,id=net0,net=10.0.2.0/24,hostfwd=tcp:127.0.0.1:$port-$address:22" \
  -device virtio-net-pci,netdev=net0,mac=02:08:20:ac:e1:00 \
  -daemonize -pidfile "$work/qemu.pid"

guest() {
  SSH_AUTH_SOCK='' timeout "${guest_timeout:-600}" ssh -F /dev/null -i "$work/key" -o IdentitiesOnly=yes \
    -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -o LogLevel=ERROR -o ConnectTimeout=5 -p "$port" admin@127.0.0.1 "$@"
}

wait_for_ssh() {
  # QEMU's port forward accepts the connection even when nothing in the
  # guest listens, and ssh then waits for a banner that never comes.
  for _ in $(seq 60); do
    if guest_timeout=15 guest true 2>/dev/null; then
      return 0
    fi
    sleep 5
  done
  echo "boot-test: no SSH as admin at $address after 300s; serial console:" >&2
  tail -n 40 "$work/serial.log" >&2
  return 1
}

failures=0
check() {
  local what=$1
  shift
  if "$@"; then
    echo "ok: $what"
  else
    echo "FAIL: $what"
    failures=$((failures + 1))
  fi
}

cloud_init_done() {
  local status
  status=$(guest cloud-init status --wait --format json)
  # SmartOS writes the default route as `gateway4`, which cloud-init
  # reports as deprecated; that is the host's doing, not the image's.
  if ! jq -e '.status == "done" and (.errors | length) == 0
      and ([.recoverable_errors[][] | select(test("`gateway4`") | not)]
        | length) == 0' <<< "$status" > /dev/null; then
    echo "$status"
    return 1
  fi
}

hostname_is_set() {
  [ "$(guest hostname)" = "$hostname" ]
}

static_address_on_net0() {
  guest ip -4 -o addr show dev net0 | grep -q "inet $address/24"
}

default_route_via_gateway() {
  guest ip -4 route show default | grep -q 'default via 10.0.2.2 dev net0'
}

resolver_configured() {
  guest 'cat /etc/resolv.conf; resolvectl dns 2>/dev/null' | grep -q '10\.0\.2\.3'
}

sudo_works() {
  guest sudo -n true
}

runcmd_ran() {
  guest test -e /var/lib/cloud-init-runcmd-ran
}

# NixOS's sshd-keygen makes the host keys. cloud-init's ssh module would
# race it, since cloud-config is not ordered against sshd-keygen, so it
# must not delete or generate them.
host_keys_left_to_nixos() {
  # cloud-init logs to the journal only (/var/log/cloud-init.log stays
  # empty). Check that the cloud-config stage ran and ran no ssh-keygen.
  local log
  log=$(guest sudo journalctl -b -u cloud-config --no-pager)
  grep -q -F "Running module ssh " <<< "$log" &&
    ! grep -q -F "['ssh-keygen'" <<< "$log"
}

root_filesystem_grown() {
  local size
  size=$(guest df -B1 --output=size / | tail -n 1)
  [ "$size" -gt $((6 * 1024 * 1024 * 1024)) ]
}

serial_console_login() {
  grep -q "$hostname login:" "$work/serial.log"
}

# zlib, qcow2's default, since every qcow2 reader can decompress it.
image_compressed() {
  qemu-img info --output=json "$image" |
    jq -e '."format-specific".data."compression-type" == "zlib"' > /dev/null &&
    qemu-img map --output=json "$image" | jq -e 'any(.[]; .compressed)' > /dev/null
}

check "image: zlib-compressed qcow2" image_compressed

if ! wait_for_ssh; then
  echo "FAIL: first boot: SSH as the user-data's user"
  exit 1
fi
echo "ok: first boot: SSH as the user-data's user"
check "first boot: cloud-init finished without errors" cloud_init_done
check "first boot: hostname from meta-data" hostname_is_set
check "first boot: static address on net0" static_address_on_net0
check "first boot: default route via the gateway" default_route_via_gateway
check "first boot: resolver from network-config" resolver_configured
check "first boot: sudo from user-data" sudo_works
check "first boot: runcmd ran" runcmd_ran
check "first boot: host keys left to NixOS" host_keys_left_to_nixos
check "first boot: root filesystem grown to the disk" root_filesystem_grown
check "first boot: login prompt on the serial console" serial_console_login

first_boot_id=$(guest cat /proc/sys/kernel/random/boot_id)
guest sudo systemctl reboot || true
for _ in $(seq 30); do
  guest_timeout=15 guest true 2>/dev/null || break
  sleep 2
done

if ! wait_for_ssh; then
  echo "FAIL: second boot: SSH as the user-data's user"
  exit 1
fi
echo "ok: second boot: SSH as the user-data's user"
rebooted() {
  [ "$(guest cat /proc/sys/kernel/random/boot_id)" != "$first_boot_id" ]
}
check "second boot: the guest rebooted" rebooted
check "second boot: cloud-init finished without errors" cloud_init_done
check "second boot: hostname from meta-data" hostname_is_set
check "second boot: static address on net0" static_address_on_net0
check "second boot: default route via the gateway" default_route_via_gateway

if [ "$failures" -ne 0 ]; then
  echo "boot-test: $failures check(s) failed"
  exit 1
fi
echo "boot-test: all checks passed"
