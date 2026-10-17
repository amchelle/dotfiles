#!/usr/bin/env python3
"""Exercise the activated zsh in a PTY with disposable history/config/data."""
import fcntl
import os
from pathlib import Path
import pty
import select
import shutil
import signal
import sqlite3
import struct
import tempfile
import termios
import time


class Shell:
    prompt = b"__DOTFILES_SMOKE_READY__ "

    def __init__(self, root):
        self.root = root
        self.output = b""
        home = Path.home()
        (root / "atuin-config").mkdir()
        (root / "atuin-config/config.toml").write_bytes(
            (home / ".config/atuin/config.toml").read_bytes()
        )
        (root / ".zshrc").write_text(
            f'source "{home}/.zshrc"\n'
            'precmd_functions=(${precmd_functions:#*starship*})\n'
            "PROMPT='__DOTFILES_SMOKE_READY__ '; RPROMPT=''\n"
            f'HISTFILE="{root}/zsh_history"\n'
        )
        env = dict(os.environ, ZDOTDIR=str(root), TERM="xterm-256color",
                   ATUIN_CONFIG_DIR=str(root / "atuin-config"),
                   ATUIN_DATA_DIR=str(root / "atuin-data"))
        self.pid, self.fd = pty.fork()
        if self.pid == 0:
            os.chdir(root)
            os.execvpe("zsh", ["zsh", "-d", "-i"], env)
        fcntl.ioctl(self.fd, termios.TIOCSWINSZ, struct.pack("HHHH", 40, 120, 0, 0))
        try:
            self.until(self.prompt)
        except BaseException:
            self.close()
            raise

    def send(self, data):
        os.write(self.fd, data)

    def until(self, needle, timeout=15):
        result = b""
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            if select.select([self.fd], [], [], 0.1)[0]:
                chunk = os.read(self.fd, 65536)
                result += chunk
                self.output += chunk
                if needle in result:
                    return result
        raise AssertionError(f"Timed out waiting for {needle!r}: {result!r}")

    def command(self, command):
        self.send(command.encode() + b"\n")
        return self.until(self.prompt)

    def close(self):
        os.kill(self.pid, signal.SIGKILL)
        os.waitpid(self.pid, 0)
        os.close(self.fd)


def check_history(shell):
    command = "printf 'atuin-smoke-recorded\\n'; (exit 23)"
    shell.command(command)
    db = shell.root / "atuin-data/history.db"
    deadline = time.monotonic() + 10
    row = None
    while time.monotonic() < deadline:
        if db.exists():
            with sqlite3.connect(db) as conn:
                row = conn.execute(
                    "SELECT exit, cwd FROM history WHERE command = ?", (command,)
                ).fetchone()
            if row and row[0] != -1:
                break
        time.sleep(0.05)
    assert row == (23, str(shell.root)), f"History lost exit status or cwd: {row!r}"
    # Search via the actual Ctrl-R widget, then replay the selected command.
    shell.send(b"\x12")
    shell.until(b"atuin-smoke-recorded")
    shell.send(b"atuin-smoke-recorded")
    time.sleep(0.2)
    shell.send(b"\r")
    shell.until(shell.prompt)
    shell.send(b"\r")
    replay = shell.until(b"\r\natuin-smoke-recorded\r\n")
    if shell.prompt not in replay:
        shell.until(shell.prompt)
    print("PASS: zsh records command/exit/cwd and Ctrl-R searches/replays Atuin history")


if __name__ == "__main__":
    assert shutil.which("atuin"), "Activate Atuin before running this test"
    with tempfile.TemporaryDirectory(prefix="dotfiles-shell-") as directory:
        shell = Shell(Path(directory).resolve())
        try:
            check_history(shell)
        finally:
            shell.close()
