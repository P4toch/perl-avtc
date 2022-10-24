#!/usr/bin/perl -w
#-----------------------------------------------------------------
# Batch queue-pnr.pl
#
# $Id: queue-pnr.pl 410 2008-02-11 09:20:59Z pbressan $
#
# (c) 2002-2007 Expedia.                   www.expediacorporate.fr
#-----------------------------------------------------------------

use strict;

use lib '../libsperl';

use Getopt::Long;

use Expedia::XML::Config;
use Expedia::Workflow::TasksProcessor;
use Expedia::Tools::Logger qw(&debug &notice &warning &error);

my $opt_help;
my $opt_mrkt;

GetOptions(
  "market=s",\$opt_mrkt,
  "help",    \$opt_help
);

my $task = 'queuing-'.$opt_mrkt;

notice('###############################################################');
notice('############        LANCEMENT DE QUEUE-PNR         ############');

my $config        = Expedia::XML::Config->new('../libsperl/Expedia/Tools/config_DDB.xml',$task);
my $processor = Expedia::Workflow::TasksProcessor->new($task, $config) if (defined $config);

notice('############            FIN DE QUEUE-PNR           ############');
notice('###############################################################');
