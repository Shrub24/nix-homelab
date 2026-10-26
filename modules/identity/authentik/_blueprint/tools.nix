{ pkgs }:
rec {
  python = pkgs.python3.withPackages (ps: [
    ps.ruamel-yaml
    ps.jsonschema
  ]);

  # The interpreter ships beside the tool so a caller needs one store path.
  tool = pkgs.runCommandLocal "authentik-blueprint-tools" { } ''
    mkdir -p $out/bin
    ln -s ${python}/bin/python3 $out/bin/authentik-blueprint-python
    cat > $out/bin/authentik-blueprint-tools <<EOF
    #!${pkgs.runtimeShell}
    exec ${python}/bin/python3 ${./assemble.py} "\$@"
    EOF
    chmod +x $out/bin/authentik-blueprint-tools
  '';
}
