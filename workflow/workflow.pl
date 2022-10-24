#!/usr/bin/perl -w
#-----------------------------------------------------------------
# Batch workflow.pl
#
# $Id: workflow.pl 410 2008-02-11 09:20:59Z pbressan $
#
# (c) 2002-2007 Expedia.                   www.expediacorporate.fr
#-----------------------------------------------------------------

use strict;

use lib '../libsperl';

use Getopt::Long;

use Expedia::XML::Config;
use Expedia::Tools::Logger qw(&debug &notice &warning &error);
use Expedia::Workflow::TasksProcessor;

my $opt_task;
my $opt_help;
my $start_version;
my $stop_version;

GetOptions(
  "task=s",  \$opt_task,
  "start_version=s", \$start_version,
  "stop_version=s",\$stop_version,
  "help",    \$opt_help
);


   $opt_help = 1
   if ( (!$opt_task || ($opt_task !~ /^(booking|synchro)$/) )
			|| (
					( ($opt_task =~ /^synchro$/) &&
						( ( ( (defined($start_version)) && ($start_version !~ m/^\d+$/) ) )      ||
							( ((defined($stop_version)) && ($stop_version =~ m/^\d+$/)) && ( (!defined($start_version)) || ($start_version !~ m/^\d+$/) ) )
						) 
					)
				) 
	);

   
  

if ($opt_help) {
  print STDERR ("\nUsage: $0 --task=[booking|synchro]\n  ");
  print STDERR ("\nOptionnal Parameter for DEBUG Mode (synchro only) : --start_version=[VERSION_NUMBER] --stop_version=[VERSION_NUMBER] \n\n");
  exit(0);
}

my $task = 'workflow-'.$opt_task;



if (($opt_task =~ /^synchro$/) &&(defined($start_version)) && ($start_version =~ m/^\d+$/) ) {

	notice('###############################################################');
	notice('############         LANCEMENT DE WORKFLOW SYNCHRO EN MODE DEBUG       ############');
	notice('#########      START_VERSION='.$start_version.'                           #########');
    notice('#########      STOP_VERSION='.$stop_version.'                           #########') if (defined($stop_version));
	my $config        = Expedia::XML::Config->new('../libsperl/Expedia/Tools/config_DDB.xml',$task);
	my $processor = Expedia::Workflow::TasksProcessor->new($task, $config, undef, undef, undef,undef,$start_version,$stop_version);



}
else{

	notice('###############################################################');
	notice('############         LANCEMENT DE WORKFLOW         ############');

	my $config        = Expedia::XML::Config->new('../libsperl/Expedia/Tools/config_DDB.xml',$task);
	my $processor = Expedia::Workflow::TasksProcessor->new($task, $config);

}




notice('############            FIN DE WORKFLOW            ############');
notice('###############################################################');
