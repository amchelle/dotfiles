# Amchelle's macOS host

Fresh nix-darwin + Home Manager configuration for `Amchelles-iMac`,
`aarch64-darwin`, user `amchellecrosson`. Determinate owns the existing Nix
installation (`nix.enable = false`); this flake does not manage Homebrew. State
versions are compatibility baselines, not update targets.

## Apply and verify

Work from this directory, inside its development shell:

```sh
nix develop
nix build --no-link .#underclass .#preflight
nix flake check
nix build --no-link '.#darwinConfigurations.Amchelles-iMac.system'
sudo -kn /run/current-system/sw/bin/darwin-rebuild switch --flake .#Amchelles-iMac
bash tests/underclass-smoke.sh
bash tests/activation-smoke.sh
python3 tests/preflight-smoke.py
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
as the reference. Zsh Autosuggestions shows matching history in dim text as you
type; Right Arrow or Ctrl-E accepts the suggestion. Sync is deliberately
disabled: no history account or upload is configured. Existing zsh history is
not imported automatically. Run `nix develop --command python3 tests/shell-smoke.py`
to exercise recording, exit status, working directory, and Ctrl-R selection/replay
in an isolated PTY.
`,` runs a command from Nixpkgs without installing it permanently. The
Home Manager setup uses [nix-index-database's prebuilt database](https://github.com/nix-community/nix-index-database)
to find a package by executable name. For example, `, cowsay hello` runs
`cowsay` with `hello` as its argument; `, -i cowsay` installs the package
instead. The database revision is tracked by `flake.lock`.

Alt-C uses the reference's synchronous fzf directory widget and `fd --type d`:
selection executes a quoted `builtin cd`, preserving pending input for the
next prompt; cancellation leaves the directory/input unchanged. It is bound
in emacs, vi insert, and vi command maps. The PTY smoke also covers paths with
spaces, pending-input preservation, and cancellation.
The esc-zsh smart-cd hook also runs synchronously on shell startup and after
each directory change: it prints an `eza` listing, then `git status` when inside
a repository. The package provides `eza` for the plugin's default listing
command.
`rh` searches recursively with `rg`, presents matches in `fzf` with a `bat` preview,
and opens the selected file and line in Helix. It is loaded as a Zsh autoloaded
function; ripgrep and bat are included with the shell packages.

## Helix

`modules/helix.nix` vendors EricCrosson's Helix configuration
(`EricCrosson/dotfiles@d87b3a5`, `home/editor/helix`): his keymaps
(Ctrl-h/j/k/l view jumps; `Space` `l/L/o/t/T` for reload, reload-all, reflow,
inlay-hint toggle, and tree-sitter subtree), editor options (`idle-timeout = 0`,
block/bar/underline cursor shapes, hidden files in the picker, inline
diagnostics on the cursor and other lines, inlay hints off), and languages
(Markdown with no language server; Python through `pyright`). The default theme
is `wolf-alabaster-light-bg`.

Helix uses the theme set he ships: `wolf-alabaster-light`,
`wolf-alabaster-light-bg`, `kitty-alabaster-dark`, and `kitty-alabaster-dark-bg`.
The two `wolf-alabaster-*` themes are vendored from Helix master (`ba40e547`) as
raw TOML under `modules/helix/themes/`, because nixpkgs' Helix 25.07.1 does not
bundle them; drop the vendored copies once `pkgs.helix` ships them. His language
servers (bash, Dockerfile, gopls, hadolint, jsonnet, ltex, nil, pyright, ruff,
shellcheck, taplo, TypeScript, and the vscode-langservers set) are installed
alongside.

Upstream also drives Helix theme switching from macOS appearance through a
`helix-theme-sync` service on top of an `appearance-sync` launchd harness. That
harness is disabled in EricCrosson's own profile (`appearance-sync.enable =
false`), so it is not vendored here: Helix keeps the single configured theme.
External reference: [EricCrosson's Helix
module](https://github.com/EricCrosson/dotfiles/blob/d87b3a5c875d0451e112ade876e333c03ba2c0d5/home/editor/helix/default.nix).


The main nixpkgs input tracks current `nixpkgs-unstable`. Atuin alone uses
the October 11 unstable revision `8aa2baf1`, whose Apple Silicon binary is
cached (18.21.0, 18.9 MiB download / 60.6 MiB installed). Current unstable's
18.23.0 requires local compilation. Check cache availability with `nix build
--dry-run` before updating this exception; avoid fetching a Rust build toolchain.

The smoke script exercises real HTTP/auth boundaries, not subscription
inference. Its optional `UNDERCLASS_ORIGIN` defaults to `http://127.0.0.1:43871`.
The upstream Underclass package disables Rust checks; building is not a routing
test.

## OMP through Preflight and Underclass

Managed inference follows `OMP / codex-pool → Preflight (127.0.0.1:46783) →
Underclass (127.0.0.1:43871) → model`. Commands, model roles, subscription
accounts, proxy key, and Underclass's admin UI stay the same. Restart existing
OMP sessions after activation: an already-running client may retain its old URL.

- OMP is **not** wrapped or shadowed. The `underclass` provider definition in
  `~/.omp/agent/models.yml` is the only OMP-specific integration: it points at
  Preflight with the proxy key read from the pool DB at request time. `omp`
  resolves from `PATH` as installed by Homebrew.
- Select Underclass yourself through `/models` in OMP, or assign it to model
  roles under `modelRoles` in `~/.omp/agent/config.yml`. This flake installs no
  model roles, no forced launch model, and no fallback chains, so Underclass is
  used only when you select it or list it in a chain you wrote. Overrides such
  as `--provider`, `--config`, and arbitrary `--model` values are ordinary OMP
  behavior, not rejected.
- `codex-pool` remains a separate launcher for Codex, using the same inspected URL.

Open `http://127.0.0.1:43871/`. Invoke `underclass-ui-token` only when ready to
paste into that local page, then replace clipboard contents. Authorize each
distinct ChatGPT/Codex identity interactively; do not copy existing clients'
OAuth tokens. Banked reset credits are **manual**; ordinary quota-window
recovery remains automatic.

Ports 43871 (Underclass/admin) and 46783 (Preflight/managed clients) were unused
when selected and are below this Mac's ephemeral range (49152–65535), avoiding
common development ports and outbound-port allocation. Neither service uses
8080. No fixed port can guarantee freedom from future collisions. Each origin
is defined once in `modules/underclass.nix`. After a config-only port change,
restart both launch agents; their executable/plist need not otherwise change.

The login-discovered launch agent is `gui/$(id -u)/org.nix-community.home.underclass`:

```sh
launchctl print "gui/$(id -u)/org.nix-community.home.underclass"
launchctl kickstart -k "gui/$(id -u)/org.nix-community.home.underclass"
launchctl print "gui/$(id -u)/org.nix-community.home.preflight"
launchctl kickstart -k "gui/$(id -u)/org.nix-community.home.preflight"
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

### Secret protection and its limits

[Preflight](https://github.com/ghuntley/preflight) is pinned at
`eb13fc015686202d15c7ed57faa3d975482bcc32`, including its vendored detection
rules. The native Darwin package is local because upstream's flake packages
Linux only. Upgrade the source pin/lock to take new upstream rules; there is no
unreviewed background rule updater on this computer.

- `~/.config/preflight/config.toml` selects **redact**, not advisory: recognized
  credentials in request text/tool results become `[REDACTED:rule-id]`.
  Supported attachments are inspected locally and sanitized where safe. Unsafe
  replacements are blocked (409); acquisition/extraction failures fail closed
  (422). Clean request bodies and response streams are preserved.
- Images/PDFs use native Poppler, Tesseract, QPDF, ExifTool, and ZBar. The worker
  always runs inside a deny-by-default macOS `sandbox-exec` profile: no network,
  no private home-file reads, and writes confined to its job directory. TOML's
  `sandbox = false` disables upstream's **Linux Bubblewrap launcher**, not this
  packaged native sandbox. Failure of native tools prevents readiness.
  Darwin rejects upstream's finite address-space limit, so the native package
  omits that Linux-only limit; CPU, file-size, descriptor, and inspection limits
  remain. This is not a hard memory cap or a Linux PID namespace.
- Preflight requires the existing Underclass proxy key and passes it through;
  credentials are read from the pool DB at startup, never embedded in Nix.
  After rotating that key, restart Preflight. No new login or client key setup.
- Cache/artifacts live in `~/.cache/preflight`, control socket in
  `~/.local/share/preflight/control.sock`, logs in `~/Library/Logs/preflight`.
  Directories are 0700 and the service uses umask 077. Logs are truncated on
  restart and record findings/IDs, not prompts or matched secrets. Treat cached
  artifacts as sensitive. `preflight cache status` and `preflight cache purge`
  use `PREFLIGHT_CONTROL` set by Home Manager (new shell after activation).
- Detection is not a guarantee that arbitrary passwords, novel formats, or all
  OCR-visible secrets are recognized. Unsupported attachments can stop a request
  instead of silently passing it. This protects the managed inference path, not
  browser/tool traffic, other applications, explicit direct Underclass calls,
  or clients that bypass these launchers. Underclass's admin URL stays direct.

`python3 tests/preflight-smoke.py` runs the actual packaged proxy against a
recording loopback upstream, with synthetic credentials and no provider calls.
Use the Nix development shell and installed `preflight`, or set `PREFLIGHT_BIN`
to a built package's `bin/preflight`. It covers native sandbox boundaries,
authentication, clean Responses/Chat bytes and SSE, nested text redaction,
PNG/PDF inspection and metadata sanitization, attachment rejection, model
discovery, and failure when upstream is down.

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
