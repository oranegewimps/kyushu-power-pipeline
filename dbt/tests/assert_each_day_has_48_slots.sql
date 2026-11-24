-- 一昨日以前の日は、種類×エリアごとに30分コマが48個そろっているはず。欠けていたら取り込み漏れ
select
    target_date,
    kind,
    area,
    count(*) as slots
from {{ ref('stg_occto__demand_30min') }}
where target_date <= date_sub(current_date('Asia/Tokyo'), interval 2 day)
group by 1, 2, 3
having count(*) != 48
