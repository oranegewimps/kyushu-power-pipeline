-- エリア×日ごとの予測精度。経営の予実会議でいう「予算達成率」に当たる見方
-- 予測・最終値の両方が48コマそろった日だけを対象にする

with fct as (
    select * from {{ ref('fct_area_demand_30min') }}
),

daily as (
    select
        area,
        target_date,
        any_value(day_type)                                   as day_type,
        any_value(holiday_name)                               as holiday_name,
        countif(forecast_mw is not null and final_mw is not null) as paired_slots,
        sum(final_mw) / 2                                     as final_mwh,     -- 30分値なので MW×0.5h
        sum(forecast_mw) / 2                                  as forecast_mwh,
        max(final_mw)                                         as peak_final_mw,
        max(forecast_mw)                                      as peak_forecast_mw,
        array_agg(slot_start_jst order by final_mw desc limit 1)[offset(0)]    as peak_final_at,
        array_agg(slot_start_jst order by forecast_mw desc limit 1)[offset(0)] as peak_forecast_at,
        avg(abs_pct_error)                                    as mape,
        avg(error_mw)                                         as bias_mw,
        max(abs(error_mw))                                    as max_abs_error_mw,
        min(final_reserve_rate_pct)                           as min_final_reserve_rate_pct,
        min(forecast_reserve_rate_pct)                        as min_forecast_reserve_rate_pct,
        avg(temperature_c)                                    as avg_temperature_c,
        max(temperature_c)                                    as max_temperature_c,
        min(temperature_c)                                    as min_temperature_c
    from fct
    group by 1, 2
)

select
    * except (paired_slots),
    safe_divide(final_mwh, forecast_mwh)                      as final_to_forecast_ratio,
    peak_final_mw - peak_forecast_mw                          as peak_error_mw,
    datetime_diff(peak_final_at, peak_forecast_at, minute)    as peak_time_gap_minutes,
    case
        when mape < 0.02 then 'A: 2%未満'
        when mape < 0.04 then 'B: 2〜4%'
        else 'C: 4%以上'
    end                                                        as accuracy_grade
from daily
where paired_slots = 48
