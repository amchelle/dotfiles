{ config, inputs, pkgs, ... }:
{
  home.packages = [ pkgs.helix pkgs.fd pkgs.fzf ];
  home.sessionVariables = {
    EDITOR = "hx";
    FZF_ALT_C_COMMAND = "fd --type d";
  };
  home.sessionPath = [ "$HOME/bin" ];

  programs.zsh = {
    enable = true;
    dotDir = config.home.homeDirectory;
    envExtra = ''
      unset NIXPKGS_ALLOW_INSECURE
    '';
    shellAliases = {
      g = "git";
      gs = "git status";
      h = "hx";
    };
    profileExtra = ''
      if [[ -x /opt/homebrew/bin/brew ]]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
      fi
      # Homebrew clients remain available; managed utilities take precedence.
      typeset -U path
      path=("$HOME/.nix-profile/bin" "/etc/profiles/per-user/$USER/bin"
            /run/current-system/sw/bin /nix/var/nix/profiles/default/bin $path)
      export PATH
    '';
    initContent = builtins.readFile ./fzf-cd-widget.zsh;
  };
  programs.atuin = {
    enable = true;
    package = inputs.atuin-nixpkgs.legacyPackages.${pkgs.stdenv.hostPlatform.system}.atuin;
    enableZshIntegration = true;
    flags = [ "--disable-up-arrow" ];
    settings = {
      dialect = "us";
      auto_sync = false;
      update_check = false;
      search_mode = "fuzzy";
    };
  };
  programs.direnv = {
    enable = true;
    silent = true;
    nix-direnv.enable = true;
    enableZshIntegration = true;
  };
  programs.starship = {
    enable = true;
    enableZshIntegration = true;
    settings = { };
    presets = [ ];
  };
  xdg.configFile."starship.toml".source = ../.config/starship.toml;
}
