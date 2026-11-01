# Readiness for a container unit. `podman --sdnotify=healthy` on a container that declares no
# healthcheck makes podman refuse to start, so the switch and the probe travel together: pass `cmd`
# for an image that ships no HEALTHCHECK, and omit it for one that does.
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
      cmd ? null,
      startPeriod ? "5s",
    }:
    {
      podman.sdnotify = "healthy";
    }
    // lib.optionalAttrs (cmd != null) {
      extraOptions = [
        "--health-cmd=${cmd}"
        "--health-interval=10s"
        "--health-timeout=3s"
        "--health-retries=3"
        "--health-start-period=${startPeriod}"
      ];
    };
}
