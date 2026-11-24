-- 8都市の気象を人口で重み付けして「九州全体の1時間ごとの気象」にする
with weather as (
    select * from {{ ref('stg_weather__hourly') }}
),

weights as (
    select * from {{ ref('seed_city_weights') }}
)

select
    w.hour_start_jst,
    w.target_date,
    sum(w.temperature_c * c.population_thousand) / sum(c.population_thousand)       as temperature_c,
    sum(w.humidity_pct * c.population_thousand) / sum(c.population_thousand)        as humidity_pct,
    sum(w.solar_radiation_wm2 * c.population_thousand) / sum(c.population_thousand) as solar_radiation_wm2,
    sum(w.cloud_cover_pct * c.population_thousand) / sum(c.population_thousand)     as cloud_cover_pct,
    count(*)                                                                         as city_count
from weather as w
inner join weights as c using (city_id)
group by 1, 2
