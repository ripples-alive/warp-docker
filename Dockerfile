ARG WARP_VERSION=latest
ARG GOST_VERSION=latest

FROM ginuerzh/gost:${GOST_VERSION} AS gost

FROM neilpang/wgcf-docker:${WARP_VERSION}

RUN apt-get update && apt-get -y upgrade \
    && apt-get install -y python3 \
    && rm -rf /var/lib/apt/lists/*

COPY --from=gost /bin/gost /

EXPOSE 1080

ENV REGION_ID=0

COPY check.sh /
COPY entry-extra.sh /
RUN sed -i '/sleep infinity/i \/entry-extra.sh' /entry.sh

CMD ["-4"]
