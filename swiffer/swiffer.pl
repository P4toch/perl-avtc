#!/usr/bin/perl -w
#-----------------------------------------------------------------
# Batch swiffer.pl
#
# $Id: swiffer.pl 410 2008-02-11 09:20:59Z pbressan $
#
# (c) 2002-2008 Expedia.                   www.expediacorporate.fr
#-----------------------------------------------------------------

use strict;

use lib '../libsperl';

use Expedia::Tools::Logger qw(&debug &notice &warning &error);
use Expedia::XML::Config;
use Expedia::Databases::MidSchemaFuncs qw(&cleanItems &unlockItems);

notice('###############################################################');
notice('############          LANCEMENT DE SWIFFER         ############');

#Trick to initialize the database connection, no Amadeus connection needed, so we use another existing parameters: here btc-air-FR
my $task = 'btc-air-FR';
my $config = Expedia::XML::Config->new('../libsperl/Expedia/Tools/config_DDB.xml', $task);

notice('+-------------------------------------------------------------+');
notice('| NETTOYAGE DES ELEMENTS                                      |');
notice('+-------------------------------------------------------------+');

cleanItems();

notice('+-------------------------------------------------------------+');
notice('| DEVERROUILLAGE DES ELEMENTS                                 |');
notice('+-------------------------------------------------------------+');

unlockItems();

notice('+-------------------------------------------------------------+');

notice('############             FIN DE SWIFFER            ############');
notice('###############################################################');
