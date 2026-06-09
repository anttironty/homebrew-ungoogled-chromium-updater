#!/bin/bash
#
# release.sh — cut a release of this Homebrew tap and pin the formula's sha256
# to the exact tarball GitHub generates for the tag.
#
# Why this is fiddly: the formula lives *inside* the very tarball it references,
# so you can't know the final sha256 until the tag's tarball exists on GitHub.
# This script does it in the only order that works:
#
#   1. (optionally) bump version+url in the formula, commit  ──┐ this commit
#   2. move/create the tag at that commit and push it         ──┘ becomes the tag
#   3. download GitHub's tarball for the tag, compute its sha256
#   4. write that sha256 into the formula on master, commit, push
#
# Homebrew reads the formula from your tap's default branch (so the corrected
# sha on `master` is what's used), but downloads + verifies the *tag tarball*.
# The sha-fix commit (step 4) is NOT part of the tag, so everything lines up.
#
# Usage:
#   ./release.sh [VERSION] [options]
#
#   VERSION      e.g. 0.1.0  (default: the `version` already in the formula)
#   -f, --force  move the tag if it already exists (required to re-tag)
#   -y, --yes    don't prompt before pushing
#   -n, --dry-run  show what would happen; make no commits, tags, or pushes
#   -h, --help   this help
#
set -euo pipefail

# ---- locate repo + formula ---------------------------------------------------
cd "$(cd "$(dirname "$0")" && pwd)"
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "Not a git repo." >&2; exit 1; }

shopt -s nullglob
FORMULAS=(Formula/*.rb)
shopt -u nullglob
[ "${#FORMULAS[@]}" -eq 1 ] || { echo "Expected exactly one Formula/*.rb, found ${#FORMULAS[@]}." >&2; exit 1; }
FORMULA="${FORMULAS[0]}"

# ---- parse args --------------------------------------------------------------
VERSION=""; FORCE=0; ASSUME_YES=0; DRY=0
while [ $# -gt 0 ]; do
  case "$1" in
    -f|--force)   FORCE=1 ;;
    -y|--yes)     ASSUME_YES=1 ;;
    -n|--dry-run) DRY=1 ;;
    -h|--help)    sed -n '2,/^set -euo/p' "$0" | sed 's/^# \{0,1\}//; $d'; exit 0 ;;
    -*)           echo "Unknown option: $1" >&2; exit 2 ;;
    *)            VERSION="$1" ;;
  esac
  shift
done

# Default VERSION from the formula's `version "..."`.
if [ -z "$VERSION" ]; then
  VERSION="$(perl -ne 'print $1 if /version\s+"([^"]+)"/' "$FORMULA")"
fi
[ -n "$VERSION" ] || { echo "Could not determine version (pass it, e.g. ./release.sh 0.1.0)." >&2; exit 1; }
VERSION="${VERSION#v}"          # normalize: accept 0.1.0 or v0.1.0
TAG="v$VERSION"

# ---- derive OWNER/REPO from origin ------------------------------------------
ORIGIN="$(git remote get-url origin 2>/dev/null || true)"
[ -n "$ORIGIN" ] || { echo "No 'origin' remote configured." >&2; exit 1; }
SLUG="$(printf '%s' "$ORIGIN" | sed -E 's#^git@github\.com:##; s#^https://github\.com/##; s#\.git$##')"
OWNER="${SLUG%%/*}"; REPO="${SLUG##*/}"
[ -n "$OWNER" ] && [ -n "$REPO" ] && [ "$OWNER" != "$SLUG" ] \
  || { echo "Could not parse owner/repo from origin: $ORIGIN" >&2; exit 1; }

TARBALL_URL="https://github.com/$OWNER/$REPO/archive/refs/tags/$TAG.tar.gz"
BRANCH="$(git rev-parse --abbrev-ref HEAD)"

echo "Repo:    $OWNER/$REPO"
echo "Branch:  $BRANCH"
echo "Version: $VERSION  (tag $TAG)"
echo "Tarball: $TARBALL_URL"
echo "Formula: $FORMULA"
[ "$DRY" -eq 1 ] && echo "(dry run — no commits/tags/pushes will be made)"
echo

# ---- preconditions -----------------------------------------------------------
if [ "$BRANCH" != "master" ] && [ "$BRANCH" != "master" ]; then
  echo "⚠️  You're on '$BRANCH', not master/master. Release from your default branch." >&2
  exit 1
fi
if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "⚠️  Working tree has uncommitted changes. Commit or stash them first." >&2
  git status --short >&2
  exit 1
fi

# Refuse to clobber an existing tag unless --force.
if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
  if [ "$FORCE" -ne 1 ]; then
    echo "Tag $TAG already exists (at $(git rev-parse --short "$TAG"))." >&2
    echo "Re-run with -f to move it to HEAD, or pass a new VERSION." >&2
    exit 1
  fi
  echo "Tag $TAG exists; will move it to HEAD ($(git rev-parse --short HEAD))."
fi

confirm() { # prompt unless -y
  [ "$ASSUME_YES" -eq 1 ] && return 0
  printf "%s [y/N] " "$1"; read -r a; case "$a" in y|Y) return 0;; *) echo "Aborted."; exit 1;; esac
}

run() { # echo + execute (or just echo under --dry-run)
  echo "+ $*"
  [ "$DRY" -eq 1 ] || "$@"
}

# ---- step 1: ensure formula version + url match the target, commit if changed
echo "==> Step 1/4: align formula version + url with $TAG"
if [ "$DRY" -eq 1 ]; then
  echo "  would set version \"$VERSION\" and url → $TARBALL_URL"
else
  VERSION="$VERSION" TARBALL_URL="$TARBALL_URL" perl -i -pe '
    s{version\s+"[^"]*"}{version "$ENV{VERSION}"};
    s{url\s+"[^"]*"}{url "$ENV{TARBALL_URL}"};
  ' "$FORMULA"
fi
if [ "$DRY" -ne 1 ] && ! git diff --quiet -- "$FORMULA"; then
  run git add "$FORMULA"
  run git commit -m "Prepare release $TAG"
else
  echo "  version/url already current — no prep commit needed."
fi

# ---- step 2: move/create tag at HEAD and push it ----------------------------
echo "==> Step 2/4: tag $TAG at HEAD and push"
confirm "Push tag $TAG (and branch $BRANCH) to $OWNER/$REPO?"
run git tag -f -a "$TAG" -m "Release $TAG"
run git push origin "$BRANCH"
run git push -f origin "refs/tags/$TAG"

# ---- step 3: fetch tarball + compute sha256 ---------------------------------
echo "==> Step 3/4: fetch $TAG tarball and compute sha256"
if [ "$DRY" -eq 1 ]; then
  echo "  would: curl $TARBALL_URL | shasum -a 256"
  SHA="<computed-after-push>"
else
  SHA=""
  for attempt in 1 2 3 4 5 6; do
    if SHA="$(curl -fsSL --retry 2 "$TARBALL_URL" | shasum -a 256 | awk '{print $1}')" \
       && [ "${#SHA}" -eq 64 ]; then
      break
    fi
    echo "  tarball not ready yet (attempt $attempt); waiting for GitHub…"
    sleep 5; SHA=""
  done
  [ "${#SHA}" -eq 64 ] || { echo "Failed to fetch/hash $TARBALL_URL" >&2; exit 1; }
  echo "  sha256 = $SHA"
fi

# ---- step 4: write sha into formula, commit, push ---------------------------
echo "==> Step 4/4: pin sha256 in $FORMULA and push"
if [ "$DRY" -eq 1 ]; then
  echo "  would set sha256 \"$SHA\" and commit \"Pin sha256 for $TAG\""
else
  SHA="$SHA" perl -i -pe 's{sha256\s+"[^"]*"}{sha256 "$ENV{SHA}"}' "$FORMULA"
  if git diff --quiet -- "$FORMULA"; then
    echo "  sha256 already correct — nothing to commit."
  else
    run git add "$FORMULA"
    run git commit -m "Pin sha256 for $TAG"
    run git push origin "$BRANCH"
  fi
fi

echo
echo "✅ Release $TAG complete."
echo "   Users can now install with:"
echo "     brew install $OWNER/${REPO#homebrew-}/${REPO#homebrew-}"
