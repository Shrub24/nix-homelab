set shell := ["bash", "-euo", "pipefail", "-c"]
set no-cd

[arg("user", long)]
run host user="dev":
  @ssh {{user}}@{{host}} "sudo systemctl start restic-backups-state.service"

[arg("user", long)]
status host user="dev":
  @ssh {{user}}@{{host}} 'service_status=0; sudo systemctl --no-pager --full status restic-backups-state.service restic-backups-state.timer || service_status=$?; if [ "$service_status" -eq 3 ] && [ "$(sudo systemctl show --property=Result --value restic-backups-state.service)" = success ]; then exit 0; fi; exit "$service_status"'

[arg("user", long)]
[arg("lines", long)]
logs host user="dev" lines="200":
  @ssh {{user}}@{{host}} "sudo journalctl -u restic-backups-state.service -u restic-backups-state.timer -n {{lines}} --no-pager"

# Restore one absolute include path from a snapshot into a fresh root-only
# staging directory under /var/tmp/state-restore on the target host. The
# remote helper (state-restore-stage) prints the resulting path to stdout; it
# never writes live service paths and accepts no arbitrary restic flags.
# Applying the staged files to live state is a separate documented per-service
# step. Transport is injection-safe: values are handed to local bash via
# shell quoting, base64-encoded locally, and only base64-alphabet characters
# ever reach the remote command; the SSH destination is charset-validated.
[arg("user", long)]
restore-stage host snapshot include_path user="dev":
  @HOST={{quote(host)}}; USER={{quote(user)}}; SNAP={{quote(snapshot)}}; INC={{quote(include_path)}}; \
  case "$USER" in *[!a-zA-Z0-9._-]*) echo "restore-stage: invalid user '$USER'" >&2; exit 2;; esac; \
  case "$HOST" in *[!a-zA-Z0-9._:-]*) echo "restore-stage: invalid host '$HOST'" >&2; exit 2;; esac; \
  SNAP64="$(printf '%s' "$SNAP" | base64 -w0)"; \
  INC64="$(printf '%s' "$INC" | base64 -w0)"; \
  ssh "$USER@$HOST" "sudo state-restore-stage --decode '$SNAP64' '$INC64'"
