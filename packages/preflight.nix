{ pkgs, src }:

let
  lib = pkgs.lib;
  tools = [
    pkgs.poppler-utils
    pkgs.tesseract
    pkgs.qpdf
    pkgs.exiftool
    pkgs.zbar
  ];
  toolPath = lib.makeBinPath tools;
  sandboxProfile = ./preflight.sb;
in
pkgs.rustPlatform.buildRustPackage {
  pname = "preflight";
  version = "0.1.0";
  inherit src;

  cargoLock.lockFile = "${src}/Cargo.lock";
  doCheck = false;
  # Darwin rejects finite RLIMIT_AS/RSS/DATA values on this host (EINVAL).
  # Keep CPU/file/fd limits and native sandboxing; do not pretend RSS enforces AS.
  postPatch = ''
    substituteInPlace src/bin/preflight-worker.rs \
      --replace-fail '(libc::RLIMIT_AS, 1536 * 1024 * 1024),' \
        '#[cfg(not(target_os = "macos"))] (libc::RLIMIT_AS, 1536 * 1024 * 1024),'
  '';
  nativeBuildInputs = [ pkgs.makeWrapper ];

  postInstall = ''
    install -Dm644 LICENSE $out/share/licenses/preflight/LICENSE
    install -Dm644 vendor/gitleaks/LICENSE $out/share/licenses/preflight/gitleaks-LICENSE
    install -Dm644 vendor/gitleaks/upstream.json $out/share/preflight/upstream.json

    mv $out/bin/preflight-worker $out/bin/preflight-worker-bin
    install -Dm644 ${sandboxProfile} $out/share/preflight/preflight.sb
    cat > $out/bin/preflight-worker <<'WORKER'
    #!/bin/sh
    set -eu
    if [ "$#" -ne 2 ]; then
      exit 64
    fi
    job=$1
    action=$2
    case "$action" in
      check|inspect|sanitize) ;;
      *) exit 64 ;;
    esac
    job=$(cd "$job" && pwd -P)
    cd "$job"
    exec /usr/bin/sandbox-exec -D "JOBDIR=$job" -f '@SANDBOX_PROFILE@' -- '@WORKER_BIN@' "$job" "$action"
    WORKER
    substituteInPlace $out/bin/preflight-worker \
      --replace-fail '@SANDBOX_PROFILE@' "$out/share/preflight/preflight.sb" \
      --replace-fail '@WORKER_BIN@' "$out/bin/preflight-worker-bin"
    chmod +x $out/bin/preflight-worker

    wrapProgram $out/bin/preflight \
      --set PREFLIGHT_WORKER $out/bin/preflight-worker \
      --set PREFLIGHT_WORKER_PATH ${toolPath} \
      --set PREFLIGHT_TOOLCHAIN_ID "$out:${toolPath}"
  '';

  passthru.nativeToolchain = tools;
  meta = {
    description = "Local proxy that scans LLM requests and attachments for secrets";
    homepage = "https://github.com/ghuntley/preflight";
    license = lib.licenses.mit;
    mainProgram = "preflight";
    platforms = [ "aarch64-darwin" ];
  };
}
