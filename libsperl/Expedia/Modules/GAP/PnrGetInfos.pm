package Expedia::Modules::GAP::PnrGetInfos;
#-----------------------------------------------------------------
# Package Expedia::Modules::GAP::PnrGetInfos
#
# $Id: PnrGetInfos.pm 609 2011-01-06 11:33:36Z pbressan $
#
# (c) 2002-2010 Egencia.                            www.egencia.eu
#-----------------------------------------------------------------

use Data::Dumper;

use Expedia::Tools::Logger      qw(&debug &notice &warning &error);


sub run {
  my $self   = shift;
  my $params = shift;

  my $globalParams = $params->{GlobalParams};
  my $moduleParams = $params->{ModuleParams};
  my $changes      = $params->{Changes};
  my $item         = $params->{Item};
  my $pnr          = $params->{PNR};
  my $ab           = $params->{ParsedXML};
  my $WBMI         = $params->{WBMI};

  # Module de reconnaissance des PAX entre fichier XML et PNR Amadeus
  my $travellers   = $ab->getTravellerStruct();
  my $market       = $ab->getCountryCode({trvPos => $ab->getWhoIsMain});
  my $nbPaxXML     = scalar(@$travellers);
  my $nbPaxPNR     = scalar(@{$pnr->{PAX}});

  debug(' PAX XML  = '.Dumper($travellers));
  debug(' PAX PNR  = '.Dumper($pnr->{PAX}));
  debug('nbPaxXML  = '.$nbPaxXML);
  debug('nbPaxPNR  = '.$nbPaxPNR);

  # Le vrai nombre de PAX est celui du PNR bien sûr !
  if ($nbPaxPNR > $nbPaxXML) {
    notice('Number of Pax in PNR is superior compared to XML !');
    $WBMI->addReport({ Code => 13, PnrId  => $pnr->{_PNR} });
  # $WBMI->status('FAILURE'); Effectué dans Workflow::TaskProcessor.pm
    return 0;
  }
  
  # Cela se produit quelque fois [...] C'est surtout pour tracer ce problème.
  if ($nbPaxPNR < $nbPaxXML) {
    notice('Number of Pax in PNR is inferior compared to XML !');
    $WBMI->addReport({ Code => 22, PnrId  => $pnr->{_PNR} });
  }
  
  # On va aller voir s'il y a autant de lignes RM *PERCODE que prévu
  my @perCodes = ();
  LINE: foreach my $i (@{$pnr->{PNRData}}) {
    if ($i->{Data} =~ /^RM\s+\*PERCODE\s*(\d+)(\/P\d)?/) {
      push @perCodes, { PERCODE => $1, PAXNUM => $2 };
    }
  }
  
  debug('@perCodes = '.Dumper(\@perCodes));
  
  if (scalar(@perCodes) < $nbPaxPNR) {
    notice('Percode missing for 1 of the travellers [...]');
    #----------------------------------------------------------
    # Si le nombre de passagers dans le PNR et XML est egal a 1
    #  on considere que nous avons le bon. Nous l'ajoutons au dossier.
    if  (($nbPaxPNR == 1) && ($nbPaxXML == 1)) {
      my $perCode = $travellers->[0]->{PerCode};
      _addPerCodeRemark($perCode, $pnr);
      push @perCodes, { PERCODE => $perCode, PAXNUM => '/P1' };
    }
    #----------------------------------------------------------
    else {
      notice('Percode missing for 1 of the travellers !');
      return 0;
    }
  }
  elsif (scalar(@perCodes) > $nbPaxPNR) {
    debug('scalar(@perCodes) > $nbPaxPNR');
    if ($nbPaxPNR == 1) {
      my $tmpPerCodes = {}; 
      my @fnlPerCodes = (); 
      foreach (@perCodes) {
        next if exists $tmpPerCodes->{$_->{PERCODE}};
        $tmpPerCodes->{$_->{PERCODE}} = 1;
        push @fnlPerCodes, $_; 
      }
      @perCodes = (); 
      @perCodes = @fnlPerCodes;
      debug('@perCodes = '.Dumper(\@perCodes));
      if (scalar(@perCodes) > $nbPaxPNR) {
        notice('Percode mismatch between Amadeus and website !');
        return 0;      
      }
    }
    else {
      notice('Percode mismatch between Amadeus and website !');
      return 0;
    }
  }
  
  foreach (@perCodes) {
    my $perCode =  $_->{PERCODE};
    my $xmlPax  = _getPax($perCode, $travellers, 1);
    if (!defined $xmlPax) {
      notice('Percode mismatch between Amadeus and website !');
      return 0;
    }
  }
  
  # <CAS 1> Il n'y a qu'un seul passager dans le dossier
  if ($nbPaxPNR == 1) {
    debug('<CAS 1>');
    my $pnrPax = $pnr->{PAX}->[0];
    my $xmlPax = $travellers->[0];
    
    $xmlPax->{PaxNum}    = 'P1';
    $pnrPax->{PerCode}   = $xmlPax->{PerCode};
    $pnrPax->{Position}  = $xmlPax->{Position};
  }
  # -------------------------------------------------------------
  # <CAS 2> MultiPax
  elsif ($nbPaxPNR > 1) {
    debug('<CAS 2>');
    # On va aller checker si les PERCODE des PAX correspondent
    foreach (@perCodes) {
      my $perCode =  $_->{PERCODE};
      my $paxNum  =  $_->{PAXNUM};
         $paxNum  =~ s/\/P(\d)/$1/ if (defined $paxNum && $paxNum =~ /\/P\d/);
      my $xmlPax  = _getPax($perCode, $travellers);
      if ((!defined $xmlPax) || (!defined $paxNum) || ($paxNum !~ /^\d$/)) {
        notice('Percode mismatch between Amadeus and website !');
        return 0;
      } else {
        $xmlPax->{PaxNum} = 'P'.$paxNum;
        $pnr->{PAX}->[$paxNum-1]->{PerCode}  = $xmlPax->{PerCode};
        $pnr->{PAX}->[$paxNum-1]->{Position} = $xmlPax->{Position};
      }
    }
  }
  
  foreach my $xmlPax (@$travellers) {
    next if (!exists $xmlPax->{PaxNum});
    # _________________________________________________________________
    # Si il s'agit d'un passager sur lequel nous devons porter 
    #   une attention particulière, nous l'indiquons [...]
    if ($xmlPax->{IsVIP} eq 'true') {
      $WBMI->addReport({
      Code      => 24,
      PnrId     => $pnr->{_PNR},
      PaxNumber => $xmlPax->{PaxNum},
      PerCode   => $xmlPax->{PerCode}, });
    }
  }
  
  my $finalTravellers = [];
  if ($nbPaxPNR <= $nbPaxXML) {
    foreach (@$travellers) {
      push @$finalTravellers, $_ if exists $_->{PaxNum};
    }
  }
  # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
  
  debug(' PAX XML = '.Dumper($finalTravellers));
  
  # Stockage pour utilisation ultérieure
  $pnr->{Travellers} = $finalTravellers;
  
  return 1;
}

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Reconnait un passager XML par rapport à son PERCODE
sub _getPax {
  my $perCode        = shift;
  my $travellers     = shift;
  my $doNotAssociate = shift;
  
  $doNotAssociate = 0
    unless ((defined $doNotAssociate) && ($doNotAssociate == 1));
  
  foreach my $xmlPax (@$travellers) {
    next if (exists $xmlPax->{associated}); # Déjà associé
    if ($perCode eq $xmlPax->{PerCode}) {
      $xmlPax->{associated} = 1 unless ($doNotAssociate == 1);
      return $xmlPax;
    }
  }
  
  return undef;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Ajout la RM *PERCODE dans le cas ou elle n'est pas présente
#   dans le PNR et que la condition suivante est remplie :
#     * 1 passager dans le PNR
#     * 1 passager dans le XML 
sub _addPerCodeRemark {
	my $perCode = shift;
	my $pnr     = shift;

	if ((!defined $perCode) || ($perCode !~ /\d+/) ||
			(!defined $pnr)     || (ref($pnr) ne 'Expedia::GDS::PNR')) {
		notice('Wrong parameter used for this method.');
		return 0;
	}
	
	notice('Adding PerCode remark and reloading PNR.');
	
	my $GDS = $pnr->{_GDS}; 
	my $RM  = 'RM *PERCODE '.$perCode.'/P1';
	
	$GDS->RT(PNR=>$pnr->{PNRId});
	$GDS->command(Command=>$RM, NoIG=>1, NoMD=>1);
	
	# ---------------------------------------------------------------------
  # Validation des modifications
  $GDS->command(Command=>'RF'.$GDS->modifsig, NoIG=>1, NoMD=>1);
  $GDS->command(Command=>'ER',                NoIG=>1, NoMD=>1);
  $GDS->command(Command=>'ER',                NoIG=>1, NoMD=>1);
  # ---------------------------------------------------------------------
  
  # ---------------------------------------------------------------------
  # Il faut reloader le PNR
  $pnr->reload;
  $GDS->IG;
  # ---------------------------------------------------------------------  

	return 1;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

1;
