# Paperless deployment aspect. The service leaf (including the GPT/docling
# composition) is the intrinsic implementation; selection supplies the
# top-level enablement, and host-scoped variants stay explicit.
_: {
  flake.modules.nixos.paperless = {
    services.paperless.enable = true;
  };
}
