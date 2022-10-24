#!/usr/bin/perl -w
#-----------------------------------------------------------------
# Batch reconciliation.pl
#
# $Id: reconciliation.pl 410 2013-03-14 09:20:59Z sdubuc $
#
# (c) 2002-2007 Expedia.                   www.expediacorporate.fr
#-----------------------------------------------------------------

use strict;

use lib '../libsperl';

use Getopt::Long;
use Expedia::XML::Config;
use Expedia::Tools::Logger qw(&debug &notice &warning &error);
use Expedia::Workflow::TasksProcessor;
use Data::Dumper;

my $opt_task;
my $opt_help;

GetOptions(
  "task=s",  \$opt_task,
  "help",    \$opt_help
);

$opt_help = 1
  unless ($opt_task );

if ($opt_help) {
  print STDERR ("\nUsage: $0 --task=[PAREC38DD|MANEC3100|DELEC38DD|.....]\n\n");
  exit(0);
}

my $task = 'tjq-'.$opt_task;

notice('###############################################################');
notice('############         LANCEMENT DE TJQ              ############');

my $config        = Expedia::XML::Config->new('../libsperl/Expedia/Tools/config_DDB.xml', $task);
my $processor = Expedia::Workflow::TasksProcessor->new($task, $config);

notice('############            FIN DE TJQ                 ############');
notice('###############################################################');
