-- OCCTO 週間。数日前時点の「その日の最大需要」の予測
with source as (
    select * from {{ source('raw', 'raw_occto_weekly') }}
),

deduped as (
    select *
    from source
    qualify row_number() over (partition by area, target_date, category order by ingested_at desc) = 1
)

select
    target_date,
    area,
    category,
    datetime(slot_start, 'Asia/Tokyo')                       as slot_start_jst,
    datetime(published_at, 'Asia/Tokyo')                     as published_at_jst,
    date_diff(target_date, date(published_at, 'Asia/Tokyo'), day) as lead_days,
    area_demand_mw,
    area_supply_mw,
    area_reserve_mw,
    block_reserve_rate_pct,
    ingested_at
from deduped
