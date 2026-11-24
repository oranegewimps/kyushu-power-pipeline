{{ config(materialized='view') }}

-- Looker Studio 用（2・3ページ目「どんなときに外れるか」「外れた日に何が起きたか」）。
-- 九州エリアの30分値。予測と最終値の両方がそろったコマだけ。
-- 誤差率・ずれは行（30分）単位なので、Looker Studio で「平均」にすると日別・時間別の値になる

select
    target_date                                         as `日付`,
    format_datetime('%H:%M', slot_start_jst)            as `時刻`,      -- 折れ線の横軸（00:00〜23:30）
    hour_of_day                                         as `時`,        -- 0〜23
    day_type                                            as `曜日区分`,
    holiday_name                                        as `祝日名`,
    forecast_mw                                         as `予測_MW`,    -- 2日前の予測
    final_mw                                            as `実績_MW`,    -- 当日の最終公表値
    error_mw                                            as `ずれ_MW`,    -- 実績 − 予測。マイナス＝予測が多すぎた
    abs_pct_error                                       as `誤差率`,
    temperature_c                                       as `気温`,
    cast(floor(temperature_c / 2) * 2 as int64)         as `気温帯`      -- 2℃刻み。26 は「26〜28℃」
from {{ ref('fct_area_demand_30min') }}
where area = '九州'
  and forecast_mw is not null
  and final_mw is not null
