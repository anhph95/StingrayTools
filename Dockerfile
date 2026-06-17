FROM python:3.11-slim

WORKDIR /app

ENV PYTHONUNBUFFERED=1
ENV PIP_NO_CACHE_DIR=1

ARG STINGRAYTOOLS_REF=dev
ARG STINGRAYTOOLS_REPO=https://github.com/anhph95/stingraytools.git

RUN apt-get update && \
    apt-get install -y --no-install-recommends git && \
    pip install --upgrade pip && \
    pip install --no-cache-dir \
      "stingray-dashboard[server] @ git+${STINGRAYTOOLS_REPO}@${STINGRAYTOOLS_REF}#subdirectory=packages/stingray-dashboard" && \
    apt-get purge -y --auto-remove git && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

EXPOSE 8050

CMD ["gunicorn", "--bind", "0.0.0.0:8050", "stingray_dashboard.app:application"]
