package Expedia::Modules::TAS::PnrGetInfos;
#-----------------------------------------------------------------
# Package Expedia::Modules::TAS::PnrGetInfos
#
# $Id: PnrGetInfos.pm 562 2009-11-30 10:33:11Z pbressan $
#
# (c) 2002-2007 Expedia.                   www.expediacorporate.fr
#-----------------------------------------------------------------

use strict;
use Data::Dumper;

use Expedia::Tools::Logger      qw(&debug &notice &warning &error);
use Expedia::Tools::GlobalFuncs qw(&stringGdsPaxName);
use Expedia::Tools::GlobalVars  qw($proxyNav);
use Expedia::Databases::MidSchemaFuncs  qw(&getUserComCode);
use Expedia::WS::Back qw(&GetTravelerUnusedCredits &SetUnusedticketAsUsed);

sub run {
  my $self   = shift;
  my $params = shift;

  my $globalParams  = $params->{GlobalParams};
  my $moduleParams  = $params->{ModuleParams};
  my $changes       = $params->{Changes};
  my $item          = $params->{Item};
  my $pnr           = $params->{PNR};
  my $ab            = $params->{ParsedXML};
  my $btcProceed    = $params->{BtcProceed};
  my $onlineBooking = $params->{OnlineBooking};

  # Module de reconnaissance des PAX entre fichier XML et PNR Amadeus
  my $travellers = $ab->getTravellerStruct();
  my $market     = $ab->getCountryCode({trvPos => $ab->getWhoIsMain});
  my $nbPaxXML   = scalar(@$travellers);
  my $nbPaxPNR   = scalar(@{$pnr->{PAX}});

  my $h_pnr        = $params->{Position};
  my $refpnr       = $params->{RefPNR};
  my $atds          = $ab->getTravelDossierStruct;
  my $position        = $h_pnr->{$refpnr};
  my $lwdPos       = $atds->[$position]->{lwdPos};
  my $airline = _formatSegments($ab->getAirSegments({lwdPos => $lwdPos}), 1);

  debug(' PAX XML = '.Dumper($travellers));
  debug(' PAX PNR = '.Dumper($pnr->{PAX}));
  debug('nbPaxXML = '.$nbPaxXML);
  debug('nbPaxPNR = '.$nbPaxPNR);

	my $liste_comcode = $globalParams->{UNUSED};
	my %h_unused_comcode = ();
	my $do_sign=0;
	my $GDS='';
    my $comcode='';
	
	$GDS = $pnr->{_GDS};
	$GDS->RT(PNR=>$pnr->{PNRId});

	foreach my $tmp_liste_comcode (@$liste_comcode)
	{
		if(!exists($h_unused_comcode{$tmp_liste_comcode}))
		{
				$h_unused_comcode{$tmp_liste_comcode}=1;
		}
	}

   ##### LOOP ON EAch traveller to know if the comcode match with a unused company comcode
   foreach my $xmlPax (@$travellers)
   {
		my $xmlFirstName = $xmlPax->{FirstName}.' '.$xmlPax->{AmadeusTitle};
		my $xmlLastName  = $xmlPax->{LastName};
		$_ = stringGdsPaxName($_, $market) foreach ($xmlFirstName, $xmlLastName);
		$comcode=&getUserComCode($xmlPax->{PerCode});
		if(defined($comcode)){notice("Comcode Pax:".$comcode);}
		if($h_unused_comcode{$comcode})
		{
			notice("GET UNUSED FOR COMCODE:".$comcode);
			my $tmp_traveller_name = substr($xmlFirstName, 0, length($xmlFirstName) - length( $xmlPax->{AmadeusTitle} ) -1 );
			my @ret = &GetTravelerUnusedCredits($proxyNav,$market,$comcode,$xmlPax->{PerCode},$xmlLastName,$tmp_traveller_name,$xmlPax->{AmadeusTitle},$airline);
			
      foreach my $rec (@ret) {
					my $airlineCnt = 0;
		    	my $statusOorACnt = 0;
		    	my $tktNumber = $rec->{TKT};
					if($rec->{RC})
					{
						my $cmdTWDResult = $GDS->command(Command=>$tktNumber, NoIG=>1, NoMD=>1);
						
						if ($cmdTWDResult->[0] =~ /NUMERO\sDE\sBILLET\sINTROUVABLE/
                  || $cmdTWDResult->[0] =~ /TICKET\sNUMBER\sNOT\sFOUND/
                  || $cmdTWDResult->[0] =~ /NO\sSE\sENCONTRO\sEL\sNUMERO\sDE\sBILLETE/
                ){
              	my @unUsedRet = &SetUnusedticketAsUsed({
						          WS            =>  $proxyNav,
						          pos           =>  $market,
						          comCode       =>  $comcode,
						          perCode       =>  $xmlPax->{PerCode},
						          ticketNumber  =>  $tktNumber,
						  	});
							foreach (@unUsedRet) { if($_->{ERROR}) { notice("error:".$_->{ERROR} ); } };
            } else {
							#$cmdTWDResult->[2] =~ /ADT\s+ST/g;
							#my $airLineStatusPos = $+[0]-2;
							my $airLineStatusPos = 46;
							foreach my $lno (3..@$cmdTWDResult) {
								if ($cmdTWDResult->[$lno] =~ /^\s\d\s/) {
									$airlineCnt++;
									my $status = substr($cmdTWDResult->[$lno],$airLineStatusPos,1);
									$statusOorACnt++ if ($status =~ /O|A/);
								} else {
									last;
								}
						
							}
						
						
							if ($statusOorACnt eq $airlineCnt && $statusOorACnt > 0 && $airlineCnt > 0) {
								$GDS->command(Command=>$rec->{RC}, NoIG=>1, NoMD=>1);
								$do_sign=1;
							} elsif ( $statusOorACnt ne $airlineCnt && $airlineCnt > 0 ) {
							     my @unUsedRet = &SetUnusedticketAsUsed({
						          WS            =>  $proxyNav,
						          pos           =>  $market,
						          comCode       =>  $comcode,
						          perCode       =>  $xmlPax->{PerCode},
						          ticketNumber  =>  substr($tktNumber,11,length($tktNumber)),
						        });
										foreach (@unUsedRet) { if($_->{ERROR}) { notice("error:".$_->{ERROR} ); } };
							} else {}
						
						}
						

					}
					if($rec->{ERROR}) { notice("error:".$rec->{ERROR} ); }
			}
		}
    } # Fin XMLPAX: foreach (@$travellers)

    #THe rc have been added, need to sign and to raise an TAS_ERROR to block the ticketing
	if($do_sign == 1)
	{
		$GDS->command(Command=>'RF'.$GDS->modifsig, NoIG=>1, NoMD=>1);
		$GDS->command(Command=>'ER',                NoIG=>1, NoMD=>1);
		$GDS->command(Command=>'ER',                NoIG=>1, NoMD=>1);
		$pnr->{TAS_ERROR} = 66;
		return 1;
	}
  
  # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
  # Le vrai nombre de PAX est celui du PNR bien sûr !
  if ($nbPaxPNR > $nbPaxXML) {
  # notice('Number of Pax in PNR is superior compared to XML ! Aborting [...]');
    $pnr->{TAS_ERROR} = 41;
    return 1;
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
			$pnr->{TAS_ERROR} = 40;
			return 1;
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
        # notice('Percode mismatch between Amadeus and website. Aborting [...]');
		    $pnr->{TAS_ERROR} = 42;
		    return 1;        
      }
    }
	  else {
      # notice('Percode mismatch between Amadeus and website. Aborting [...]');
		  $pnr->{TAS_ERROR} = 42;
		  return 1;
	  }
	}
  
  foreach (@perCodes) {
    my $perCode =  $_->{PERCODE};
    my $xmlPax  = _getPax($perCode, $travellers, 1);
    if (!defined $xmlPax) {
      # notice('Percode mismatch between Amadeus and website. Aborting [...]');
      $pnr->{TAS_ERROR} = 42;
      return 1;
    }
  }
  # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
    	
  # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
  # Si le dossier est "Online", on applique le process habituel
  if ($btcProceed) {
    debug('Online booking [...]');
    
    # -------------------------------------------------------------
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
      $xmlPax->{FIRSTNAME} = $pnrFirstName;
      $xmlPax->{LASTNAME}  = $pnrLastName;
    }
    # -------------------------------------------------------------
    # <CAS 2> MultiPax
    elsif ($nbPaxPNR > 1) {

      my $paxNum = 0;
    
      PNRPAX: foreach my $pnrPax (@{$pnr->{PAX}}) {
    
        $paxNum++;
    
        my $pnrLastName;
        my $pnrFirstName;
    
        if (($pnrPax->{'Data'} =~ /^(.*)\/(.*[^\(])(\(.*)$/) ||
            ($pnrPax->{'Data'} =~ /^(.*)\/(.*)$/)) {
          $pnrLastName  = $1;
          $pnrFirstName = $2;
          $_ = stringGdsPaxName($_, $market) foreach ($pnrFirstName, $pnrLastName);
          debug("pnrFirstName = $pnrFirstName.");
          debug("pnrLastName  = $pnrLastName.");
    
          XMLPAX: foreach my $xmlPax (@$travellers) {
    
            next XMLPAX if (exists $xmlPax->{PaxNum});
    
            my $xmlFirstName = $xmlPax->{FirstName}.' '.$xmlPax->{AmadeusTitle};
            my $xmlLastName  = $xmlPax->{LastName};
            $_ = stringGdsPaxName($_, $market) foreach ($xmlFirstName, $xmlLastName);
            debug("xmlFirstName = $xmlFirstName.");
            debug("xmlLastName  = $xmlLastName.");
    
            next XMLPAX unless ($pnrFirstName eq $xmlFirstName);
            next XMLPAX unless ($pnrLastName  eq $xmlLastName);
    
            $xmlPax->{PaxNum}    = 'P'.$paxNum;
            $pnrPax->{PerCode}   = $xmlPax->{PerCode};
            $pnrPax->{Position}  = $xmlPax->{Position};
            $xmlPax->{FIRSTNAME} = $pnrFirstName;
            $xmlPax->{LASTNAME}  = $pnrLastName;
    
            last XMLPAX;
          } # Fin XMLPAX: foreach (@$travellers)
    
        }
        else {
          notice("Pax LineNo = '".$pnrPax->{'LineNo'}."' doesn't match regexp !");
          debug ("Pax Data   = '".$pnrPax->{'Data'}."'.");
          return 0;
        }
    
      } # Fin PNRPAX: foreach my $pnrPax (@{$pnr->{PAX}})
    
    }

  } # Fin if ($btcProceed)
  # µµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµ
  # Si le dossier est "Offline"
  else {
    debug('Offline booking [...]');
    # -------------------------------------------------------------
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
      $xmlPax->{FIRSTNAME} = $pnrFirstName;
      $xmlPax->{LASTNAME}  = $pnrLastName;
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
        # notice('Percode mismatch between Amadeus and website. Aborting [...]');
          $pnr->{TAS_ERROR} = 42;
          return 1;
        } else {
          $xmlPax->{PaxNum} = 'P'.$paxNum;
          $pnr->{PAX}->[$paxNum-1]->{PerCode}  = $xmlPax->{PerCode};
          $pnr->{PAX}->[$paxNum-1]->{Position} = $xmlPax->{Position};
          my $pnrLastName;
          my $pnrFirstName;
          if (($pnr->{PAX}->[$paxNum-1]->{'Data'} =~ /^(.*)\/(.*[^\(])(\(.*)$/) ||
              ($pnr->{PAX}->[$paxNum-1]->{'Data'} =~ /^(.*)\/(.*)$/)) {
            $pnrLastName  = $1;
            $pnrFirstName = $2;
            $_ = stringGdsPaxName($_, $market) foreach ($pnrFirstName, $pnrLastName);
            debug("pnrFirstName = $pnrFirstName.");
            debug("pnrLastName  = $pnrLastName.");
          }
          $xmlPax->{FIRSTNAME} = $pnrFirstName;
          $xmlPax->{LASTNAME}  = $pnrLastName;
        }
      }
    }
    # -------------------------------------------------------------    
  }
  # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

  debug(' PAX XML = '.Dumper($travellers));
  debug(' PAX PNR = '.Dumper($pnr->{PAX}));
  
  # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
  # Vérification que tous les passagers XML ont été reconnus dans AMADEUS
  # ~~~ Si il y a plus de passagers dans le XML que dans le PNR       ~~~
  # ~~~ Vidage de ceux qui sont en trop dans $travellers              ~~~
  my $numberOfRecognizedPax = 0;
  
  foreach my $xmlPax (@$travellers) {
    #if (!exists $xmlPax->{PaxNum}) {
    #  my $fullName = $xmlPax->{FirstName}.' '.$xmlPax->{LastName};
    #  notice("XMLPAX = '$fullName' hasn't been found or recognized in Amadeus. Aborting.");
    #} else {
      $numberOfRecognizedPax++;
    #}
  }
  
  # return 0 unless ($numberOfRecognizedPax == $nbPaxPNR);
  if ($numberOfRecognizedPax != $nbPaxPNR) {
    $pnr->{TAS_ERROR} = 50;
    return 1;
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

 # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Fonction visant Ã pplanir les segments
sub _formatSegments {
  my $h_segments = shift;
  my $substitute = shift;

  $substitute = 1 if (!defined $substitute);

  my @vendors = ();

  foreach (@$h_segments) { push (@vendors, $_->{VendorCode}); last;}

  my $vendors = join(' ', @vendors);
     $vendors =~ s/(KL|NW|KQ)/AF/ig if ($substitute == 1);

  debug('Vendors = '.$vendors);

  return $vendors;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

1;
