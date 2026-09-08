## 1. Declarative integration

- [x] 1.1 Add the pinned upstream flake input and import its NixOS module solely in the home-forge configuration; verify `nix flake lock --update-input traktor-m3u-sync` succeeds.
- [x] 1.2 Configure the home-forge manual M3U-import and iTunes-export worker with `/music` source paths, `file://localhost/M:` locations, persistent state/input paths, and no automatic trigger; verify the home-forge configuration evaluates.
- [x] 1.3 Adopt the upstream states/jobs module restructure: bump the pin, rewire to a named state domain plus `navidrome` import and `itunes` export jobs (import chains export via `onSuccess`), and map locations to `file://localhost/M:/library` under the normalized music root; verify evaluation and the generated unit names.

## 2. Operator workflow

- [x] 2.1 Document the manual Navidrome download, import, export, and Engine DJ validation sequence; verify formatting and strict OpenSpec validation pass.
- [ ] 2.2 Deploy home-forge, process a downloaded Navidrome M3U, and validate the generated XML in Engine DJ; verify both services succeed and the guest resolves its imported locations on `M:`.
- [ ] 2.4 Ship a `playlist-sync` command (fetch `/music`-rooted M3Us via the Subsonic API into the import dir, then start the import job); deploy and run it end to end
  - verify: home-forge eval, `playlist-sync` exports + triggers import, engine DB updates, strict validation
- [ ] 2.3 Wire the `engine` direct-DB export job (import chains to it via `onSuccess`); deploy and validate `export@engine` publishes into the quiesced guest DB.
