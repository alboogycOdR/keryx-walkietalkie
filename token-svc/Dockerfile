FROM python:3.12-slim

WORKDIR /srv
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app ./app
COPY alembic.ini ./alembic.ini
COPY alembic ./alembic
COPY scripts ./scripts
COPY openapi-v2.yaml ./openapi-v2.yaml

RUN useradd --system --uid 10001 --no-create-home tokensvc
USER tokensvc

EXPOSE 8080
# --no-access-log: uvicorn's default access line can include query strings.
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8080", "--no-access-log"]
