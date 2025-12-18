#!/usr/bin/env bash
set -Eeuo pipefail

# ─────────────────────────────────────────────────────────────
#  Chromium Widevine CDM Installer
#  - Mozilla-verified
#  - SHA-512 only
#  - Safe sudo re-exec
#  - Guaranteed cleanup
#  - Marker-based uninstall support
# ─────────────────────────────────────────────────────────────

# -------------------------
# Colors & logging helpers
# -------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RESET='\033[0m'

info()    { echo -e "${BLUE}==>${RESET} $*"; }
success() { echo -e "${GREEN}✔${RESET} $*"; }
warn()    { echo -e "${YELLOW}⚠${RESET} $*"; }
fatal()   { echo -e "${RED}✖${RESET} $*" >&2; exit 1; }

# -------------------------
# Paths
# -------------------------
INSTALL_DIR="/usr/lib/chromium/WidevineCdm"
LICENSE_DIR="/usr/share/licenses/chromium-widevine"
SYMLINK="/usr/lib/chromium/libwidevinecdm.so"
MARKER_FILE="$INSTALL_DIR/.installed-by-widevine-installer"

# -------------------------
# Cleanup handler
# -------------------------
cleanup() {
  local exit_code=$?
  [[ -n "${TMP_DIR:-}" && -d "$TMP_DIR" ]] && rm -rf "$TMP_DIR"
  (( exit_code != 0 )) && echo -e "${RED}✖${RESET} Script failed (exit code $exit_code)" >&2
  exit "$exit_code"
}

trap cleanup EXIT

# -------------------------
# Root check (auto sudo)
# -------------------------
if [[ $EUID -ne 0 ]]; then
  warn "Root privileges required"
  info "Re-running with sudo…"
  SCRIPT_PATH="$(readlink -f "$0" 2>/dev/null || realpath "$0")"
  exec sudo --preserve-env=PATH bash "$SCRIPT_PATH" "$@"
fi

# -------------------------
# Dependency check
# -------------------------
for dep in bash curl jq unzip sha512sum; do
  command -v "$dep" &>/dev/null || fatal "Missing dependency: $dep"
done

# -------------------------
# Uninstall logic
# -------------------------
if [[ "${1:-}" == "--uninstall" ]]; then
  [[ -f "$MARKER_FILE" ]] || fatal "No installer marker found — refusing to uninstall"

  info "Uninstalling Widevine CDM"

  rm -f "$SYMLINK"
  rm -rf "$INSTALL_DIR"
  rm -rf "$LICENSE_DIR"

  success "Widevine CDM uninstalled successfully"
  exit 0
fi

# -------------------------
# Detect existing install
# -------------------------
if [[ -f "$MARKER_FILE" ]]; then
  warn "Widevine CDM was previously installed by this installer"
  echo
  echo "Choose an action:"
  echo "  [1] Reinstall"
  echo "  [2] Uninstall"
  echo "  [3] Abort"
  read -rp "Selection [1-3]: " choice

  case "$choice" in
    1) info "Proceeding with reinstall…" ;;
    2) exec "$0" --uninstall ;;
    *) fatal "Aborted by user" ;;
  esac
fi

# -------------------------
# Fetch Widevine metadata
# -------------------------
info "Fetching Widevine metadata from Mozilla"

WIDEVINE_JSON="$(curl -fsSL \
  https://raw.githubusercontent.com/mozilla-firefox/firefox/refs/heads/main/toolkit/content/gmp-sources/widevinecdm.json
)"

HASH_FUNCTION="$(jq -r '.hashFunction' <<<"$WIDEVINE_JSON")"
SOURCE_URL="$(jq -r '.vendors["gmp-widevinecdm"].platforms["Linux_x86_64-gcc3"].mirrorUrls[0]' <<<"$WIDEVINE_JSON")"
HASH_VALUE="$(jq -r '.vendors["gmp-widevinecdm"].platforms["Linux_x86_64-gcc3"].hashValue' <<<"$WIDEVINE_JSON")"

[[ "$HASH_FUNCTION" == "sha512" ]] \
  || fatal "Unsupported hash function: $HASH_FUNCTION (expected sha512)"

[[ -n "$SOURCE_URL" && "$SOURCE_URL" != "null" ]] \
  || fatal "Failed to retrieve Widevine URL"

[[ -n "$HASH_VALUE" && "$HASH_VALUE" != "null" ]] \
  || fatal "Failed to retrieve Widevine hash value"

success "Metadata validated (sha512)"

# -------------------------
# Temporary workspace
# -------------------------
TMP_DIR="$(mktemp -d)"
CRX_FILE="$TMP_DIR/$(basename "$SOURCE_URL")"

# -------------------------
# Download
# -------------------------
info "Downloading Widevine CDM"
curl -fL --progress-bar -o "$CRX_FILE" "$SOURCE_URL"
[[ -s "$CRX_FILE" ]] || fatal "Download failed"

# -------------------------
# Verify checksum
# -------------------------
info "Verifying SHA-512 checksum"
echo "${HASH_VALUE}  ${CRX_FILE}" | sha512sum -c -

# -------------------------
# Extract
# -------------------------
info "Extracting Widevine CDM"
unzip -q "$CRX_FILE" -d "$TMP_DIR" 2>/dev/null || true

# -------------------------
# Validate files
# -------------------------
WIDEVINE_SO="$TMP_DIR/_platform_specific/linux_x64/libwidevinecdm.so"
MANIFEST="$TMP_DIR/manifest.json"
LICENSE="$TMP_DIR/LICENSE"

for file in "$WIDEVINE_SO" "$MANIFEST" "$LICENSE"; do
  [[ -f "$file" ]] || fatal "Missing file: $(basename "$file")"
done

# -------------------------
# Install
# -------------------------
info "Installing Widevine CDM"

mkdir -p "$INSTALL_DIR/_platform_specific/linux_x64" "$LICENSE_DIR"

install -Dm755 "$WIDEVINE_SO" \
  "$INSTALL_DIR/_platform_specific/linux_x64/libwidevinecdm.so"

install -Dm644 "$MANIFEST" \
  "$INSTALL_DIR/manifest.json"

install -Dm644 "$LICENSE" \
  "$INSTALL_DIR/LICENSE"

install -Dm644 "$LICENSE" \
  "$LICENSE_DIR/LICENSE"

ln -sf \
  "$INSTALL_DIR/_platform_specific/linux_x64/libwidevinecdm.so" \
  "$SYMLINK"

# -------------------------
# Marker file (LAST STEP)
# -------------------------
cat >"$MARKER_FILE" <<EOF
Installed by chromium-widevine installer
Source: Mozilla Widevine CDM
EOF

success "Widevine CDM installed successfully"

