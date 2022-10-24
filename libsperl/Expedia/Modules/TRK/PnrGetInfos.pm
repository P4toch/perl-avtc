package Expedia::Modules::TRK::PnrGetInfos;
#-----------------------------------------------------------------
# Package Expedia::Modules::TRK::PnrGetInfos
#
# $Id: PnrGetInfos.pm 504 2009-03-06 17:45:13Z pbressan $
#
# (c) 2002-2008 Expedia.                   www.expediacorporate.fr
#-----------------------------------------------------------------

use strict;
use Data::Dumper;

use Expedia::Tools::Logger qw(&debug &notice &warning &error);
use Expedia::Tools::GlobalFuncs qw(&stringGdsPaxName);

sub run {
  my $self   = shift;
  my $params = shift;

  my $globalParams = $params->{GlobalParams};
  my $moduleParams = $params->{ModuleParams};
  my $changes      = $params->{Changes};
  my $item         = $params->{Item};
  my $pnr          = $params->{PNR};
  my $b            = $params->{ParsedXML};

  # Module de reconnaissance des PAX entre fichier XML et PNR Amadeus
  my $travellers = $b->getTravellerStruct();
  my $market     = $b->getCountryCode({trvPos => $b->getWhoIsMain});
  my $nbPaxXML   = scalar(@$travellers);
  my $nbPaxPNR   = scalar(@{$pnr->{PAX}});

  debug(' PAX XML = '.Dumper($travellers));
  debug(' PAX PNR = '.Dumper($pnr->{PAX}));
  debug('nbPaxXML = '.$nbPaxXML);
  debug('nbPaxPNR = '.$nbPaxPNR);

  # Le vrai nombre de PAX est celui du PNR bien sûr !
  if ($nbPaxPNR != $nbPaxXML) {
    notice('Pax number is not equal between PNR and XML !');
    return 0;
  }

  # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
  # <CAS 1> Il n'y a qu'un seul passager dans le dossier
  if ($nbPaxPNR == 1) {
    debug('<CAS 1>');
    my $pnrPax = $pnr->{PAX}->[0];
    my $xmlPax = $travellers->[0];
      
    my $pnrLastName;
    my $pnrFirstName;
      
    if (($pnrPax->{'Data'} =~ /^(.*)\/(.*[^\(])(\(.*)$/) ||
        ($pnrPax->{'Data'} =~ /^(.*)\/(.*)$/)) {
      $pnrLastName  = $1;
      $pnrFirstName = $2;
      $_ = stringGdsPaxName($_, $market) foreach ($pnrFirstName, $pnrLastName);
      debug("pnrFirstName = $pnrFirstName.");
      debug("pnrLastName  = $pnrLastName.");
    }

    $xmlPax->{PaxNum}    = 'P1';
    $pnrPax->{PerCode}   = $xmlPax->{PerCode};
    $pnrPax->{Position}  = $xmlPax->{Position};
  }
  # -------------------------------------------------------------
  # <CAS 2> MultiPax
  elsif ($nbPaxPNR > 1) {
    debug('<CAS 2>');
    my @perCodes = ();
    # On va aller voir s'il y a autant de RM *PERCODE que prévu
    LINE: foreach my $i (@{$pnr->{PNRData}}) {
      if ($i->{Data} =~ /^RM\s+\*PERCODE\s+(\d+)(\/P\d)?/) {
        push @perCodes, { PERCODE => $1, PAXNUM => $2 };
      }
    }
    if (scalar(@perCodes) != $nbPaxPNR) {
      notice('<1> Cannot associate PASSENGERS between PNR & XML. Aborting [...]');
      return 0;
    } else {
      # On va aller checker si les PERCODE des PAX correspondent
      foreach (@perCodes) {
        my $perCode =  $_->{PERCODE};
        my $paxNum  =  $_->{PAXNUM};
           $paxNum  =~ s/\/P(\d)/$1/ if (defined $paxNum && $paxNum =~ /\/P\d/);
        my $xmlPax  = _getPax($perCode, $travellers);
        if ((!defined $xmlPax) || (!defined $paxNum) || ($paxNum !~ /^\d$/)) {
          notice('<2> Cannot associate PASSENGERS between PNR & XML. Aborting [...]');
          return 0;
        } else {
          $xmlPax->{PaxNum} = 'P'.$paxNum;
          $pnr->{PAX}->[$paxNum-1]->{PerCode}  = $xmlPax->{PerCode};
          $pnr->{PAX}->[$paxNum-1]->{Position} = $xmlPax->{Position};
        }
      }
    }
  }
  # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

  debug(' PAX XML = '.Dumper($travellers));
  debug(' PAX PNR = '.Dumper($pnr->{PAX}));

  # ---------------------------------------------------------------------
  # Vérification que tous les passagers XML ont été reconnus dans AMADEUS
  foreach my $xmlPax (@$travellers) {
    if (!exists $xmlPax->{PaxNum}) {
      my $fullName = $xmlPax->{FirstName}.' '.$xmlPax->{LastName};
      notice("XMLPAX = '$fullName' hasn't been recognized in Amadeus. Aborting.");
      return 0;
    }
  }
  # ---------------------------------------------------------------------  

  debug(' PAX XML = '.Dumper($travellers));

  # Stockage pour utilisation ultérieure
  $pnr->{Travellers} = $travellers;

  return 1;
}

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Reconnait un passager XML par rapport à son PERCODE
sub _getPax {
  my $perCode    = shift;
  my $travellers = shift;
  
  foreach my $xmlPax (@$travellers) {
    next if (exists $xmlPax->{associated}); # Déjà associé
    if ($perCode eq $xmlPax->{PerCode}) {
      $xmlPax->{associated} = 1;
      return $xmlPax;
    }
  }

  return undef;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

1;
