ARG MICROWARP_VERSION=latest

FROM ghcr.io/ccbkkb/microwarp:${MICROWARP_VERSION}

RUN apk add --no-cache grep openssl

ENV REGION_ID=0

COPY check.sh /
RUN sed -i '/1\.1\.1\.1/a\\[ -n "$UNLOCK_STREAM" ] && \/check.sh &' /app/entrypoint.sh
