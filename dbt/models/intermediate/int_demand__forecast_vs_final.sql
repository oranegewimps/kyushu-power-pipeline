-- 同じエリア・同じ30分コマについて「2日前時点の予測」と「当日の最終公表値」を横に並べる
with demand as (
    select * from {{ ref('stg_occto__demand_30min') }}
)

select
    area,
    target_date,
    slot_start_jst,
    any_value(hour_of_day)                                                          as hour_of_day,
    max(if(kind = 'two_day_ahead', area_demand_mw, null))                           as forecast_mw,
    max(if(kind = 'same_day', area_demand_mw, null))                                as final_mw,
    max(if(kind = 'two_day_ahead', lead_hours, null))                               as forecast_lead_hours,
    max(if(kind = 'two_day_ahead', area_reserve_rate_pct, null))                    as forecast_reserve_rate_pct,
    max(if(kind = 'same_day', area_reserve_rate_pct, null))                         as final_reserve_rate_pct,
    max(if(kind = 'same_day', block_reserve_rate_pct, null))                        as final_block_reserve_rate_pct,
    max(if(kind = 'two_day_ahead', published_at_jst, null))                         as forecast_published_at_jst,
    max(if(kind = 'same_day', published_at_jst, null))                              as final_published_at_jst
from demand
group by 1, 2, 3
