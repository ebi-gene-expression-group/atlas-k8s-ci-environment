"""Shared helpers for GXA browser scenarios."""

from __future__ import annotations

from typing import Any

import httpx
from playwright.sync_api import Page, Response

from helpers import save_accession


class Gxa:
    """Live GXA origin (context path included, no trailing slash)."""

    def __init__(self, base_url: str) -> None:
        self.base_url = base_url.rstrip("/")
        self._accession: str | None = None

    def baseline_accession(self) -> str:
        """Public RNA-seq baseline accession from GET /json/experiments."""
        if self._accession:
            return self._accession
        response = httpx.get(f"{self.base_url}/json/experiments", timeout=60.0)
        response.raise_for_status()
        saved = save_accession(_Json(response.json()))
        self._accession = saved["accession"]
        return self._accession

    def open(self, page: Page, path: str) -> Response:
        """Open a path under the GXA context and fail on an error page."""
        if not path.startswith("/"):
            path = "/" + path
        # Absolute URL: a leading slash on page.goto replaces the /gxa context path.
        url = f"{self.base_url}{path}"
        page.set_default_navigation_timeout(90_000)
        page.set_default_timeout(30_000)
        response = page.goto(url, wait_until="domcontentloaded")
        assert response is not None, f"no response for {url}"
        assert response.ok, f"{url} returned HTTP {response.status}"
        error = page.locator("h4", has_text="Error:")
        assert error.count() == 0, f"{url} rendered the GXA error page"
        return response

    def expect_experiment(self, page: Page, accession: str) -> None:
        """Server-rendered experiment shell for this accession."""
        assert accession in page.url, f"{accession} missing from {page.url}"
        page.locator("#experimentDescription").wait_for(state="visible")
        page.locator("#experiment-page").wait_for(state="attached")
        assert accession in page.content(), f"{accession} missing from experiment page HTML"

    def expect_heatmap(self, page: Page) -> None:
        """Results tab heatmap has drawn (Highcharts), not only the empty mount point."""
        chart = page.locator("#experiment-page .gxaHeatmapContainer .highcharts-container")
        chart.first.wait_for(state="visible", timeout=90_000)
        page.locator("#experiment-page .gxaHeatmapContainer .highcharts-point").first.wait_for(
            state="visible", timeout=90_000
        )
        self.dismiss_banner(page)

    def dismiss_banner(self, page: Page) -> None:
        banner = page.get_by_text("I agree, dismiss this banner")
        if banner.count():
            banner.first.click()

    def has_tab(self, page: Page, tab: str) -> bool:
        page.locator("#experiment-page .tabs-title").first.wait_for(state="visible", timeout=60_000)
        return page.locator("#experiment-page .tabs-title", has_text=tab).count() > 0


class _Json:
    def __init__(self, payload: Any) -> None:
        self._payload = payload

    def json(self) -> Any:
        return self._payload
