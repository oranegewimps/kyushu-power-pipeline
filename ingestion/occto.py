"""電力広域的運営推進機関（OCCTO）「広域予備率Web公表システム」の CSV 取得と解析。

利用条件: 公開情報は出典を記載すれば自由に利用でき、加工した場合はその旨も記載する
（「系統情報サービス・広域予備率Web公表システムのご利用に際して」より）。

3種類の CSV を使う。過去の日付を指定すると「その予測を出した時点の値」が返ってくる。
  - weekly         週間（対象日の数日前に公表。1日の最大需要・最小予備率の時点だけ）
  - two_day_ahead  翌々日（2日前に公表。30分ごと）
  - same_day       翌日・当日（当日夜の最終公表値。30分ごと）

複数日をまとめて取得すると先頭の公表時刻しか残らないため、1日ずつ取得する。
"""

from __future__ import annotations

import csv
import hashlib
import io
import re
from dataclasses import dataclass, field
from datetime import date, datetime, time, timedelta, timezone

import requests

JST = timezone(timedelta(hours=9))
BASE = "https://web-kohyo.occto.or.jp/kks-web-public"
USER_AGENT = "kyushu-power-pipeline/1.0 (portfolio project; one request per 2 seconds)"

KINDS = {"weekly": "01", "two_day_ahead": "05", "same_day": "02"}

# CSV の列名 → BigQuery の列名。列は位置ではなく名前で探す（種類ごとに列の並びが違うため）
METRIC_COLUMNS = {
    "広域ブロック需要(MW)": "block_demand_mw",
    "広域ブロック供給力(MW)": "block_supply_mw",
    "広域ブロック予備力(MW)": "block_reserve_mw",
    "広域予備率(%)": "block_reserve_rate_pct",
    "広域使用率(%)": "block_usage_rate_pct",
    "エリア需要(MW)": "area_demand_mw",
    "エリア供給力(MW)": "area_supply_mw",
    "エリア予備力(MW)": "area_reserve_mw",
}
AREAS = {"北海道", "東北", "東京", "中部", "北陸", "関西", "中国", "四国", "九州", "沖縄"}


class SchemaChangedError(Exception):
    """CSV の構造が想定と違う。黙って間違ったデータを入れないために止める。"""


class DataNotAvailableError(Exception):
    """指定日のデータが公開されていない（保存期間外など）。"""


@dataclass
class ParsedFile:
    kind: str
    target_date: date
    published_at: datetime
    rows: list[dict] = field(default_factory=list)
    warnings: list[str] = field(default_factory=list)


def new_session() -> requests.Session:
    """ダウンロード画面を一度開いてセッション Cookie を受け取る（無いと CSV が返らない）。"""
    s = requests.Session()
    s.headers["User-Agent"] = USER_AGENT
    s.get(f"{BASE}/download", timeout=30).raise_for_status()
    return s


def build_params(kind: str, target_date: date) -> dict:
    ymd = target_date.strftime("%Y/%m/%d")
    return {"jhSybt": KINDS[kind], "tgtYmdFrom": ymd, "tgtYmdTo": ymd}


def fetch_csv(session: requests.Session, kind: str, target_date: date, timeout: int = 60) -> bytes:
    resp = session.get(f"{BASE}/download/downloadCsv", params=build_params(kind, target_date), timeout=timeout)
    resp.raise_for_status()
    ctype = resp.headers.get("Content-Type", "")
    if "csv" not in ctype:
        # 保存期間外などのときは CSV ではなくエラー画面（HTML）が返る
        raise DataNotAvailableError(f"{kind} {target_date}: CSV ではなく {ctype} が返った")
    return resp.content


def sha256(raw: bytes) -> str:
    return hashlib.sha256(raw).hexdigest()


_UPDATE_RE = re.compile(r"(\d{4}/\d{1,2}/\d{1,2} \d{1,2}:\d{2}) UPDATE")


def _num(v: str | None) -> float | None:
    if v is None:
        return None
    v = v.strip()
    if v in ("", "-", "***"):
        return None
    return float(v)


def _slot_start(target_date: date, hhmm: str) -> datetime:
    """'00:30' は 0:00〜0:30 のコマ。終了時刻なので30分引いて開始時刻にする（'24:00' も扱える）。"""
    h, m = map(int, hhmm.split(":"))
    end = datetime.combine(target_date, time(0), tzinfo=JST) + timedelta(hours=h, minutes=m)
    return end - timedelta(minutes=30)


def parse_csv(raw: bytes, kind: str, target_date: date) -> ParsedFile:
    try:
        text = raw.decode("utf-8-sig")
    except UnicodeDecodeError as e:
        raise SchemaChangedError(f"{kind} {target_date}: UTF-8 で読めない（文字コードが変わった可能性）") from e

    lines = text.splitlines()
    if not lines:
        raise SchemaChangedError(f"{kind} {target_date}: 空のファイル")
    m = _UPDATE_RE.search(lines[0])
    if not m:
        raise SchemaChangedError(f"{kind} {target_date}: 1行目に公表時刻（UPDATE）がない: {lines[0][:60]}")
    published_at = datetime.strptime(m.group(1), "%Y/%m/%d %H:%M").replace(tzinfo=JST)

    reader = csv.reader(io.StringIO("\n".join(lines[1:])))
    header = next(reader, None) or []
    time_col = "対象時刻" if kind == "weekly" else "時刻"
    required = ["対象年月日", "エリア名", "ブロックNo", time_col, *METRIC_COLUMNS]
    if kind == "weekly":
        required.append("区分名")
    missing = [c for c in required if c not in header]
    if missing:
        raise SchemaChangedError(f"{kind} {target_date}: 列が見つからない {missing}（ヘッダ: {header}）")
    idx = {c: header.index(c) for c in header}

    result = ParsedFile(kind=kind, target_date=target_date, published_at=published_at)
    for cols in reader:
        if not cols:
            continue
        d = datetime.strptime(cols[idx["対象年月日"]], "%Y/%m/%d").date()
        if d != target_date:
            result.warnings.append(f"別の日付の行: {cols[:4]}")
            continue
        area = cols[idx["エリア名"]]
        if area not in AREAS:
            raise SchemaChangedError(f"{kind} {target_date}: 想定外のエリア名「{area}」")
        row = {
            "target_date": target_date,
            "kind": kind,
            "published_at": published_at,
            "area": area,
            "block_no": int(cols[idx["ブロックNo"]]),
            "slot_start": _slot_start(target_date, cols[idx[time_col]]),
        }
        if kind == "weekly":
            row["category"] = cols[idx["区分名"]]
        for jp, en in METRIC_COLUMNS.items():
            row[en] = _num(cols[idx[jp]])
        result.rows.append(row)

    # 件数チェック: 30分値は 48コマ × 10エリア
    if kind != "weekly":
        expected = 48 * len(AREAS)
        if len(result.rows) != expected:
            result.warnings.append(f"{kind}: {len(result.rows)} 行（通常 {expected} 行）")
    if not result.rows:
        raise SchemaChangedError(f"{kind} {target_date}: データ行が1行もない")
    return result
