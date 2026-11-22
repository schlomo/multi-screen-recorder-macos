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
    vm_ip=$(tart ip --wait 120 "$1") || vm_failed "$1 has no IP address within 120 s"
    local deadline=300
    SECONDS=0
    while ((SECONDS < deadline)); do
        if guest true 2>/dev/null; then return 0; fi
        sleep 5
    done
    vm_failed "$1 did not answer over SSH within $deadline s"
}

# Waits until the automatic login of $guest_user has finished: the user owns
# the console and the tccd of their GUI session runs. SSH answers before that,
# and until then the user's own permissions (Microphone) read as denied.
vm_wait_for_login() {
    local deadline=120
    SECONDS=0
    while ((SECONDS < deadline)); do
        if guest "[[ \$(stat -f %Su /dev/console) == $guest_user ]] &&
            launchctl print gui/\$(id -u)/com.apple.tccd 2>/dev/null | grep -q '^[[:space:]]*state = running'"; then
            echo "$me: $guest_user is logged in, after $SECONDS s"
            return 0
        fi
        sleep 1
    done
    vm_failed "$vm_booted: $guest_user was not logged in with tccd running within $deadline s"
}

# Dies with the reason and the tail of the VM's output, which the exit trap deletes with $work.
vm_failed() {
    echo "tart output of $vm_booted:" >&2
    tail -n 20 "$work/tart-run-$vm_booted.log" >&2
    die "$1"
}

# Stops the VM vm_start booted, if it is still running, after the guest wrote
# its disk: an image stopped right after an installation lost the installed files.
vm_stop() {
    if [[ -n ${vm_pid:-} ]] && kill -0 "$vm_pid" 2>/dev/null; then
        guest sync
        # A VM that is still starting is not yet running for tart stop: end its process instead.
        tart stop --timeout 60 "$vm_booted" || kill "$vm_pid"
        for _ in $(seq 15); do kill -0 "$vm_pid" 2>/dev/null || break; sleep 1; done
        if kill -0 "$vm_pid" 2>/dev/null; then kill -9 "$vm_pid"; fi
        wait "$vm_pid" || true
    fi
    vm_pid=""
}
