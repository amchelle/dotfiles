{ ... }:
{
  nixpkgs.hostPlatform = "aarch64-darwin";
  nix.enable = false;
  launchd.daemons.nix-gc.serviceConfig = {
    Label = "org.nix-community.nix-gc";
    ProgramArguments = [
      "/nix/var/nix/profiles/default/bin/nix-collect-garbage"
      "--delete-older-than"
      "7d"
    ];
    StartCalendarInterval = [{ Hour = 3; Minute = 0; }];
  };
  launchd.daemons.nix-store-optimise.serviceConfig = {
    Label = "org.nix-community.nix-store-optimise";
    ProgramArguments = [
      "/nix/var/nix/profiles/default/bin/nix-store"
      "--optimise"
    ];
    StartCalendarInterval = [{ Hour = 4; Minute = 15; }];
  };
  users.users.amchellecrosson.home = "/Users/amchellecrosson";
  # Activation is privileged; only this installed, root-owned entrypoint is exempt.
  security.sudo.extraConfig = ''
    amchellecrosson ALL=(root) NOPASSWD: /run/current-system/sw/bin/darwin-rebuild
  '';
  security.pam.services.sudo_local.touchIdAuth = true;
  system.stateVersion = 7;
}
