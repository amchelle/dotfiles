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
sudo -kn /run/current-system/sw/bin/darwin-rebuild switch --flake .#Amchelles-iMac
bash tests/underclass-smoke.sh
bash tests/activation-smoke.sh
```

Direnv uses Home Manager's `programs.direnv.silent` to suppress routine
loading/cache messages and the environment export diff without hiding errors
or `.envrc` stderr. This is configured in `~/.config/direnv/direnv.toml`, so it
also applies to existing shells after activation. To verify a fresh load, run
`(unset DIRENV_DIFF DIRENV_WATCHES DIRENV_DIR; eval "$(direnv export zsh)")`
from this directory in Zsh: the development environment should load without
routine direnv output. Unapproved or failing `.envrc` files still report errors.

Nix store maintenance is declarative through root launchd daemons because
Determinate owns the Nix installation (`nix.enable = false`): garbage collection
runs daily at 03:00 and deletes generations older than 7 days; store
optimization runs daily at 04:15. These jobs take effect after activation.

The first activation requires authentication to install the sudo rule. Once
installed, only `amchellecrosson` running the root-owned
`/run/current-system/sw/bin/darwin-rebuild` is exempt; unrelated sudo commands
still require authentication. `-kn` ignores cached credentials and fails rather
than prompting. The smoke check verifies both sides of that boundary.

This is still root-equivalent trust in this user's Nix configurations:
`darwin-rebuild` can activate arbitrary configuration. It is not a sandbox.
Never grant passwordless access to a user-writable activation script.

Sudo uses macOS's native Touch ID PAM module through `sudo_local`, which
survives OS updates without editing Apple's main PAM policy. For ordinary
sudo commands, an enrolled Touch ID keyboard/sensor and a local interactive
session are required; the password remains a fallback. Rebuilds bypass
authentication entirely via the narrower rule above. Verify biometrics in
a local terminal with `bash tests/touchid-smoke.sh`; use your fingerprint,
not password fallback. No fingerprint data is managed by these dotfiles.

Before `darwin-rebuild` is installed, bootstrap once with authentication:

```sh
sudo /nix/var/nix/profiles/default/bin/nix run .#darwin-rebuild -- switch --flake .#Amchelles-iMac
```

Atuin provides fuzzy Ctrl-R history search without taking over Up Arrow, using
[EricCrosson's shell](https://github.com/EricCrosson/dotfiles/blob/d87b3a5c875d0451e112ade876e333c03ba2c0d5/profiles/eric/modules/zsh.nix)
as the reference. Sync is deliberately disabled: no history account or upload
is configured. Existing zsh history is not imported automatically.
Run `nix develop --command python3 tests/shell-smoke.py` to exercise recording,
exit status, working directory, and Ctrl-R selection/replay in an isolated PTY.
Alt-C uses the reference's synchronous fzf directory widget and `fd --type d`:
selection executes a quoted `builtin cd`, preserving pending input for the
next prompt; cancellation leaves the directory/input unchanged. It is bound
in emacs, vi insert, and vi command maps. The PTY smoke also covers paths with
spaces, pending-input preservation, and cancellation.

The main nixpkgs input tracks current `nixpkgs-unstable`. Atuin alone uses
the October 11 unstable revision `8aa2baf1`, whose Apple Silicon binary is
cached (18.21.0, 18.9 MiB download / 60.6 MiB installed). Current unstable's
18.23.0 requires local compilation. Check cache availability with `nix build
--dry-run` before updating this exception; avoid fetching a Rust build toolchain.

The smoke script exercises real HTTP/auth boundaries, not subscription
inference. Its optional `UNDERCLASS_ORIGIN` defaults to `http://127.0.0.1:43871`.
The upstream Underclass package disables Rust checks; building is not a routing
test.

## OMP through Underclass

- The managed `omp` executable in Home Manager's profile replaces the
  Homebrew command in the configured Zsh `PATH`. It launches the existing
  `/opt/homebrew/bin/omp` with `~/.config/underclass/omp-pool.yml`.
- The launcher checks Underclass and its proxy key before starting; if the
  service is unavailable, `omp` exits instead of falling back to direct
  inference. It rejects `--model`, `--provider`, and `--config` overrides.
- Every OMP model role, including `judge`, resolves through Underclass, and
  model fallback is disabled. This does not prevent a user from bypassing the
  managed command by invoking the Homebrew executable by absolute path or
  otherwise changing OMP's configuration. Network-level egress enforcement
  would be required to guarantee that broader boundary.
- `codex-pool` remains a separate launcher for Codex.

Open `http://127.0.0.1:43871/`. Invoke `underclass-ui-token` only when ready to
paste into that local page, then replace clipboard contents. Authorize each
distinct ChatGPT/Codex identity interactively; do not copy existing clients'
OAuth tokens. Banked reset credits are **manual**; ordinary quota-window
recovery remains automatic.

Port 43871 was unused on this Mac when selected and is below its ephemeral
range (49152–65535), avoiding common development ports and outbound-port
allocation. No fixed port can guarantee freedom from future collisions.
The service bind, launcher checks, Codex URL, and OMP provider URL share one
Nix origin. After a config-only port change, restart the launch agent with
the command below; its executable/plist need not otherwise change.

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
