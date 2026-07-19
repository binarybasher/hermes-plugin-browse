# browse - Web Content Extraction Plugin

Extracts web page content using a two-tier approach: fast Obscura text dump
for static pages, with automatic web2md/Playwright fallback for JavaScript-heavy
pages. No API key required.

Pair with the built-in `ddgs` provider for search.

## What problem it solves

Hermes's built-in web extract backends (Firecrawl, Tavily, SearXNG) all require
API keys or external services. This plugin uses only local tools - Obscura
(a lightweight headless browser) and web2md (Playwright + system Chromium) -
to extract content from any URL without third-party dependencies.

It also solves the bot-blocking problem: web2md uses a real Chromium browser
via Playwright with proper Chrome 131 Linux headers, avoiding the CAPTCHA
walls that block headless browsers on Google, DuckDuckGo, and other sites.

## Dependencies

| Dependency | Version | Purpose |
|-----------|---------|---------|
| Obscura | any | Fast text extraction (static pages) |
| web2md | any | Full JS render via Playwright (SPAs, JS-heavy pages) |
| Playwright | ≥1.48 | Browser automation (used by web2md) |
| Chromium | ≥131 | System browser (snap or apt) |
| Python | ≥3.14 | web2md runtime |
| `~/.hermes/scripts/browse` | - | Wrapper script (included) |

## Installation

```bash
# 1. Install the plugin
hermes plugins install binarybasher/hermes-plugin-browse --enable

# 2. Run the setup command (installs Obscura, Chromium, Playwright, web2md, ddgs)
hermes browse setup

# 3. Set as extract backend
hermes config set web.extract_backend browse

# 4. (Optional) Set ddgs for search
hermes config set web.search_backend ddgs
```

Or install manually:

```bash
# 1. Clone into plugins directory
git clone https://github.com/binarybasher/hermes-plugin-browse.git ~/.hermes/plugins/web/browse

# 2. Run setup
bash ~/.hermes/plugins/web/browse/setup.sh

# 3. Enable and configure
hermes config set plugins.enabled '["browse"]'
hermes config set web.extract_backend browse
hermes config set web.search_backend ddgs
```

## How it works

```
web_extract(url) call
  │
  ├─ 1. Obscura fast text dump (30s timeout)
  │     └─ Returns clean text for static pages
  │
  └─ 2. If empty/short: web2md + Playwright (45s timeout)
        └─ Full Chromium render for JS-heavy pages
```

The plugin registers as a `WebSearchProvider` with `supports_extract=True`.
It implements the standard Hermes extract contract:

```json
{
  "success": true,
  "data": [
    {
      "url": "https://example.com",
      "title": "",
      "content": "Extracted text...",
      "raw_content": "Extracted text...",
      "metadata": {"provider": "browse-script"}
    }
  ]
}
```

## Configuration

```yaml
# ~/.hermes/config.yaml
web:
  search_backend: ddgs      # built-in DuckDuckGo search
  extract_backend: browse   # this plugin

plugins:
  enabled: '["browse"]'
```

## Files

```
~/.hermes/plugins/web/browse/
├── plugin.yaml       # Plugin manifest
├── README.md         # This file
├── setup.sh          # Dependency installation
├── __init__.py       # Plugin registration
└── provider.py       # WebSearchProvider implementation
```

## Troubleshooting

**"browse script not found"**: The plugin requires `~/.hermes/scripts/browse`
to exist and be executable. Run `setup.sh` to create it.

**"web2md fails with Playwright error"**: web2md needs the system Chromium
browser. On Ubuntu: `snap install chromium`. The setup script configures
the path automatically.

**"Obscura returns empty"**: Some sites block headless browsers. The plugin
automatically falls back to web2md/Playwright for these cases.

## License

MIT - same as Hermes Agent.
