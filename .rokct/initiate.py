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
import shutil
import hashlib
import json
import subprocess
import sys
import time
import urllib.request
import urllib.error
import http.client
import io
import zipfile

# Pinned by tools/gen_protocol_lock.py - do not edit these constants by hand.
# Every fetch below is pinned to this commit, so what this script downloads is
# immutable; the executable targets are additionally SHA-256 verified against
# EXPECTED_SHA256 before they are written anywhere.
PROTOCOL_REF = "0ad5de7353bf3997cde17cb0cec70736b8bd4a49"
EXPECTED_SHA256 = {
    "profiles/web/initiate.py": "df582d290428e8ab03b4ea51b9c284de2f0947c64f57eba8c85f18ddfcdf933f",
    "workflows/maintenance.yml": "df37cf18061299ce6d413f3f9f5017882a7bd044e56e15bad24a13b03cff473d",
}
GITHUB_ZIP_BASE = (
    f"https://github.com/RokctAI/The-Rokct-Protocol/archive/{PROTOCOL_REF}.zip"
)
PROTOCOL_DIR = (
    os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    if "profiles" in os.path.abspath(__file__)
    else os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
)
PROJECT_ROOT = os.getcwd()
ROKCT_DIR = os.path.join(PROJECT_ROOT, ".rokct")
REMOTE_PREFIX = f"The-Rokct-Protocol-{PROTOCOL_REF}"

GITHUB_RAW_BASE = (
    f"https://raw.githubusercontent.com/RokctAI/The-Rokct-Protocol/{PROTOCOL_REF}"
)


def check_for_update():
    """Data-only update check. The old self-update fetched initiate.py from
    the mutable main branch and execv'd it - executing unpinned future code,
    which the PROTOCOL_REF pinning exists to prevent. Now we only fetch the
    lockfile from main AS DATA, compare its pinned ref to ours, and tell the
    user to re-run the installer. Nothing fetched here is ever executed."""
    if os.environ.get("CI"):
        # CI must run the committed copy deterministically.
        return
    url = "https://raw.githubusercontent.com/RokctAI/The-Rokct-Protocol/main/protocol.lock.json"
    try:
        req = urllib.request.Request(
            url,
            headers={"User-Agent": "Mozilla/5.0", "X-Trace-Id": "initiate-bootstrap"},
        )
        with urllib.request.urlopen(req, timeout=10) as r:
            latest_ref = json.loads(r.read().decode()).get("ref", "")
        if latest_ref and latest_ref != PROTOCOL_REF:
            print(
                "[init] A newer protocol version is available - re-run the installer to update."
            )
    except Exception as e:
        print(f"[init] Update check failed: {e}", file=sys.stderr)


def verify_pinned(rel_posix, data):
    """SHA-256 check for the executable fetch targets, before any write."""
    expected = EXPECTED_SHA256.get(rel_posix)
    if expected is None:
        return
    digest = hashlib.sha256(data).hexdigest()
    if digest != expected:
        print(
            f"[init] Integrity check failed for {rel_posix} (ref {PROTOCOL_REF}):",
            file=sys.stderr,
        )
        print(f"[init]   expected sha256 {expected}", file=sys.stderr)
        print(f"[init]   actual   sha256 {digest}", file=sys.stderr)
        print("[init] Refusing to install unverified code.", file=sys.stderr)
        sys.exit(1)


# Bounded retry for transient network failures (connection resets, timeouts,
# 429/5xx): 4 attempts with 2s/4s/8s backoff. Definitive HTTP errors such as
# 404 or 401/403 still fail fast - retrying cannot fix those.
FETCH_ATTEMPTS = 4
TRANSIENT_HTTP_CODES = (429, 500, 502, 503, 504)


def fetch_url(url):
    """GET url, retrying transient errors; raises the last error when out of
    attempts (with e.fetch_attempts set so callers can report the count)."""
    for attempt in range(1, FETCH_ATTEMPTS + 1):
        try:
            req = urllib.request.Request(
                url,
                headers={
                    "User-Agent": "Mozilla/5.0",
                    "X-Trace-Id": "initiate-bootstrap",
                },
            )
            with urllib.request.urlopen(req, timeout=10) as r:
                return r.read()
        except urllib.error.HTTPError as e:
            if e.code not in TRANSIENT_HTTP_CODES or attempt == FETCH_ATTEMPTS:
                e.fetch_attempts = attempt
                raise
            err = e
        except (
            urllib.error.URLError,
            http.client.HTTPException,
            ConnectionError,
            TimeoutError,
        ) as e:
            if attempt == FETCH_ATTEMPTS:
                e.fetch_attempts = attempt
                raise
            err = e
        delay = 2**attempt
        print(
            f"[init] Transient error fetching {url} (attempt {attempt}/{FETCH_ATTEMPTS}): {err} - retrying in {delay}s",
            file=sys.stderr,
        )
        time.sleep(delay)


def fetch_file_from_github(rel_path, dest_path):
    rel_posix = rel_path.replace(os.sep, "/")
    url = f"{GITHUB_RAW_BASE}/{rel_posix}"
    os.makedirs(os.path.dirname(dest_path), exist_ok=True)
    try:
        data = fetch_url(url)
    except Exception as e:
        print(
            f"[init] Failed to fetch {rel_path} after {getattr(e, 'fetch_attempts', 1)} attempt(s): {e}",
            file=sys.stderr,
        )
        sys.exit(1)
    verify_pinned(rel_posix, data)
    with open(dest_path, "wb") as f:
        f.write(data)
    print(f"[init] Fetched {rel_path}")


def file_hash(path):
    if not os.path.exists(path):
        return None
    with open(path, "rb") as f:
        return hashlib.sha256(f.read()).hexdigest()


def ensure_file(rel_path, dest_path):
    src = os.path.join(PROTOCOL_DIR, rel_path)
    if os.path.exists(dest_path):
        if os.path.exists(src) and file_hash(src) == file_hash(dest_path):
            return
    if os.path.exists(src):
        shutil.copy2(src, dest_path)
        print(f"[init] Updated {rel_path}")
    else:
        fetch_file_from_github(rel_path, dest_path)


def copy_versioned(src_rel, dst_abs):
    dst_dir = os.path.dirname(dst_abs)
    os.makedirs(dst_dir, exist_ok=True)

    src = os.path.join(PROTOCOL_DIR, src_rel)
    # When running from a committed .rokct/ inside the project itself,
    # PROTOCOL_DIR resolves to PROJECT_ROOT, so src and dst can be the
    # same file (e.g. .cursorrules). Copying a file onto itself raises
    # shutil.SameFileError - just skip.
    if os.path.exists(src) and os.path.abspath(src) == os.path.abspath(dst_abs):
        print(f"[init] Skipping self-copy of {src_rel}")
        return
    if os.path.exists(src):
        # Dedup directly against the protocol source; integrity of fetched
        # content is enforced by protocol.lock.json / EXPECTED_SHA256, not by
        # the old advisory core/templates manifest.
        if file_hash(src) == file_hash(dst_abs):
            print(f"[init] Skipping unchanged {dst_abs}")
            return
        shutil.copy2(src, dst_abs)
    else:
        fetch_file_from_github(src_rel, dst_abs)
    print(f"[init] Copied {src_rel} -> {dst_abs}")


def copy_dir(src, dst, include_rok=False):
    """Sync a protocol directory into the consumer checkout.

    include_rok only affects the remote fallback below: when the protocol is
    checked out locally, `.rok` is already present at PROTOCOL_DIR and the
    local branch has always skipped it (copying it into .rokct/skills/ would
    just duplicate the tree inside the protocol repo itself)."""
    if not os.path.isdir(src):
        # Remote mode - derive path from src
        rel_src = src.replace(PROTOCOL_DIR + os.sep, "") if PROTOCOL_DIR in src else src
        fetch_dir_from_github(rel_src, dst, include_rok=include_rok)
        return
    os.makedirs(dst, exist_ok=True)
    for item in os.listdir(src):
        # Skip sync files, maintenance, and the init guide - handled separately
        if item in (
            "sync_workspace.py",
            "sync_workspace.yml",
            "maintenance.yml",
            "init_protocol.md",
            ".rok",
        ):
            continue
        s = os.path.join(src, item)
        d = os.path.join(dst, item)
        if os.path.isdir(s):
            copy_dir(s, d, include_rok=include_rok)
        else:
            copy_versioned(os.path.relpath(s, PROTOCOL_DIR), d)
    print(f"[init] Synced directory {src} -> {dst}")


def safe_extract_path(dst, rel):
    """Resolve an archive-controlled relative path under dst, refusing any
    entry that escapes the destination (zip-slip). Same realpath+commonpath
    containment check as the opportunities wrappers' _safe_path()."""
    dest = os.path.realpath(os.path.join(dst, rel))
    base = os.path.realpath(dst)
    if os.path.commonpath([base, dest]) != base:
        print(
            f"[init] Refusing to extract archive entry outside destination: {rel}",
            file=sys.stderr,
        )
        sys.exit(1)
    return dest


# Files only ever skipped when the whole workflows/ directory is fetched -
# they are installed separately (or deliberately not installed at all).
WORKFLOW_ONLY_SKIPS = ("sync_workspace.py", "sync_workspace.yml", "maintenance.yml")


def skip_fetched_entry(rel_src, rel, include_rok):
    """Whether a zip entry at `rel` (relative to the fetched `rel_src`) must
    not be extracted.

    `.rok/` is RokctAI-only tooling. Excluding it here - during extraction,
    rather than deleting it after the fact - means it is never created on a
    non-org machine's disk at all, not even transiently inside a staging
    directory, and nothing is left behind if the run dies mid-loop. Callers
    that legitimately provision org tooling opt in with include_rok=True; the
    default is the safe one, so a new caller cannot leak it by omission.

    Fetching workflows/.rok is unaffected either way: that call names the
    directory itself as rel_src, so its contents are top-level entries rather
    than ".rok/..." paths."""
    if not include_rok and ".rok" in rel.split("/"):
        return True
    return rel_src == "workflows" and rel in WORKFLOW_ONLY_SKIPS


def fetch_dir_from_github(rel_src, dst, include_rok=False):
    # Zip entries always use forward slashes; on Windows callers pass
    # os.sep-separated paths (e.g. copy_dir strips PROTOCOL_DIR + os.sep,
    # leaving "core\\skills"), which would match no entries and silently
    # fetch 0 files.
    rel_src = rel_src.replace(os.sep, "/")
    prefix = f"{REMOTE_PREFIX}/{rel_src}/"
    try:
        print(f"[init] Fetching directory from GitHub: {rel_src}")
        z = zipfile.ZipFile(io.BytesIO(fetch_url(GITHUB_ZIP_BASE)))
        os.makedirs(dst, exist_ok=True)
        count = 0
        for name in z.namelist():
            if name.startswith(prefix) and not name.endswith("/"):
                rel = name[len(prefix) :]
                if skip_fetched_entry(rel_src, rel, include_rok):
                    continue
                data = z.read(name)
                verify_pinned(f"{rel_src}/{rel}", data)
                dest = safe_extract_path(dst, rel)
                os.makedirs(os.path.dirname(dest), exist_ok=True)
                with open(dest, "wb") as f:
                    f.write(data)
                count += 1
        print(f"[init] Fetched {count} files from {rel_src}")
    except Exception as e:
        print(
            f"[init] Failed to fetch directory {rel_src} after {getattr(e, 'fetch_attempts', 1)} attempt(s): {e}",
            file=sys.stderr,
        )
        sys.exit(1)


def load_rok_distribution(src_dir):
    """workflows/.rok/distribution.json maps each canonical workflow to an
    optional {"trimmed_variant": file, "full_trigger_repos": [repo names]}.
    A missing manifest means every file distributes verbatim."""
    manifest_path = os.path.join(src_dir, "distribution.json")
    if not os.path.exists(manifest_path):
        return {}
    with open(manifest_path, "r", encoding="utf-8") as f:
        return json.load(f)


def select_rok_workflows(src_dir, repo_name):
    """Pick which workflows/.rok file each repo gets, as (source file,
    install-as name) pairs. A workflow with a trimmed_variant installs the
    canonical file only for the repos in full_trigger_repos; every other repo
    (unknown included) gets the trimmed variant under the canonical name, so
    repos the shared suite hard-gates away from never carry schedule/push
    triggers that can only no-op. Unlisted files distribute verbatim."""
    manifest = load_rok_distribution(src_dir)
    variants = {
        cfg["trimmed_variant"]
        for cfg in manifest.values()
        if cfg.get("trimmed_variant")
    }
    repo = (repo_name or "").lower()
    pairs = []
    for item in sorted(os.listdir(src_dir)):
        if item == "distribution.json" or item in variants:
            continue
        if not os.path.isfile(os.path.join(src_dir, item)):
            continue
        cfg = manifest.get(item, {})
        trimmed = cfg.get("trimmed_variant")
        full_repos = [r.lower() for r in cfg.get("full_trigger_repos", [])]
        if trimmed and repo not in full_repos:
            pairs.append((trimmed, item))
        else:
            pairs.append((item, item))
    return pairs


def ensure_rokct_gitignore():
    """Write .rokct/.gitignore before anything is staged under .rokct/.

    `skills/` and `tmp/` are provisioned, session-ephemeral trees that must
    never be committed. This used to run at the end of main(), which left a
    window on a first-ever run where those directories existed on disk while
    still untracked-and-not-ignored - long enough for a `git add -A` to stage
    them."""
    gitignore_path = os.path.join(ROKCT_DIR, ".gitignore")
    required_ignores = ("skills/", "tmp/")
    if not os.path.exists(gitignore_path):
        with open(gitignore_path, "w", encoding="utf-8") as f:
            f.write("\n".join(required_ignores) + "\n")
        print(f"[init] Created {gitignore_path}")
        return
    txt = open(gitignore_path, "r", encoding="utf-8").read()
    missing = [entry for entry in required_ignores if entry not in txt]
    if missing:
        with open(gitignore_path, "a", encoding="utf-8") as f:
            f.write("\n".join(missing) + "\n")
        print(f"[init] Updated {gitignore_path} (added: {', '.join(missing)})")


def detect_repo_owner():
    try:
        url = subprocess.check_output(
            ["git", "config", "--get", "remote.origin.url"],
            text=True,
            stderr=subprocess.DEVNULL,
        ).strip()
        if "RokctAI/" in url:
            return url.split("RokctAI/")[-1].replace(".git", "")
    except Exception:
        pass
    return None


def main():
    check_for_update()
    os.makedirs(ROKCT_DIR, exist_ok=True)
    # First thing after .rokct/ exists: nothing below may stage into an
    # unignored directory.
    ensure_rokct_gitignore()

    core_templates_src = os.path.join(PROTOCOL_DIR, "core", "templates")
    for fname in [
        "memory.md",
        "decision_log.md",
        "project_map.md",
        "active_session.txt",
    ]:
        dest_fname = os.path.join(ROKCT_DIR, fname)
        if not os.path.exists(dest_fname):
            copy_versioned(os.path.join("core", "templates", fname), dest_fname)

    # Markdownlint config for the agent-maintained .rokct/ docs. markdownlint-cli2
    # applies per-directory config to everything beneath .rokct/, keeping consumer
    # repos green under the org-standard rule set without touching their root config.
    copy_versioned(
        os.path.join("core", "templates", ".markdownlint.json"),
        os.path.join(ROKCT_DIR, ".markdownlint.json"),
    )

    copy_versioned(".cursorrules", os.path.join(PROJECT_ROOT, ".cursorrules"))

    repo_owner = detect_repo_owner()
    if repo_owner:
        # RokctAI repos provision the org toolchain too: SDK_ECOSYSTEM.md's
        # compose flow runs .rokct/skills/.rok/flutter/scripts/compose.py, and
        # .rokct/skills/ is git-ignored and wiped by end_protocol.py.
        copy_dir(
            os.path.join(PROTOCOL_DIR, "core", "skills"),
            os.path.join(ROKCT_DIR, "skills"),
            include_rok=True,
        )
    else:
        core_skills_dir = os.path.join(PROTOCOL_DIR, "core", "skills")
        dst = os.path.join(ROKCT_DIR, "skills")
        # Standalone bootstrap: nothing is checked out locally, so stage
        # core/skills from the pinned release zip first - the same remote
        # fallback copy_dir() takes for the RokctAI branch above, minus .rok,
        # which the fetch never extracts on this path (include_rok defaults to
        # False) so it never touches a non-org machine's disk. Walking the
        # staged copy keeps the non-org selection below (skill directories
        # only) identical to the local-checkout case, instead of dying on
        # os.listdir() of a directory that was never fetched.
        temp_core_skills = os.path.join(ROKCT_DIR, "tmp", "core_skills")
        staged = not os.path.isdir(core_skills_dir)
        try:
            if staged:
                fetch_dir_from_github("core/skills", temp_core_skills)
                core_skills_dir = temp_core_skills
            os.makedirs(dst, exist_ok=True)
            for item in os.listdir(core_skills_dir):
                s = os.path.join(core_skills_dir, item)
                if os.path.isdir(s) and item != ".rok":
                    copy_dir(s, os.path.join(dst, item))
        finally:
            # finally, not a trailing statement: an aborted fetch, a failed
            # copy or a Ctrl-C must not leave the staging tree behind.
            if staged and os.path.isdir(temp_core_skills):
                shutil.rmtree(temp_core_skills)
                print("[init] Cleaned up temporary core/skills directory")

    copy_versioned(
        os.path.join("profiles", "web", "rules.md"),
        os.path.join(ROKCT_DIR, "profiles.md"),
    )

    copy_dir(
        os.path.join(PROTOCOL_DIR, "workflows"), os.path.join(ROKCT_DIR, "workflows")
    )

    # Distribution of Protocol-only (RokctAI) workflows
    # Skipped in CI: GITHUB_TOKEN lacks the `workflows` permission, so any
    # file deployed into .github/workflows/ gets the compose commit-back
    # remote-rejected by GitHub.
    repo_owner = detect_repo_owner()
    if repo_owner and not os.environ.get("CI"):
        rok_workflows_src = os.path.join(PROTOCOL_DIR, "workflows", ".rok")
        # Staged under the git-ignored .rokct/tmp/ rather than
        # .rokct/workflows/.rok: the latter sits in a tracked directory, so a
        # run that died before the cleanup left org-only workflow sources
        # committable.
        temp_rok_workflows = os.path.join(ROKCT_DIR, "tmp", "rok_workflows")
        staged_rok = not os.path.isdir(rok_workflows_src)
        try:
            if staged_rok:
                fetch_dir_from_github("workflows/.rok", temp_rok_workflows)
                src_dir = temp_rok_workflows
            else:
                src_dir = rok_workflows_src

            if os.path.isdir(src_dir):
                dst_workflows = os.path.join(PROJECT_ROOT, ".github", "workflows")
                os.makedirs(dst_workflows, exist_ok=True)
                for src_name, dst_name in select_rok_workflows(src_dir, repo_owner):
                    shutil.copy2(
                        os.path.join(src_dir, src_name),
                        os.path.join(dst_workflows, dst_name),
                    )
                    suffix = f" (from {src_name})" if src_name != dst_name else ""
                    print(f"[init] Deployed Protocol workflow: {dst_name}{suffix}")
        finally:
            if staged_rok and os.path.isdir(temp_rok_workflows):
                shutil.rmtree(temp_rok_workflows)
                print("[init] Cleaned up temporary workflows/.rok directory")
    else:
        # Ensure no Protocol-only workflows exist in non-RokctAI repos
        pass

    # Fleet standard, mirroring ensure_rokct_gitignore(): force LF for
    # Python files so composer.json sha256 pins (computed from the committed
    # LF blobs) verify on Windows runners, where autocrlf checkouts otherwise
    # materialize *.py with CRLF endings and change the on-disk hash.
    # newline="\n" keeps the file itself LF even when this runs on Windows.
    attributes_path = os.path.join(PROJECT_ROOT, ".gitattributes")
    required_attributes = ("*.py text eol=lf",)
    if not os.path.exists(attributes_path):
        with open(attributes_path, "w", encoding="utf-8", newline="\n") as f:
            f.write("\n".join(required_attributes) + "\n")
        print(f"[init] Created {attributes_path}")
    else:
        txt = open(attributes_path, "r", encoding="utf-8").read()
        missing = [entry for entry in required_attributes if entry not in txt]
        if missing:
            with open(attributes_path, "a", encoding="utf-8", newline="\n") as f:
                if txt and not txt.endswith("\n"):
                    f.write("\n")
                f.write("\n".join(missing) + "\n")
            print(f"[init] Updated {attributes_path} (added: {', '.join(missing)})")

    try:
        email = subprocess.check_output(
            ["git", "config", "user.email"], text=True, stderr=subprocess.DEVNULL
        ).strip()
    except Exception:
        email = ""
    if email:
        prefix = email.split("@")[0].replace(".", "").lower()
        domain = email.split("@")[1].lower()
        # Non-security use: short fingerprint of the email domain to build a
        # human-readable safe identity. usedforsecurity=False documents intent
        # and clears bandit B324 (CWE-327) without changing the digest output.
        domain_hash = hashlib.md5(domain.encode(), usedforsecurity=False).hexdigest()[
            :6
        ]
        safe_id = f"{prefix}.{domain_hash}"
        mem = os.path.join(ROKCT_DIR, "memory.md")
        existing_mem_content = ""
        if os.path.exists(mem):
            with open(mem, "r", encoding="utf-8") as f:
                existing_mem_content = f.read()
        if safe_id not in existing_mem_content:
            with open(mem, "a", encoding="utf-8") as f:
                f.write(f"\n## Safe ID\n\n{safe_id}\n")
            print(f"[init] Registered safe identity: {safe_id}")

    print("[init] Web profile file operations complete.")

    ensure_file(
        "workflows/sync_workspace.py", os.path.join(ROKCT_DIR, "sync_workspace.py")
    )
    if not os.environ.get("CI"):
        ensure_file(
            "workflows/sync_workspace.yml",
            os.path.join(PROJECT_ROOT, ".github", "workflows", "sync_workspace.yml"),
        )

    dest_initiate = os.path.join(ROKCT_DIR, "initiate.py")
    if os.path.abspath(__file__) != dest_initiate:
        shutil.copy2(os.path.abspath(__file__), dest_initiate)
        print("[init] Copied initiate.py -> .rokct/initiate.py")

    ensure_file(
        "profiles/web/end_protocol.py", os.path.join(ROKCT_DIR, "end_protocol.py")
    )

    config_path = os.path.join(ROKCT_DIR, ".workspace_config.json")
    if not os.path.exists(config_path):
        repo_owner = detect_repo_owner()
        if repo_owner:
            parent_repo = "RokctAI/occultation"
            print(
                f"[init] Detected RokctAI repo — routing working files to {parent_repo}"
            )
        else:
            print(
                "[init] Not a RokctAI repo — skipping workspace config (web agent cannot prompt for parent repo)"
            )
            parent_repo = None

        if parent_repo:
            workspace_config = {
                "parent_repo": parent_repo,
                "parent_branch": "main",
                "working_files": [
                    "memory.md",
                    "decision_log.md",
                    "project_map.md",
                    "active_session.txt",
                ],
            }
            with open(config_path, "w", encoding="utf-8") as f:
                json.dump(workspace_config, f, indent=2)
            print(
                f"[init] Created .rokct/.workspace_config.json pointing to {workspace_config['parent_repo']}"
            )


if __name__ == "__main__":
    main()
