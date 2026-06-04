set shell := ["bash", "-euo", "pipefail", "-c"]
set no-cd

[arg("user", long)]
run host user="dev":
  @ssh {{user}}@{{host}} "sudo systemctl start restic-backups-state.service"

[arg("user", long)]
status host user="dev":
  @ssh {{user}}@{{host}} "sudo systemctl --no-pager --full status restic-backups-state.service restic-backups-state.timer"

[arg("user", long)]
[arg("lines", long)]
logs host user="dev" lines="200":
  @ssh {{user}}@{{host}} "sudo journalctl -u restic-backups-state.service -u restic-backups-state.timer -n {{lines}} --no-pager"
