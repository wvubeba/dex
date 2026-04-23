#!/usr/bin/env bash
#
# Upgrade script: apply custom patches to a new upstream Dex release.
#
# Usage:
#   ./scripts/apply-patches.sh <new-upstream-tag>
#
# Example:
#   ./scripts/apply-patches.sh v2.46.0
#
# Prerequisites:
#   - The 'upstream' remote must point to https://github.com/dexidp/dex.git
#   - The previous patched branch must exist (to cherry-pick from)
#
# What it does:
#   1. Fetches latest upstream tags
#   2. Creates a new branch from the specified tag
#   3. Cherry-picks the two patch commits from the previous patched branch
#   4. Reports success or conflicts to resolve
#
set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "Usage: $0 <new-upstream-tag>"
    echo "Example: $0 v2.46.0"
    exit 1
fi

NEW_TAG="$1"

# Strip leading 'v' for branch name
BRANCH_NAME="${NEW_TAG#v}-patched"

echo "==> Fetching upstream tags..."
git fetch upstream --tags

echo "==> Verifying tag ${NEW_TAG} exists..."
if ! git rev-parse "${NEW_TAG}" >/dev/null 2>&1; then
    echo "ERROR: Tag ${NEW_TAG} not found. Available recent tags:"
    git tag --sort=-v:refname | head -20
    exit 1
fi

# Find the current patched branch to cherry-pick from
CURRENT_PATCHED=$(git branch --list '*-patched' | sed 's/^[* ]*//' | sort -V | tail -1)
if [[ -z "${CURRENT_PATCHED}" ]]; then
    echo "ERROR: No existing *-patched branch found to cherry-pick from."
    exit 1
fi

echo "==> Current patched branch: ${CURRENT_PATCHED}"
echo "==> Creating new branch ${BRANCH_NAME} from ${NEW_TAG}..."
git checkout -b "${BRANCH_NAME}" "${NEW_TAG}"

# Get the two patch commits (skip any CI-only commits)
# We look for our specific commit messages
PATCH1=$(git log "${CURRENT_PATCHED}" --oneline --grep='Extract "scope" claim from Access Token' --format='%H' | head -1)
PATCH2=$(git log "${CURRENT_PATCHED}" --oneline --grep='Split space-delimited groups claim' --format='%H' | head -1)

if [[ -z "${PATCH1}" ]]; then
    echo "ERROR: Could not find Patch 1 commit ('Extract scope claim') on ${CURRENT_PATCHED}"
    exit 1
fi
if [[ -z "${PATCH2}" ]]; then
    echo "ERROR: Could not find Patch 2 commit ('Split space-delimited groups') on ${CURRENT_PATCHED}"
    exit 1
fi

echo "==> Cherry-picking Patch 1: ${PATCH1:0:8} (scope from access token)..."
if ! git cherry-pick "${PATCH1}"; then
    echo ""
    echo "CONFLICT: Patch 1 has conflicts. Resolve them, then run:"
    echo "  git cherry-pick --continue"
    echo "  git cherry-pick ${PATCH2}"
    echo "  git push origin ${BRANCH_NAME}"
    exit 1
fi

echo "==> Cherry-picking Patch 2: ${PATCH2:0:8} (space-delimited groups)..."
if ! git cherry-pick "${PATCH2}"; then
    echo ""
    echo "CONFLICT: Patch 2 has conflicts. Resolve them, then run:"
    echo "  git cherry-pick --continue"
    echo "  git push origin ${BRANCH_NAME}"
    exit 1
fi

echo ""
echo "==> Success! Branch ${BRANCH_NAME} created with both patches applied."
echo ""
echo "Next steps:"
echo "  1. Build & test:  go build ./... && go test ./connector/oidc/"
echo "  2. Push:          git push origin ${BRANCH_NAME}"
echo "  3. Tag (optional): git tag v${BRANCH_NAME} && git push origin v${BRANCH_NAME}"
