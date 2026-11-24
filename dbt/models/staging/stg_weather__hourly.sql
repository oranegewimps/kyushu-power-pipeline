with source as (
    select * from {{ source('raw', 'raw_weather_hourly') }}
),

deduped as (
    select *
    from source
    qualify row_number() over (partition by city_id, hour_start order by ingested_at desc) = 1
)

select
    target_date,
    datetime(hour_start, 'Asia/Tokyo') as hour_start_jst,
    city_id,
    prefecture,
    temperature_2m        as temperature_c,
    relative_humidity_2m  as humidity_pct,
    precipitation         as precipitation_mm,
    cloud_cover           as cloud_cover_pct,
    shortwave_radiation   as solar_radiation_wm2,
    ingested_at
from deduped
