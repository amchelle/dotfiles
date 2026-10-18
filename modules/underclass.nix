{ config, inputs, pkgs, ... }:
let
  underclass = inputs.underclass.packages.aarch64-darwin.underclass;
  preflight = pkgs.callPackage ../packages/preflight.nix { src = inputs.preflight-src; };
  home = config.home.homeDirectory;
  dataDir = "${home}/.local/share/underclass";
  logDir = "${home}/Library/Logs/underclass";
  db = "${dataDir}/pool.db";
  # Unused locally and below this Mac's 49152–65535 ephemeral range.
  bind = "127.0.0.1:43871";
  origin = "http://${bind}";
  preflightBind = "127.0.0.1:46783";
  inspectedOrigin = "http://${preflightBind}";
  preflightData = "${home}/.local/share/preflight";
  preflightCache = "${home}/.cache/preflight";
  preflightLogs = "${home}/Library/Logs/preflight";
  # Both services create private runtime paths before opening data or logs.
  privatePaths = ''
    uid=$(${pkgs.coreutils}/bin/id -u)
    fail() { printf 'Unsafe service path: %s\n' "$1" >&2; exit 1; }
    private_directory() {
      local path=$1
      if [[ -e $path || -L $path ]]; then
        [[ -d $path && ! -L $path ]] || fail "$path"
        [[ $(${pkgs.coreutils}/bin/stat -c %u "$path") == "$uid" ]] || fail "$path"
      else
        ${pkgs.coreutils}/bin/mkdir -p -- "$path"
      fi
      ${pkgs.coreutils}/bin/chmod 700 -- "$path"
    }
    private_file() {
      local path=$1
      if [[ -e $path || -L $path ]]; then
        [[ -f $path && ! -L $path ]] || fail "$path"
        [[ $(${pkgs.coreutils}/bin/stat -c %u "$path") == "$uid" ]] || fail "$path"
        ${pkgs.coreutils}/bin/chmod 600 -- "$path"
      fi
    }
  '';
  service = pkgs.writeShellScript "underclass-service" ''
    set -euo pipefail
    umask 077
    ${privatePaths}
    private_directory '${dataDir}'
    private_directory '${logDir}'
    for file in '${db}' '${db}-wal' '${db}-shm' \
                '${logDir}/stdout.log' '${logDir}/stderr.log'; do
      private_file "$file"
    done
    export HOME='${home}'
    export UNDERCLASS_DATA_DIR='${dataDir}'
    export UNDERCLASS_CONFIG_DIR='${home}/.config/underclass'
    export UNDERCLASS_AUTO_CODEX_RESETS=false
    export RUST_LOG=info
    unset UNDERCLASS_PROXY_KEY UNDERCLASS_UI_TOKEN UNDERCLASS_BIND UNDERCLASS_MONITOR_SOCKET
    exec > '${logDir}/stdout.log' 2> '${logDir}/stderr.log'
    exec ${underclass}/bin/underclass --log-format json serve
  '';
  readKey = ''
    read_key() {
      local key=$1
      [[ -f '${db}' && -r '${db}' ]] || {
        printf 'Underclass database unavailable; start or repair the user service.\n' >&2
        return 1
      }
      value=$(${pkgs.sqlite}/bin/sqlite3 -readonly '${db}' \
        "SELECT value FROM config WHERE key = '$key';" 2>/dev/null) || {
        printf 'Underclass key query failed; start or repair the user service.\n' >&2
        return 1
      }
      [[ -n $value ]] || {
        printf 'Underclass key missing; start or repair the user service.\n' >&2
        return 1
      }
    }
  '';
  preflightService = pkgs.writeShellScript "preflight-service" ''
    set -euo pipefail
    umask 077
    ${privatePaths}
    private_directory '${preflightData}'
    private_directory '${preflightCache}'
    private_directory '${preflightLogs}'
    for file in '${preflightLogs}/stdout.log' '${preflightLogs}/stderr.log'; do
      private_file "$file"
    done
    ${readKey}
    read_key proxy_key
    export HOME='${home}'
    export PREFLIGHT_CLIENT_KEY="$value"
    unset value PREFLIGHT_UPSTREAM_KEY PREFLIGHT_FILE_API_KEY PREFLIGHT_WORKER PREFLIGHT_WORKER_PATH PREFLIGHT_TOOLCHAIN_ID
    export PREFLIGHT_CONTROL='${preflightData}/control.sock'
    export NO_PROXY=127.0.0.1,localhost
    export RUST_LOG=info
    exec > '${preflightLogs}/stdout.log' 2> '${preflightLogs}/stderr.log'
    exec ${preflight}/bin/preflight serve --config '${home}/.config/preflight/config.toml'
  '';
  uiToken = pkgs.writeShellScriptBin "underclass-ui-token" ''
    set -euo pipefail
    ${readKey}
    read_key ui_token
    printf '%s' "$value" | /usr/bin/pbcopy
    unset value
    printf 'Underclass admin token copied to clipboard.\n'
    printf 'Clipboard is sensitive; replace its contents after pasting.\n' >&2
  '';
  requireService = ''
    ${readKey}
    read_key proxy_key
    if ! ${pkgs.curl}/bin/curl --noproxy '*' --fail --silent --output /dev/null \
        --connect-timeout 2 --max-time 3 '${origin}/'; then
      printf 'Underclass unavailable at ${origin}; start or repair the user service. No direct-account fallback.\n' >&2
      exit 1
    fi
    if ! ${pkgs.curl}/bin/curl --noproxy '*' --fail --silent --output /dev/null \
        --connect-timeout 2 --max-time 3 '${inspectedOrigin}/readyz'; then
      printf 'Preflight unavailable at ${inspectedOrigin}; start or repair the user service. No uninspected fallback.\n' >&2
      exit 1
    fi
  '';
  codexPool = pkgs.writeShellScriptBin "codex-pool" ''
    set -euo pipefail
    [[ -x /opt/homebrew/bin/codex ]] || {
      printf 'Existing Homebrew Codex is missing: /opt/homebrew/bin/codex\n' >&2
      exit 1
    }
    ${requireService}
    export UNDERCLASS_PROXY_KEY="$value"
    unset value
    exec /opt/homebrew/bin/codex \
      -c 'model_provider="underclass"' \
      -c 'model_providers.underclass.name="Underclass"' \
      -c 'model_providers.underclass.base_url="${inspectedOrigin}/v1"' \
      -c 'model_providers.underclass.env_key="UNDERCLASS_PROXY_KEY"' \
      -c 'model_providers.underclass.wire_api="responses"' \
      -c 'model_providers.underclass.requires_openai_auth=false' \
      -c 'model_providers.underclass.supports_websockets=false' "$@"
  '';
  ompModels = {
    providers.underclass = {
      baseUrl = "${inspectedOrigin}/v1";
      api = "openai-responses";
      auth = "apiKey";
      authHeader = true;
      apiKey = "!${pkgs.sqlite}/bin/sqlite3 -readonly ${db} \"SELECT value FROM config WHERE key = 'proxy_key';\"";
      compat = {
        statefulResponses = false;
        supportsDeveloperRole = false;
        supportsSamplingParams = false;
      };
      models = map (id: {
        inherit id;
        reasoning = true;
        input = [ "text" "image" ];
        # Conservative local budget, not an advertised subscription maximum.
        contextWindow = 272000;
        maxTokens = 128000;
        omitMaxOutputTokens = true;
      }) [ "gpt-6.1-sol" "gpt-6-luna" "gpt-6-astra" ];
    };
  };
in {
  home.packages = [ underclass preflight uiToken codexPool ];
  xdg.configFile."underclass/config.toml".text = ''
    bind = "${bind}"
    auto_codex_resets = false
  '';
  xdg.configFile."preflight/config.toml".text = ''
    bind = "${preflightBind}"
    upstream = "${origin}"
    mode = "redact"
    # Upstream's sandbox switch selects Linux Bubblewrap. Our packaged worker
    # always uses macOS sandbox-exec instead, including startup checks.
    sandbox = false
    cache_dir = "${preflightCache}"
    control_socket = "${preflightData}/control.sock"
  '';
  home.sessionVariables.PREFLIGHT_CONTROL = "${preflightData}/control.sock";
  launchd.agents.preflight = {
    enable = true;
    domain = "gui";
    config = {
      ProgramArguments = [ "${preflightService}" ];
      RunAtLoad = true;
      KeepAlive = true;
      ProcessType = "Background";
      ThrottleInterval = 10;
      Umask = 63;
    };
  };
  launchd.agents.underclass = {
    enable = true;
    # ~/Library/LaunchAgents is rediscovered at graphical login after reboot.
    # Explicit user-domain registration does not reliably survive reboot.
    domain = "gui";
    config = {
      ProgramArguments = [ "${service}" ];
      RunAtLoad = true;
      KeepAlive = true;
      ProcessType = "Background";
      ThrottleInterval = 10;
      Umask = 63;
    };
  };
  # JSON is valid YAML; no runtime keys enter the Nix store.
  home.file.".omp/agent/models.yml".text = builtins.toJSON ompModels;
}
