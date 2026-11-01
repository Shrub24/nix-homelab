# Readiness for a container unit. `podman --sdnotify=healthy` requires an explicit
# `--health-cmd`: an image's own HEALTHCHECK does not satisfy it, and podman refuses to start
# (exit 125, "sdnotify policy \"healthy\" requires a healthcheck to be set"). So the switch and
# the probe travel together, and `cmd` has no default.
#
# Merge it as a sibling of the container literal — `lib.mkMerge [ { ... } (mkReadyProbe { ... }) ]` —
# so the probe's `extraOptions` concatenate with the container's rather than replace them.
#
# A ready container also needs a start bound: podman's unit sets TimeoutStartSec = 0 as a
# definition, so a probe that never passes would hold the activation open instead of failing it.
# The budget is the application's, so it is stated at the call site, not here.
#
# Only the first pass matters: `--health-on-failure` stays at its default, so a container that
# fails a check later keeps running and starts no restart loop.
{ lib }:
{
  mkReadyProbe =
    {
      cmd,
      startPeriod ? "5s",
    }:
    {
      podman.sdnotify = "healthy";
      extraOptions = [
        "--health-cmd=${cmd}"
        "--health-interval=10s"
        "--health-timeout=3s"
        "--health-retries=3"
        "--health-start-period=${startPeriod}"
      ];
    };
}
