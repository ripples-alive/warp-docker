# build microsocks
FROM alpine:latest AS builder
RUN apk add --no-cache build-base git
RUN git clone https://github.com/rofl0r/microsocks.git && \
    cd /microsocks && make

FROM alpine:latest

RUN apk add --no-cache bash wireguard-tools iptables iproute2 curl grep openssl

COPY --from=builder /microsocks/microsocks /usr/local/bin/microsocks

RUN curl -fsSL git.io/wgcf.sh | bash && mkdir -p /etc/wgcf
WORKDIR /etc/wgcf
VOLUME ["/etc/wgcf"]

COPY check.sh /
COPY healthcheck.sh /
COPY entrypoint.sh /

RUN chmod +x /check.sh /healthcheck.sh /entrypoint.sh

ENV REGION_ID=0

HEALTHCHECK --interval=30s --timeout=15s --start-period=20s --retries=3 CMD /healthcheck.sh

ENTRYPOINT ["/entrypoint.sh"]
