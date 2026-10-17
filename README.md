# Amchelle's macOS host

Fresh nix-darwin + Home Manager configuration for `Amchelles-iMac`,
`aarch64-darwin`, user `amchellecrosson`. Determinate owns the existing Nix
installation (`nix.enable = false`); this flake does not manage Homebrew. State
versions are compatibility baselines, not update targets.

## Apply and verify

Work from this directory, inside its development shell:

```sh
nix develop
nix build --no-link .#underclass
nix flake check
nix build --no-link '.#darwinConfigurations.Amchelles-iMac.system'
sudo darwin-rebuild switch --flake .#Amchelles-iMac
bash tests/underclass-smoke.sh
```

For the first activation, before `darwin-rebuild` is on PATH:

```sh
sudo /nix/var/nix/profiles/default/bin/nix run .#darwin-rebuild -- switch --flake .#Amchelles-iMac
```

The smoke script exercises real HTTP/auth boundaries, not subscription
inference. Its optional `UNDERCLASS_ORIGIN` defaults to `http://127.0.0.1:8080`.
The upstream Underclass package disables Rust checks; building is not a routing
test.

## Explicit subscription pool

- `codex-pool` runs the existing `/opt/homebrew/bin/codex` with transient
  provider overrides; model, sandbox settings, authentication and ordinary
  defaults remain in the existing Codex configuration.
- `omp-pool` runs the existing `/opt/homebrew/bin/omp` with a role overlay and
  the standard Responses transport. It disables stateful chaining and model
  fallback. Ordinary `omp` keeps its defaults. The judge remains on its existing
  provider.
- Both launchers fail closed if the local service/key is unavailable. Neither
  silently falls back to direct-account inference.
- The three explicit models have a conservative **local** 272000-token context
  budget, not a claim of advertised subscription capacity. Inherited API-price
  estimates are not subscription billing. No extended context or output cap is
  sent.

Open `http://127.0.0.1:8080/`. Invoke `underclass-ui-token` only when ready to
paste into that local page, then replace clipboard contents. Authorize each
distinct ChatGPT/Codex identity interactively; do not copy existing clients'
OAuth tokens. Banked reset credits are **manual**; ordinary quota-window
recovery remains automatic.

The login-discovered launch agent is `gui/$(id -u)/org.nix-community.home.underclass`:

```sh
launchctl print "gui/$(id -u)/org.nix-community.home.underclass"
launchctl kickstart -k "gui/$(id -u)/org.nix-community.home.underclass"
utop
```

Data lives in `~/.local/share/underclass/pool.db`; keys are minted there and
read at runtime. Data/log parents are 0700, DB/log files 0600, process
umask 077. The upstream 0666 monitor socket is protected by its 0700 parent.
Logs in `~/Library/Logs/underclass/` are truncated at service start; request
bodies are not logged. This is a user-session service, not availability while
logged out or asleep.

After reboot, macOS discovers the persisted plist in `~/Library/LaunchAgents`
at graphical login. `RunAtLoad` starts it, `KeepAlive` supervises it, and the
launcher waits for `/nix/store`. This intentionally uses the GUI domain rather
than explicit user-domain registration, whose reboot persistence is affected by
https://github.com/nix-community/home-manager/issues/9656.
Reboot/login autostart is the intended lifecycle, not a demonstrated acceptance
result; availability before login is not provided.

## Preservation and rollback

The pre-Phoenix revision has a local `pre-phoenix-<UTC timestamp>` tag. Legacy
tracked files (including encrypted secrets and keys, without decryption) and
live shell/Git files are checksum-verified under the private directory
`~/.local/state/dotfiles-backups/20261017T131111Z/`. Home Manager also preserves
collisions with `.pre-phoenix-20261017T131111Z`; no force-overwrite is
configured. The live Git ignore file is intentionally unmanaged.

For a later managed generation, `sudo darwin-rebuild switch --rollback` restores
the prior host generation. First activation has no prior Darwin generation: stop
and boot out the user agent, use the installed Darwin uninstaller if reverting
the foundation, then restore only backed-up shell/Git files after removing their
managed symlinks. Keep the pool data intact. Before upgrading Underclass, take a
consistent SQLite `.backup`; never casually restore an old OAuth refresh-token
snapshot. Git/Nix rollback does not reverse token rotations or database
migrations.

No runtime credentials, DB, logs, backups, or execution evidence belong in Git.
