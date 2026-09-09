"""Tavern callbacks for the GXA JSON journey (save + shape checks)."""

from __future__ import annotations

from typing import Any


def save_accession(response: Any) -> dict[str, str]:
    """Pick a public experiment accession from GET /json/experiments."""
    body = response.json()
    experiments = body.get("experiments") or []
    assert experiments, "GET /json/experiments returned an empty experiments list"
    baseline = next(
        (
            item
            for item in experiments
            if item.get("rawExperimentType") == "RNASEQ_MRNA_BASELINE"
        ),
        experiments[0],
    )
    accession = baseline.get("experimentAccession") or ""
    assert accession, "experimentAccession missing on selected experiment"
    return {"accession": accession}


def save_gene_id(response: Any) -> dict[str, str]:
    """Pick a gene id from GET /json/experiments/{accession} profiles.rows."""
    body = response.json()
    rows = (body.get("profiles") or {}).get("rows") or []
    assert rows, "experiment JSON has no profiles.rows to search / gene-page"
    gene_id = rows[0].get("id") or ""
    assert gene_id, "profiles.rows[0] has no id"
    return {"gene_id": gene_id}


def assert_search_facets(response: Any) -> None:
    """GET /json/search/baseline_facets is a non-empty JSON object."""
    body = response.json()
    assert isinstance(body, dict), f"baseline_facets: expected object, got {type(body)}"
    assert body, "GET /json/search/baseline_facets returned an empty object"


def assert_bioentity(response: Any) -> None:
    """GET /json/bioentity-information/{geneId} has bioentityProperties."""
    body = response.json()
    props = body.get("bioentityProperties") or []
    assert props, "bioentityProperties missing or empty"


def assert_non_empty_array(response: Any) -> None:
    """Response JSON is a non-empty array (e.g. GET /json/suggestions)."""
    body = response.json()
    assert isinstance(body, list), f"expected array, got {type(body)}"
    assert body, "expected a non-empty array"
