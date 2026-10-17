{ config, inputs, pkgs, ... }:
let
  underclass = inputs.underclass.packages.aarch64-darwin.underclass;
  home = config.home.homeDirectory;
  dataDir = "${home}/.local/share/underclass";
  logDir = "${home}/Library/Logs/underclass";
  db = "${dataDir}/pool.db";
  service = pkgs.writeShellScript "underclass-service" ''
    set -euo pipefail
    umask 077
    uid=$(${pkgs.coreutils}/bin/id -u)
    fail() { printf 'Unsafe Underclass path: %s\n' "$1" >&2; exit 1; }
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
        --connect-timeout 2 --max-time 3 http://127.0.0.1:8080/; then
      printf 'Underclass unavailable at http://127.0.0.1:8080; start or repair the user service. No direct-account fallback.\n' >&2
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
      -c 'model_providers.underclass.base_url="http://127.0.0.1:8080/v1"' \
      -c 'model_providers.underclass.env_key="UNDERCLASS_PROXY_KEY"' \
      -c 'model_providers.underclass.wire_api="responses"' \
      -c 'model_providers.underclass.requires_openai_auth=false' \
      -c 'model_providers.underclass.supports_websockets=false' "$@"
  '';
  ompPool = pkgs.writeShellScriptBin "omp-pool" ''
    set -euo pipefail
    [[ -x /opt/homebrew/bin/omp ]] || {
      printf 'Existing Homebrew omp is missing: /opt/homebrew/bin/omp\n' >&2
      exit 1
    }
    ${requireService}
    unset value
    export PI_OPENAI_STATEFUL=0
    exec /opt/homebrew/bin/omp \
      --config '${home}/.config/underclass/omp-pool.yml' \
      --model underclass/gpt-6.1-sol "$@"
  '';
  ompModels = {
    providers.underclass = {
      baseUrl = "http://127.0.0.1:8080/v1";
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
  home.packages = [ underclass uiToken codexPool ompPool ];
  xdg.configFile."underclass/config.toml".text = ''
    bind = "127.0.0.1:8080"
    auto_codex_resets = false
  '';
  launchd.agents.underclass = {
    enable = true;
    domain = "user";
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
  xdg.configFile."underclass/omp-pool.yml".text = builtins.toJSON {
    modelRoles = {
      default = "underclass/gpt-6.1-sol";
      vision = "underclass/gpt-6-luna:auto";
      plan = "underclass/gpt-6.1-sol:auto";
      task = "underclass/gpt-6-luna:auto";
      commit = "underclass/gpt-6-luna:auto";
      judge = "openrouter/inception/mercury-decide:free";
      slow = "underclass/gpt-6.1-sol:auto";
      smol = "underclass/gpt-6-luna:auto";
    };
    retry.modelFallback = false;
  };
}
