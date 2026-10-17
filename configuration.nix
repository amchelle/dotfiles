{ ... }:
{
  nixpkgs.hostPlatform = "aarch64-darwin";
  nix.enable = false;
  system.primaryUser = "amchellecrosson";
  users.users.amchellecrosson.home = "/Users/amchellecrosson";
  system.stateVersion = 7;
}
