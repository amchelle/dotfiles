{ config, inputs, pkgs, ... }:
let
  smartCd = pkgs.fetchFromGitHub {
    owner = "esc-zsh";
    repo = "smart-cd";
    rev = "57051138141179c293dcaef2da659e42ad4f9eeb";
    sha256 = "sha256-TgWwvJqQvIjRXpYuSVZ4ZqJCqLF7a5IIqLPzyYNWaTs=";
  };
in
{
  home.packages = [ pkgs.helix pkgs.fd pkgs.fzf pkgs.eza ];
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
    '';
    initContent = ''
      # Show directory contents and Git status on directory changes.
      source ${smartCd}/smart-cd.zsh
      ${builtins.readFile ./fzf-cd-widget.zsh}
      source ${pkgs.zsh-autosuggestions}/share/zsh-autosuggestions/zsh-autosuggestions.zsh
      ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=8'
    '';
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
