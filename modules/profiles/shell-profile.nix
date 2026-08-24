{
  config,
  lib,
  pkgs,
  ...
}:

let
  weztermCfg = config.profiles.wezterm-mux;
in
{
  options.profiles.wezterm-mux = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable wezterm-mux-server (system-level persistent mux server).";
    };
    user = lib.mkOption {
      type = lib.types.str;
      default = "dev";
      description = "User to run the mux server as.";
    };
  };

  config = {
    environment.systemPackages = with pkgs; [
      bat
      btop
      duf
      eza
      fd
      fzf
      jq
      lsof
      ncdu
      yq-go
      ripgrep
      zoxide
      zsh-autosuggestions
      zsh-powerlevel10k
      wezterm
      isd
      nix-du
    ];

    # nixpkgs ships default `ls`/`ll`/`l` aliases via mkDefault; clear the
    # global set with mkForce so root/rescue Bash stays stock.
    environment.shellAliases = lib.mkForce { };
    programs.zsh.shellAliases = {
      ls = "eza --group-directories-first";
      ll = "eza -lh --group-directories-first";
      la = "eza -lah --group-directories-first";
      lt = "eza --tree --level=2";
      cat = "bat --paging=never";
      rg = "rg --smart-case --hidden --glob '!.git'";
    };

    programs.mosh.enable = true;

    programs.zsh = {
      enable = true;
      enableCompletion = true;
      autosuggestions.enable = true;
      syntaxHighlighting.enable = true;

      interactiveShellInit = ''
        source ${pkgs.zsh-powerlevel10k}/share/zsh-powerlevel10k/powerlevel10k.zsh-theme

        if command -v zoxide >/dev/null 2>&1; then
          eval "$(zoxide init zsh)"
        fi

        if [ -f /etc/zsh/p10k.zsh ]; then
          source /etc/zsh/p10k.zsh
        fi
      '';
    };

    environment.etc."zsh/p10k.zsh".text = builtins.readFile ./p10k.zsh;

    # `deps = [ "users" ]` keeps this after home creation; otherwise the first
    # dev login on a fresh boot hits zsh-newuser-install.
    system.activationScripts.dev-zshrc = {
      deps = [ "users" ];
      text = ''
        if [ -d /home/dev ]; then
          if [ ! -e /home/dev/.zshrc ]; then
            install -m 0644 -o dev -g users /dev/null /home/dev/.zshrc
          fi

          if ! grep -Fq '[ -f /etc/zsh/p10k.zsh ] && source /etc/zsh/p10k.zsh' /home/dev/.zshrc; then
            printf '\n[ -f /etc/zsh/p10k.zsh ] && source /etc/zsh/p10k.zsh\n' >> /home/dev/.zshrc
          fi

          chown dev:users /home/dev/.zshrc
          chmod 0644 /home/dev/.zshrc
        fi
      '';
    };

    systemd.tmpfiles.settings."wezterm" = lib.mkIf weztermCfg.enable {
      "/home/${weztermCfg.user}/.local/share/wezterm".d = {
        user = weztermCfg.user;
        group = "users";
        mode = "0755";
      };
    };

    systemd.services.wezterm-mux-server = lib.mkIf weztermCfg.enable {
      description = "WezTerm Mux Server";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        User = weztermCfg.user;
        ExecStart = "${pkgs.wezterm}/bin/wezterm-mux-server";
        RuntimeDirectory = "wezterm-mux";
        Restart = "on-failure";
        RestartSec = 5;
      };
    };
  };
}
