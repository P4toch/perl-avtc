#!/usr/bin/perl -w
#-----------------------------------------------------------------
# Batch btc-train.pl
#
# $Id: btc-train.pl 587 2010-04-07 09:27:06Z pbressan $
#
# (c) 2002-2008 Expedia.                   www.expediacorporate.fr
#-----------------------------------------------------------------

use strict;

use lib '../libsperl';

use Getopt::Long;

use Expedia::Tools::Logger qw(&debug &notice &warning &error);
use Expedia::XML::Config;
use Expedia::Workflow::TasksProcessor;

my $opt_task;
my $opt_help;

GetOptions(
  "task=s",  \$opt_task,
  "help",    \$opt_help
);

$opt_help = 1
  unless ($opt_task && ($opt_task =~ /^(rail-errors|btc-rail|btc-rail-dev|meetings-rail|meetings-rail-dev)$/));

if ($opt_help) {
  print STDERR ("                           [btc-rail|btc-rail-dev]              (v2 Ravel Gold)\n");
  print STDERR ("                           [meetings-rail|meetings-rail-dev]    (v2 Ravel Gold)\n");
  print STDERR ("                           [rail-errors]\n\n");
  exit(0);
}

my $task = $opt_task;

notice('###############################################################');
notice('############         LANCEMENT DE BTC-TRAIN        ############');

my $config        = Expedia::XML::Config->new('../libsperl/Expedia/Tools/config_DDB.xml',$task);
my $processor = Expedia::Workflow::TasksProcessor->new($task, $config) if (defined $config);

notice('############            FIN DE BTC-TRAIN           ############');
notice('###############################################################');
