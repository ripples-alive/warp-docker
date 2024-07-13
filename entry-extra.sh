#!/bin/sh

[ -n "$UNLOCK_STREAM" ] && /check.sh &

/gost -L :1080
