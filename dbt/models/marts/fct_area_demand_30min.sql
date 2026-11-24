{{
  config(
    materialized='incremental',
    incremental_strategy='insert_overwrite',
    partition_by={'field': 'target_date', 'data_type': 'date', 'granularity': 'day'},
    cluster_by=['area'],
    on_schema_change='append_new_columns'
  )
}}

-- 30分ごと・エリアごとの予実ファクト。予測誤差、予備率、曜日区分、九州は気象も付ける
-- 増分更新: 公表値の修正を拾うため、直近 lookback_days 日分のパーティションを毎回置き換える

with fv as (
    select * from {{ ref('int_demand__forecast_vs_final') }}
    {% if is_incremental() %}
    where target_date >= date_sub(current_date('Asia/Tokyo'), interval {{ var('lookback_days') }} day)
    {% endif %}
)

select
    fv.target_date,
    fv.area,
    fv.slot_start_jst,
    fv.hour_of_day,
    c.day_type,
    c.holiday_name,
    fv.forecast_mw,
    fv.final_mw,
    fv.final_mw - fv.forecast_mw                                     as error_mw,
    safe_divide(abs(fv.final_mw - fv.forecast_mw), fv.final_mw)       as abs_pct_error,
    fv.forecast_lead_hours,
    fv.forecast_reserve_rate_pct,
    fv.final_reserve_rate_pct,
    fv.final_block_reserve_rate_pct,
    fv.forecast_published_at_jst,
    fv.final_published_at_jst,
    -- 気象は九州8都市のみ取得しているので、九州エリアにだけ付ける
    if(fv.area = '九州', w.temperature_c, null)                       as temperature_c,
    if(fv.area = '九州', w.humidity_pct, null)                        as humidity_pct,
    if(fv.area = '九州', w.solar_radiation_wm2, null)                 as solar_radiation_wm2,
    if(fv.area = '九州', w.cloud_cover_pct, null)                     as cloud_cover_pct
from fv
left join {{ ref('int_calendar__days') }} as c using (target_date)
left join {{ ref('int_weather__kyushu_hourly') }} as w
    on datetime_trunc(fv.slot_start_jst, hour) = w.hour_start_jst
