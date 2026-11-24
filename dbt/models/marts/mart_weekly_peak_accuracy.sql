-- 数日前の「週間」予測の最大需要は、当日の実際のピークとどれだけずれたか
with weekly as (
    select * from {{ ref('stg_occto__weekly') }}
    where category = '最大需要'
      and lead_days >= 1 -- 当日公表のもの（公表開始日のみ）は予測とみなさない
),

daily as (
    select * from {{ ref('mart_forecast_accuracy_daily') }}
)

select
    w.area,
    w.target_date,
    d.day_type,
    w.lead_days,
    w.published_at_jst                                        as weekly_published_at_jst,
    w.area_demand_mw                                          as weekly_peak_forecast_mw,
    d.peak_forecast_mw                                        as two_day_peak_forecast_mw,
    d.peak_final_mw,
    d.peak_final_mw - w.area_demand_mw                        as weekly_peak_error_mw,
    safe_divide(d.peak_final_mw - w.area_demand_mw, d.peak_final_mw) as weekly_peak_error_pct,
    safe_divide(d.peak_final_mw - d.peak_forecast_mw, d.peak_final_mw) as two_day_peak_error_pct,
    datetime_diff(d.peak_final_at, w.slot_start_jst, minute)  as weekly_peak_time_gap_minutes
from weekly as w
inner join daily as d using (area, target_date)
