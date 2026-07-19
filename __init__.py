"""Browse-script web search plugin — user-installed, survives updates.

Backed by ``~/.hermes/scripts/browse`` which wraps Obscura (fast text),
web2md/Playwright (JS-heavy pages), and DuckDuckGo Lite (search).
No API key required.

Provides:
  - Web extract provider (browse) — register_web_search_provider
  - CLI command: hermes browse setup — installs dependencies
"""

from __future__ import annotations

import logging
import os
import subprocess
import sys

logger = logging.getLogger(__name__)

_SETUP_SCRIPT = os.path.join(os.path.dirname(__file__), "setup.sh")

# Import provider — works both in-repo (plugins/web/browse/) and standalone
try:
    from plugins.web.browse.provider import BrowseWebSearchProvider
except ImportError:
    from provider import BrowseWebSearchProvider  # standalone repo


def register(ctx) -> None:
    """Register the browse-script provider and CLI setup command."""
    ctx.register_web_search_provider(BrowseWebSearchProvider())
    _register_cli(ctx)
    logger.info("Browse plugin registered: extract provider + hermes browse setup")


def _register_cli(ctx) -> None:
    """Register ``hermes browse setup`` CLI subcommand."""

    def _build_browse_parser(subparsers, *, cmd_browse=None):
        browse_parser = subparsers.add_parser(
            "browse",
            help="Browse plugin — web content extraction",
        )
        browse_sub = browse_parser.add_subparsers(dest="browse_action")

        setup_parser = browse_sub.add_parser(
            "setup",
            help="Install browse plugin dependencies (Obscura, Chromium, Playwright, web2md, ddgs)",
        )
        setup_parser.set_defaults(func=_cmd_browse_setup)

    def _cmd_browse_setup(args):
        """Run the browse plugin setup script."""
        if not os.path.isfile(_SETUP_SCRIPT):
            print(f"Setup script not found: {_SETUP_SCRIPT}", file=sys.stderr)
            sys.exit(1)
        result = subprocess.run(
            ["bash", _SETUP_SCRIPT],
            cwd=os.path.dirname(_SETUP_SCRIPT),
        )
        sys.exit(result.returncode)

    ctx.register_cli_command(
        name="browse",
        help="Browse plugin — web content extraction",
        setup_fn=_build_browse_parser,
        handler_fn=_cmd_browse_setup,
        description="Install and manage the browse web extraction plugin",
    )
