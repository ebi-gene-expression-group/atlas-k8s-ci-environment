"""Skip live GXA system tests unless GXA_SYSTEM_BASE is set."""

from __future__ import annotations

import os
from pathlib import Path

import pytest

from junit_order import number_junit_testcases_in_document_order

REQUIRED_ENV = ("GXA_SYSTEM_BASE",)


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


@pytest.hookimpl(hookwrapper=True)
def pytest_sessionfinish(session: pytest.Session, exitstatus: int) -> object:
    """After pytest writes --junitxml, number cases so Jenkins lists run order."""
    yield
    xmlpath = getattr(session.config.option, "xmlpath", None)
    if xmlpath:
        number_junit_testcases_in_document_order(Path(xmlpath))
