FROM neilpang/wgcf-docker

RUN apt-get update && apt-get -y upgrade \
    && apt-get install -y python3 \
    && rm -rf /var/lib/apt/lists/*

ARG VERSION=2.11.5

RUN curl -fL 'Mozilla' https://github.com/ginuerzh/gost/releases/download/v${VERSION}/gost-linux-amd64-${VERSION}.gz | gunzip > /gost \
    && chmod +x /gost

EXPOSE 1080

ENV REGION_ID=0

COPY check.sh /
COPY entry-extra.sh /
RUN sed -i '/sleep infinity/i \/entry-extra.sh' /entry.sh

CMD ["-4"]
