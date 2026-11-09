# Projection of the notification recovery contract (D-131) for
# tests/check-notify-recovery-contract.sh.
#
# A registered failure event means "automatic recovery ended", so a monitored
# unit that restarts must restart in direct mode, must have a finite start
# limit for that ending to exist, and an unmonitored unit must carry neither.
# The projection is evaluated for the real configuration and for single-field
# mutations, so the same rules that must accept the fleet must reject it when a
# field is forced away.
{ flake }:
let
  lib = flake.inputs.nixpkgs.lib;

  directive =
    text: key:
    let
      matches = builtins.filter (line: lib.hasPrefix "${key}=" line) (lib.splitString "\n" text);
    in
    if matches == [ ] then null else lib.last (map (line: lib.removePrefix "${key}=" line) matches);

  inspect =
    config:
    let
      events = config.services.notify.events;
      monitored = builtins.filter (
        name: events.${name}.failure != null || events.${name}.success != null
      ) (builtins.attrNames events);
      isMonitored = name: lib.elem name monitored;

      services = map (lib.removeSuffix ".service") (
        builtins.filter (name: lib.hasSuffix ".service" name) (lib.attrNames config.systemd.units)
      );
      text = name: config.systemd.units."${name}.service".text or "";

      restart = name: directive (text name) "Restart";
      restarting =
        name:
        let
          value = restart name;
        in
        value != null && value != "no";
      restartMode = name: directive (text name) "RestartMode";
      limit = name: directive (text name) "StartLimitIntervalSec";

      findings = lib.concatMap (
        name:
        lib.optional (
          isMonitored name && restarting name && restartMode name != "direct"
        ) "${name}: restarts without RestartMode=direct, so every failed attempt notifies"
        ++
          lib.optional (isMonitored name && restarting name && (limit name == null || limit name == "0"))
            "${name}: restarts without a finite start limit, so the failure a notification reports never occurs"
        ++ lib.optional (
          !(isMonitored name) && restartMode name != null
        ) "${name}: carries RestartMode=${restartMode name} but registers no notification event"
      ) services;
    in
    {
      inherit findings;
      restartingMonitored = builtins.filter (name: isMonitored name && restarting name) services;
      restartingUnmonitored = builtins.filter (name: !(isMonitored name) && restarting name) services;
      notifyAssertionFailures = map (assertion: assertion.message) (
        builtins.filter (assertion: !assertion.assertion) config.assertions
      );
    };

  mutate = host: modules: inspect (host.extendModules { inherit modules; }).config;

  report =
    host:
    let
      real = inspect host.config;
      subject = builtins.head real.restartingMonitored;
      stray = builtins.head real.restartingUnmonitored;
      unbounded = mutate host [
        {
          systemd.services.${subject}.unitConfig.StartLimitIntervalSec = lib.mkForce "0";
        }
      ];
    in
    {
      inherit (real)
        findings
        restartingMonitored
        notifyAssertionFailures
        ;
      forcedNormal = {
        unit = subject;
        findings =
          (mutate host [
            {
              systemd.services.${subject}.serviceConfig.RestartMode = lib.mkForce "normal";
            }
          ]).findings;
      };
      strays = {
        unit = stray;
        findings =
          (mutate host [
            {
              systemd.services.${stray}.serviceConfig.RestartMode = lib.mkForce "direct";
            }
          ]).findings;
      };
      unbounded = {
        unit = subject;
        notifyAssertionFailures = unbounded.notifyAssertionFailures;
      };
    };
in
lib.mapAttrs (_: report) flake.nixosConfigurations
