package Expedia::Modules::GAP::Srfoid;
#-----------------------------------------------------------------
# Package Expedia::Modules::GAP::Srfoid
#
# $Id: Srfoid.pm 410 2008-02-11 09:20:59Z pbressan $
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

  my $atds         = $ab->getAirTravelDossierStruct;
  
  my $lwdPos       = $atds->[0]->{lwdPos};
  my $travellers   = $pnr->{Travellers};
  my $nbPax        = scalar @$travellers;
    
  return 1 if ($nbPax == 1);

  my $sfroids = $ab->getSrfoids({lwdPos => $lwdPos});
  debug('srfoids = '.Dumper($sfroids));
    
  # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
  # MONO PAX
  if ($nbPax == 1) {
    foreach my $srfoid (@$sfroids) {
      my $command  =  'SRFOID-';
         $command .=  $srfoid->{DocType}.$srfoid->{DocNumber}           if ($srfoid->{DocType} ne 'FF');
         $command .=  'FF'.$srfoid->{SupplierCode}.$srfoid->{DocNumber} if ($srfoid->{DocType} eq 'FF');
         $command  =~ s/&//ig;
       push(@{$changes->{add}}, { 'Data' => $command });
    }
  }
  # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
  # MULTI PAX    
  elsif ($nbPax > 1) {

    PAX: foreach my $traveller (@$travellers) {
      my $tPerCode = $traveller->{PerCode};
      SRFOID: foreach my $srfoid (@$sfroids) {
        my $sPerCode = $srfoid->{PerCode};
        next SRFOID unless ($tPerCode eq $sPerCode);
        my $command  =  'SRFOID-';
           $command .=  $srfoid->{DocType}.$srfoid->{DocNumber}.'/'.$traveller->{PaxNum}           if ($srfoid->{DocType} ne 'FF');
           $command .=  'FF'.$srfoid->{SupplierCode}.$srfoid->{DocNumber}.'/'.$traveller->{PaxNum} if ($srfoid->{DocType} eq 'FF');
           $command  =~ s/&//ig;
       push(@{$changes->{add}}, { 'Data' => $command });
      }
    }

  }
  # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
  
  return 1;  
}

1;
