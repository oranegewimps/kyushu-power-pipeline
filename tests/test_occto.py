"""OCCTO CSV パーサーのテスト。

実ファイルと同じ構造のテスト用 CSV をコードで組み立てて使う（数値は架空）。
"""

from datetime import date

import pytest

from ingestion.occto import AREAS, SchemaChangedError, parse_csv

D = date(2026, 11, 22)
METRICS = (
    '"広域ブロック需要(MW)","広域ブロック供給力(MW)","広域ブロック予備力(MW)","広域予備率(%)","広域使用率(%)",'
    '"エリア需要(MW)","エリア供給力(MW)","エリア予備力(MW)"'
)
SAME_DAY_HEADER = f'"対象年月日","時刻","ブロックNo","エリア名",{METRICS}'
TWO_DAY_HEADER = f'"対象年月日","区分名","時刻","ブロックNo","エリア名",{METRICS}'
WEEKLY_HEADER = f'"対象年月日","区分名","ブロックNo","エリア名","対象時刻",{METRICS}'


def slots():
    for i in range(1, 49):
        minutes = i * 30
        yield f"{minutes // 60:02d}:{minutes % 60:02d}"


def make_same_day(header=SAME_DAY_HEADER, areas=AREAS, n_slots=48, update="2026/11/22 22:58 UPDATE") -> bytes:
    lines = [f'"{update}"', header]
    for t in list(slots())[:n_slots]:
        for a in sorted(areas):
            lines.append(
                f'"2026/11/22","{t}","1","{a}","81679.0","90163.2","8484.1","10.39","90.59","8310","9257.9","947.9"'
            )
    return ("﻿" + "\r\n".join(lines)).encode("utf-8")


def make_two_day() -> bytes:
    lines = ['"2026/11/20 17:43 UPDATE"', TWO_DAY_HEADER]
    for t in slots():
        for a in sorted(AREAS):
            lines.append(f'"2026/11/22","***","{t}","1","{a}","3337","3470","133","3.99","96.17","8220","9000","780"')
    return ("﻿" + "\r\n".join(lines)).encode("utf-8")


def make_weekly() -> bytes:
    lines = ['"2026/11/19 18:13 UPDATE"', WEEKLY_HEADER]
    for a in sorted(AREAS):
        lines.append(
            f'"2026/11/22","最大需要","1","{a}","18:30","3818","4234","416","10.9","89.1","10700","11800","1100"'
        )
        lines.append(
            f'"2026/11/22","最小予備率","1","{a}","18:30","3818","4234","416","10.9","89.1","10700","11800","1100"'
        )
    return ("﻿" + "\r\n".join(lines)).encode("utf-8")


def test_same_day_has_480_rows_and_published_at():
    r = parse_csv(make_same_day(), "same_day", D)
    assert len(r.rows) == 480
    assert r.published_at.isoformat() == "2026-11-22T22:58:00+09:00"
    assert r.warnings == []


def test_slot_end_time_is_converted_to_slot_start():
    """'00:30' は 0:00〜0:30 のコマ → 開始時刻 0:00。'24:00' は 23:30 開始。"""
    r = parse_csv(make_same_day(), "same_day", D)
    starts = sorted({row["slot_start"] for row in r.rows})
    assert starts[0].isoformat() == "2026-11-22T00:00:00+09:00"
    assert starts[-1].isoformat() == "2026-11-22T23:30:00+09:00"


def test_metrics_are_mapped_by_column_name():
    r = parse_csv(make_same_day(), "same_day", D)
    kyushu = next(x for x in r.rows if x["area"] == "九州")
    assert kyushu["area_demand_mw"] == 8310
    assert kyushu["block_reserve_rate_pct"] == 10.39


def test_two_day_ahead_with_different_column_order():
    """翌々日は列の並びが違う（区分名が入る）が、列名で読むので同じ結果になる。"""
    r = parse_csv(make_two_day(), "two_day_ahead", D)
    assert len(r.rows) == 480
    assert r.published_at.date() == date(2026, 11, 20)
    assert next(x for x in r.rows if x["area"] == "九州")["area_demand_mw"] == 8220


def test_weekly_keeps_category():
    r = parse_csv(make_weekly(), "weekly", D)
    assert len(r.rows) == 20
    assert {x["category"] for x in r.rows} == {"最大需要", "最小予備率"}
    assert r.rows[0]["slot_start"].isoformat() == "2026-11-22T18:00:00+09:00"


def test_missing_slots_are_warned():
    r = parse_csv(make_same_day(n_slots=47), "same_day", D)
    assert any("470 行" in w for w in r.warnings)


def test_renamed_column_raises():
    with pytest.raises(SchemaChangedError, match="エリア需要"):
        parse_csv(make_same_day(header=SAME_DAY_HEADER.replace("エリア需要(MW)", "エリア需要量(MW)")), "same_day", D)


def test_unknown_area_raises():
    with pytest.raises(SchemaChangedError, match="想定外のエリア名"):
        parse_csv(make_same_day(areas={"九州", "火星"}), "same_day", D)


def test_missing_update_line_raises():
    raw = make_same_day().decode("utf-8-sig").split("\r\n", 1)[1].encode("utf-8")
    with pytest.raises(SchemaChangedError, match="公表時刻"):
        parse_csv(raw, "same_day", D)


def test_wrong_encoding_raises():
    raw = make_same_day().decode("utf-8-sig").encode("cp932")
    with pytest.raises(SchemaChangedError, match="UTF-8"):
        parse_csv(raw, "same_day", D)
