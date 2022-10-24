package Expedia::Modules::GAP::RpChange;
#-----------------------------------------------------------------
# Package Expedia::Modules::GAP::RpChange
#
# $Id: RpChange.pm 410 2008-02-11 09:20:59Z pbressan $
#
# (c) 2002-2007 Expedia.                   www.expediacorporate.fr
#-----------------------------------------------------------------

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
  my $h_pnr        = $params->{Position};
  my $refpnr       = $params->{RefPNR};
  
  my $position        = $h_pnr->{$refpnr};

  my $atds = $ab->getTravelDossierStruct;  
  
  my $pos  = $atds->[$position]->{lwdPos};   # Position du LightWeightDossier dans le XML
  my $type = $atds->[$position]->{lwdType};  # Type du LightWeightDossier
  
  debug("pos:".$pos);
  debug("type:".$type);
  
  my $gdsQ = $ab->getGDSQueue({lwdPos => $pos, lwdType => $type});
    
  my $releaseResp = $gdsQ->{IsReleaseResponsibility};
  
  if (defined $releaseResp && $releaseResp eq 'true')
  {
     push (@{$changes->{add}}, { Data => 'RP/'.$gdsQ->{OfficeId}.'/ALL' })
  }


  return 1;
}

1;
