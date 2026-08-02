#!/usr/bin/env python3
"""
The-Rokct-Protocol: compose.py wrapper for Flutter
Fetches sdk_composer.py and sdk_installer_base.py from GitHub, executes composer locally.
"""
import os, sys, subprocess, tempfile, urllib.request

GITHUB_RAW_BASE = "https://raw.githubusercontent.com/RokctAI/The-Rokct-Protocol/main"
COMPOSER_PATH   = "core/utils/flutter/sdk_composer.py"
INSTALLER_BASE_PATH = "core/utils/flutter/sdk_installer_base.py"


def fetch_script(path):
    url = f"{GITHUB_RAW_BASE}/{path}"
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0", "X-Trace-Id": "flutter-bootstrap"})
        with urllib.request.urlopen(req, timeout=10) as resp:
            if resp.status == 200:
                return resp.read().decode("utf-8")
    except Exception:
        pass
    return None


def main():
    composer_code = fetch_script(COMPOSER_PATH)
    installer_base_code = fetch_script(INSTALLER_BASE_PATH)
    
    if not composer_code or not installer_base_code:
        print("Error: Flutter composer scripts not found on GitHub.", file=sys.stderr)
        sys.exit(1)

    # Write both to the current working directory temporarily so imports match.
    # sdk_installer_base.py must land in .rokct/ specifically: each cached SDK's
    # install.py does sys.path.append(os.path.join(os.getcwd(), '.rokct')) before
    # importing it, so writing it to the cwd root (as this used to do) causes
    # "ModuleNotFoundError: No module named 'sdk_installer_base'" for every SDK.
    tmp_composer = os.path.join(os.getcwd(), "_tmp_sdk_composer.py")
    rokct_dir = os.path.join(os.getcwd(), ".rokct")
    os.makedirs(rokct_dir, exist_ok=True)
    tmp_installer_base = os.path.join(rokct_dir, "sdk_installer_base.py")

    with open(tmp_composer, "w", encoding="utf-8") as f:
        f.write(composer_code)
        
    # Always overwrite with the freshly-fetched copy: a stale local file left
    # over from a prior run must never shadow fixes pushed to GitHub.
    with open(tmp_installer_base, "w", encoding="utf-8") as f:
        f.write(installer_base_code)

    try:
        result = subprocess.run([sys.executable, tmp_composer] + sys.argv[1:], check=False)
        sys.exit(result.returncode)
    finally:
        if os.path.exists(tmp_composer):
            os.unlink(tmp_composer)
        if os.path.exists(tmp_installer_base):
            os.unlink(tmp_installer_base)


if __name__ == "__main__":
    main()
