package Expedia::Modules::TAS::RetrievePNR;
#-----------------------------------------------------------------
# Package Expedia::Modules::TAS::RetrievePNR
#
# $Id: RetrievePNR.pm 410 2008-02-11 09:20:59Z pbressan $
#
# (c) 2002-2007 Expedia.                   www.expediacorporate.fr
#-----------------------------------------------------------------

use strict;
use Data::Dumper;

use Expedia::Tools::Logger qw(&debug &notice &warning &error);
use Expedia::Tools::GlobalVars qw($cnxMgr);

sub run {
  my $self   = shift;
  my $params = shift;

  my $globalParams = $params->{GlobalParams};
  my $moduleParams = $params->{ModuleParams};
  my $changes      = $params->{Changes};
  my $item         = $params->{Item};
  my $PNR          = $params->{PNR};
  my $ab           = $params->{ParsedXML};

  $PNR->getXML($ab->getTpid({trvPos => $ab->getWhoIsMain})); # LoL !

  return 1;  
}

1;
