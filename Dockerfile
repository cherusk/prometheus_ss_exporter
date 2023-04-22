FROM python:3.7-slim

ARG EXPORTER_USER_HOME="/usr/local/exporter"
ENV EXPORTER_HOME="${EXPORTER_USER_HOME}"

COPY . /prometheus-ss-exporter

RUN set -ex \
        && apt-get update \
        && apt-get install -y git curl \
        && apt-get clean \
        && pip install --no-cache-dir -U pip \
        && cd /prometheus-ss-exporter \
        && python3 setup.py install

EXPOSE 8090

HEALTHCHECK --interval=1s --timeout=2s --retries=1 \
    CMD curl -f http://localhost:"${PORT}"/health || exit 1

USER root
WORKDIR "${EXPORTER_HOME}"

ENTRYPOINT prometheus_ss_exporter --port "${PORT}" --cnfg "${CONFIG_FILE}"
