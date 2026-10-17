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

    def expect_search_results(self, page: Page, example: str) -> None:
        """An example search showed results for that query."""
        assert "Search results" in page.title(), f"{example} title was {page.title()!r} at {page.url}"
        assert page.locator("h4", has_text="Error:").count() == 0, f"{example} rendered the GXA error page"
        empty = page.get_by_text("Sorry, we could not find results matching your search criteria")
        assert empty.count() == 0, f"{example} returned no results ({page.url})"

        # A single gene or gene-set query redirects to /genes/ or /genesets/.
        core = example.split(" (", 1)[0]
        if "/genes/" in page.url or "/genesets/" in page.url:
            name = page.locator(".gxaBioentityName")
            name.wait_for(state="visible")
            assert name.inner_text().strip(), f"{example} gene page had an empty name"
            if "/genesets/" in page.url:
                assert core in page.url or core in name.inner_text(), (
                    f"{example} geneset page did not mention {core}"
                )
                if " (" in example:
                    label = example.split(" (", 1)[1].rstrip(")")
                    description = page.locator(".gxaBioentityDescription")
                    description.wait_for(state="visible")
                    assert label in description.inner_text(), (
                        f"{example} geneset description was {description.inner_text()!r}"
                    )
        else:
            term = page.locator(".searchterm")
            term.wait_for(state="visible")
            assert core in term.inner_text(), f"{example} search term was {term.inner_text()!r}"

        self._expect_expression_results(page, example)
        self.dismiss_banner(page)

    def _expect_expression_results(self, page: Page, example: str) -> None:
        """Baseline draws a heatmap; differential-only queries render a results table.

        A gene-set page can resolve with an empty facet tree, so the card is the result.
        """
        if page.locator("#differential.is-active").count() and not page.locator("#baseline.is-active").count():
            page.locator("#gxaDifferentialTab .gxaDifferentialResultsTable tbody tr").first.wait_for(
                state="visible", timeout=120_000
            )
            return

        # The facet tree is in the first React paint. An empty tree has the heading and no species.
        page.locator("#gxaBaselineTab h4", has_text="Filter your results").wait_for(
            state="visible", timeout=60_000
        )
        if page.locator("#gxaBaselineTab h5").count() == 0:
            assert "/genes/" in page.url or "/genesets/" in page.url, (
                f"{example} baseline tab had no facets at {page.url}"
            )
            return
        page.locator("#baseline.is-active .highcharts-point").first.wait_for(
            state="visible", timeout=120_000
        )

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
