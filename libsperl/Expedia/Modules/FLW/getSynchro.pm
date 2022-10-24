package Expedia::Modules::FLW::getSynchro;
#-----------------------------------------------------------------
# Package Expedia::Modules::FLW::getSynchro
#
# $Id: getSynchro.pm 410 2008-02-11 09:20:59Z pbressan $
#
# (c) 2002-2007 Expedia.                   www.expediacorporate.fr
#-----------------------------------------------------------------

use strict;
use Data::Dumper;

use Expedia::Tools::Logger              qw(&debug &notice &warning &error);
use Expedia::Databases::WorkflowManager qw(&getNewMsgRelatedToSynchro &getNewMsgRelatedToSynchro_Debug);

sub run {
  my $self   = shift;
  my $params = shift;
  
  my $globalParams = $params->{GlobalParams};
  my $moduleParams = $params->{ModuleParams};
  my $changes      = $params->{Changes};
  my $start_version = $globalParams->{_START_VERSION};
  my $stop_version = $globalParams->{_STOP_VERSION} ;

  my $items;
  
   if (defined($start_version) && $start_version =~ m/^\d+$/) 
  {
  
	   # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
	   # Recupération des messages liés à la SYNCHRO des profils -- DEBUG MODE
  
		$items = &getNewMsgRelatedToSynchro_Debug($start_version,$stop_version);
  
  }
  else
  {
  
	  # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
	  # Recupération des messages liés à la SYNCHRO des profils
	  
	  $items = &getNewMsgRelatedToSynchro;
	  	 
  }
  
   # Fin : Recupération des messages liés à la SYNCHRO des profils
	  # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
	  
  return [] if ((!defined $items) || (scalar @$items == 0));  
  
  return $items;
}

1;
