#!/bin/bash
# Publishes a GitHub release for the current commit.
#
#   1. checks: on main, clean working tree, HEAD pushed, tag V<YY.MM.XX> not used yet
#   2. builds SimplePlug.app (macOS) and zips it
#   3. creates the release (tag V<version> on HEAD) with the macOS zip
#   4. attaches the Windows zip: reuses the CI build of the same commit if there is one,
#      otherwise dispatches the Windows workflow, which builds it and attaches it
#
# The version is YY.MM.XX (see version.sh): the XX is the number of commits made this month,
# so every release needs a new commit.
#
# Usage: ./release.sh [options]
#   -n FILE       release notes file (default: commit subjects since the previous release)
#   -y            don't ask for confirmation
#   --dry-run     run the checks and the build, publish nothing
#   --no-windows  don't attach a Windows zip
#   -h, --help    show this help
set -euo pipefail
cd "$(dirname "$0")"

usage() {
    sed -n '2,/^set -euo/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'
}
die()  { echo "✗ $*" >&2; exit 1; }
step() { echo "→ $*"; }

NOTES_FILE=""; ASSUME_YES=0; DRY_RUN=0; WINDOWS=1
while [ $# -gt 0 ]; do
    case "$1" in
        -n) [ $# -ge 2 ] || die "-n needs a file"; NOTES_FILE="$2"; shift 2 ;;
        -y) ASSUME_YES=1; shift ;;
        --dry-run) DRY_RUN=1; shift ;;
        --no-windows) WINDOWS=0; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
    esac
done
[ -z "$NOTES_FILE" ] || [ -f "$NOTES_FILE" ] || die "Notes file not found: $NOTES_FILE"

# --- 1. Checks -------------------------------------------------------------------------------
command -v gh >/dev/null || die "gh (GitHub CLI) is required: https://cli.github.com"
gh auth status >/dev/null 2>&1 || die "gh isn't logged in (run: gh auth login)"

BRANCH=$(git rev-parse --abbrev-ref HEAD)
[ "$BRANCH" = main ] || die "Releases are made from main (you're on $BRANCH)"
[ -z "$(git status --porcelain)" ] || die "The working tree isn't clean: commit or stash your changes first"
git fetch -q origin main --tags
SHA=$(git rev-parse HEAD)
[ "$SHA" = "$(git rev-parse origin/main)" ] || die "HEAD isn't what's on origin/main: push (or pull) first"

VERSION=$(./version.sh --plain)
TAG="V$VERSION"
if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null || gh release view "$TAG" >/dev/null 2>&1; then
    die "$TAG already exists: make a new commit first (the version counts the commits of the month)"
fi

# --- 2. macOS build --------------------------------------------------------------------------
step "Building SimplePlug.app $VERSION"
./build.sh >/dev/null
BUILT=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" build/SimplePlug.app/Contents/Info.plist)
[ "$BUILT" = "$VERSION" ] || die "The built app says $BUILT, expected $VERSION"
MAC_ZIP="build/SimplePlug-$TAG-macOS-$(uname -m).zip"   # the in-app updater looks for "-macOS-<arch>.zip"
rm -f "$MAC_ZIP"
ditto -c -k --keepParent build/SimplePlug.app "$MAC_ZIP"

# --- Release notes ---------------------------------------------------------------------------
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
NOTES="$WORK/notes.md"
if [ -n "$NOTES_FILE" ]; then
    cp "$NOTES_FILE" "$NOTES"
else
    PREV=$(git describe --tags --match 'V[0-9]*' --abbrev=0 2>/dev/null || true)
    {
        echo "**Changes**"
        if [ -n "$PREV" ]; then git log --no-merges --format='- %s' "$PREV..HEAD"
        else git log --no-merges --format='- %s' -20; fi
    } > "$NOTES"
fi
cat >> "$NOTES" <<EOF


**macOS** — \`SimplePlug-$TAG-macOS-$(uname -m).zip\`
Unzip, drag \`SimplePlug.app\` to Applications, then (the app isn't notarized):
\`\`\`
xattr -dr com.apple.quarantine /Applications/SimplePlug.app
\`\`\`
The app offers new versions by itself (or *SimplePlug › Check for Updates…*).
EOF
if [ "$WINDOWS" = 1 ]; then
    cat >> "$NOTES" <<EOF

**Windows (experimental)** — \`SimplePlug-$TAG-windows-x64.zip\`
Unzip and run \`SimplePlug.exe\` (unsigned: SmartScreen › *More info* › *Run anyway*).
EOF
fi

# --- 3. Windows zip --------------------------------------------------------------------------
WIN_ZIP=""
if [ "$WINDOWS" = 1 ]; then
    RUN=$(gh run list --workflow=windows.yml --commit "$SHA" --status success --limit 1 \
              --json databaseId -q '.[0].databaseId' 2>/dev/null || true)
    if [ -n "$RUN" ]; then
        step "Windows: reusing the CI build of this commit (run $RUN)"
        gh run download "$RUN" --name SimplePlug-windows-x64 --dir "$WORK/win" >/dev/null
        WIN_ZIP="$WORK/win/SimplePlug-$TAG-windows-x64.zip"
        [ -f "$WIN_ZIP" ] || die "The CI artifact doesn't contain $(basename "$WIN_ZIP") (found: $(ls "$WORK/win"))"
    else
        step "Windows: no CI build for this commit, the workflow will be dispatched after the release is created"
    fi
fi

# --- Summary / confirmation ------------------------------------------------------------------
echo
echo "  Tag       $TAG  ($(git rev-parse --short HEAD))"
echo "  Title     $TAG — SimplePlug (macOS AU + Windows VST3)"
echo "  macOS     $MAC_ZIP"
if [ "$WINDOWS" = 0 ]; then echo "  Windows   (skipped)"
elif [ -n "$WIN_ZIP" ]; then echo "  Windows   $(basename "$WIN_ZIP") (from CI run $RUN)"
else echo "  Windows   built by dispatching the workflow"; fi
echo "  Notes:"; sed 's/^/    | /' "$NOTES"
echo

if [ "$DRY_RUN" = 1 ]; then echo "Dry run: nothing was published."; exit 0; fi
if [ "$ASSUME_YES" != 1 ]; then
    printf "Publish %s on GitHub? [y/N] " "$TAG"
    read -r answer
    case "$answer" in y|Y|yes) ;; *) echo "Cancelled."; exit 1 ;; esac
fi

# --- 4. Publish ------------------------------------------------------------------------------
step "Creating release $TAG"
gh release create "$TAG" "$MAC_ZIP" --target "$SHA" \
    --title "$TAG — SimplePlug (macOS AU + Windows VST3)" --notes-file "$NOTES"

if [ -n "$WIN_ZIP" ]; then
    step "Attaching the Windows zip"
    gh release upload "$TAG" "$WIN_ZIP"
elif [ "$WINDOWS" = 1 ]; then
    step "Dispatching the Windows workflow (about 5 minutes)"
    BEFORE=$(gh run list --workflow=windows.yml --event workflow_dispatch --limit 1 --json databaseId -q '.[0].databaseId' || true)
    gh workflow run windows.yml --ref main -f attach_to_tag="$TAG"
    NEW=""
    for _ in $(seq 1 30); do
        sleep 2
        NEW=$(gh run list --workflow=windows.yml --event workflow_dispatch --limit 1 --json databaseId -q '.[0].databaseId' || true)
        [ -n "$NEW" ] && [ "$NEW" != "$BEFORE" ] && break
        NEW=""
    done
    [ -n "$NEW" ] || die "Couldn't find the workflow run: check the Actions tab, then attach the zip by hand"
    gh run watch "$NEW" --exit-status --interval 20 >/dev/null || die "The Windows build failed (run $NEW): the release exists without a Windows zip"
fi

echo
step "Done: $(gh release view "$TAG" --json url -q .url)"
gh release view "$TAG" --json assets -q '.assets[].name' | sed 's/^/    /'
