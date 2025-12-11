#!/usr/bin/env bash
set -euo pipefail

# Build a production-only tree in the current checkout by pruning dev assets,
# pointing submodules at main, and dropping the views-library submodule.
# Intended to run in a dedicated release worktree/clone (will delete files).

ROOT="$(pwd)"
if [[ ! -d .git ]]; then
  echo "Error: must be run from repo root (no .git found)." >&2
  exit 1
fi

if git diff --quiet --ignore-submodules HEAD 2>/dev/null; then
  CLEAN=1
else
  CLEAN=0
fi

echo "== BlackCat release tree builder =="
echo "Root: $ROOT"
if [[ $CLEAN -eq 0 ]]; then
  echo "Warning: working tree not clean; continuing may drop local changes." >&2
fi

# Paths to remove (dev-only)
REMOVE_PATHS=(
  ".github"
  ".tmp-check.ps1"
  "bin"
  "docker"
  "docker-compose.yml"
  "examples"
  "gen-db-stub.php"
  "infra"
  "k8s"
  "monitoring"
  "phpstan"
  "provisioning"
  "reflect-db.php"
  "scripts"
  "templates"
  "tests"
  "tmp-parse.ps1"
  "tools"
  "docs/tests"
  "schema"
)

echo "-> Removing dev-only files/dirs..."
for p in "${REMOVE_PATHS[@]}"; do
  git rm -rf --ignore-unmatch "$p" >/dev/null 2>&1 || true
  rm -rf "$p" 2>/dev/null || true
done

# Drop views-library submodule if present
if grep -q 'views-library' .gitmodules 2>/dev/null; then
  echo "-> Dropping views-library submodule..."
  git submodule deinit -f views-library >/dev/null 2>&1 || true
  git rm -f views-library >/dev/null 2>&1 || true
  rm -rf .git/modules/views-library 2>/dev/null || true
fi

# Point submodules to main instead of dev
if [[ -f .gitmodules ]]; then
  echo "-> Rewriting submodules to track main..."
  perl -pi -e 's/branch = dev/branch = main/g' .gitmodules
fi

echo "-> Updating submodule pointers (remote main)..."
git submodule update --remote --recursive >/dev/null 2>&1 || true

git add .gitmodules packages >/dev/null 2>&1 || true

echo "Done. Review with: git status --short --ignore-submodules=all"
echo "When satisfied: git commit -am \"chore: build release tree\" && git push origin release/main"
