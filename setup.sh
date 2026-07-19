#!/usr/bin/env bash
# setup.sh — Install dependencies for the browse plugin
#
# Usage:
#   bash ~/.hermes/plugins/web/browse/setup.sh
#
# Installs:
#   - Obscura (if not present)
#   - web2md + Playwright (if not present)
#   - System Chromium (if not present)
#   - The browse wrapper script at ~/.hermes/scripts/browse
#   - The ddgs Python package (for search pairing)
#
# Idempotent — safe to run multiple times.

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}=== Browse Plugin Setup ===${NC}"
echo ""

# --- Obscura ---
if command -v obscura &>/dev/null; then
    echo -e "  ${GREEN}✓${NC} Obscura: $(which obscura)"
else
    echo -e "  ${YELLOW}→${NC} Installing Obscura..."
    if command -v cargo &>/dev/null; then
        cargo install obscura 2>&1 | tail -3
        echo -e "  ${GREEN}✓${NC} Obscura installed"
    else
        echo -e "  ${RED}✗${NC} Cargo not found — install Rust first: curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh"
        echo "     Then re-run this script."
        exit 1
    fi
fi

# --- System Chromium ---
CHROMIUM_PATH=""
if [ -f /snap/chromium/current/usr/lib/chromium-browser/chrome ]; then
    CHROMIUM_PATH=/snap/chromium/current/usr/lib/chromium-browser/chrome
    echo -e "  ${GREEN}✓${NC} Chromium (snap): $CHROMIUM_PATH"
elif command -v chromium-browser &>/dev/null; then
    CHROMIUM_PATH=$(which chromium-browser)
    echo -e "  ${GREEN}✓${NC} Chromium (apt): $CHROMIUM_PATH"
elif command -v chromium &>/dev/null; then
    CHROMIUM_PATH=$(which chromium)
    echo -e "  ${GREEN}✓${NC} Chromium: $CHROMIUM_PATH"
else
    echo -e "  ${YELLOW}→${NC} Installing Chromium via snap..."
    if command -v snap &>/dev/null; then
        sudo snap install chromium 2>&1 | tail -3
        CHROMIUM_PATH=/snap/chromium/current/usr/lib/chromium-browser/chrome
        echo -e "  ${GREEN}✓${NC} Chromium installed"
    else
        echo -e "  ${RED}✗${NC} Snap not available — install Chromium manually"
        echo "     sudo apt install -y chromium-browser"
        exit 1
    fi
fi

# --- Playwright + web2md ---
PYTHON_BIN=""
for py in python3.14 python3.13 python3.12 python3.11 python3; do
    if command -v "$py" &>/dev/null; then
        PYTHON_BIN="$py"
        break
    fi
done

if [ -z "$PYTHON_BIN" ]; then
    echo -e "  ${RED}✗${NC} No Python 3 found"
    exit 1
fi

echo -e "  ${GREEN}✓${NC} Python: $PYTHON_BIN ($($PYTHON_BIN --version))"

# Install playwright
if ! $PYTHON_BIN -c "import playwright" 2>/dev/null; then
    echo -e "  ${YELLOW}→${NC} Installing playwright..."
    $PYTHON_BIN -m pip install --user playwright 2>&1 | tail -3
    echo -e "  ${GREEN}✓${NC} Playwright installed"
else
    echo -e "  ${GREEN}✓${NC} Playwright already installed"
fi

# Install web2md
if ! $PYTHON_BIN -c "import web2md" 2>/dev/null; then
    echo -e "  ${YELLOW}→${NC} Installing web2md..."
    $PYTHON_BIN -m pip install --user web2md 2>&1 | tail -3
    echo -e "  ${GREEN}✓${NC} web2md installed"
else
    echo -e "  ${GREEN}✓${NC} web2md already installed"
fi

# Patch web2md to use system Chromium
WEB2MD_CLI=$($PYTHON_BIN -c "import web2md; import os; print(os.path.join(os.path.dirname(web2md.__file__), 'cli.py'))" 2>/dev/null)
if [ -n "$WEB2MD_CLI" ] && [ -f "$WEB2MD_CLI" ]; then
    # Fix shebang if needed
    SHEBANG=$(head -1 "$WEB2MD_CLI" 2>/dev/null || echo "")
    if [[ "$SHEBANG" != *"$PYTHON_BIN"* ]]; then
        echo -e "  ${YELLOW}→${NC} Patching web2md shebang to $PYTHON_BIN..."
        sudo sed -i "1s|#!/usr/bin/python3.*|#!$(which $PYTHON_BIN)|" "$WEB2MD_CLI"
    fi

    # Add executable_path if not present
    if ! grep -q "executable_path" "$WEB2MD_CLI" 2>/dev/null; then
        echo -e "  ${YELLOW}→${NC} Patching web2md to use system Chromium..."
        # Add executable_path to PLAYWRIGHT_CONFIG
        sed -i "s|\"sleep_after_load\": 2,.*|\"sleep_after_load\": 2,\n    \"executable_path\": \"$CHROMIUM_PATH\"|" "$WEB2MD_CLI"
        # Update launch call
        sed -i "s|p.chromium.launch(headless=PLAYWRIGHT_CONFIG\[\"headless\"\])|p.chromium.launch(\n                headless=PLAYWRIGHT_CONFIG[\"headless\"],\n                executable_path=PLAYWRIGHT_CONFIG.get(\"executable_path\")\n            )|" "$WEB2MD_CLI"
    fi
    echo -e "  ${GREEN}✓${NC} web2md patched for system Chromium"
fi

# --- ddgs package (for search pairing) ---
if ! $PYTHON_BIN -c "import ddgs" 2>/dev/null; then
    echo -e "  ${YELLOW}→${NC} Installing ddgs (for search pairing)..."
    $PYTHON_BIN -m pip install --user ddgs 2>&1 | tail -3
    echo -e "  ${GREEN}✓${NC} ddgs installed"
else
    echo -e "  ${GREEN}✓${NC} ddgs already installed"
fi

# --- Browse wrapper script ---
BROWSE_SCRIPT="$HOME/.hermes/scripts/browse"
mkdir -p "$(dirname "$BROWSE_SCRIPT")"

cat > "$BROWSE_SCRIPT" << 'BROWSE_EOF'
#!/usr/bin/env bash
# ~/.hermes/scripts/browse
# Unified browsing wrapper — picks the right tool for the job.
#
# Usage:
#   browse <url>                    Fast fetch (Obscura, plain text)
#   browse --js <url>               Full JS render (web2md, Playwright)
#   browse --raw <url>              Raw HTTP response (no JS, no render)

set -euo pipefail

CHROMIUM_PATH="${CHROMIUM_PATH:-/snap/chromium/current/usr/lib/chromium-browser/chrome}"
UA="Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"

MODE="fast"
URL=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --js) MODE="js"; shift ;;
        --raw) MODE="raw"; shift ;;
        *) URL="$1"; shift ;;
    esac
done

if [[ -z "$URL" ]]; then
    echo "Usage: browse [--js|--raw] <url>" >&2
    exit 1
fi

# --- Raw HTTP (no browser, no JS) ---
if [[ "$MODE" == "raw" ]]; then
    exec obscura fetch \
        --dump original \
        --wait 0 \
        --user-agent "$UA" \
        "$URL" 2>/dev/null
fi

# --- Fast fetch (Obscura, text dump) ---
if [[ "$MODE" == "fast" ]]; then
    exec obscura fetch \
        --dump text \
        --wait 0 \
        --stealth \
        --user-agent "$UA" \
        "$URL" 2>/dev/null
fi

# --- Full JS render (web2md via Playwright) ---
if [[ "$MODE" == "js" ]]; then
    TMPDIR=$(mktemp -d /tmp/browse-js-XXXXXX)
    web2md "$URL" "$TMPDIR" --depth 0 --count 1 >/dev/null 2>&1
    MD_FILE=$(find "$TMPDIR" -name "*.md" -type f 2>/dev/null | head -1)
    if [[ -n "$MD_FILE" ]]; then
        cat "$MD_FILE"
    else
        echo "[browse] No markdown output generated for $URL" >&2
        exit 1
    fi
    rm -rf "$TMPDIR"
fi
BROWSE_EOF

chmod +x "$BROWSE_SCRIPT"
echo -e "  ${GREEN}✓${NC} Browse wrapper: $BROWSE_SCRIPT"

echo ""
echo -e "${GREEN}=== Setup complete ===${NC}"
echo ""
echo "Next steps:"
echo "  1. Enable the plugin:  hermes config set plugins.enabled '[\"browse\"]'"
echo "  2. Set as extract:     hermes config set web.extract_backend browse"
echo "  3. Set ddgs for search: hermes config set web.search_backend ddgs"
echo "  4. Restart Hermes or start a new session"
