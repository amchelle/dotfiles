{ config, pkgs, ... }:

{
  home.username = "amchelle";
  home.homeDirectory = "/home/amchelle";

  home.stateVersion = "22.05";

  programs.home-manager.enable = true;
  programs.vscode = {
    enable = true;
  };

  home.packages = with pkgs; [
    entr
    git
  ];

  home.file.".direnvrc" = {
    text = "source /run/current-system/sw/share/nix-direnv/direnvrc";
  };

  home.file.".zshenv" = {
    text = ''
      export DIRENV_LOG_FORMAT=""
    '';
  };

  home.file.".zshrc" = {
    text = ''
      eval "$(direnv hook zsh)"
    '';
  };
}
