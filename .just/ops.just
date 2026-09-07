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
