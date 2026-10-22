# Music runbook

Operator steps for the `home-forge` music stack that Nix cannot seed.

## Navidrome + AudioMuse plugin

After the Navidrome binary is installed and running:

1. Navidrome Admin → Plugins → `audiomuse.ai`: enable, set the AudioMuse API URL and key.
2. Complete the AudioMuse first-run wizard (web UI on `:8000`).
3. Symfonium → Navidrome connection: configure as an OpenSubsonic server.

These settings live in Navidrome's application database and AudioMuse's setup
state, so they survive a redeploy but not a fresh instance. Upstream exposes no
stable import path, which is why they are not declarative.
