"""Open-Meteo から九州8県の県庁所在地の気温などを1時間単位で取得する。

過去分は archive API、直近（約5日以内）は forecast API の past_days を使う。
API キー不要。非商用利用の範囲で使っている。
"""

from __future__ import annotations

from datetime import date, datetime, timedelta

import requests

from ingestion.occto import JST

ARCHIVE_URL = "https://archive-api.open-meteo.com/v1/archive"
FORECAST_URL = "https://api.open-meteo.com/v1/forecast"
HOURLY_VARS = ["temperature_2m", "relative_humidity_2m", "precipitation", "cloud_cover", "shortwave_radiation"]

# 県庁所在地（緯度・経度）
CITIES = {
    "fukuoka": ("福岡県", 33.5902, 130.4017),
    "saga": ("佐賀県", 33.2494, 130.2988),
    "nagasaki": ("長崎県", 32.7503, 129.8777),
    "kumamoto": ("熊本県", 32.8031, 130.7079),
    "oita": ("大分県", 33.2382, 131.6126),
    "miyazaki": ("宮崎県", 31.9111, 131.4239),
    "kagoshima": ("鹿児島県", 31.5966, 130.5571),
    "kitakyushu": ("福岡県", 33.8834, 130.8752),
}

ARCHIVE_LAG_DAYS = 6


def fetch_weather(start: date, end: date, session: requests.Session | None = None) -> list[dict]:
    """start〜end（両端含む）の1時間値を全都市分返す。"""
    s = session or requests.Session()
    today = datetime.now(JST).date()
    use_archive = end <= today - timedelta(days=ARCHIVE_LAG_DAYS)
    rows: list[dict] = []
    for city_id, (pref, lat, lon) in CITIES.items():
        params = {
            "latitude": lat,
            "longitude": lon,
            "hourly": ",".join(HOURLY_VARS),
            "timezone": "Asia/Tokyo",
        }
        if use_archive:
            url = ARCHIVE_URL
            params |= {"start_date": start.isoformat(), "end_date": end.isoformat()}
        else:
            url = FORECAST_URL
            params |= {"past_days": min((today - start).days + 1, 92), "forecast_days": 1}
        resp = s.get(url, params=params, timeout=60)
        resp.raise_for_status()
        hourly = resp.json()["hourly"]
        for i, t in enumerate(hourly["time"]):
            ts = datetime.fromisoformat(t).replace(tzinfo=JST)
            if not (start <= ts.date() <= end):
                continue
            row = {"target_date": ts.date(), "hour_start": ts, "city_id": city_id, "prefecture": pref}
            for v in HOURLY_VARS:
                row[v] = hourly[v][i]
            rows.append(row)
    return rows
