-- 九州エリア: 気温帯 × 曜日区分 × 時間帯ごとの需要と予測誤差。
-- 「暑い日・寒い日ほど予測が外れるか」「冷暖房でどれだけ需要が増えるか」を見るため

with fct as (
    select *
    from {{ ref('fct_area_demand_30min') }}
    where area = '九州'
      and final_mw is not null
      and forecast_mw is not null
      and temperature_c is not null
)

select
    cast(floor(temperature_c / 2) * 2 as int64)            as temperature_band_c, -- 2℃刻み
    day_type,
    case
        when hour_of_day between 0 and 5 then '深夜'
        when hour_of_day between 6 and 11 then '午前'
        when hour_of_day between 12 and 17 then '午後'
        else '夜'
    end                                                     as time_of_day,
    count(*)                                                as slots,
    avg(final_mw)                                           as avg_final_mw,
    avg(abs_pct_error)                                      as mape,
    avg(error_mw)                                           as bias_mw
from fct
group by 1, 2, 3
