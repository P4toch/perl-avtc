#!/usr/bin/perl -w
#-----------------------------------------------------------------
# Batch synchro.pl
#
# $Id: synchro.pl 646 2011-04-05 10:20:32Z pbressan $
#
# (c) 2002-2009 Expedia.                   www.expediacorporate.fr
#-----------------------------------------------------------------

use strict;
use Getopt::Long;

use lib '../libsperl';

use Expedia::XML::Config;
use Expedia::Tools::Logger qw(&debug &notice &warning &error);
use Expedia::Workflow::TasksProcessor;

my $opt_mrkt;
my $opt_help;

GetOptions(
  'market=s', \$opt_mrkt,
  'help',     \$opt_help,
);

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Affichage de l'aide
if ($opt_help) {
  print STDERR ("\nUsage: $0 --market=[FR|GB|...] --help\n\n");
  exit(0);
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

my $task = 'synchro-'.$opt_mrkt;

notice('###############################################################');
notice('############          LANCEMENT DE SYNCHRO         ############');

my $config        = Expedia::XML::Config->new('../libsperl/Expedia/Tools/config_DDB.xml',$task);
my $processor = Expedia::Workflow::TasksProcessor->new($task, $config) if (defined $config);

notice('############             FIN DE SYNCHRO            ############');
notice('###############################################################');
