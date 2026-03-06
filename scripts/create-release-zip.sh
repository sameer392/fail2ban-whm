#!/bin/bash
# Create a release zip that extracts to 'fail2ban-whm' (not the GitHub default repo-tag format)
# Usage: ./scripts/create-release-zip.sh [VERSION]
#   VERSION defaults to v1.0.0
# Output: releases/fail2ban-whm-{VERSION}.zip

set -e
VERSION="${1:-v1.0.0}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RELEASES_DIR="$REPO_ROOT/releases"
OUTPUT_NAME="fail2ban-whm-${VERSION}.zip"
OUTPUT_PATH="$RELEASES_DIR/$OUTPUT_NAME"
TMP_DIR="$(mktemp -d)"

cleanup() { rm -rf "$TMP_DIR"; }
trap cleanup EXIT

mkdir -p "$RELEASES_DIR"
mkdir -p "$TMP_DIR/fail2ban-whm"
rsync -a --exclude='.git' --exclude='*.zip' --exclude='releases' "$REPO_ROOT/" "$TMP_DIR/fail2ban-whm/"

cd "$TMP_DIR"
zip -r "$OUTPUT_PATH" fail2ban-whm

echo "Created: $OUTPUT_PATH"
echo "Extracts to: fail2ban-whm/"
