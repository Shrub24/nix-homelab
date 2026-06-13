{ pkgs, ... }:
{
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
  ];

  environment.shellAliases = {
    ls = "eza --group-directories-first";
    ll = "eza -lh --group-directories-first";
    la = "eza -lah --group-directories-first";
    lt = "eza --tree --level=2";
    cat = "bat --paging=never";
    rg = "rg --smart-case --hidden --glob '!.git'";
  };

  users.defaultUserShell = pkgs.zsh;
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

  system.activationScripts.dev-zshrc = ''
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
}
