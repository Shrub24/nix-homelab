# Observability domain: langfuse, the LLM observability stack (the phoenix
# successor) on oci-melb-1. The aspect owner supplies the enablement that
# selection means; the options and runtime body live in the sibling
# contributor ./langfuse/service.nix, which publishes the same aspect name.
{
  flake.modules.nixos.langfuse = {
    # Selecting the deployment aspect is the only enablement.
    services.langfuse.enable = true;
  };
}
