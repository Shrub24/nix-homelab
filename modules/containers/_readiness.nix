# Readiness for a container unit. `podman --sdnotify=healthy` on a container that declares no
# healthcheck makes podman refuse to start, so the switch and the probe travel together: pass `cmd`
# for an image that ships no HEALTHCHECK, and omit it for one that does.
#
# Merge it as a sibling of the container literal — `lib.mkMerge [ { ... } (mkReadyProbe { ... }) ]` —
# so the probe's `extraOptions` concatenate with the container's rather than replace them.
{ lib }:
{
  mkReadyProbe =
    {
      cmd ? null,
      interval ? "5s",
      timeout ? "3s",
      retries ? 10,
      startPeriod ? "5s",
    }:
    {
      podman.sdnotify = "healthy";
    }
    // lib.optionalAttrs (cmd != null) {
      extraOptions = [
        "--health-cmd=${cmd}"
        "--health-interval=${interval}"
        "--health-timeout=${timeout}"
        "--health-retries=${toString retries}"
        "--health-start-period=${startPeriod}"
      ];
    };
}
