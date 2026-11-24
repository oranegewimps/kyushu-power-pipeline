-- OCCTO 30分値。時刻を日本時間にそろえ、予測のリードタイム（公表から対象コマまで何時間前か）を付ける
with source as (
    select * from {{ source('raw', 'raw_occto_demand_30min') }}
),

-- 同じコマが二重に入っていた場合は、最後に取り込んだ行を使う
deduped as (
    select *
    from source
    qualify row_number() over (partition by kind, area, slot_start order by ingested_at desc) = 1
)

select
    target_date,
    kind,
    area,
    block_no,
    datetime(slot_start, 'Asia/Tokyo')                         as slot_start_jst,
    extract(hour from datetime(slot_start, 'Asia/Tokyo'))      as hour_of_day,
    datetime(published_at, 'Asia/Tokyo')                       as published_at_jst,
    timestamp_diff(slot_start, published_at, minute) / 60.0    as lead_hours,
    area_demand_mw,
    area_supply_mw,
    area_reserve_mw,
    safe_divide(area_reserve_mw, area_demand_mw) * 100         as area_reserve_rate_pct,
    block_demand_mw,
    block_supply_mw,
    block_reserve_rate_pct,
    block_usage_rate_pct,
    file_sha256,
    ingested_at
from deduped
