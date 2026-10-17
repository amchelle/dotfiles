{ ... }:
{
  programs.git = {
    enable = true;
    settings = {
      user = {
        name = "Amchelle Crosson";
        email = "amchelle@protonmail.com";
      };
      alias = {
        a = "add";
        b = "branch";
        c = "commit";
        cl = "clone";
        co = "checkout";
        cn = "checkout --detach";
        d = "diff";
        di = "diff ':(exclude)./**/package-lock.json' ':(exclude)./**/yarn.lock'";
        dc = "diff --cached";
        dci = "diff --cached ':(exclude)./**/package-lock.json' ':(exclude)./**/yarn.lock'";
        dn = "diff --name-only";
        dcn = "diff --cached --name-only";
        ds = "diff --cached";
        f = "fetch";
        fwl = "push --force-with-lease";
        l = "log --graph --pretty=format:'%C(yellow)%h%C(cyan)%d%Creset %s %C(white)- %an, %ar%Creset'";
        p = "pull";
        fsl = "push --force-with-lease";
        re = "restore";
        rs = "restore --staged";
        s = "status";
        su = "submodule update";
        exec = "!exec ";
        recommit = "commit --reuse-message=HEAD@{1}";
        alias = ''!git config --list | grep "alias\\." | sed "s/alias\\.\\([^=]*\\)=\\(.*\\)/\\1\\\t => \\2/" | sort'';
      };
      core.excludesFile = "/Users/amchellecrosson/.config/git/ignore";
      color = {
        ui = true;
        interactive = "auto";
        diff-highlight = {
          oldNormal = "red bold";
          oldHighlight = "red bold reverse";
          newNormal = "green bold";
          newHighlight = "green bold reverse";
        };
        diff = {
          meta = "11";
          frag = "magenta bold";
          commit = "yellow bold";
          old = "red bold";
          new = "green bold";
          whitespace = "red reverse";
        };
      };
      push.default = "simple";
      pull.rebase = true;
      rerere.enabled = true;
      url."git@github.com:" = {
        insteadOf = "gh:";
        pushInsteadOf = "gh:";
      };
    };
  };
  programs.delta = {
    enable = true;
    enableGitIntegration = true;
    options.line-numbers = true;
  };
}
