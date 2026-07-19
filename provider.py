"""Browse-script web extract provider — user plugin.

Wraps the ``~/.hermes/scripts/browse`` shell script as a Hermes web extract
provider. Lives in ``~/.hermes/plugins/web/browse/`` so it survives Hermes
updates. Provides content extraction via Obscura (fast text dump) with
web2md/Playwright fallback for JS-heavy pages.

Search is handled by the built-in ``ddgs`` provider (DuckDuckGo via the
``ddgs`` Python package). This plugin is extract-only.

Enable with: ``hermes config set plugins.enabled '[\"browse\"]'``
Then set:    ``hermes config set web.extract_backend browse``
"""

from __future__ import annotations

import logging
import os
import subprocess
from typing import Any, Dict, List

from agent.web_search_provider import WebSearchProvider

logger = logging.getLogger(__name__)

_BROWSE_SCRIPT = os.path.expanduser("~/.hermes/scripts/browse")
_EXTRACT_TIMEOUT = 30
_JS_EXTRACT_TIMEOUT = 45


def _run_browse(*args: str, timeout: int = _EXTRACT_TIMEOUT) -> str:
    """Run the browse script and return stdout, or raise on failure."""
    result = subprocess.run(
        [_BROWSE_SCRIPT, *args],
        capture_output=True,
        text=True,
        timeout=timeout,
    )
    if result.returncode != 0:
        stderr = result.stderr.strip()
        raise RuntimeError(stderr or f"browse exited {result.returncode}")
    return result.stdout


class BrowseWebSearchProvider(WebSearchProvider):
    """Web extract provider backed by the ``browse`` shell script.

    Extract: Obscura fast text dump, with web2md/Playwright fallback for JS pages.
    Search: not provided — use the built-in ``ddgs`` provider instead.
    """

    @property
    def name(self) -> str:
        return "browse"

    @property
    def display_name(self) -> str:
        return "Browse Script (Obscura + web2md extract)"

    def is_available(self) -> bool:
        """Return True when the browse script exists and is executable."""
        return os.path.isfile(_BROWSE_SCRIPT) and os.access(_BROWSE_SCRIPT, os.X_OK)

    def supports_search(self) -> bool:
        return False

    def supports_extract(self) -> bool:
        return True

    def extract(self, urls: List[str], **kwargs: Any) -> Any:
        """Extract content from URLs via the browse script.

        Tries fast Obscura text dump first; falls back to web2md/Playwright
        for JS-heavy pages. Returns a list of result dicts matching the
        legacy contract.
        """
        results = []
        for url in urls:
            try:
                # Fast path: Obscura text dump
                content = _run_browse(url, timeout=_EXTRACT_TIMEOUT)
                if not content.strip() or len(content.strip()) < 50:
                    # Fallback: full JS render via web2md
                    logger.info("browse extract: fast path empty for %s, trying JS", url)
                    content = _run_browse("--js", url, timeout=_JS_EXTRACT_TIMEOUT)

                results.append(
                    {
                        "url": url,
                        "title": "",
                        "content": content.strip(),
                        "raw_content": content.strip(),
                        "metadata": {"provider": "browse-script"},
                    }
                )
            except subprocess.TimeoutExpired:
                logger.warning("browse extract timed out for %s", url)
                results.append(
                    {
                        "url": url,
                        "title": "",
                        "content": "",
                        "raw_content": "",
                        "metadata": {"error": "timeout"},
                    }
                )
            except Exception as exc:
                logger.warning("browse extract error for %s: %s", url, exc)
                results.append(
                    {
                        "url": url,
                        "title": "",
                        "content": "",
                        "raw_content": "",
                        "metadata": {"error": str(exc)},
                    }
                )

        return {"success": True, "data": results}

    def get_setup_schema(self) -> Dict[str, Any]:
        return {
            "name": "Browse Script (Obscura + web2md extract)",
            "badge": "free · no key · extract only",
            "tag": (
                "Uses the local browse script (~/.hermes/scripts/browse) — "
                "Obscura for fast text extract, web2md/Playwright for JS-heavy "
                "pages. No API key needed. Pair with ddgs for search."
            ),
            "env_vars": [],
        }
