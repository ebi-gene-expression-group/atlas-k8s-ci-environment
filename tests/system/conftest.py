"""Skip live GXA system tests unless GXA_SYSTEM_BASE is set."""

from __future__ import annotations

import os
from collections.abc import MutableMapping
from pathlib import Path
from typing import Any

import pytest

from junit_order import number_junit_testcases_in_document_order

REQUIRED_ENV = ("GXA_SYSTEM_BASE",)
_JOURNEY_KEYS = ("accession", "gene_id")
_JOURNEY_REQUIRED = {
    "one_experiment": ("accession",),
    "search": ("gene_id",),
    "gene": ("gene_id",),
}
_journey: dict[str, str] = {}


def pytest_collection_modifyitems(
    config: pytest.Config, items: list[pytest.Item]
) -> None:
    missing = [name for name in REQUIRED_ENV if not os.environ.get(name)]
    if not missing:
        return
    reason = (
        "Missing env for system tests: "
        + ", ".join(missing)
        + " (e.g. http://host:port/gxa, no trailing slash)"
    )
    skip_marker = pytest.mark.skip(reason=reason)
    for item in items:
        path = str(getattr(item, "path", "") or getattr(item, "fspath", ""))
        if path.endswith(".yaml") or path.endswith(".yml"):
            item.add_marker(skip_marker)


def pytest_tavern_beta_before_every_test_run(
    test_dict: dict, variables: dict
) -> None:
    """Carry accession/gene_id across one-stage Tavern tests (Jenkins JUnit per stage)."""
    variables.update(_journey)
    missing = [
        key
        for key in _JOURNEY_REQUIRED.get(test_dict.get("test_name") or "", ())
        if not variables.get(key)
    ]
    if missing:
        pytest.skip("missing " + ", ".join(missing) + " from earlier journey stage")


def pytest_tavern_beta_after_every_test_run(test_dict: dict, variables: dict) -> None:
    for key in _JOURNEY_KEYS:
        value = variables.get(key)
        if value:
            _journey[key] = str(value)


def pytest_tavern_beta_before_every_request(request_args: MutableMapping) -> None:
    print(f"{request_args.get('method', '?')} {request_args.get('url', '')}", flush=True)


def pytest_tavern_beta_after_every_response(expected: Any, response: Any) -> None:
    print(f"status {getattr(response, 'status_code', '?')}", flush=True)


@pytest.hookimpl(hookwrapper=True)
def pytest_sessionfinish(session: pytest.Session, exitstatus: int) -> object:
    """After pytest writes --junitxml, number cases so Jenkins lists run order."""
    yield
    xmlpath = getattr(session.config.option, "xmlpath", None)
    if xmlpath:
        number_junit_testcases_in_document_order(Path(xmlpath))
