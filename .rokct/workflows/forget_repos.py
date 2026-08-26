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
import re
import subprocess
import urllib.request
from pathlib import Path

ROKCT_DIR = Path.cwd() / ".rokct"
WORKING_FILES = ["memory.md", "decision_log.md", "project_map.md"]


def check_repo_status_git(repo_url):
    """Fallback check for private repositories using git ls-remote."""
    url = f"https://github.com/{repo_url}.git"
    env = os.environ.copy()
    env["GIT_TERMINAL_PROMPT"] = "0"
    env["GIT_ASKPASS"] = "true"
    try:
        res = subprocess.run(
            ["git", "ls-remote", url],
            capture_output=True,
            text=True,
            env=env,
            timeout=10,
        )
        if res.returncode == 0:
            return ("exists", None)
        stderr = res.stderr.lower()
        if "not found" in stderr:
            return ("gone", None)
        # If it fails with permission denied, auth required, etc., it exists but is private
        return ("exists", None)
    except Exception:
        return ("exists", None)


def check_repo_status(repo_url):
    """
    Check the status of a GitHub repository.
    Returns:
        - ('exists', None): Repo exists at current URL.
        - ('renamed', new_url): Repo was renamed to new_url.
        - ('gone', None): Repo is gone (404).
    """
    # Audit GitHub repo status to handle renames (301/302) or deletions (404)
    # allowing the protocol to clean up dead sync markers
    url = f"https://github.com/{repo_url}"
    try:
        # Use a custom request to handle redirects manually
        req = urllib.request.Request(
            url,
            headers={"User-Agent": "Mozilla/5.0", "X-Trace-Id": "forget-repos-check"},
        )

        # We use a handler that doesn't automatically follow redirects to catch the 301
        class NoRedirectHandler(urllib.request.HTTPRedirectHandler):
            def redirect_request(self, req, fp, code, msg, hdrs, newurl):
                return None  # Stop redirection

        opener = urllib.request.build_opener(NoRedirectHandler())
        with opener.open(req) as response:
            status = response.getcode()
            if status == 200:
                return ("exists", None)
            elif status in (301, 302):
                new_url = response.getheader("Location")
                # Extract 'Owner/Repo' from the new URL
                if new_url:
                    # Handle relative URLs or full GitHub URLs
                    if "github.com" in new_url:
                        parts = (
                            new_url.split("github.com/")[-1]
                            .replace(".git", "")
                            .split("/")
                        )
                        if len(parts) >= 2:
                            return ("renamed", f"{parts[0]}/{parts[1]}")
                return ("exists", None)  # Fallback if redirect is weird
            elif status == 404:
                return check_repo_status_git(repo_url)
    except urllib.error.HTTPError as e:
        if e.code == 404:
            return check_repo_status_git(repo_url)
        if e.code in (301, 302):
            new_url = e.headers.get("Location")
            if new_url and "github.com" in new_url:
                parts = new_url.split("github.com/")[-1].replace(".git", "").split("/")
                if len(parts) >= 2:
                    return ("renamed", f"{parts[0]}/{parts[1]}")
    except Exception:
        pass
    return ("exists", None)  # Default to exists if unreachable (network down, etc.)


def forget_repo_from_content(content, repo_to_forget):
    """Remove all sync blocks associated with a specific repository."""
    blocks = re.split(
        r"(<!-- ROKCT-SYNC-START: .*? -->\n.*?<!-- ROKCT-SYNC-END: .*? -->\n)",
        content,
        flags=re.DOTALL,
    )
    new_content = []

    for part in blocks:
        if part.startswith("<!-- ROKCT-SYNC-START:"):
            match = re.search(r"ROKCT-SYNC-START: ([^/]+/[^/]+)/", part)
            if match:
                repo = match.group(1)
                if repo == repo_to_forget:
                    continue  # Skip this block
        new_content.append(part)

    return "".join(new_content)


def rename_repo_in_content(content, old_repo, new_repo):
    """Update all sync markers from an old repo name to a new one."""
    # Replace START markers
    content = content.replace(
        f"ROKCT-SYNC-START: {old_repo}/", f"ROKCT-SYNC-START: {new_repo}/"
    )
    # Replace END markers
    content = content.replace(
        f"ROKCT-SYNC-END: {old_repo}/", f"ROKCT-SYNC-END: {new_repo}/"
    )
    return content


def main():
    if not ROKCT_DIR.is_dir():
        print(
            "[forget] .rokct/ not found. This script must be run in the parent repository."
        )
        return

    all_synced_repos = set()
    for filename in WORKING_FILES:
        path = ROKCT_DIR / filename
        if path.exists():
            content = path.read_text(encoding="utf-8")
            matches = re.findall(r"ROKCT-SYNC-START: ([^/]+/[^/]+)/", content)
            all_synced_repos.update(matches)

    if not all_synced_repos:
        print("[forget] No synced repositories found in memory.")
        return

    print(
        f"[forget] Found {len(all_synced_repos)} synced repositories: {', '.join(all_synced_repos)}"
    )

    repos_to_remove = []
    renames = {}  # {old_repo: new_repo}

    for repo in all_synced_repos:
        print(f"[forget] Checking {repo}...", end=" ")
        status, value = check_repo_status(repo)
        if status == "exists":
            print("Exists")
        elif status == "renamed":
            print(f"RENAMED to {value}")
            renames[repo] = value
        elif status == "gone":
            print("GONE")
            repos_to_remove.append(repo)

    if not repos_to_remove and not renames:
        print("[forget] No changes needed. Everything is up to date.")
        return

    for filename in WORKING_FILES:
        path = ROKCT_DIR / filename
        if path.exists():
            content = path.read_text(encoding="utf-8")
            original_content = content

            # 1. Handle Renames
            for old_repo, new_repo in renames.items():
                content = rename_repo_in_content(content, old_repo, new_repo)

            # 2. Handle Deletions
            for repo in repos_to_remove:
                content = forget_repo_from_content(content, repo)

            if content != original_content:
                path.write_text(content, encoding="utf-8")
                print(f"[forget] Cleaned and updated {filename}")

    print("[forget] Memory maintenance complete.")


if __name__ == "__main__":
    main()
