"""Search every example listed for genes and for biological conditions.

The home form prints those examples as links under each query field.
"""

from __future__ import annotations

import pytest
from playwright.sync_api import Page

from support import Gxa

# Examples: line under "Gene / Gene properties" and "Biological conditions".
GENE_EXAMPLES = (
    "REG1B",
    "zinc finger",
    "O14777 (UniProt)",
    "GO:0010468 (regulation of gene expression)",
)
CONDITION_EXAMPLES = (
    "lung",
    "leaf",
    "valproic acid",
    "cancer",
)


def _example_labels(page: Page, input_id: str) -> list[str]:
    column = page.locator(f"#{input_id}").locator(
        "xpath=ancestor::div[contains(@class, 'columns')][1]"
    )
    links = column.get_by_role("link")
    return [links.nth(index).inner_text().strip() for index in range(links.count())]


def test_search_examples_listed(page: Page, gxa: Gxa) -> None:
    gxa.open(page, "/home")
    assert _example_labels(page, "home-search-gene-query-input") == list(GENE_EXAMPLES)
    assert _example_labels(page, "home-search-condition-query-input") == list(CONDITION_EXAMPLES)


@pytest.mark.parametrize("example", GENE_EXAMPLES)
def test_gene_example(page: Page, gxa: Gxa, example: str) -> None:
    _search_example(page, gxa, "home-search-gene-query-input", example)


@pytest.mark.parametrize("example", CONDITION_EXAMPLES)
def test_condition_example(page: Page, gxa: Gxa, example: str) -> None:
    _search_example(page, gxa, "home-search-condition-query-input", example)


def _search_example(page: Page, gxa: Gxa, input_id: str, example: str) -> None:
    gxa.open(page, "/home")
    column = page.locator(f"#{input_id}").locator(
        "xpath=ancestor::div[contains(@class, 'columns')][1]"
    )
    link = column.get_by_role("link", name=example, exact=True)
    page.set_default_navigation_timeout(120_000)
    with page.expect_navigation(wait_until="domcontentloaded", timeout=120_000):
        link.click()
    gxa.expect_search_results(page, example)
