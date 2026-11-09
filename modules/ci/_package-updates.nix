# The scheduled update transaction: one run refreshes the lock and the
# registered package pins, then proposes the combined result on its own branch,
# so CI sees the new inputs and the new pins together rather than two
# intermediate updates and then their combination. A value-imported helper of
# effects.nix.
{
  config,
  lib,
  pkgs,
  effects,
}:
primaryRepo:
let
  coordinatorSystem = config.nixos.hosts.home-forge.system;
  publish = pkgs.writers.writePython3Bin "nixbot-package-updates-publish" { } (
    builtins.readFile ./_package-updates-publish.py
  );
  updater = config.flake.apps.${coordinatorSystem}.update-packages.program;
  branch = "automation/package-updates";
  title = "chore(deps): Refresh flake inputs and package pins";
  script = ''
    set -euo pipefail
    cd "''${NIXBOT_EFFECT_CHECKOUT:?nixbot must supply the checkout}"
    work=$(mktemp -d)
    report=$work/package-updates.json
    body=$work/package-updates.md

    # Package update scripts are trusted repository code, and the contract keeps
    # them away from a credential that can push: the token is read here and the
    # file it came from leaves the environment before the batch runs.
    token=$(jq -r '.token.data.token' "$HERCULES_CI_SECRETS_JSON")
    unset HERCULES_CI_SECRETS_JSON

    # The batch stages through a jj workspace; the clone starts as plain git.
    [ -d .jj ] || jj git init --colocate >/dev/null

    status=0
    nix run .#update-packages -- --refresh-inputs --json "$report" --markdown "$body" || status=$?
    if [ ! -f "$report" ]; then
      echo "package-updates: the batch wrote no report (exit $status)" >&2
      exit 1
    fi
    outcome=$(jq -r .outcome "$report")
    echo "package-updates: outcome=$outcome (exit $status)"
    # `partial` is proposable and names what failed; `aborted` carries no tree.
    case "$outcome" in
      complete | partial) ;;
      *)
        echo "package-updates: nothing proposable" >&2
        exit 1
        ;;
    esac

    if [ -z "$(git status --porcelain)" ]; then
      echo "package-updates: nothing to publish"
      exit 0
    fi

    jj describe -m ${lib.escapeShellArg title} -r @
    jj bookmark set ${lib.escapeShellArg branch} -r @
    jj git push --bookmark ${lib.escapeShellArg branch}

    TOKEN="$token" ${lib.getExe publish} \
      ${lib.escapeShellArg primaryRepo.remoteHttpUrl} \
      ${lib.escapeShellArg "${primaryRepo.owner}/${primaryRepo.name}"} \
      ${lib.escapeShellArg branch} \
      ${lib.escapeShellArg (primaryRepo.branch or "main")} \
      ${lib.escapeShellArg title} \
      "$body"
  '';
in
{
  # Weekly, at the minute the fleet's previous weekly refresh used.
  when = {
    minute = 43;
    hour = [ 4 ];
    dayOfWeek = [ "Mon" ];
  };
  outputs.effects.update = effects.mkEffect {
    name = "package-updates";
    checkout = true;
    # One producer: an overlapping run would refresh from a moved base.
    lock = "package-updates";
    # The effect pushes and opens the pull request with the forge token nixbot
    # supplies; no operator-provisioned credential is involved.
    secretsMap.token = {
      type = "GitToken";
    };
    inputs = [
      pkgs.git
      pkgs.jq
      pkgs.jujutsu
      config.flake.nixosConfigurations.home-forge.config.nix.package
      updater
      publish
    ];
    effectScript = script;
  };
}
