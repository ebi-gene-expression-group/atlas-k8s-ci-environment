"""Number JUnit testcases in document order so Jenkins' A–Z UI matches execution."""

from __future__ import annotations

import re
import xml.etree.ElementTree as ET
from pathlib import Path

_PREFIX = re.compile(r"^\d{2}_")


def number_junit_testcases_in_document_order(xml_path: Path) -> None:
    """Prefix each ``testcase`` name with a zero-padded index from XML order.

    Jenkins' JUnit publisher stores cases in a TreeMap keyed by name, so the UI
    is alphabetical regardless of pytest's report order. Numbering makes that
    sort match execution (pytest writes testcases in run order).
    """
    path = Path(xml_path)
    if not path.is_file():
        return
    tree = ET.parse(path)
    for index, case in enumerate(tree.iter("testcase"), start=1):
        name = case.get("name") or ""
        if _PREFIX.match(name):
            continue
        case.set("name", f"{index:02d}_{name}")
    tree.write(path, encoding="utf-8", xml_declaration=True)
