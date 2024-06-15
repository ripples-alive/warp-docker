#!/bin/sh

rm -f /usr/bin/warp_unlock.sh
yes '' | bash /unlock.sh -E -N $UNLOCK_TYPE -M 3 -T "$TELEGRAM_BOT"
tail -F /root/result.log &

/gost -L :1080
