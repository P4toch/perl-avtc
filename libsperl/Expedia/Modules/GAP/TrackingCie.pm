package Expedia::Modules::GAP::TrackingCie;
#-----------------------------------------------------------------
# Package Expedia::Modules::GAP::TrackingCie
#
# $Id: TrackingCie.pm 642 2011-03-18 14:03:38Z pbressan $
#
# (c) 2002-2010 Egencia.                            www.egencia.eu
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
  my $h_pnr        = $params->{Position};
  my $refpnr       = $params->{RefPNR};
  
  my $atds = $ab->getTravelDossierStruct;  

  # ERASING THE "OSI YY CORPORATE" LINES (GAP MALFUNCTION)
  # Désactivé le 11/09/2009 - Demande Céline Perdriau
  # foreach my $line (@{$pnr->{'PNRData'}}) {
  #   next unless ($line->{Data} =~ /OSI\s*YY\s*CORPORATE/);
  #   push(@{$changes->{del}}, $line->{'LineNo'});
  # }
 
  my $position        = $h_pnr->{$refpnr};

  my $countryCode = $ab->getCountryCode({trvPos => $ab->getWhoIsMain });

  debug('countryCode = '.$countryCode);
    
  my $lwdPos    = $atds->[$position]->{lwdPos};
  my $contracts = $ab->getTravelDossierContracts({lwdPos => $lwdPos});
  my $vendors1  = _formatSegments($ab->getAirSegments({lwdPos => $lwdPos}), 1);
  my $vendors2  = _formatSegments($ab->getAirSegments({lwdPos => $lwdPos}), 0);
  my $airFare   = getPnrAirFare($pnr);
    
  # my $hasAfKlDiscountContract = 0;
  # my $hasAfKlTrackingContract = 0;
  
  # ____________________________________________________________________________
  # Spécificité Angleterre
  if ($countryCode eq 'GB') {
    push (@{$changes->{add}}, { Data => 'OS BAPIN 1111'  });
    push (@{$changes->{add}}, { Data => 'OS COPIN 63481' });
  }
  # Spécificité France - Company "OS"
  push (@{$changes->{add}}, { Data => 'OS OS OS0076586729' })
    if (($countryCode eq 'FR') && ($vendors1 =~ /OS/));
  # ____________________________________________________________________________
  
  # ____________________________________________________________________________
  # Tracking Management for Virgin Atlantic in UK
  if (($countryCode eq 'GB') && ($vendors1 =~ /VS/)) {
    
    my $osiLines   = {};
    my $ftLines    = {};
    my $minVsLine  = '9876543210';
    
    foreach (@{$pnr->{'Segments'}}) {
      $minVsLine = $_->{'LineNo'} if (($_->{'Data'} =~ /^VS.*$/) && ($_->{'LineNo'} < $minVsLine)); 
    }
    debug('minVsLine = '.$minVsLine);
    foreach (@{$pnr->{'PNRData'}}) {
      if ($_->{'Data'} =~ /^OSI\s*VS\s*\*?\s*(\w+)(\/.*)?$/) {
        my $osiCode = $1;
        $osiLines->{$_->{'LineNo'}} = $osiCode;
      }
      if ($_->{'Data'} =~ /^FT\s*PAX\s*\*F\*(\w+)(\/.*)?$/) {
        my $ftCode  = $1;
        my $ftSeg   = $2;
        $ftLines->{$_->{'LineNo'}} = $ftCode if (!defined $ftSeg || $ftSeg =~ /\/S$minVsLine/);
      }
    }
    debug('$osiLines = '.Dumper($osiLines));
    debug('$ftLines  = '.Dumper($ftLines));

    # If the booking holds an OSI VS<tracking> line but no Virgin FT line
    #   then delete the OSI VS<tracking> line 
    if ((scalar(keys(%$osiLines)) > 0) && (scalar(keys(%$ftLines)) == 0)) {
      foreach (keys %$osiLines) {
        push (@{$changes->{del}}, $_);
        delete $osiLines->{$_};
      }
    }
    # If the booking holds several OSI VS<tracking> lines with
    #   different dealcodes, delete the one(s) that are not identical
    #   to the dealcode in the FT line
    if ((scalar(keys(%$osiLines)) > 0) && (scalar(keys(%$ftLines)) > 0)) {
      foreach my $osiLine (keys %$osiLines) {
        my $found = 0;
        foreach my $ftLine (keys %$ftLines) {
          $found = 1 if ($osiLines->{$osiLine} eq $ftLines->{$ftLine});
        }
        if (!$found) {
          push (@{$changes->{del}}, $osiLine);
          delete $osiLines->{$osiLine};
        }
      }
    }
    # If the booking holds no OSI VS<tracking> line but holds an FT line
    #   whith dealcode AC010001 or AC1668382 then ...
    foreach my $ftLine (keys %$ftLines) {
      if (scalar(keys(%$osiLines)) == 0) {
        if ($ftLines->{$ftLine} eq 'AC010001') { push (@{$changes->{add}}, { Data => 'OS VS*AC010001/AGENT CORPORATE AGREEMENT' } ) }
        if ($ftLines->{$ftLine} eq 'A1668382') { push (@{$changes->{add}}, { Data => 'OS VS A1668382' } ) }
      }
    }
  }
  # ____________________________________________________________________________
  
  my $delFtLines = 0;
  
  # ----------------------------------------------------------------------------
  # Pour chacun des contrats si les conditions sont remplies, on construit la
  #  phrase de contrat tracking.
  foreach my $contract (@$contracts) {

    # Désactivé le 11/09/2009 - Demande Céline Perdriau
    # $hasAfKlDiscountContract = 1 if (($contract->{ContractType}    eq 'DISCOUNT')  &&
    #                                  ($contract->{SupplierCode}    =~ /^(AF|KL)$/) &&
    #                                  ($contract->{SupplierService} eq 'AIR')       &&
    #                                  ($contract->{CorporateNumber} ne '002000'));
    # $hasAfKlTrackingContract = 1 if (($contract->{ContractType}    eq 'TRACKING')  &&
    #                                  ($contract->{SupplierCode}    =~ /^(AF|KL)$/) &&
    #                                  ($contract->{SupplierService} eq 'AIR'));

    next if ($contract->{ContractType} eq 'DISCOUNT'); # On s'intéresse aux contrats TRACKING

    my $supplierCode = $contract->{SupplierCode};
    debug('supplierCode = '.$supplierCode);

    # Désactivé le 11/09/2009 - Demande Céline Perdriau
    # push (@{$changes->{add}}, { Data => 'OS'.$contract->{SupplierCode}.$contract->{CorporateNumber} })
    #   if ((                                    ($supplierCode !~ /^(BA|AF|UU|KL)$/)    && ($vendors1 =~ /$supplierCode/)) ||
    #       (($countryCode !~ /^(FR|GB|BE)$/) && ($supplierCode =~ /^(BA)$/)             && ($vendors1 =~ /$supplierCode/)) ||
    #       (($countryCode !~ /^(FR)$/)       && ($supplierCode =~ /^(AF|UU)$/)          && ($vendors1 =~ /$supplierCode/)));

    push (@{$changes->{add}}, { Data => 'SKBTOB BA-/'.$contract->{CorporateNumber} })
      if  (($countryCode =~ /^(GB|BE|DE)$/) && ($supplierCode =~ /^(BA)$/)             && ($vendors1 =~ /$supplierCode/));

      #if  (($countryCode =~ /^(FR|BE|IT|ES|DE|IE|SE|CH)$/) && ($supplierCode =~ /^(BA)$/) && ($vendors1 =~ /$supplierCode/));
      # OTRS201103110000194
    push (@{$changes->{add}}, { Data => 'SKDTID BA-'.$contract->{CorporateNumber} })
      if  ( ($supplierCode =~ /^(BA)$/) && ($vendors1 =~ /$supplierCode/));

    # Désactivé le 11/09/2009 - Demande Céline Perdriau
    # push (@{$changes->{add}}, { Data => 'OSYYOIN'.$contract->{CorporateNumber} })
    #   if  (($countryCode eq 'BE')           && ($supplierCode =~ /^(KL|AF)$/)          && ($vendors2 =~ /$supplierCode/));

    push (@{$changes->{add}}, { Data => 'FSAXZE'.$contract->{CorporateNumber} })
      if  (($countryCode eq 'FR')           && ($supplierCode =~ /^(UU)$/)             && ($vendors1 =~ /$supplierCode/));

    # Désactivé le 11/09/2009 - Demande Céline Perdriau
    # push (@{$changes->{add}}, { Data => 'OSYYOIN'.$contract->{CorporateNumber} })
    #   if  (($countryCode eq 'FR')           && ($supplierCode =~ /^(AF|KL|NW|KQ)$/)    && ($vendors1 =~ /$supplierCode/));

    # Enhancement #11286 - Demande Céline Perdriau - 31/08/2010
    # enhancement EGE-51900 - remove the country restriction 
    push (@{$changes->{add}}, { Data => 'FT*'.$contract->{CorporateNumber} })
      if  (($supplierCode =~ /^(IB)$/)             && ($vendors1 =~ /$supplierCode/));
      
    debug('CorporateNumber:'.$contract->{CorporateNumber});
    debug('AirFare:'.$airFare);   
     
    # Enhancement #12301
    push (@{$changes->{add}}, { Data => 'FT*'.$contract->{CorporateNumber} })
      if  (($countryCode eq 'ES')           && ($supplierCode =~ /^(JK)$/)             && ($vendors1 =~ /$supplierCode/));

    # Enhancement #12572
    # remove EGE-46831
    #push (@{$changes->{add}}, { Data => 'FT*'. $contract->{CorporateNumber} })
    #  if  ( ($supplierCode =~ /^(QR)$/)           && ($vendors1 =~ /$supplierCode/) );

    # Enhancement #12572
    push (@{$changes->{add}}, { Data => 'FT*'.$contract->{CorporateNumber} })
      if  ( ($countryCode eq 'FR')           && ($supplierCode =~ /^(SS)$/)            && ($vendors1 =~ /$supplierCode/));

    # Enhancement #57505
	push (@{$changes->{add}}, { Data => 'FT*'.$contract->{CorporateNumber} })
	if ( ($countryCode eq 'PL')              && ($supplierCode =~ /^(LO)$/)            && ($vendors1 =~ /$supplierCode/));

    # Enhancement #EGE-59562
    # Enhancement #EGE-40076
    push (@{$changes->{add}}, { Data => 'FT*'.$contract->{CorporateNumber} })
      if  ( ($countryCode eq 'AU')           && ($supplierCode =~ /^(VA)$/)            && ($vendors1 =~ /$supplierCode/));

	# Enhancement #EGE-114569
	if ( $supplierCode =~ /^(CX|SQ|BR|TG|JL|MI)$/ && $countryCode eq 'SG'  && $vendors1 =~ /$supplierCode/ )
	{
		#EGE-129696
		if ($supplierCode =~ /^(SQ)$/) {
			$delFtLines = 1;
		}
		push (@{$changes->{add}}, { Data => 'FT*'.$contract->{CorporateNumber} });
	}   
	  
  }
  
  if ($delFtLines == 1) {
    foreach (@{$pnr->{PNRData}}) {
      if ($_->{Data} =~ /^FT /) {
        push(@{$changes->{del}}, $_->{LineNo});
      }
    }
  }

  # ----------------------------------------------------------------------------

  # Si j'ai un contrat TRACKING et un contrat DISCOUNT AirFrance/KLM
  # Désactivé le 11/09/2009 - Demande Céline Perdriau
  # push (@{$changes->{add}}, { Data => 'OSAF CORPORATE;OSKL CORPORATE' })
  #   if (($hasAfKlDiscountContract == 1) &&
  #       ($hasAfKlTrackingContract == 1) &&
  #       ($countryCode eq 'FR'));
  
  # Tous les pays - Company "AF" -  Demande Corinne Desimeur le 20/11/2008
  # Si on a un contrat Discount "AF" - Modif Céline Perdriau le 26/02/2009
  # Désactivé le 11/09/2009 - Demande Céline Perdriau
  # push (@{$changes->{add}}, { Data => 'SKTLPWAF-CORPORATE' })
  #   if (($vendors1 =~ /AF/) && ($hasAfKlDiscountContract));

  return 1;  
}

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Fonction visant à applanir les segments
sub _formatSegments {
  my $h_segments = shift;
  my $substitute = shift;
  
  $substitute = 1 if (!defined $substitute);

  my @vendors = ();

  foreach (@$h_segments) { push (@vendors, $_->{VendorCode}); }
  
  my $vendors = join(' ', @vendors);
     $vendors =~ s/(KL|NW|KQ)/AF/ig if ($substitute == 1);

  debug('Vendors = '.$vendors);

  return $vendors;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Récupérer le AirFare dans un PNR
sub getPnrAirFare {
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
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

1;
