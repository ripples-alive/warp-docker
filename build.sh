#!/bin/sh

NAME=warp
BUILDER=${NAME}-builder
GOST_VERSION=2.12.0

docker buildx create --use --name $BUILDER
docker buildx inspect --bootstrap

docker buildx build \
    --platform linux/amd64,linux/arm64 \
    --push \
    --pull \
    --tag ripples/$NAME:$GOST_VERSION \
    --build-arg GOST_VERSION=$GOST_VERSION \
    --builder $BUILDER .

docker buildx stop $BUILDER
docker buildx rm $BUILDER
