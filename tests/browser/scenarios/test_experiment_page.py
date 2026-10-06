"""Experiment HTML shell for Results and Plots.

Both paths are the same Thymeleaf page; the client uses the URL suffix.
"""

from __future__ import annotations

import pytest
from playwright.sync_api import Page

from support import Gxa


@pytest.mark.parametrize("tab", ["Results", "Plots"])
def test_experiment_tab(page: Page, gxa: Gxa, tab: str) -> None:
    accession = gxa.baseline_accession()
    gxa.open(page, f"/experiments/{accession}/{tab}")
    gxa.expect_experiment(page, accession)
    if not gxa.has_tab(page, tab):
        pytest.skip(f"{accession} has no {tab} tab")
    if tab == "Results":
        gxa.expect_heatmap(page)
