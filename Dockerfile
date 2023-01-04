FROM python:3.7-slim

ARG EXPORTER_USER_HOME="/usr/local/exporter"
ENV EXPORTER_HOME="${EXPORTER_USER_HOME}"

COPY . /prometheus-ss-exporter

RUN set -ex \
        && apt-get update \
        && apt-get install -y git \
        && apt-get clean \
        && useradd -ms /bin/bash -d ${EXPORTER_HOME} exporter \
        && pip install --no-cache-dir -U pip \
        && cd /prometheus-ss-exporter \
        && python3 setup.py install

# install ss2 from forked pyroute2
RUN /bin/bash -c "git clone https://github.com/cherusk/pyroute2.git \
                  && pushd pyroute2 \
                  && git checkout -B install_ss2_as_module origin/install_ss2_as_module \
                  && python3 setup.py install \
                  && popd \
                  && rmdir --ignore-fail-on-non-empty pyroute2"

EXPOSE 8090

USER exporter
WORKDIR "${EXPORTER_HOME}"

ENTRYPOINT prometheus_ss_exporter --port "${PORT}" --cnfg "${CONFIG_FILE}"
