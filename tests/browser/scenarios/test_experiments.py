"""Experiments catalogue page renders a table of experiments."""

from __future__ import annotations

from playwright.sync_api import Page

from support import Gxa


def test_experiments_list(page: Page, gxa: Gxa) -> None:
    gxa.open(page, "/experiments")
    assert "Experiments" in page.title()
    # The mount point is empty until the catalogue replaces "Loading, please wait".
    page.locator("#experiments a[href*='/experiments/E-']").first.wait_for(
        state="visible", timeout=10_000
    )
