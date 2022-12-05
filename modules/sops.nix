{ config, ...}:

{
  sops.defaultSopsFile = ../secrets/main.yaml;
  sops.secrets.github_runner_token_stratos = {
    mode = "0400";
    owner = config.users.users.amchelle.name;
    group = "users";
  };
}
