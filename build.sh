#!/bin/sh

GOST_VERSION=2.12.0

docker pull neilpang/wgcf-docker
docker build . -t ripples/warp:gost$GOST_VERSION
docker push ripples/warp:gost$GOST_VERSION
