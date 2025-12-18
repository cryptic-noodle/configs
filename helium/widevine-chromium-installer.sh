#!/usr/bin/env bash
set -Eeuo pipefail

# ─────────────────────────────────────────────────────────────
#  Chromium Widevine CDM Installer
#  - Mozilla-verified (SHA-512)
#  - Safe sudo re-exec (file + curl|bash)
#  - Guaranteed cleanup
#  - Marker-based uninstall
# ─────────────────────────────────────────────────────────────

# -------------------------
# Configuration
# -------------------------
INSTALL_DIR="/usr/lib/chromium/WidevineCdm"
LICENSE_DIR="/usr/share/licenses/chromium-widevine"
SYMLINK="/usr/lib/chromium/libwidevinecdm.so"
MARKER_FILE="$INSTALL_DIR/.installed-by-widevine-installer"

# -------------------------
# Colors & logging
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
# Cleanup
# -------------------------
cleanup() {
  local ec=$?
  [[ -n "${TMP_DIR:-}" && -d "$TMP_DIR" ]] && rm -rf "$TMP_DIR"
  (( ec != 0 )) && echo -e "${RED}✖${RESET} Script failed (exit code $ec)" >&2
  exit "$ec"
}
trap cleanup EXIT

# -------------------------
# Root check
# -------------------------
if [[ $EUID -ne 0 ]]; then
  warn "Root privileges required"
  info "Re-running with sudo…"

  if [[ -t 0 ]]; then
    # Script executed from a file
    SCRIPT_PATH="$(readlink -f "$0" 2>/dev/null || realpath "$0")"
    exec sudo --preserve-env=PATH bash "$SCRIPT_PATH" "$@"
  else
    # Script executed via pipe (curl | bash, wget | bash)
    TMP_SCRIPT="$(mktemp)"
    cat >"$TMP_SCRIPT"
    exec sudo --preserve-env=PATH bash "$TMP_SCRIPT" "$@"
  fi
fi


# -------------------------
# Dependencies
# -------------------------
for dep in bash curl jq unzip sha512sum; do
  command -v "$dep" &>/dev/null || fatal "Missing dependency: $dep"
done

# -------------------------
# Uninstall mode
# -------------------------
if [[ "${1:-}" == "--uninstall" ]]; then
  [[ -f "$MARKER_FILE" ]] || fatal "Installer marker not found — refusing uninstall"

  info "Uninstalling Widevine CDM"
  rm -f "$SYMLINK"
  rm -rf "$INSTALL_DIR" "$LICENSE_DIR"

  success "Widevine CDM uninstalled"
  exit 0
fi

# -------------------------
# Existing install detection
# -------------------------
if [[ -f "$MARKER_FILE" ]]; then
  warn "Widevine CDM was installed by this installer"
  echo
  echo "Choose an action:"
  echo "  [1] Reinstall"
  echo "  [2] Uninstall"
  echo "  [3] Abort"
  read -rp "Selection [1-3]: " choice

  case "$choice" in
    1) info "Reinstalling…" ;;
    2) exec "$0" --uninstall ;;
    *) fatal "Aborted by user" ;;
  esac
fi

# -------------------------
# Fetch metadata
# -------------------------
info "Fetching Widevine metadata from Mozilla"

WIDEVINE_JSON="$(curl -fsSL \
  https://raw.githubusercontent.com/mozilla-firefox/firefox/refs/heads/main/toolkit/content/gmp-sources/widevinecdm.json
)"

HASH_FUNCTION="$(jq -r '.hashFunction' <<<"$WIDEVINE_JSON")"
SOURCE_URL="$(jq -r '.vendors["gmp-widevinecdm"].platforms["Linux_x86_64-gcc3"].mirrorUrls[0]' <<<"$WIDEVINE_JSON")"
HASH_VALUE="$(jq -r '.vendors["gmp-widevinecdm"].platforms["Linux_x86_64-gcc3"].hashValue' <<<"$WIDEVINE_JSON")"

[[ "$HASH_FUNCTION" == "sha512" ]] || fatal "Unsupported hash function: $HASH_FUNCTION"
[[ -n "$SOURCE_URL" && "$SOURCE_URL" != "null" ]] || fatal "Failed to retrieve download URL"
[[ -n "$HASH_VALUE" && "$HASH_VALUE" != "null" ]] || fatal "Failed to retrieve checksum"

success "Metadata validated (SHA-512)"

# -------------------------
# Workspace
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
info "Verifying checksum"
echo "${HASH_VALUE}  ${CRX_FILE}" | sha512sum -c -

# -------------------------
# Extract
# -------------------------
info "Extracting Widevine CDM"
# CRX3 files contain a header; unzip warns but extracts correctly
unzip -q "$CRX_FILE" -d "$TMP_DIR" 2>/dev/null || true

# -------------------------
# Validate files
# -------------------------
WIDEVINE_SO="$TMP_DIR/_platform_specific/linux_x64/libwidevinecdm.so"
MANIFEST="$TMP_DIR/manifest.json"
LICENSE="$TMP_DIR/LICENSE"

for f in "$WIDEVINE_SO" "$MANIFEST" "$LICENSE"; do
  [[ -f "$f" ]] || fatal "Missing file: $(basename "$f")"
done

# -------------------------
# Install
# -------------------------
info "Installing Widevine CDM"

mkdir -p "$INSTALL_DIR/_platform_specific/linux_x64" "$LICENSE_DIR"

install -Dm755 "$WIDEVINE_SO" \
  "$INSTALL_DIR/_platform_specific/linux_x64/libwidevinecdm.so"

install -Dm644 "$MANIFEST" "$INSTALL_DIR/manifest.json"
install -Dm644 "$LICENSE" "$INSTALL_DIR/LICENSE"
install -Dm644 "$LICENSE" "$LICENSE_DIR/LICENSE"

ln -sf \
  "$INSTALL_DIR/_platform_specific/linux_x64/libwidevinecdm.so" \
  "$SYMLINK"

# -------------------------
# Marker
# -------------------------
cat >"$MARKER_FILE" <<EOF
Installed by chromium-widevine installer
Source: Mozilla Widevine CDM
EOF

success "Widevine CDM installed successfully"
