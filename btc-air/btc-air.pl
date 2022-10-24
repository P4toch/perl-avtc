#!/usr/bin/perl -w
#-----------------------------------------------------------------
# Batch btc-air.pl
#
# $Id: btc-air.pl 644 2011-04-05 09:50:31Z pbressan $
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
my $opt_pnr;

GetOptions(
  'market=s',\$opt_mrkt,
  'task=s',  \$opt_task,
  'pnr=s',   \$opt_pnr,
  'help',    \$opt_help
);

$opt_help = 1
  unless (($opt_task && $opt_mrkt) &&
         (($opt_task =~ /^(btc-air|btc-air-dev|meetings-air|meetings-air-dev)$/)));
          
$opt_help = 1
  if     ((defined $opt_task) && (defined $opt_mrkt) &&
          ($opt_task =~ /^(meetings-air|meetings-air-dev)$/) &&
          ($opt_mrkt ne 'FR')); # Meetings uniquement pour la France


if ($opt_help) {
  print STDERR ("\nUsage: $0 --market=[FR|BE|...] --task=[btc-air|btc-air-dev]");
  print STDERR ("\nUsage: $0 --market=[FR|BE|...] --task=[btc-air|btc-air-dev] --pnr=[xxxxxx]");
  print STDERR ("\nUsage: $0 --market=[FR]                            --task=[meetings-air|meetings-air-dev]\n\n");
  exit(0);
}

my $task = '';
   $task = $opt_task.'-'.$opt_mrkt          if ($opt_task =~ /^(btc-air|meetings-air)$/);
   $task = 'btc-air-'.$opt_mrkt.'-dev'      if ($opt_task =~ /^(btc-air-dev)$/);
   $task = 'meetings-air-'.$opt_mrkt.'-dev' if ($opt_task =~ /^(meetings-air-dev)$/);

notice('###############################################################');
notice("############         LANCEMENT DE GAP-AIR $opt_mrkt $opt_pnr      ############");

my $config        = Expedia::XML::Config->new('../libsperl/Expedia/Tools/config_DDB.xml',$task);
my $processor = Expedia::Workflow::TasksProcessor->new($task, $config, $opt_pnr) if ( defined $config );

notice("############            FIN DE GAP-AIR $opt_mrkt $opt_pnr     ############");
notice('###############################################################');
