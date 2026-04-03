#!/bin/sh

set -eu

NAME=warp
BUILDER=${NAME}-builder
BUILD_HTTP_PROXY=${http_proxy:-${HTTP_PROXY:-}}
BUILD_HTTPS_PROXY=${https_proxy:-${HTTPS_PROXY:-}}
BUILD_NO_PROXY=${no_proxy:-${NO_PROXY:-}}

cleanup() {
    docker buildx stop "$BUILDER" >/dev/null 2>&1 || true
    docker buildx rm "$BUILDER" >/dev/null 2>&1 || true
}

trap cleanup EXIT INT TERM

docker buildx rm "$BUILDER" >/dev/null 2>&1 || true

set -- \
    --use \
    --name "$BUILDER"

if [ -n "$BUILD_HTTP_PROXY" ]; then
    set -- "$@" \
        --driver-opt "env.http_proxy=$BUILD_HTTP_PROXY" \
        --driver-opt "env.HTTP_PROXY=$BUILD_HTTP_PROXY"
fi

if [ -n "$BUILD_HTTPS_PROXY" ]; then
    set -- "$@" \
        --driver-opt "env.https_proxy=$BUILD_HTTPS_PROXY" \
        --driver-opt "env.HTTPS_PROXY=$BUILD_HTTPS_PROXY"
fi

if [ -n "$BUILD_NO_PROXY" ]; then
    set -- "$@" \
        --driver-opt "env.no_proxy=$BUILD_NO_PROXY" \
        --driver-opt "env.NO_PROXY=$BUILD_NO_PROXY"
fi

docker buildx create "$@"
docker buildx inspect --bootstrap

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

docker buildx build "$@" .
