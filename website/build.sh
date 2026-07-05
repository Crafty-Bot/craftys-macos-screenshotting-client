#!/usr/bin/env bash
set -euo pipefail

# Builds the CraftyCannon docs site with mkdocs-material.
# Source of truth for content stays in the top-level *.md files and docs/;
# this script copies them into website/docs/ (generated, gitignored) and
# builds static HTML into website/site/.

cd "$(dirname "$0")"
ROOT="$(cd .. && pwd)"

if [ ! -d .venv ]; then
  python3 -m venv .venv
fi
# shellcheck disable=SC1091
source .venv/bin/activate
pip install --quiet --upgrade pip
pip install --quiet -r requirements.txt

rm -rf docs site
mkdir -p docs/docs

# Top-level docs (kept at the same filenames so existing relative links resolve).
cp "$ROOT/ARCHITECTURE.md" docs/
cp "$ROOT/USER_GUIDE.md" docs/
cp "$ROOT/FEATURES.md" docs/
cp "$ROOT/TOOLS.md" docs/
cp "$ROOT/UPLOAD_BACKENDS.md" docs/
cp "$ROOT/REDACTION.md" docs/
cp "$ROOT/CHANGELOG.md" docs/
cp "$ROOT/README.md" docs/index.md

# docs/ subfolder, preserved at the same relative path.
cp "$ROOT/docs/SETUP.md" docs/docs/
cp "$ROOT/docs/UPDATE_NOTES.md" docs/docs/

mkdocs build

echo "Built site -> $(pwd)/site"
