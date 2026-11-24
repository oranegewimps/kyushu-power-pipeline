{{ config(materialized='view') }}

-- Looker Studio 用（2・3ページ目「どんなときに外れるか」「外れた日に何が起きたか」）。
-- 九州エリアの30分値。予測と最終値の両方がそろったコマだけ。
-- 誤差率・ずれは行（30分）単位なので、Looker Studio で「平均」にすると日別・時間別の値になる。
-- 列名は英数字（日本語の表示名は Looker Studio のデータソース画面で付ける）

select
    target_date,                                                    -- 日付
    day_type,                                                       -- 曜日区分
    format_datetime('%H:%M', slot_start_jst)       as slot_time,    -- 時刻（00:00〜23:30）。折れ線の横軸
    format('%02d時', hour_of_day)                  as hour_label,   -- 時（00時〜23時）。文字なので集計されない
    forecast_mw,                                                    -- 予測（2日前）
    final_mw,                                                       -- 実績（当日の最終公表値）
    error_mw,                                                       -- 実績 − 予測。マイナス＝予測が多すぎた
    abs_pct_error                                  as pct_error,    -- 誤差率
    temperature_c,                                                  -- 気温（九州8都市の人口加重平均）
    cast(floor(temperature_c / 2) * 2 as int64)    as temp_band_c   -- 気温帯（2℃刻みの下限。26 = 26〜28℃）
from {{ ref('fct_area_demand_30min') }}
where area = '九州'
  and forecast_mw is not null
  and final_mw is not null
