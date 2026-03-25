#!/bin/sh

NAME=warp
BUILDER=${NAME}-builder
MICROWARP_VERSION=0.1.0

docker buildx create --use --name $BUILDER
docker buildx inspect --bootstrap

docker buildx build \
    --platform linux/amd64,linux/arm64 \
    --push \
    --pull \
    --tag ripples/$NAME:$MICROWARP_VERSION \
    --build-arg MICROWARP_VERSION=$MICROWARP_VERSION \
    --builder $BUILDER .

docker buildx stop $BUILDER
docker buildx rm $BUILDER
