#!/bin/sh

NAME=warp
BUILDER=${NAME}-builder

docker buildx create --use --name $BUILDER
docker buildx inspect --bootstrap

docker buildx build \
    --platform linux/amd64,linux/arm64 \
    --push \
    --pull \
    --tag ripples/$NAME:latest \
    --builder $BUILDER .

docker buildx stop $BUILDER
docker buildx rm $BUILDER
