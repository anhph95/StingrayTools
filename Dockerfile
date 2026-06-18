FROM python:3.11-slim

WORKDIR /app

ENV PYTHONUNBUFFERED=1
ENV PIP_NO_CACHE_DIR=1

ARG STINGRAYTOOLS_REF=main
ARG STINGRAYTOOLS_REPO=https://github.com/anhph95/stingraytools.git

RUN apt-get update && \
    apt-get install -y --no-install-recommends git && \
    pip install --upgrade pip && \
    pip install --no-cache-dir \
      "stingray-dashboard[server] @ git+${STINGRAYTOOLS_REPO}@${STINGRAYTOOLS_REF}#subdirectory=packages/stingray-dashboard" && \
    apt-get purge -y --auto-remove git && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

COPY packages/stingray-dashboard/docker-entrypoint.sh /app/docker-entrypoint.sh
RUN chmod +x /app/docker-entrypoint.sh

EXPOSE 8050

CMD ["/app/docker-entrypoint.sh"]
