#!/bin/sh

set -eu

NAME=warp
BUILDER=${NAME}-builder
BUILD_HTTP_PROXY=${http_proxy:-${HTTP_PROXY:-}}
BUILD_HTTPS_PROXY=${https_proxy:-${HTTPS_PROXY:-}}
BUILD_NO_PROXY=${no_proxy:-${NO_PROXY:-}}

set -- \
    --platform linux/amd64,linux/arm64 \
    --push \
    --pull \
    --tag "ripples/$NAME:latest" \
    --builder "$BUILDER"

if [ -n "$BUILD_HTTP_PROXY" ]; then
    set -- "$@" \
        --build-arg "http_proxy=$BUILD_HTTP_PROXY" \
        --build-arg "HTTP_PROXY=$BUILD_HTTP_PROXY"
fi

if [ -n "$BUILD_HTTPS_PROXY" ]; then
    set -- "$@" \
        --build-arg "https_proxy=$BUILD_HTTPS_PROXY" \
        --build-arg "HTTPS_PROXY=$BUILD_HTTPS_PROXY"
fi

if [ -n "$BUILD_NO_PROXY" ]; then
    set -- "$@" \
        --build-arg "no_proxy=$BUILD_NO_PROXY" \
        --build-arg "NO_PROXY=$BUILD_NO_PROXY"
fi

docker buildx create --use --name $BUILDER
docker buildx inspect --bootstrap

docker buildx build "$@" .

docker buildx stop $BUILDER
docker buildx rm $BUILDER
