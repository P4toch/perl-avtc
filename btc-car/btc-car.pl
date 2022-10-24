#!/usr/bin/perl -w
#-----------------------------------------------------------------
# Batch btc-car.pl
#
# $Id: btc-car.pl 644 2014-01-16 09:50:31Z sdubuc $
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
my $opt_mrkt;

GetOptions(
  'market=s',\$opt_mrkt,
  'task=s',  \$opt_task,
  'help',    \$opt_help
);

$opt_help = 1
  unless (($opt_task && $opt_mrkt) &&
         (($opt_task =~ /^(btc-car|btc-car-dev)$/)));

if ($opt_help) {
  print STDERR ("\nUsage: $0 --market=[FR|BE|...] --task=[btc-car|btc-car-dev]");
  print STDERR ("\nUsage: $0 --market=[FR]                            --task=[btc-car|btc-car-dev]\n\n");
  exit(0);
}

my $task = '';
   $task = $opt_task.'-'.$opt_mrkt          if ($opt_task =~ /^(btc-car)$/);
   $task = 'btc-car-'.$opt_mrkt.'-dev'      if ($opt_task =~ /^(btc-car-dev)$/);

notice('###############################################################');
notice("############         LANCEMENT DE BTC-CAR $opt_mrkt       ############");

my $config        = Expedia::XML::Config->new('../libsperl/Expedia/Tools/config_DDB.xml',$task);
my $processor = Expedia::Workflow::TasksProcessor->new($task, $config) if (defined $config);

notice("############            FIN DE BTC-CAR $opt_mrkt          ############");
notice('###############################################################');
