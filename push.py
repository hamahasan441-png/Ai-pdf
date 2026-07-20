#!/usr/bin/env python3
import argparse
import shutil
import subprocess
import sys
from pathlib import Path


def run(cmd, cwd=None, check=True):
    print(f"$ {' '.join(cmd)}")
    result = subprocess.run(cmd, cwd=cwd, text=True)
    if check and result.returncode != 0:
        sys.exit(result.returncode)
    return result.returncode


def require_cmd(name, install_hint=None):
    if shutil.which(name) is None:
        print(f"ERROR: required command not found: {name}")
        if install_hint:
            print(install_hint)
        sys.exit(1)


def is_git_repo(path: Path) -> bool:
    return (path / ".git").exists()


def gh_authenticated() -> bool:
    return subprocess.run(
        ["gh", "auth", "status"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    ).returncode == 0


def ensure_clean_branch(repo: Path, base: str, branch: str):
    run(["git", "fetch", "origin", base], cwd=repo)
    code = subprocess.run(
        ["git", "show-ref", "--verify", "--quiet", f"refs/heads/{branch}"],
        cwd=repo,
    ).returncode
    if code == 0:
        run(["git", "checkout", branch], cwd=repo)
    else:
        run(["git", "checkout", "-b", branch, f"origin/{base}"], cwd=repo)


def stage_and_commit(repo: Path, commit_message: str):
    run(["git", "add", "-A"], cwd=repo)
    diff_code = subprocess.run(["git", "diff", "--cached", "--quiet"], cwd=repo).returncode
    if diff_code == 0:
        print("No staged changes found. Copy files into the repo first.")
        sys.exit(1)
    run(["git", "commit", "-m", commit_message], cwd=repo)


def push_branch(repo: Path, branch: str):
    run(["git", "push", "-u", "origin", branch], cwd=repo)


def create_pr(repo_slug, base, branch, title, body, body_file):
    cmd = ["gh", "pr", "create", "--repo", repo_slug, "--base", base, "--head", branch, "--title", title]
    if body_file:
        cmd += ["--body-file", body_file]
    elif body:
        cmd += ["--body", body]
    else:
        cmd += ["--fill"]
    run(cmd)


def main():
    parser = argparse.ArgumentParser(
        description="Create branch, commit, push, and open PR using git + GitHub CLI."
    )
    parser.add_argument("--repo-path", required=True, help="Local path to cloned repository")
    parser.add_argument("--repo-slug", required=True, help="GitHub repo slug, e.g. hamahasan441-png/Ai-pdf")
    parser.add_argument("--base", default="main", help="Base branch name")
    parser.add_argument("--branch", required=True, help="Feature branch name to create/use")
    parser.add_argument("--commit-message", required=True, help="Commit message")
    parser.add_argument("--pr-title", required=True, help="Pull request title")
    parser.add_argument("--pr-body", default=None, help="Inline PR body text")
    parser.add_argument("--pr-body-file", default=None, help="Path to markdown file for PR body")
    parser.add_argument("--open", action="store_true", help="Open created PR in browser after creation")
    args = parser.parse_args()

    repo = Path(args.repo_path).expanduser().resolve()

    require_cmd("git", "Install Git first.")
    require_cmd("gh", "Install GitHub CLI from https://cli.github.com/ and run: gh auth login")

    if not gh_authenticated():
        print("ERROR: GitHub CLI is not authenticated. Run: gh auth login")
        sys.exit(1)

    if not repo.exists() or not is_git_repo(repo):
        print(f"ERROR: not a git repository: {repo}")
        sys.exit(1)

    ensure_clean_branch(repo, args.base, args.branch)
    stage_and_commit(repo, args.commit_message)
    push_branch(repo, args.branch)
    create_pr(args.repo_slug, args.base, args.branch, args.pr_title, args.pr_body, args.pr_body_file)

    if args.open:
        run(["gh", "pr", "view", "--repo", args.repo_slug, "--web"])

    print("Done.")


if __name__ == "__main__":
    main()
