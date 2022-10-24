#!/bin/sh

NLS_LANG=FRENCH_FRANCE.WE8ISO8859P1
BATCH_PATH=/var/egencia/workflow

cd $BATCH_PATH

/usr/bin/perl ./workflow.pl $* 2>&1 /dev/null
