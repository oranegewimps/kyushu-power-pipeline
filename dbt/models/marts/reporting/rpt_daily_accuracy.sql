{{ config(materialized='view') }}

-- Looker Studio 用（1ページ目「予測はどれくらい当たっているか」）。
-- 画面側で計算フィールドを作らなくて済むよう、列名を日本語にし、割合はそのまま平均できる形にしておく

select
    target_date                                   as `日付`,
    area                                          as `エリア`,
    day_type                                      as `曜日区分`,
    holiday_name                                  as `祝日名`,
    mape                                          as `誤差率`,          -- 0.017 = 1.7%（表示形式をパーセントにする）
    bias_mw                                       as `ずれ_MW`,         -- 実績 − 予測。マイナス＝予測が多すぎた
    if(mape < 0.02, 1, 0)                         as `誤差2パーセント未満`, -- 平均すると「誤差2%未満の日の割合」になる
    peak_final_mw                                 as `実績ピーク_MW`,
    peak_forecast_mw                              as `予測ピーク_MW`,
    avg_temperature_c                             as `平均気温`,
    max_temperature_c                             as `最高気温`
from {{ ref('mart_forecast_accuracy_daily') }}
