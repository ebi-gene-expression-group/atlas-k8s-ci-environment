"""Unit tests for JUnit name numbering (no live GXA)."""

from __future__ import annotations

from pathlib import Path

from junit_order import number_junit_testcases_in_document_order


def test_numbers_testcases_in_document_order(tmp_path: Path) -> None:
    xml = tmp_path / "junit.xml"
    xml.write_text(
        '<?xml version="1.0" encoding="utf-8"?>'
        '<testsuites name="pytest tests">'
        '<testsuite name="pytest" tests="3">'
        '<testcase classname="helpers" name="test_assert_last" time="0.1" />'
        '<testcase classname="journey" name="gxa_json_journey" time="1.0" />'
        '<testcase classname="helpers" name="test_save_first" time="0.1" />'
        "</testsuite></testsuites>",
        encoding="utf-8",
    )
    number_junit_testcases_in_document_order(xml)
    text = xml.read_text(encoding="utf-8")
    assert 'name="01_test_assert_last"' in text
    assert 'name="02_gxa_json_journey"' in text
    assert 'name="03_test_save_first"' in text


def test_does_not_double_prefix(tmp_path: Path) -> None:
    xml = tmp_path / "junit.xml"
    xml.write_text(
        '<?xml version="1.0" encoding="utf-8"?>'
        '<testsuite name="pytest" tests="1">'
        '<testcase classname="helpers" name="01_already" time="0.1" />'
        "</testsuite>",
        encoding="utf-8",
    )
    number_junit_testcases_in_document_order(xml)
    assert 'name="01_already"' in xml.read_text(encoding="utf-8")
    assert "01_01_" not in xml.read_text(encoding="utf-8")
