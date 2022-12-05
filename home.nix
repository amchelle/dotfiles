{ config, pkgs, ... }:

{
  home.username = "amchelle";
  home.homeDirectory = "/home/amchelle";

  home.stateVersion = "22.05";

  programs.home-manager.enable = true;
  programs.direnv.enable = true;
  programs.direnv.nix-direnv.enable = true;
  programs.zsh.enable = true;
  programs.vscode = {
    enable = true;
  };
  
  programs.kitty = {
    enable = true;
    settings = {
      cursor_blink_interval = 0;
      scrollback_lines = 50000;
    };
  };

  home.packages = with pkgs; [
    _1password-gui
    amber
    entr
    fd
    git
    gnupg
    nodePackages.typescript-language-server
    ripgrep
    sops
    starship
    thunderbird
  ];

  home.file.".direnvrc" = {
    text = "source /run/current-system/sw/share/nix-direnv/direnvrc";
  };

  home.file.".zshenv" = {
    text = ''
      export DIRENV_LOG_FORMAT=""
      export EDITOR=hx
    '';
  };

  home.file.".zshrc" = {
    text = ''
      alias g='git'
      alias gs='git status'
      eval "$(direnv hook zsh)"
      eval "$(starship init zsh)"
    '';
  };
  
  home.file.".config/starship.toml" = {
    source = ./.config/starship.toml;
  };

  home.file.".gitconfig" = {
    text = ''
      [user]
        email = amchelle@protonmail.com
        name = Amchelle Crosson
        
      [alias]
        a = add
        b = branch
        c = commit
        cl = clone
        co = checkout
        cn = checkout --detach
        d = diff
        di = diff ':(exclude)./**/package-lock.json' ':(exclude)./**/yarn.lock'
        dc = diff --cached
        dci = diff --cached ':(exclude)./**/package-lock.json' ':(exclude)./**/yarn.lock'
        dn = diff --name-only
        dcn = diff --cached --name-only
        f = fetch
        l = log --graph --pretty=format:'%C(yellow)%h%C(cyan)%d%Creset %s %C(white)- %an, %ar%Creset'
        p = pull
        fsl = push --force-with-lease
        re = restore
        rs = restore --staged
        s = status
        su = submodule update

        exec = "!exec " 

        # After `git reset --soft HEAD^1`, commit with the same commit message
        # Source: https://stackoverflow.com/a/25930432
        recommit = commit --reuse-message=HEAD@{1}

        alias = !git config --list | grep \"alias\\\\.\" | sed \"s/alias\\\\.\\\\([^=]*\\\\)=\\\\(.*\\\\)/\\\\1\\\\\\t => \\\\2/\" | sort

        # git branchless
        bs = branchless sync   
        
      [color]
        ui = true
        interactive = auto

      [push]
        default = simple

      [pull]
        rebase = true

      [rerere]
        enabled = true
    
      [url "git@github.com:"]
        insteadOf = "gh:"
        PushInsteadOf = "gh:"
        # example: git clone gh:amchelle/dotfiles

      [delta]
        line-numbers = true
        # side-by-side=true

      [color "diff-highlight"]
        oldNormal = red bold
        oldHighlight = red bold reverse
        newNormal = green bold
        newHighlight = green bold reverse

      [color "diff"]
        meta = 11
        frag = magenta bold
        commit = yellow bold
        old = red bold
        new = green bold
        whitespace = red reverse

      [diff-so-fancy]
        markEmptyLines = false
        changeHunkIndicators = true

      [git-up "fetch"]
        prune = true
        all = false

      [git-up "push"]
        auto = false
        all = false
        tags = false

      [git-up "rebase"]
        auto = true
        show-hashes = false

      [git-up "updates"]
        check = false

      [gpg]
        program = gpg
    '';
  };
}
