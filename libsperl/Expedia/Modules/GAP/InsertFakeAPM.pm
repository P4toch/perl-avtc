package Expedia::Modules::GAP::InsertFakeAPM;
#-----------------------------------------------------------------
# Package Expedia::Modules::GAP::InsertFakeApm
#
# $Id: InsertFakeAPM.pm 508 2009-06-10 13:09:24Z pbressan $
#
# (c) 2002-2008 Expedia.                   www.expediacorporate.fr
#-----------------------------------------------------------------

use strict;
use Data::Dumper;

use Expedia::Tools::Logger qw(&debug &notice &warning &error);

sub run {
  my $self   = shift;
  my $params = shift;

  my $globalParams = $params->{GlobalParams};
  my $moduleParams = $params->{ModuleParams};
  my $changes      = $params->{Changes};
  my $item         = $params->{Item};
  my $pnr          = $params->{PNR};
  my $ab           = $params->{ParsedXML};
  
  my $market       = $ab->getCountryCode({trvPos => $ab->getWhoIsMain });

  return 1 if ($market ne 'GB'); # On applique ceci au marché GB uniquement

  # =====================================================================
  # S'il existe déjà une ligne de APM, ce n'est pas la peine [...]
  my $apmFound = 0;
  foreach (@{$pnr->{'PNRData'}}) {
    last if ($apmFound == 1);
    if ($_->{Data} =~ /^SK CTCM BA/) {$apmFound = 1; }
  }
  return 1 if ($apmFound == 1);
  return 1 if (scalar(@{$pnr->{Segments}}) == 0);
  # On ne fait rien, également si le trajet ne comporte pas de vols BA
  my $bafFound = 0; # baf for BA flight
  foreach (@{$pnr->{Segments}}) {
    last if ($bafFound == 1);
    $bafFound = 1 if ((defined $_->{'Data'}) && (substr($_->{'Data'}, 0, 2) eq 'BA'));
  }
  # =====================================================================

  # =====================================================================
  push (@{$changes->{add}}, { Data => 'SKCTCMBA-447888111222' })
    if (($apmFound == 0) && ($bafFound == 1));
  # =====================================================================

  return 1;
}

1;
