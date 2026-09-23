set shell := ["bash", "-euo", "pipefail", "-c"]
set no-cd

[arg("user", long)]
ssh host user="dev":
  @ssh {{user}}@{{host}}

ssh-root host:
  @ssh root@{{host}}

[arg("user", long)]
spice host="home-forge" user="dev":
  @ssh -f -N -o ClearAllForwardings=no -o ExitOnForwardFailure=yes -L 5900:127.0.0.1:5900 {{user}}@{{host}}
  @echo "SPICE tunnel ready: spice://127.0.0.1:5900"

[arg("user", long)]
[arg("unit", long)]
[arg("lines", long)]
logs host user="dev" unit="tailscaled" lines="200":
  @ssh {{user}}@{{host}} "sudo journalctl -u {{unit}} -n {{lines}} --no-pager"

[arg("user", long)]
status host user="dev":
  @ssh {{user}}@{{host}} "hostnamectl; echo; sudo systemctl --no-pager --full status tailscaled"

[arg("user", long)]
tailscale-status host user="dev":
  @ssh {{user}}@{{host}} "sudo tailscale status"

[arg("user", long)]
breakglass host user="dev":
  @ssh {{user}}@{{host}} "set -euo pipefail; hostnamectl; echo '---'; readlink -f /nix/var/nix/profiles/system; echo '---'; sudo nix-env -p /nix/var/nix/profiles/system --list-generations"

_usb-op operation vendor product host vm user:
  #!/usr/bin/env bash
  set -euo pipefail
  operation={{quote(operation)}}
  vendor={{quote(vendor)}}
  product={{quote(product)}}
  host={{quote(host)}}
  vm={{quote(vm)}}
  user={{quote(user)}}

  if [[ ! $vendor =~ ^[[:xdigit:]]{4}$ || ! $product =~ ^[[:xdigit:]]{4}$ ]]; then
    echo "vendor and product IDs must be exactly four hexadecimal characters" >&2
    exit 2
  fi

  printf -v remote_command 'bash -s -- %q %q %q %q' "$operation" "$vm" "${vendor,,}" "${product,,}"
  ssh -- "$user@$host" "$remote_command" <<'REMOTE'
  set -euo pipefail
  operation=$1
  vm=$2
  vendor=$3
  product=$4

  matches=()
  for candidate in /sys/bus/usb/devices/*; do
    [[ -f $candidate/idVendor && -f $candidate/idProduct && -f $candidate/busnum && -f $candidate/devnum ]] || continue
    [[ ${candidate##*/} != usb* ]] || continue
    [[ ${vendor,,} == $(<"$candidate/idVendor") && ${product,,} == $(<"$candidate/idProduct") ]] || continue
    matches+=("$(realpath "$candidate")")
  done

  if (( ${#matches[@]} != 1 )); then
    printf 'expected exactly one USB device matching %s:%s, found %d\n' "$vendor" "$product" "${#matches[@]}" >&2
    exit 1
  fi

  device=${matches[0]}
  bus=$(<"$device/busnum")
  dev=$(<"$device/devnum")
  xml=$(mktemp)
  trap 'rm -f "$xml"' EXIT
  cat >"$xml" <<XML
  <hostdev mode='subsystem' type='usb' managed='yes'>
    <source>
      <vendor id='0x$vendor'/>
      <product id='0x$product'/>
      <address bus='$bus' device='$dev'/>
    </source>
  </hostdev>
  XML

  case $operation in
    attach)
      sudo -n virsh attach-device "$vm" "$xml" --live
      ;;
    detach)
      sudo -n virsh detach-device "$vm" "$xml" --live
      sudo -n sync

      declare -A disks=()
      while IFS= read -r -d '' block_dir; do
        for entry in "$block_dir"/*; do
          [[ -e $entry ]] || continue
          disks["/dev/${entry##*/}"]=1
        done
      done < <(find "$device" -type d -name block -print0)

      for disk in "${!disks[@]}"; do
        [[ -b $disk ]] || continue
        mapfile -t nodes < <(lsblk -nrpo NAME "$disk" | tac)
        for node in "${nodes[@]}"; do
          mapfile -t mountpoints < <(findmnt -rn --raw -S "$node" -o TARGET)
          for mountpoint in "${mountpoints[@]}"; do
            sudo -n umount -- "$mountpoint"
          done
        done

        # Deleting the disk's SCSI device removes the disk and all partitions.
        scsi_device=$(readlink -f "/sys/block/${disk##*/}/device" 2>/dev/null || true)
        if [[ -n $scsi_device && -e $scsi_device/delete ]]; then
          printf '1\n' | sudo -n tee "$scsi_device/delete" >/dev/null
        fi
      done
      ;;
    *)
      echo "unsupported USB operation: $operation" >&2
      exit 2
      ;;
  esac
  REMOTE

[arg("host", long)]
[arg("vm", long)]
[arg("user", long)]
usb-attach vendor product host="home-forge" vm="windows-dj" user="dev": (_usb-op "attach" vendor product host vm user)

[arg("host", long)]
[arg("vm", long)]
[arg("user", long)]
usb-detach vendor product host="home-forge" vm="windows-dj" user="dev": (_usb-op "detach" vendor product host vm user)
