#!/bin/sh

BUILDER=warp-builder
GOST_VERSION=2.12.0

docker pull neilpang/wgcf-docker

docker buildx create --use --name $BUILDER
docker buildx inspect --bootstrap

docker buildx build \
    --platform linux/amd64,linux/arm64 \
    --output "type=image,push=true" \
    --tag ripples/warp:gost$GOST_VERSION \
    --builder $BUILDER .

docker buildx stop $BUILDER
docker buildx rm $BUILDER
