ARG BASE_IMAGE
FROM ${BASE_IMAGE}
USER root
COPY . /tmp/brand
RUN sh /tmp/brand/apply.sh /app/client/dist && rm -rf /tmp/brand
USER node
