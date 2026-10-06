"""Playwright fixtures for live GXA scenarios.

Scenarios are pytest modules under tests/browser/scenarios/. Add a file named
test_<name>.py; every test_* function in it is collected. Use `page` and `gxa`.
"""

from __future__ import annotations

import os
from pathlib import Path

import pytest

from support import Gxa


@pytest.fixture
def output_path(pytestconfig: pytest.Config, request: pytest.FixtureRequest) -> str:
    """Short artifact folder. Leave the pytest node id intact so the Testing panel can list tests."""
    output_dir = Path(pytestconfig.getoption("--output")).resolve()
    return str(output_dir / _report_name(request.node))


def _report_name(item: pytest.Item) -> str:
    name = (getattr(item, "originalname", None) or item.name).removeprefix("test_")
    name = name.replace("_", "-")
    callspec = getattr(item, "callspec", None)
    if callspec is not None:
        extras = [
            str(value).lower()
            for key, value in callspec.params.items()
            if key != "browser_name"
        ]
        if extras:
            name = "-".join([name, *extras])
    return name


@pytest.fixture(scope="session")
def gxa() -> Gxa:
    url = os.environ.get("GXA_SYSTEM_BASE", "").rstrip("/")
    if not url:
        pytest.skip(
            "Set GXA_SYSTEM_BASE (e.g. http://host:port/gxa) or run task test:browser ENV=staging"
        )
    return Gxa(url)
