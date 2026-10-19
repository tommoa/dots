"""Resolve user agenix secrets at runtime, before shell-command quoting."""

import os
from pathlib import Path
import platform
import re
import subprocess
import sys


def get_agenix_dir():
    if platform.system() == "Darwin":
        try:
            result = subprocess.run(
                ["getconf", "DARWIN_USER_TEMP_DIR"],
                capture_output=True, text=True, check=True,
            )
        except (OSError, subprocess.CalledProcessError) as error:
            raise RuntimeError("Cannot resolve the Darwin agenix runtime directory") from error
        directory = result.stdout.strip()
        if not directory:
            raise RuntimeError("getconf returned an empty Darwin runtime directory")
    else:
        directory = os.environ.get("XDG_RUNTIME_DIR")
        if not directory:
            raise RuntimeError("XDG_RUNTIME_DIR is not set; user agenix secrets are unavailable")
    return Path(directory) / "agenix"


def main():
    if len(sys.argv) != 2 or not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.-]*", sys.argv[1]):
        print("Usage: mail-secret <agenix-secret-name>", file=sys.stderr)
        return 2
    name = sys.argv[1]
    try:
        value = (get_agenix_dir() / name).read_text().strip()
        if not value:
            raise RuntimeError("Secret file is empty")
    except (OSError, RuntimeError, UnicodeError) as error:
        print(f"Mail secret {name!r} is unavailable; activate Home Manager/agenix and retry.", file=sys.stderr)
        if isinstance(error, RuntimeError):
            print(str(error), file=sys.stderr)
        return 1
    print(value)
    return 0


if __name__ == "__main__":
    sys.exit(main())
