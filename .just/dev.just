set shell := ["bash", "-euo", "pipefail", "-c"]
set no-cd

setup:
  @sops -d secrets/services/notification-daemon.yaml > /tmp/notification-daemon.json
