"""Home page renders the search form."""

from __future__ import annotations

from playwright.sync_api import Page

from support import Gxa


def test_home(page: Page, gxa: Gxa) -> None:
    gxa.open(page, "/home")
    assert "Home" in page.title()
    page.locator("#search-atlas").wait_for(state="visible")
    page.locator("#home-search-gene-query-input").wait_for(state="visible")
    page.locator("#experiments-summary-panel").wait_for(state="attached")
