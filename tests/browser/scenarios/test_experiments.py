"""Experiments catalogue page renders."""

from __future__ import annotations

from playwright.sync_api import Page

from support import Gxa


def test_experiments_list(page: Page, gxa: Gxa) -> None:
    gxa.open(page, "/experiments")
    assert "Experiments" in page.title()
    page.locator("#experiments").wait_for(state="attached")
