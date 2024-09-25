#!/bin/sh

VERSION=2.11.5

docker pull neilpang/wgcf-docker
docker build . -t ripples/warp:$VERSION --build-arg VERSION=$VERSION
docker push ripples/warp:$VERSION
