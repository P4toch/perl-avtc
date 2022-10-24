#!/bin/sh

NLS_LANG=FRENCH_FRANCE.WE8ISO8859P1
BATCH_PATH=/var/egencia/libsperl/Expedia/Tools/

cd $BATCH_PATH

/usr/bin/perl ./Conversion.pl $* 2>&1 /dev/null
