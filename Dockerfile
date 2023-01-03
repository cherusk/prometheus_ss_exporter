FROM python:3.7-slim

ARG EXPORTER_USER_HOME="/usr/local/exporter"
ENV EXPORTER_HOME="${EXPORTER_USER_HOME}"

COPY . /prometheus-ss-exporter

RUN set -ex \
        && useradd -ms /bin/bash -d ${EXPORTER_HOME} exporter \
        && pip install --no-cache-dir -U pip \
        && cd /prometheus-ss-exporter \
        && python3 setup.py install

EXPOSE 8090

USER exporter
WORKDIR "${EXPORTER_HOME}"

ENTRYPOINT prometheus_ss_exporter --port "${PORT}" --cnfg "${CONFIG_FILE}"