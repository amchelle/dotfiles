{ ... }:
{
  nixpkgs.hostPlatform = "aarch64-darwin";
  nix.enable = false;
  system.primaryUser = "amchellecrosson";
  users.users.amchellecrosson.home = "/Users/amchellecrosson";
  # Activation is privileged; only this installed, root-owned entrypoint is exempt.
  security.sudo.extraConfig = ''
    amchellecrosson ALL=(root) NOPASSWD: /run/current-system/sw/bin/darwin-rebuild
  '';
  security.pam.services.sudo_local.touchIdAuth = true;
  system.stateVersion = 7;
}
