# 取り込み（python -m ingestion.main）と dbt（dbt build）の両方を動かすイメージ
FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PYTHONUTF8=1

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY ingestion/ ingestion/
COPY dbt/ dbt/
RUN dbt deps --project-dir dbt --profiles-dir dbt

# 実行するコマンドは Cloud Run ジョブ側で指定する
CMD ["python", "-m", "ingestion.main"]
