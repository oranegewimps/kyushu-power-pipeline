-- 日付ごとの曜日・祝日・平日/休日の区分（需要は休日に下がるため）
with days as (
    select distinct target_date from {{ ref('stg_occto__demand_30min') }}
),

holidays as (
    select * from {{ ref('seed_jp_holidays') }}
)

select
    d.target_date,
    extract(dayofweek from d.target_date)               as day_of_week, -- 1=日曜
    format_date('%a', d.target_date)                    as day_name,
    h.holiday_name,
    case
        when h.holiday_date is not null then '祝日'
        when extract(dayofweek from d.target_date) in (1, 7) then '土日'
        -- お盆・年末年始は祝日ではないが需要が休日並みに下がる
        when format_date('%m-%d', d.target_date) between '08-13' and '08-16' then '長期休暇'
        when format_date('%m-%d', d.target_date) >= '12-29'
            or format_date('%m-%d', d.target_date) <= '01-03' then '長期休暇'
        else '平日'
    end                                                  as day_type
from days as d
left join holidays as h on d.target_date = h.holiday_date
