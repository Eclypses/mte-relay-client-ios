#!/bin/bash
set -euo pipefail

# Release workflow note:
# - This repository uses squash merges to master.
# - Releases are created from develop.
# - Preflight checks are intentionally simple: branch, clean tree, and "not behind origin/develop".
# - Complex divergence handling is intentionally avoided to match this workflow.

# Usage: ./release.sh 4.3.2

# --- CONFIGURATION ---
REPO_URL="https://github.com/Eclypses/eclypses-aws-mte-relay-client-ios"
SETTINGS_PATH="Classes/MteRelay/Settings.swift"
CHANGELOG_PATH="CHANGELOG.md"
PACKAGE_PATH="Package.swift"
PODSPEC_PATH="MteRelay.podspec"
# ---------------------

TARGET_BRANCH="develop"

require_clean_tree() {
  if [ -n "$(git status --porcelain)" ]; then
    echo "Error: Working tree is not clean. Commit/stash changes before running release.sh."
    exit 1
  fi
}

require_develop_branch() {
  local current_branch
  current_branch="$(git rev-parse --abbrev-ref HEAD)"
  if [ "$current_branch" != "$TARGET_BRANCH" ]; then
    echo "Error: release must be run from '$TARGET_BRANCH' (current: '$current_branch')."
    exit 1
  fi
}

require_up_to_date_with_origin() {
  git fetch origin "$TARGET_BRANCH" --prune

  if ! git merge-base --is-ancestor "origin/$TARGET_BRANCH" HEAD; then
    echo "Error: local '$TARGET_BRANCH' is behind origin/$TARGET_BRANCH. Run: git pull --ff-only origin $TARGET_BRANCH"
    exit 1
  fi
}

# 1. Validation
if [ -z "${1:-}" ]; then
  echo "Error: No version supplied."
  echo "Usage: ./release.sh <new_version>"
  echo "Example: ./release.sh 4.3.2"
  exit 1
fi

if ! command -v git >/dev/null 2>&1; then
  echo "Error: git is required but not found."
  exit 1
fi

if ! git rev-parse --git-dir >/dev/null 2>&1; then
  echo "Error: release.sh must be run from inside a git repository."
  exit 1
fi

require_develop_branch
require_clean_tree
require_up_to_date_with_origin

# STRIP 'v' if the user accidentally typed it (e.g. v4.3.2 -> 4.3.2)
CLEAN_VERSION="${1#v}"
TAG_VERSION="v$CLEAN_VERSION"
DATE=$(date +%Y-%m-%d)

if git rev-parse -q --verify "refs/tags/$TAG_VERSION" >/dev/null; then
  echo "Error: tag '$TAG_VERSION' already exists locally."
  exit 1
fi

if git ls-remote --tags origin | grep -q "refs/tags/$TAG_VERSION$"; then
  echo "Error: tag '$TAG_VERSION' already exists on origin."
  exit 1
fi

echo "🚀 Preparing release: $TAG_VERSION on $DATE"

if ! grep -q "## \[Unreleased\]" "$CHANGELOG_PATH"; then
  echo "Error: CHANGELOG.md must contain a '## [Unreleased]' section."
  exit 1
fi

# 2. Update Settings.swift (Use CLEAN version: "4.3.2")
# Looks for: static let relayVersion = "..."
sed -i '' "s/static let relayVersion = \".*\"/static let relayVersion = \"$CLEAN_VERSION\"/" "$SETTINGS_PATH"

# 3. Update Package.swift Comment (Use CLEAN version: "4.3.2")
# Looks for: // Version: ...
sed -i '' "s/\/\/ Relay Package Version: .*/\/\/ Relay Package Version: $CLEAN_VERSION/" "$PACKAGE_PATH"

# 4. Update MteRelay.podspec
# Looks for: s.version = '...'
sed -i '' "s/s.version      = '.*'/s.version      = '$CLEAN_VERSION'/" "$PODSPEC_PATH"
# Looks for: :tag => "..."
sed -i '' "s/:tag => \".*\"/:tag => \"$TAG_VERSION\"/" "$PODSPEC_PATH"

# 5. Update CHANGELOG.md Headers
# Uses tags like [4.3.2] for headers
# NOTE: Requires a '## [Unreleased]' section in your CHANGELOG.md to work.
SEARCH="## \[Unreleased\]"
REPLACE="## [Unreleased]\\
\\
### Added\\
-\\
\\
### Changed\\
-\\
\\
### Fixed\\
-\\
\\
\\
## [$CLEAN_VERSION] - $DATE"

sed -i '' "s/$SEARCH/$REPLACE/" "$CHANGELOG_PATH"

# 6. Update CHANGELOG.md Reference Links
# IMPORTANT: The URL must match the Git Tag (which now has 'v')
# Link format: [4.3.2]: .../releases/tag/v4.3.2
NEW_LINK="[$CLEAN_VERSION]: $REPO_URL/releases/tag/$TAG_VERSION"

echo "" >> "$CHANGELOG_PATH"
echo "$NEW_LINK" >> "$CHANGELOG_PATH"

# 7. Git Operations
echo "📦 Committing changes..."
git add "$SETTINGS_PATH" "$PACKAGE_PATH" "$PODSPEC_PATH" "$CHANGELOG_PATH"
git commit -m "chore: bump version to $CLEAN_VERSION"

echo "🏷️  Tagging version $TAG_VERSION..."
git tag -a "$TAG_VERSION" -m "Release version $CLEAN_VERSION"

echo "✅ Done! Validate the changes, then run:"
echo "   git push origin $TARGET_BRANCH $TAG_VERSION"
