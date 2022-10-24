package Expedia::Modules::GAP::AFSubCards;
#-----------------------------------------------------------------
# Package Expedia::Modules::GAP::AFSubCards
#
# $Id: AFSubCards.pm 492 2008-12-10 13:51:20Z pbressan $
#
# (c) 2002-2007 Expedia.                   www.expediacorporate.fr
#-----------------------------------------------------------------

use strict;
use Data::Dumper;

use Expedia::Tools::Logger qw(&debug &notice &warning &error);

sub run {
  my $self   = shift;
  my $params = shift;

  my $globalParams   = $params->{GlobalParams};
  my $moduleParams   = $params->{ModuleParams};
  my $changes        = $params->{Changes};
  my $item           = $params->{Item};
  my $pnr            = $params->{PNR};
  my $ab             = $params->{ParsedXML};
  my $WBMI           = $params->{WBMI};
 
  my $h_pnr        = $params->{Position};
  my $refpnr       = $params->{RefPNR};
  
  my $position        = $h_pnr->{$refpnr};
       
  my $atds = $ab->getTravelDossierStruct;   
    
  my $lwdPos         = $atds->[$position]->{lwdPos};
  my $countryCode    = $ab->getCountryCode({trvPos => $ab->getWhoIsMain});
  my $airSegments    = $ab->getAirSegments({lwdPos => $lwdPos});
  my $departureDate  = _dateXML($airSegments->[0]->{DepDateTime});
  my $hasAFintoSegs  = _hasAFintoSegments($airSegments);
  my $productPricing = $ab->getAirProductPricing({lwdPos => $lwdPos});
  my $travellers     = $pnr->{Travellers};
    
# return 1 unless ($countryCode eq 'FR'); # Commenté le 07 Août 2008 - Céline me dit qu'il peut y avoir des cartes abos AF sur les autres POS !
  return 1 unless ($hasAFintoSegs == 1);
# return 1 unless ($productPricing->{FareType} eq 'TARIF_ABONNEMENT');

  # ______________________________________________________________
  # Dans le cas d'une synchro rapide, le tarif est peut-être PUBLIC
  #   mais il s'agit bien d'une tarification SUBSCRIPTION =X
  if ($productPricing->{FareType} eq 'TARIF_PUBLIC') {
    my $airFare = _getPnrAirFare($pnr);
    debug('airFare = '.$airFare);
    return 1 if ($airFare ne 'SUBSCRIPTION');
    $pnr->getXML($ab->getTpid({trvPos => $ab->getWhoIsMain})); # LoL !
    return 1 unless (_hasSintoClassOfService($pnr) == 1);
    $productPricing->{FareType} = 'TARIF_ABONNEMENT';
  }
  # ______________________________________________________________
  
  return 1 unless ($productPricing->{FareType} eq 'TARIF_ABONNEMENT');
  
  my $GDS = $pnr->{_GDS};
     $GDS->RT(PNR=>$pnr->{'PNRId'}, NoMD=>1, NoPostIG=>1);
    
  my $message1 = 'RM @@ CHECK CARTE ABO AF';
  my $message2 = ' ET RETARIFER DOSSIER EN TARIF ABO @@';
    
  my $lines   = [];
    
  PAX: foreach my $pax (@$travellers) {
      
    my $lsCards      = $ab->getTravellerLoyaltySubscriptionCards({trvPos => $pax->{Position}});
    my $AFSubCard    = [];
    my $AFSubCard1   = _cardFilter($lsCards);
    my $AFSubCard2   = _cardFilterWithValidity($lsCards, $departureDate);
    my $nbAFSubCard1 = scalar(@$AFSubCard1);
    my $nbAFSubCard2 = scalar(@$AFSubCard2);
    my $chkCarteAbo  = 1;
      
    # ----------------------------------------------------------------------
    # On détermine ce que l'on fait ici
    if ($nbAFSubCard1 == 1) { $AFSubCard = $AFSubCard1; $chkCarteAbo = 0; }
    if ($nbAFSubCard2 == 1) { $AFSubCard = $AFSubCard2; $chkCarteAbo = 0; }
    # ----------------------------------------------------------------------      
      
    if ($chkCarteAbo) {
      BOUCLE: {
        $GDS->command(Command=>$message1.'/'.$pax->{PaxNum}.$message2, NoIG=>1, NoMD=>1);
        $WBMI->addReport({ Code        => 1,
                           PnrId       => $pnr->{_PNR},
                           AmadeusMesg => $message1.'/'.$pax->{PaxNum}.$message2,
                           PaxNumber   => $pax->{PaxNum},
                           PerCode     => $pax->{PerCode}});
        $GDS->command(Command=>'RF'.$GDS->{_MODIFSIG}, NoIG=>1, NoMD=>1);
        $lines = $GDS->command(Command=>'ER', NoIG=>1, NoMD=>1);
        if ( (grep (/CHANGTS SIMULT DANS PNR/, @$lines)) ||
		     (grep (/VERIFIER LE PNR ET REESSAYER/ ,   @$lines)) ||
		     (grep (/VERIFIER LE CONTENU DU PNR/ ,   @$lines)) ) {
          $GDS->command(Command=>'IG', NoIG=>0, NoMD=>1);
          $GDS->RT(PNR=>$pnr->{'PNRId'}, NoMD=>1, NoPostIG=>1);
          redo BOUCLE;
        }
      } # Fin BOUCLE
      next PAX;
    } else {
      my $cardNumber = $AFSubCard->[0]->{CardNumber}; # Je prends la première.
      my $command    = "FDAF $cardNumber/".$pax->{PaxNum};
      BOUCLE: {
        $lines = $GDS->command(Command=>$command, NoIG=>1, NoMD=>1);
        if (grep(/FORMAT ERRONE/, @$lines)) {
	        $GDS->command(Command=>$message1.'/'.$pax->{PaxNum}.$message2, NoIG=>1, NoMD=>1);
          $WBMI->addReport({ Code        => 1,
                             PnrId       => $pnr->{_PNR},
                             AmadeusMesg => $message1.'/'.$pax->{PaxNum}.$message2,
                             PaxNumber   => $pax->{PaxNum},
                             PerCode     => $pax->{PerCode}});
          $GDS->command(Command=>'RF'.$GDS->{_MODIFSIG}, NoIG=>1, NoMD=>1);
          $GDS->command(Command=>'ER', NoIG=>1, NoMD=>1);            
        } else {
          $lines = $GDS->command(Command=>'FXP', NoIG=>1, NoMD=>1);
	        if (grep(/REDUCTION NON VALABLE/, @$lines)          || 
	            grep(/CONTROLER NOM\/PRENOM/, @$lines)          ||
	            grep(/PROBLEME ACCES REFERENTIEL/, @$lines)     ||
	            grep(/NUMERO NON VALIDE-MCO MANQUANT/, @$lines) ||
	            grep(/CARTE NON VALABLE/, @$lines)              ||
	            grep(/VERIFICATION DE CARTE NON EFFECTUEE/, @$lines)) {
            $GDS->command(Command=>'IG', NoIG=>1, NoMD=>1);	                
	          $lines = $GDS->RT(PNR=>$pnr->{'PNRId'}, NoMD=>1, NoPostIG=>1);
	          $GDS->command(Command=>$message1.'/'.$pax->{PaxNum}.$message2, NoIG=>1, NoMD=>1);
            $WBMI->addReport({ Code        => 1,
                               PnrId       => $pnr->{_PNR},
                               AmadeusMesg => $message1.'/'.$pax->{PaxNum}.$message2,
                               PaxNumber   => $pax->{PaxNum},
                               PerCode     => $pax->{PerCode}});
	        }
	        $GDS->command(Command=>'RF'.$GDS->{_MODIFSIG}, NoIG=>1, NoMD=>1);
          $lines = $GDS->command(Command=>'ER', NoIG=>1, NoMD=>1);
             if ( (grep (/CHANGTS SIMULT DANS PNR/, @$lines)) ||
		     (grep (/VERIFIER LE PNR ET REESSAYER/ ,   @$lines)) ||
		     (grep (/VERIFIER LE CONTENU DU PNR/ ,   @$lines)) ) {
            $GDS->command(Command=>'IG', NoIG=>0, NoMD=>1);
            $GDS->RT(PNR=>$pnr->{'PNRId'}, NoMD=>1, NoPostIG=>1);
            redo BOUCLE;
          }
          $GDS->command(Command=>'ER', NoIG=>1, NoMD=>1);
        }
      } # Fin BOUCLE:
    }
  } # PAX: foreach my $pax (@$travellers)

  return 1;  
}

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Il y a t-il un segment AirFrance dans les Segments ?
sub _hasAFintoSegments {
  my $airSegments = shift;
  
  foreach (@$airSegments) {
    return 1
      if (((exists $_->{ConveyorCode}) && ($_->{ConveyorCode} =~ /^(AF|A5|DB|YS)$/)) ||
          ((exists $_->{VendorCode})   && ($_->{VendorCode}   =~ /^(AF|A5|DB|YS)$/)));
  }

  return 0;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Cette méthode permet de filter les cartes d'abonnement
#   air france uniquement
sub _cardFilter {
  my $lsCards = shift;

  debug('lsCards = '.Dumper($lsCards));

  my @res = ();

  foreach my $card (@$lsCards) {
    next if ($card->{CardType}        ne 'SC');
    next if ($card->{SupplierService} ne 'AIR');
    next if ($card->{CardName}        eq '');
    next if ($card->{SupplierCode}    !~ /^(AF|A5|DB|YS)$/);
    push (@res, $card);
  }

  debug('res = '.Dumper(\@res));

  return \@res;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Cette méthode permet de filter les cartes d'abonnement
#   air france uniquement avec des dates de validité
#   qui correspondent à la date de départ du voyage.
sub _cardFilterWithValidity {
  my $lsCards       = shift;
  my $departureDate = shift;

  debug('lsCards = '.Dumper($lsCards));
  debug('departureDate = '.$departureDate);

  my @res = ();

  foreach my $card (@$lsCards) {
    next if ($card->{CardType}        ne 'SC');
    next if ($card->{SupplierService} ne 'AIR');
    next if ($card->{CardName}        eq '');
    next if ($card->{SupplierCode}    !~ /^(AF|A5|DB|YS)$/);
    next if ($card->{CardValidFrom}   eq '');
    next if ($card->{CardValidTo}     eq '');
    my $cardValidFrom = _dateXML($card->{CardValidFrom});
    my $cardValidTo   = _dateXML($card->{CardValidTo});
    next unless ($cardValidFrom <= $departureDate);
    next unless ($cardValidTo   >= $departureDate);
    push (@res, $card);
  }

  debug('res = '.Dumper(\@res));

  return \@res;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Découpage d'une date de type XML pour pouvoir être
#   comparée avec un comparateur de type < ou > ou =
sub _dateXML {
  my $xmlDate = shift;
  
  debug('xmlDate = '.$xmlDate);

  my $newDate = substr($xmlDate, 0, 4).
                substr($xmlDate, 5, 2).
                substr($xmlDate, 8, 2);
  debug('newDate = '.$newDate);
  
  return $newDate;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Récupérer le AirFare dans un PNR
sub _getPnrAirFare {
  my $pnr = shift;
  
  my $airFare = '';
  
  foreach (@{$pnr->{PNRData}}) {
    if ($_->{Data} =~ /^RM \*AIRFARE (PUBLIC|EXPEDIA|EGENCIA|CORPORATE|SUBSCRIPTION|YOUNG|SENIOR) /) {
      $airFare = $1;
      last;
    }
  }
  
  return $airFare;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Je recherche si j'ai bien du S dans les balises
#  <classOfService>S</classOfService> XML Amadeus.
sub _hasSintoClassOfService {
  my $pnr = shift;
  
  return 0 if (!defined $pnr->{_XMLPNR});
  
  my $pnrdoc = $pnr->{_XMLPNR};
  
  my @originDestinationDetailsNodes = $pnrdoc->getElementsByTagName('originDestinationDetails');
  
  my @itineraryInfoNodes      = ();
  my @tmpNodes                = ();
  
  foreach my $oNode (@originDestinationDetailsNodes) {
    @tmpNodes = $oNode->getElementsByTagName('itineraryInfo');
    push @itineraryInfoNodes, $_ foreach (@tmpNodes);
  }
  
  foreach my $iNode (@itineraryInfoNodes) {
    my $segName        = $iNode->find('elementManagementItinerary/segmentName')->to_literal->value();
    my $classOfService = $iNode->find('travelProduct/productDetails/classOfService')->to_literal->value();
   	next unless ($segName eq 'AIR');
   	next unless ($iNode->find('travelProduct/offpointDetail/cityCode')->to_literal->value());
	  next unless ($iNode->find('relatedProduct/status')->to_literal->value() eq 'HK');
    return 1 if ($classOfService eq 'S');
    next;
  }
  
  return 0;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

1;
