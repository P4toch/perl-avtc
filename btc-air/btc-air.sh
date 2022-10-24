#!/bin/sh

NLS_LANG=FRENCH_FRANCE.WE8ISO8859P1
BATCH_PATH=/var/egencia/btc-air

cd $BATCH_PATH

/usr/bin/perl ./btc-air.pl $* 2>&1 /dev/null
