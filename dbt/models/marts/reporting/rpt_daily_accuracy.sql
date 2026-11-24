{{ config(materialized='view') }}

-- Looker Studio 用（1ページ目「予測はどれくらい当たっているか」）。
-- 列は必要なものだけに絞る。列名は英数字にする（日本語の列名は Looker Studio で数値として扱えないことがあるため）。
-- 日本語の表示名は Looker Studio のデータソース画面で付ける

select
    target_date,                                  -- 日付
    area,                                         -- エリア
    mape,                                         -- 誤差率。0.017 = 1.7%（表示形式をパーセントにする）
    cast(if(mape < 0.02, 1, 0) as float64) as within_2pct  -- 平均すると「誤差2%未満の日の割合」になる
from {{ ref('mart_forecast_accuracy_daily') }}
