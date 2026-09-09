"""Unit tests for Tavern helpers (no live GXA)."""

from __future__ import annotations

from types import SimpleNamespace

import pytest

from helpers import (
    assert_bioentity,
    assert_non_empty_array,
    assert_search_facets,
    save_accession,
    save_gene_id,
)


def _json_response(payload: object) -> SimpleNamespace:
    return SimpleNamespace(json=lambda: payload)


def test_save_accession_prefers_rnaseq_baseline() -> None:
    saved = save_accession(
        _json_response(
            {
                "experiments": [
                    {
                        "experimentAccession": "E-MTAB-1",
                        "rawExperimentType": "RNASEQ_MRNA_DIFFERENTIAL",
                    },
                    {
                        "experimentAccession": "E-MTAB-2",
                        "rawExperimentType": "RNASEQ_MRNA_BASELINE",
                    },
                ]
            }
        )
    )
    assert saved == {"accession": "E-MTAB-2"}


def test_save_accession_falls_back_to_first() -> None:
    saved = save_accession(
        _json_response({"experiments": [{"experimentAccession": "E-PROT-1"}]})
    )
    assert saved == {"accession": "E-PROT-1"}


def test_save_accession_rejects_empty_list() -> None:
    with pytest.raises(AssertionError):
        save_accession(_json_response({"experiments": []}))


def test_save_gene_id() -> None:
    saved = save_gene_id(
        _json_response({"profiles": {"rows": [{"id": "ENSG0000001"}]}})
    )
    assert saved == {"gene_id": "ENSG0000001"}


def test_assert_search_facets_and_bioentity() -> None:
    assert_search_facets(_json_response({"homo sapiens": {"ORGANISM_PART": ["liver"]}}))
    assert_bioentity(_json_response({"bioentityProperties": [{"type": "symbol"}]}))


def test_assert_non_empty_array() -> None:
    assert_non_empty_array(_json_response(["REG1A"]))
    with pytest.raises(AssertionError):
        assert_non_empty_array(_json_response([]))
    with pytest.raises(AssertionError):
        assert_non_empty_array(_json_response({"query": "REG"}))
