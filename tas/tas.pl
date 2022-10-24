#!/usr/bin/perl -w
#-----------------------------------------------------------------
# Batch tas.pl
#
# $Id: tas.pl 649 2011-04-05 10:23:32Z pbressan $
#
# (c) 2002-2007 Expedia.                   www.expediacorporate.fr
#-----------------------------------------------------------------

use strict;
use Data::Dumper;
use Getopt::Long;

use lib '../libsperl';

use Expedia::Tools::Logger qw(&debug &notice &warning &error &monitore);
use Expedia::XML::Config;
use Expedia::Workflow::TasksProcessor;
use Expedia::Tools::GlobalVars qw($hMarket);

my $opt_help;
my $opt_task;
my $opt_agcy;
my $opt_prdt;
my $opt_pnr;

GetOptions(
  'agency=s',  \$opt_agcy,
  'task=s',    \$opt_task,
  'product=s', \$opt_prdt,
  'pnr=s'   , \$opt_pnr,
  'help',      \$opt_help
);

$opt_help = 1
  unless (($opt_task && $opt_agcy && $opt_prdt)                    &&
          ($opt_task =~ /^(tas|tas-finish|tas-report|tas-stats)$/) &&          
          ($opt_prdt =~ /^(air|rail)$/));

if ($opt_help) {
  print STDERR ("\nUsage: $0 --agency  = [Paris|Manchester|Bruxelles|Munchen|Barcelona|Sydney|Delhi|Varsovie|Prague|Zurich|Amsterdam|Istanbul|Copenhague|Helsinki|Oslo|Stockholm|Milan|Singapour|Hongkong|Manille|Dublin]\n".
                "              --product = [air|rail]\n".
                " (DEFAULT)    --task    = [tas|tas-finish|tas-report|tas-stats]\n".
                " (OPTIONNAL)  --pnr     = XXXXX\n");
  exit(0);
}



my $task = $opt_task.'-'.$opt_agcy.':'.$opt_prdt;

my $log_task='';
if ($opt_task eq 'tas') {$log_task='TAS_TICKETING';}
if ($opt_task eq 'tas-finish'){ $log_task='TAS_FINISH';}
if ($opt_task eq 'tas-stats'){ $log_task='TAS_STATS';}
if ($opt_task eq 'tas-report'){ $log_task='TAS_REPORT';}

&monitore($log_task,'',"INFO",$hMarket->{$opt_agcy},$opt_prdt,'','',"START");


notice('###############################################################');
notice('############            LANCEMENT DE TAS           ############');

my $config        = Expedia::XML::Config->new('../libsperl/Expedia/Tools/config_DDB.xml',$task);
my $processor = Expedia::Workflow::TasksProcessor->new($task, $config,$opt_pnr) if (defined $config);

notice('############               FIN DE TAS              ############');
notice('###############################################################');

&monitore($log_task,'',"INFO",$hMarket->{$opt_agcy},$opt_prdt,'','',"END");
