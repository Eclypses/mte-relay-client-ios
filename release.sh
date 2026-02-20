#!/bin/bash
set -euo pipefail

# Usage: ./release.sh 4.3.2

# --- CONFIGURATION ---
REPO_URL="https://github.com/Eclypses/eclypses-aws-mte-relay-client-ios"
SETTINGS_PATH="Classes/MteRelay/Settings.swift"
CHANGELOG_PATH="CHANGELOG.md"
PACKAGE_PATH="Package.swift"
# ---------------------

require_clean_tree() {
  if [ -n "$(git status --porcelain)" ]; then
    echo "Error: Working tree is not clean. Commit/stash changes before running release.sh."
    exit 1
  fi
}

require_develop_branch() {
  local current_branch
  current_branch="$(git rev-parse --abbrev-ref HEAD)"
  if [ "$current_branch" != "develop" ]; then
    echo "Error: Releases must be cut from 'develop'. Current branch: '$current_branch'."
    exit 1
  fi
}

# 1. Validation
if [ -z "$1" ]; then
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

# STRIP 'v' if the user accidentally typed it (e.g. v4.3.2 -> 4.3.2)
CLEAN_VERSION="${1#v}"
TAG_VERSION="v$CLEAN_VERSION"
DATE=$(date +%Y-%m-%d)

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

# 4. Update CHANGELOG.md Headers
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

# 5. Update CHANGELOG.md Reference Links
# IMPORTANT: The URL must match the Git Tag (which now has 'v')
# Link format: [4.3.2]: .../releases/tag/v4.3.2
NEW_LINK="[$CLEAN_VERSION]: $REPO_URL/releases/tag/$TAG_VERSION"

echo "" >> "$CHANGELOG_PATH"
echo "$NEW_LINK" >> "$CHANGELOG_PATH"

# 6. Git Operations
echo "📦 Committing changes..."
git add "$SETTINGS_PATH" "$PACKAGE_PATH" "$CHANGELOG_PATH"
git commit -m "chore: bump version to $CLEAN_VERSION"

echo "🏷️  Tagging version $TAG_VERSION..."
git tag -a "$TAG_VERSION" -m "Release version $CLEAN_VERSION"

echo "✅ Done! Validate the changes, then run:"
echo "   git push origin develop && git push origin $TAG_VERSION"
