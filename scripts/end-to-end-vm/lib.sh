# Sourced by scripts/end-to-end-setup and scripts/end-to-end-test: the VM's
# names, the guest's paths and the SSH helpers. The caller sets `me` (its name
# for error messages) and `work` (a folder of its own for the VM's output).
# The VM's user is the Cirrus Labs images' admin, whose published password
# askpass answers.
set -euo pipefail

vm_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
image_vm="msr-end-to-end"
base_image="ghcr.io/cirruslabs/macos-tahoe-vanilla:latest"
guest_user="admin"
guest_home="/Users/$guest_user"
guest_app_root="$guest_home/msr"
guest_tools="$guest_home/end-to-end-tools"

die() { echo "$me: $*" >&2; exit 1; }

require() {
    for tool in "$@"; do
        command -v "$tool" >/dev/null || die "$tool is not on the PATH"
    done
}

vm_exists() { tart get "$1" >/dev/null 2>&1; }

ssh_options=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR
    -o PubkeyAuthentication=no -o ConnectTimeout=5 -o ServerAliveInterval=15)

# Runs a command in the running VM over SSH ($vm_ip, set by vm_start).
guest() {
    SSH_ASKPASS="$vm_dir/askpass" SSH_ASKPASS_REQUIRE=force DISPLAY=none \
        ssh "${ssh_options[@]}" "$guest_user@$vm_ip" "$@"
}

# Boots the VM $1 without a window and waits until it answers over SSH.
vm_start() {
    vm_booted=$1
    tart run --no-graphics "$1" >"$work/tart-run-$1.log" 2>&1 &
    vm_pid=$!
    vm_ip=$(tart ip --wait 120 "$1")
    for _ in $(seq 60); do
        if guest true 2>/dev/null; then return 0; fi
        sleep 5
    done
    die "$1 did not answer over SSH within 300 s (tart output: $work/tart-run-$1.log)"
}

# Stops the VM vm_start booted, if it is still running, after the guest wrote
# its disk: an image stopped right after an installation lost the installed files.
vm_stop() {
    if [[ -n ${vm_pid:-} ]] && kill -0 "$vm_pid" 2>/dev/null; then
        guest sync
        tart stop --timeout 60 "$vm_booted"
        wait "$vm_pid" || true
    fi
    vm_pid=""
}
