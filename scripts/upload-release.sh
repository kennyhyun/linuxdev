#!/bin/bash

set -e

# 사용법 확인
if [ "$#" -lt 1 ] || [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
    echo "Usage: $0 <archive_name> [tag] [title]"
    echo ""
    echo "Arguments:"
    echo "  archive_name  Base name of archive (without extension)"
    echo "  tag          Release tag (default: v$(date +%Y%m%d))"
    echo "  title        Release title (default: VM Export $(date +%Y-%m-%d))"
    echo ""
    echo "Examples:"
    echo "  $0 linuxdev-arm64-20250827"
    echo "  $0 linuxdev-arm64-20250827 v1.0.0 'Stable Release'"
    echo ""
    echo "Files to upload:"
    echo "  - <archive_name>.7z (or .7z.*)"
    echo "  - <archive_name>.sha256"
    exit 0
fi

ARCHIVE_NAME="$1"
TAG="${2:-v$(date +%Y%m%d)}"
TITLE="${3:-VM Export $(date +%Y-%m-%d)}"

# exports 디렉토리로 이동
cd "$(dirname "$0")/../exports"

# 파일 존재 확인
if [ ! -f "${ARCHIVE_NAME}.sha256" ]; then
    echo "❌ Checksum file not found: ${ARCHIVE_NAME}.sha256"
    exit 1
fi

# 아카이브 파일 확인
if [ -f "${ARCHIVE_NAME}.7z" ]; then
    ARCHIVE_FILES="${ARCHIVE_NAME}.7z"
    EXTRACT_CMD="7z x ${ARCHIVE_NAME}.7z"
    NOTES="VM disk image. Extract with: $EXTRACT_CMD"
elif [ -f "${ARCHIVE_NAME}.7z.001" ]; then
    ARCHIVE_FILES="${ARCHIVE_NAME}.7z.*"
    EXTRACT_CMD="7z x ${ARCHIVE_NAME}.7z.001"
    NOTES="VM disk image split into 2GB volumes. Extract with: $EXTRACT_CMD"
else
    echo "❌ Archive file not found: ${ARCHIVE_NAME}.7z or ${ARCHIVE_NAME}.7z.001"
    exit 1
fi

# GitHub CLI 확인
if ! command -v gh >/dev/null 2>&1; then
    echo "❌ GitHub CLI not found. Install with: brew install gh"
    exit 1
fi

# 파일 목록 출력
echo "📁 Files to upload:"
ls -lh $ARCHIVE_FILES "${ARCHIVE_NAME}.sha256"

echo ""
echo "🚀 Creating GitHub Release..."
echo "Tag: $TAG"
echo "Title: $TITLE"

# GitHub Release 생성
gh release create "$TAG" $ARCHIVE_FILES "${ARCHIVE_NAME}.sha256" \
    --title "$TITLE" \
    --notes "$NOTES"

echo "✅ GitHub Release created successfully!"
echo "🔗 View at: https://github.com/$(gh repo view --json owner,name -q '.owner.login + "/" + .name')/releases/tag/$TAG"