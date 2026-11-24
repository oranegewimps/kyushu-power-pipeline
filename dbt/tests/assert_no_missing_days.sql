-- 取り込み開始日から一昨日までの間に、抜けている日がないか
with bounds as (
    select min(target_date) as first_day
    from {{ ref('stg_occto__demand_30min') }}
),

expected as (
    select d as target_date
    from bounds,
        unnest(generate_date_array(first_day, date_sub(current_date('Asia/Tokyo'), interval 2 day))) as d
)

select e.target_date
from expected as e
left join (select distinct target_date from {{ ref('stg_occto__demand_30min') }}) as a using (target_date)
where a.target_date is null
