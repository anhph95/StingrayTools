FROM python:3.12-slim

WORKDIR /app

ENV PYTHONUNBUFFERED=1
ENV PIP_NO_CACHE_DIR=1

COPY packages/stingray-dashboard/ /tmp/stingray-dashboard/

RUN pip install --upgrade pip \
    && pip install "/tmp/stingray-dashboard[server]"

EXPOSE 8050

CMD ["gunicorn", "--bind", "0.0.0.0:8050", "stingray_dashboard.app:application"]
