package Expedia::Modules::TAS::InsertFakeAPM;
#-----------------------------------------------------------------
# Package Expedia::Modules::TAS::InsertFakeApm
#
# $Id: InsertFakeAPM.pm 517 2009-06-10 13:16:17Z pbressan $
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
  my $GDS          = $params->{GDS};
  my $btcProceed   = $params->{BtcProceed};
  
  my $market       = $globalParams->{market};


    return 1 if ($market ne 'GB'); # On applique ceci au marché GB uniquement

    # =====================================================================
    # S'il existe déjà une ligne de APM, ce n'est pas la peine [...]
    my $apmFound = 0;
    foreach (@{$pnr->{'PNRData'}}) {
      last if ($apmFound == 1);
      $apmFound = 1 if ($_->{Data} =~ /^SK CTCM BA/);
    }
    return 1 if ($apmFound == 1);
    # On ne fait rien, également si le trajet ne comporte pas de vols BA
    my $bafFound = 0; # baf for BA flight
    foreach (@{$pnr->{Segments}}) {
      last if ($bafFound == 1);
      $bafFound = 1 if (substr($_->{'Data'}, 0, 2) eq 'BA');
    }
    # =====================================================================

    # =====================================================================
    if (($apmFound == 0) && ($bafFound == 1)) {
      my $GDS = $pnr->{_GDS};
         $GDS->RT(PNR=>$pnr->{PNRId}, NoIG=>1);
         $GDS->command(Command=>'SKCTCMBA-447888111222',  NoIG=>1, NoMD=>1);
         $GDS->command(Command=>'RF'.$GDS->modifsig,      NoIG=>1, NoMD=>1);
         $GDS->command(Command=>'ER',                     NoIG=>1, NoMD=>1);
         $GDS->command(Command=>'ER',                     NoIG=>1, NoMD=>1);
    }
    # =====================================================================


  return 1;
}

1;
