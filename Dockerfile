# build microsocks
FROM alpine:latest AS builder
RUN apk add --no-cache build-base git
RUN git clone https://github.com/rofl0r/microsocks.git && \
    cd /microsocks && make

FROM alpine:latest

RUN apk add --no-cache wireguard-tools iptables iproute2 wget curl grep openssl

COPY --from=builder /microsocks/microsocks /usr/local/bin/microsocks

RUN curl -fsSL git.io/wgcf.sh | bash && mkdir -p /wgcf
WORKDIR /wgcf
VOLUME /wgcf

COPY check.sh /
COPY entrypoint.sh /

ENV REGION_ID=0

CMD ["/entrypoint.sh"]
