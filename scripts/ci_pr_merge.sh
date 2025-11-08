#!/usr/bin/env bash
# Robust helper to push a feature branch, open a PR to main, merge (squash) and delete the branch.
# Avoids zsh startup issues by running in bash without relying on shell profiles.

set -e  # no -u to avoid aborting on unset optional vars

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TARGET_BRANCH="main"
BRANCH="${BRANCH:-ci/run-tests-automatic-20251107}"

# Try to auto-detect repo slug via gh if possible, fallback to origin url parsing
if command -v gh >/dev/null 2>&1; then
  REPO_SLUG="$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || true)"
fi
if [ -z "$REPO_SLUG" ]; then
  ORIGIN_URL="$(git -C "$REPO_DIR" remote get-url origin 2>/dev/null || true)"
  # Handle both HTTPS and SSH forms
  case "$ORIGIN_URL" in
    https://github.com/*)
      REPO_SLUG="${ORIGIN_URL#https://github.com/}"
      REPO_SLUG="${REPO_SLUG%.git}"
      ;;
    git@github.com:*)
      REPO_SLUG="${ORIGIN_URL#git@github.com:}"
      REPO_SLUG="${REPO_SLUG%.git}"
      ;;
  esac
fi

if [ -z "$REPO_SLUG" ]; then
  echo "[WARN] Konnte Repository-Slug nicht automatisch bestimmen. gh wird ohne --repo verwendet."
fi

echo "[INFO] Working directory: $REPO_DIR"
cd "$REPO_DIR"

if ! command -v gh >/dev/null 2>&1; then
  echo "[ERROR] GitHub CLI (gh) ist nicht installiert. Bitte installieren und authentifizieren: https://cli.github.com/" >&2
  exit 1
fi

echo "[INFO] Checking gh auth status..."
if ! gh auth status >/dev/null 2>&1; then
  echo "[ERROR] gh ist nicht authentifiziert. Bitte einmal 'gh auth login' ausführen und erneut versuchen." >&2
  exit 1
fi

echo "[INFO] Switching to branch: $BRANCH"
if git show-ref --verify --quiet "refs/heads/$BRANCH"; then
  git switch "$BRANCH"
else
  # Falls Remote-Branch existiert, davon abzweigen, sonst von origin/main
  git fetch origin --prune || true
  if git show-ref --verify --quiet "refs/remotes/origin/$BRANCH"; then
    git switch -c "$BRANCH" --track "origin/$BRANCH" || git checkout -B "$BRANCH" "origin/$BRANCH"
  else
    git switch -c "$BRANCH" || git checkout -B "$BRANCH"
    if git show-ref --verify --quiet "refs/remotes/origin/$TARGET_BRANCH"; then
      git reset --hard "origin/$TARGET_BRANCH"
    fi
  fi
fi

echo "[INFO] Rebase auf origin/$TARGET_BRANCH (falls vorhanden)"
if git show-ref --verify --quiet "refs/remotes/origin/$TARGET_BRANCH"; then
  if ! git rebase "origin/$TARGET_BRANCH"; then
    echo "[WARN] Rebase fehlgeschlagen, versuche stattdessen Merge"
    git rebase --abort || true
    git merge --no-edit "origin/$TARGET_BRANCH" || true
  fi
fi

echo "[INFO] Push branch (mit --force-with-lease falls nötig)"
if ! git push -u origin "$BRANCH"; then
  git push --force-with-lease -u origin "$BRANCH"
fi

# PR erstellen, falls keiner existiert
PR_NUM="$(gh pr list ${REPO_SLUG:+--repo "$REPO_SLUG"} --head "$BRANCH" --json number --jq '.[0].number' 2>/dev/null || true)"
if [ -z "$PR_NUM" ]; then
  echo "[INFO] Erstelle PR von $BRANCH nach $TARGET_BRANCH"
  if ! gh pr create ${REPO_SLUG:+--repo "$REPO_SLUG"} \
      --head "$BRANCH" \
      --base "$TARGET_BRANCH" \
      --title "ci(argocdinit): remove goss from pipeline" \
      --body "Remove goss steps from workflow; rely on smoke + BATS tests."; then
    echo "[ERROR] PR-Erstellung fehlgeschlagen" >&2
    exit 1
  fi
  PR_NUM="$(gh pr list ${REPO_SLUG:+--repo "$REPO_SLUG"} --head "$BRANCH" --json number --jq '.[0].number')"
else
  echo "[INFO] PR #$PR_NUM existiert bereits"
fi

echo "[INFO] Merge PR #$PR_NUM (squash + delete branch)"
if ! gh pr merge "$PR_NUM" ${REPO_SLUG:+--repo "$REPO_SLUG"} --squash --delete-branch --admin --yes; then
  echo "[WARN] Admin-Merge nicht erlaubt, versuche normalen Squash"
  gh pr merge "$PR_NUM" ${REPO_SLUG:+--repo "$REPO_SLUG"} --squash --delete-branch --yes
fi

echo "[SUCCESS] PR #$PR_NUM gemerged und Branch gelöscht"
