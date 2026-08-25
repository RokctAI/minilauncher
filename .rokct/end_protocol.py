# Copyright (c) 2026 RokctAI
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

# compliance-ignore-file: structural-special-dirs
import os
import hashlib
import shutil
import urllib.request

PROTOCOL_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PROJECT_ROOT = os.getcwd()
ROKCT_DIR = os.path.join(PROJECT_ROOT, ".rokct")
# Pinned by tools/gen_protocol_lock.py - do not edit these constants by hand.
# Manifest fetches are data-only, but pinning keeps them immutable too.
PROTOCOL_REF = "dd09984c0def9009c379db5993d00e4a37e34e1b"
GITHUB_RAW_BASE = (
    f"https://raw.githubusercontent.com/RokctAI/The-Rokct-Protocol/{PROTOCOL_REF}"
)


def dir_hash(d):
    if not os.path.isdir(d):
        return None
    h = hashlib.sha256()
    for root, dirs, files in os.walk(d):
        dirs.sort()
        for f in sorted(files):
            p = os.path.join(root, f)
            h.update(os.path.relpath(p, d).encode())
            with open(p, "rb") as fh:
                h.update(fh.read())
    return h.hexdigest()[:16]


def file_hash(path):
    if not os.path.exists(path):
        return None
    with open(path, "rb") as f:
        return hashlib.sha256(f.read()).hexdigest()


_PINNED_HASH_CACHE = {}


def pinned_file_hash(rel):
    """Full SHA-256 of the protocol's pinned copy of rel: the local checkout
    when available, else the raw file at PROTOCOL_REF (data-only fetch).
    Returns None when the pinned copy cannot be read - callers then keep the
    working file, the safe default. Replaces the old advisory
    core/templates/manifest.json lookups; protocol.lock.json is the single
    enforcing integrity mechanism for pinned content."""
    if rel in _PINNED_HASH_CACHE:
        return _PINNED_HASH_CACHE[rel]
    digest = None
    p = os.path.join(PROTOCOL_DIR, rel)
    if os.path.exists(p):
        digest = file_hash(p)
    else:
        url = f"{GITHUB_RAW_BASE}/{rel}"
        try:
            req = urllib.request.Request(
                url, headers={"User-Agent": "Mozilla/5.0", "X-Trace-Id": "agent-http"}
            )
            with urllib.request.urlopen(req, timeout=10) as r:
                digest = hashlib.sha256(r.read()).hexdigest()
        except Exception:
            digest = None
    _PINNED_HASH_CACHE[rel] = digest
    return digest


def touch(path):
    with open(path, "w", encoding="utf-8") as f:
        f.write("")


def main():
    if not os.path.isdir(ROKCT_DIR):
        print("[end] .rokct/ not found, nothing to do")
        return

    pristine_skills = "86400b7a6e267879"

    skills_dir = os.path.join(ROKCT_DIR, "skills")
    if os.path.isdir(skills_dir):
        shutil.rmtree(skills_dir)
        print("[end] Deleted skills/ (unconditional cleanup)")

    # compose.py's wrapper fetches this into .rokct/ at runtime and deletes it
    # in its finally block; clean up any copy a crashed run left behind.
    installer_base = os.path.join(ROKCT_DIR, "sdk_installer_base.py")
    if os.path.isfile(installer_base):
        os.remove(installer_base)
        print("[end] Deleted sdk_installer_base.py (transient compose runtime fetch)")

    workflows_dir = os.path.join(ROKCT_DIR, "workflows")
    if os.path.isdir(workflows_dir):
        for f in os.listdir(workflows_dir):
            fpath = os.path.join(workflows_dir, f)
            if os.path.isfile(fpath) and f != "init_protocol.md":
                os.remove(fpath)
                print(f"[end] Deleted workflow: {f}")
        print("[end] Cleaned workflows/ (kept init_protocol.md)")

    for item in os.listdir(ROKCT_DIR):
        item_path = os.path.join(ROKCT_DIR, item)
        # install_state.json now lives at .rokct/cache/install_state.json
        # (cache/ is keep-whitelisted below); a legacy copy at .rokct/'s own
        # root is kept explicitly until the composer migrates it there.
        if item in ("active_session.txt", "initiate.py", "install_state.json"):
            print(f"[end] Kept {item} (protocol tool)")
            continue
        if item == ".sync_ready":
            continue
        if os.path.isdir(item_path):
            if item in (
                "workflows",
                "agent",
                "evidence",
                "images",
                "templates",
                "types",
                "config",
                "cache",
            ):
                continue
            shutil.rmtree(item_path)
            print(f"[end] Deleted directory: {item}")
            continue
        core_key = f"core/templates/{item}"
        profile_rel = f"profiles/web/{item}"
        if item == "profiles.md":
            profile_rel = "profiles/web/rules.md"
        item_digest = file_hash(item_path)
        if item_digest is not None and item_digest in (
            pinned_file_hash(core_key),
            pinned_file_hash(profile_rel),
        ):
            os.remove(item_path)
            print(f"[end] Deleted pristine {item}")
        else:
            print(f"[end] Kept modified {item}")

    touch(os.path.join(ROKCT_DIR, ".sync_ready"))
    print(
        "[end] Created .sync_ready marker — CI will pick this up when active session ends"
    )
    print("[end] End protocol cleanup complete.")


if __name__ == "__main__":
    main()
