#!/usr/bin/perl -w
#-----------------------------------------------------------------
# Batch tracking.pl
#
# $Id: tracking.pl 530 2009-06-10 14:59:37Z pbressan $
#
# (c) 2002-2009 Expedia.                   www.expediacorporate.fr
#-----------------------------------------------------------------

use strict;

use lib '../libsperl';

use Getopt::Long;

use Expedia::XML::Config;
use Expedia::Tools::Logger qw(&debug &notice &warning &error);
use Expedia::Workflow::TasksProcessor;

my $opt_help;
my $opt_mrkt;

GetOptions(
  "market=s",\$opt_mrkt,
  "help",    \$opt_help
);

my $task = 'tracking-'.$opt_mrkt;

notice('###############################################################');
notice('############         LANCEMENT DE TRACKING         ############');

my $config        = Expedia::XML::Config->new('../libsperl/Expedia/Tools/config_DDB.xml',$task);
my $processor = Expedia::Workflow::TasksProcessor->new($task, $config) if (defined $config);

notice('############            FIN DE TRACKING            ############');
notice('###############################################################');
