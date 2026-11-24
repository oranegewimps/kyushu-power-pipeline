-- 「予測」は対象日より前に公表されていなければならない。
-- 当日以降に公表された値が予測として入っていたら、未来の情報が混ざっている（データリーク）
select
    area,
    target_date,
    published_at_jst
from {{ ref('stg_occto__demand_30min') }}
where kind = 'two_day_ahead'
  and date(published_at_jst) >= target_date
