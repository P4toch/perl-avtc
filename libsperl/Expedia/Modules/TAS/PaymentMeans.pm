package Expedia::Modules::TAS::PaymentMeans;
#-----------------------------------------------------------------
# Package Expedia::Modules::TAS::PaymentMeans
#
# $Id: PaymentMeans.pm 713 2012-07-26 SDU $
#
# (c) 2002-2009 Expedia.                   www.expediacorporate.fr
#
#(\___/)
#(='+'=)
#
#-----------------------------------------------------------------

use strict;
use Data::Dumper;
use Clone qw(clone);

use Expedia::WS::Back           qw(&BO_GetBookingFormOfPayment);
use Expedia::Tools::Logger      qw(&debug &notice &warning &error);
use Expedia::Tools::GlobalVars  qw($cnxMgr $h_context $N1111);
use Expedia::Databases::MidSchemaFuncs  qw(&getFpec);
use Expedia::XML::MsgGenerator;
use Expedia::Tools::GlobalFuncs   qw(&getRTUMarkup &check_TQN_markup);


# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
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
  my $GDS          = $params->{GDS};
  my $market       = $globalParams->{market};
      
  my $countryCode  = $ab->getCountryCode({trvPos => $ab->getWhoIsMain});
   my $fpec         = &getFpec($countryCode);

  my $h_pnr        = $params->{Position};
  my $refpnr       = $params->{RefPNR};
  my $position     = $h_pnr->{$refpnr};
  notice("Position du pnr:".$refpnr." dans le traveldossier:".$position);
   
  my @add          = (); # Elements à ajouter en Amadeus.
  my @del          = (); # Numéros de lignes à supprimer en Amadeus. 
  
  my $haveFP	   = 0;
  
  # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
  # On commence par recharger le PNR
  $pnr->reload;
  # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
  
 
    #ADD THE METADDOSIER IF NOT EXISTS   
   unless ( grep { $_->{Data} =~ /RM \*METADOSSIER/ } @{$pnr->{PNRData}} ) {
               push (@add, { Data => 'RM *METADOSSIER '.$params->{ParsedXML}->getMdCode });
    }
     
  # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
  # Is markup Egencia Database (XML)
  my $atds			 = $ab->getTravelDossierStruct;
  my $hasMarkup      = $atds->[$position]->{lwdHasMarkup};
	 
  my $lwdPos       = $atds->[$position]->{lwdPos};
  my $lwdCode      = $atds->[$position]->{lwdCode};
  my $lwdHasMarkup = $atds->[$position]->{lwdHasMarkup};
  $globalParams->{RTU_markup}='';
   if ($hasMarkup eq 'true')
   {
  	notice('THIS IS A MARKUP XML: '.$hasMarkup);
  	$self->_chgFopEC($pnr, $market,$countryCode);
	$globalParams->{RTU_markup}='EC';
  	 return 1;
   }	
 
  # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
  

  # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
  # Is markup GDS Markup (UK AF)  
  my $vendors1  = _formatSegments($ab->getAirSegments({lwdPos => $lwdPos}), 1);
  my $DBCarrier = '';
  $DBCarrier = _getMarkupPerPos($vendors1,$market);
  my $airFare = _getPnrAirFareEgencia($pnr);
  debug('market = '.$market);
  debug('vendors1 = '.$vendors1);
  if(defined($DBCarrier)){debug('DBCarrier = '.$DBCarrier);}
  debug('airFare = '.$airFare);
  

  
  if(defined($DBCarrier) && defined($airFare))
  {
     if( ($airFare eq 1) and ($DBCarrier eq 1) )
     {
       notice('THIS IS A MARKUP GDS: '.$airFare.' / '.$DBCarrier); 
       $self->_chgFopEC($pnr, $market,$countryCode);
	   $globalParams->{RTU_markup}='EC';
       return 1;
     }
  } 
  # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@  

	if (getRTUMarkup($market)) {  
		
		my $GDS    = $pnr->{_GDS};	
		my $lines        = $GDS->command(Command => 'RT'.$pnr->{_PNR}, NoIG => 1, NoMD => 0);	
		my $lines_tqn    = $GDS->command(Command => 'TQN', NoIG => 1, NoMD => 0);
	
		$lwdHasMarkup= check_TQN_markup($lines_tqn, $pnr, $market);
		notice('RTU MARKUP :'.$lwdHasMarkup);
		if ($lwdHasMarkup eq 'true'){
			$globalParams->{RTU_markup}='EC';
			$self->_chgFopEC($pnr, $market,$countryCode);
			return 1;
		}else {
			$globalParams->{RTU_markup}='';
		}

	}

  
  
  
  
  # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
  # Is the FOP is in navision?
  $GDS->RT(PNR => $pnr->{PNRId}, NoPostIG => 1, NoMD => 1);
  
   my $travellers   	= $pnr->{Travellers}; 
   my $nbPax        	= scalar @$travellers; 
  notice('No Pax founded in XML booking !') if ($nbPax == 0);
  return 0                                  if ($nbPax == 0);
   
     $countryCode  = $market;
     $fpec         = &getFpec($countryCode);
   
  my $fstSegComp   = $pnr->{'Segments'}->[0]->{'Data'};
     $fstSegComp   = '' unless (defined $fstSegComp);
     $fstSegComp   = substr($fstSegComp, 0, 2) if ($fstSegComp ne '');
  # -----------------------------------------------------------
    
  # ----------------------------------------------------------------------------
  # Pour chacun des voyageurs du dossier, nous allons récupérer les moyens de paiement [...]
  PAX: foreach my $traveller (@$travellers) {

   	my $ccId= $ab->getCcUsedCode({trvPos => $traveller->{Position}});
    my $ComCode  = $ab->getPerComCode({trvPos => $traveller->{Position}});
    my $paymentMean = $ab->getPaymentMean({trvPos => $traveller->{Position}, lwdCode => $lwdCode});
	my $percode= $traveller->{PerCode};
	my $tmp_lc      = '';
    my $cc;
	  
	$cc=undef   if (!exists $paymentMean->{PaymentType});
	my $type= $paymentMean->{PaymentType};
	

	  
	
	my $cToken = undef;
	  
	if ($type =~  /^(CC|OOCC|ICCR)$/ || $globalParams->{RTU_markup} ne 'EC' ) {
		my $service = $paymentMean->{Service};
		notice("SERVICE:".$service);
        if($service eq '' || !$service ) { $service='AIR';}
		my $token   = $paymentMean->{CcCode};
		my $CC1           = undef;
		$CC1           = $ccId->{CC1} if ((exists $ccId->{CC1}) && ($ccId->{CC1} ne ''));
		my $res = BO_GetBookingFormOfPayment('BackWebService', $countryCode,$ComCode, $token,$percode,$service,$fstSegComp,$CC1,$pnr->{PNRId});
		$cc=undef unless defined($res);
		$cc=$res->{FormOfPayment} if defined($res->{FormOfPayment});
		if($res->{PaymentType} eq 'EC'){
			$cc=$fpec;
		}
		if (defined $res->{Financial}){
			if($res->{Financial} eq 'FIRSTCARD'){ 
				$tmp_lc = '/'.$N1111; 
				$cc=$cc.$tmp_lc if(defined $cc);
			}
		}
		
		$cToken=$token;
	}
	  # -----------------------------------------------------------------------
	  # Type EC = En Compte
	elsif ($type eq 'EC' || $globalParams->{RTU_markup} eq 'EC' ) {
		$cc=$fpec;
	}
	
	_manageBCODE({market => $market,
	              ab     => $ab,
	              lwdPos => $lwdPos,
	              pnr    => $pnr,
	              fop    => \$cc,
	              fpec   => $fpec,
	              nbPax  => $nbPax,
	              del    => \@del,
	              add    => \@add});
	if (defined($pnr->{TAS_ERROR})) {
		return 1;
	}
	
	if (defined $cc) {
        push(@add, { Data => $cc.'/'.$traveller->{PaxNum}, PerCode => $traveller->{PerCode}, PaxNumber => $traveller->{PaxNum} });
      } else {
        push(@add, { Data => 'RM @@ INSERT FP/'.$traveller->{PaxNum}.' @@' });
        $WBMI->addReport({ Code        => 2,
                           PnrId       => $pnr->{_PNR},
                           AmadeusMesg => 'RM @@ INSERT FP/'.$traveller->{PaxNum}.' @@',
                           PaxNumber   => $traveller->{PaxNum},
                           PerCode     => $traveller->{PerCode}});
      }
      
    if (defined($cToken)) {
      if (length($cToken) == 16) {
        $cToken = substr($cToken, 0, 8).'___'.substr($cToken, 8, 8);
      }
      push (@add, {Data => 'RM *TOKEN '.$cToken.'/'.$traveller->{PaxNum}});
    }
  }
  # ---------------------------------------------------------------------------- 

  # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
  
  #we have added a FOP, we have to remove all FP lines
  # Récupération des numéros de lignes à supprimer
  my @fpLinesToDel = _getFpLinesNoToDelete($pnr);
  push @del, $_ foreach (@fpLinesToDel);
  notice("Suppression de la FOP:".$_) foreach (@fpLinesToDel);
  
  # Delete TOKEN lines
  my @tokenLinesNoToDel = _getTokenLinesNoToDelete($pnr);
  foreach my $tokenLineNoToDel (@tokenLinesNoToDel) {
    push(@del, $tokenLineNoToDel);
    notice('Suppression du TOKEN:'.$tokenLineNoToDel);
  }
  
  # Appliquer les changements en Amadeus.
  _applyChanges($pnr, \@del, \@add, $WBMI);
  # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
  	
  return 1;
}

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# _chgFop : Change le moyen de paiement dans le dossier par FPEC
sub _chgFopEC {
  my $self   = shift;
  my $pnr    = shift;
  my $market = shift;
  my $countryCode = shift;

  notice('TAS will change FPCC to FPEC !');
  
  my $GDS = $pnr->{_GDS};

  $pnr->reload;
  # $GDS->RT(PNR=>$pnr->{PNRId}, NoIG=>1);

  # ---------------------------------------------------------------------
  # Suppression des lignes 'FP '   
  my @linesToDelete = ();
  DATA: foreach (@{$pnr->{'PNRData'}}) {
    if (($_->{'Data'} =~ /^FP /)) {
      push(@linesToDelete, $_->{'LineNo'});
    }
  }
  foreach (sort triDecroissant (@linesToDelete)) {
    $GDS->command(Command=>'XE '.$_, NoIG=>1, NoMD=>1);
  }
  # ---------------------------------------------------------------------

  # ---------------------------------------------------------------------
  # Ajout des nouvelles FP pour chacun des PAX
  my $i    = 1;
  my $fpec         = &getFpec($countryCode); 
  foreach (@{$pnr->{PAX}}) {
    $GDS->command(Command=>$fpec.'/P'.$i, NoIG=>1, NoMD=>1);
    $i++;
  }
  # ---------------------------------------------------------------------

  # ---------------------------------------------------------------------
  # Validation des modifications
  $GDS->command(Command=>'RF'.$GDS->modifsig, NoIG=>1, NoMD=>1);
  $GDS->command(Command=>'ER', NoIG=>1, NoMD=>1);
  $GDS->command(Command=>'ER', NoIG=>1, NoMD=>1);
  # ---------------------------------------------------------------------  

  return 1;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Récupérer les numéros des lignes FP FICTIF à supprimer d'Amadeus.
sub _getFpLinesNoToDeleteFictif {
  my $pnr = shift;
  
  my @linesNo = ();
  
  # Suppression des lignes FP fictives [ FP CCVI4444333322221111 ]
  DATA: foreach (@{$pnr->{'PNRData'}}) {
    if (($_->{'Data'} =~ /^FP\s+CCVI(?:,)?4444333322221111(.*)$/) ||
        ($_->{'Data'} =~ /^FP\s+CCVI(?:,)?XXXXXXXXXXXX1111(.*)$/) ||
        ($_->{'Data'} =~ /^FP\s+VI(?:,)?4444333322221111(.*)$/) ||
        ($_->{'Data'} =~ /^FP\s+VI(?:,)?XXXXXXXXXXXX1111(.*)$/) ) {
      push (@linesNo, $_->{'LineNo'});
    }
  }
  
  return @linesNo;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Récupérer les numéros des lignes FP à supprimer d'Amadeus.
sub _getFpLinesNoToDelete {
  my $pnr = shift;
  
  my @linesNo = ();
  	
  DATA: foreach (@{$pnr->{'PNRData'}}) {
    if (($_->{'Data'} =~ /^RM\s*PLEASE ASK FOR CREDIT CARD/) ||
        ($_->{'Data'} =~ /^FP /) ||
        ($_->{'Data'} =~ /^RC\s*CC\s*HOTEL\s*ONLY/) ) {
      push (@linesNo, $_->{'LineNo'});
    }
  }
  
  return @linesNo;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Récupérer les numéros des lignes TOKEN à supprimer d'Amadeus.
sub _getTokenLinesNoToDelete {
  my $pnr = shift;
  
  my @linesNo = ();
  
  foreach (@{$pnr->{PNRData}}) {
    if ($_->{Data} =~ /^RM \*TOKEN /) {
      push(@linesNo, $_->{LineNo});
    }
  }
  
  return @linesNo;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Applique les modifications en Amadeus.
sub _applyChanges {
  my $pnr        = shift;
  my $del        = shift; # Numéros des lignes à supprimer.
  my $add        = shift; # Éléments à ajouter.
  my $WBMI       = shift; # WBMI
  
  my $travellers = $pnr->{Travellers};
  my $nbPax      = scalar @$travellers;
    
  @$del = sort {$b <=> $a} (@$del);
  my $ER1 = []; my $ER2 = []; my $FP = []; my @supAdd = ();
  my $GDS = $pnr->{_GDS};
  
  RETRY: {{
    $GDS->command(Command=>'XE'.$_, NoIG=>1, NoMD=>1) foreach (@$del);
    
    # ---------------------------------------------------------------------
    # On scrute le résultat de l'envoi de commandes FP CC
    #  afin de pour différencier les différents cas.
    CMD: foreach my $cmd (@$add) {
 
      $FP = $GDS->command(Command=>$cmd->{Data}, NoIG=>1, NoMD=>1);
      next CMD unless ($cmd->{Data} =~ /^FP CC/);
      my $code = 0;
         if  (grep(/CARTE DE CREDIT EXPIREE/,   @$FP))  { $code = 19; }
      elsif ((grep(/NUMERO DE COMPTE ERRONE/,   @$FP)) ||
             (grep(/MODE DE PAIEMENT ERRONE/,   @$FP)) ||
             (grep(/ERREUR CARTE (DE)? CREDIT/, @$FP))) { $code = 20; }
      if ($code != 0) {
        my $mesg = 'RM @@ CREDIT CARD REJECTED BY AMADEUS @@';
           $mesg = 'RM @@ CREDIT CARD REJECTED BY AMADEUS/'.$cmd->{PaxNumber}.' @@' if ($nbPax > 1);
        $WBMI->addReport({
          Code        => $code,
          PnrId       => $pnr->{_PNR},
          AmadeusMesg => $mesg,
          PaxNumber   => $cmd->{PaxNumber},
          PerCode     => $cmd->{PerCode},
          AddWbmiMesg => _cardMask($cmd->{Data}) });
        push @supAdd, { Data =>  $mesg };
      }
    }
    # ---------------------------------------------------------------------
    
    # ---------------------------------------------------------------------  
    # Validation des modifications.
           $GDS->command(Command=>'RF'.$GDS->modifsig, NoIG=>1, NoMD=>1);
    $ER1 = $GDS->command(Command=>'ER',                NoIG=>1, NoMD=>1);
    $ER2 = $GDS->command(Command=>'ER',                NoIG=>1, NoMD=>1);
    # ---------------------------------------------------------------------
  
  if (   (grep(/CHANGTS SIMULT DANS PNR/, @$ER1)) ||
		 (grep(/CHANGTS SIMULT DANS PNR/, @$ER2)) ||
		 (grep (/VERIFIER LE PNR ET REESSAYER/ ,   @$ER1)) ||
		 (grep (/VERIFIER LE CONTENU DU PNR/ ,   @$ER1))  ||
		 (grep (/VERIFIER LE PNR ET REESSAYER/ ,   @$ER2)) ||
		 (grep (/VERIFIER LE CONTENU DU PNR/ ,   @$ER2))  
	 ) 
	{
      $pnr->reload;
      # $GDS->RT(PNR=>$pnr->{PNRId}, NoIG=>1);
      my @newDel = _getFpLinesNoToDeleteFictif($pnr);
       $del      = \@newDel;
      @$del      = sort {$b <=> $a} (@$del);
      goto RETRY;
    }
  }};
  
  # Si on a de nouveaux éléments à ajouter en Amadeus.
  _applyChanges($pnr, [], \@supAdd, $WBMI) if (scalar @supAdd > 0);
  
  return 1;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Masquage d'une partie du numéro de carte de crédit
#   pour affichage dans WBMI.
sub _cardMask {
  my $fpcc = shift;

  my $res  = ''; 

  if ($fpcc =~ /^(FP CC\w{2},?)(\d+)\/(\d+)?(\/P\d)?$/) {
    my $begin  = $1;
    my $nums   = $2;
    my $exp    = $3 || '';
    my $length = length($nums);
    my $substr = substr($nums, $length -4, 4);
    my $tmp    = '*'x($length -4);
    $res = ' '.$begin.$tmp.$substr.'/'.$exp;
  }

  return $res;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@


# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Routine de Tri Des Numériques
sub triDecroissant { $b <=> $a } 
sub triCroissant   { $a <=> $b }
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

 # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Fonction visant à applanir les segments
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

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
sub _getMarkupPerPos
{
  my $aircode = shift;
  my $market  = shift;
  
  my $midDB        = $cnxMgr->getConnectionByName('mid');
  
  # -------------------------------------------------------------------
  # Récupération des dossiers à traiter pour BTC-AIR
  my $query = "
    SELECT AIRLINECODE
    FROM MARKUPINCLUDEDAIRLINES
    WHERE AIRLINECODE= ? 
    AND POSCODE= ? ";
  
  my $results = $midDB->saarBind($query, [$aircode, $market]);
   debug('results = '.Dumper($results));
  # -------------------------------------------------------------------
  
  return () unless ((defined $results) && (scalar @$results > 0));
  
  my @finalRes = ();
    
  return 1;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Récupérer le AirFare dans un PNR
sub _getPnrAirFareEgencia {
  my $pnr = shift;
  
  my $airFare = '';
  
  foreach (@{$pnr->{PNRData}}) {
    if ($_->{Data} =~ /^RM \*AIRFARE EGENCIA/) {
      $airFare = 1;
      last;
    }
  }
  
  return $airFare;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@





# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Récupérer l'online pricing dans un PNR
sub getPnrOnlinePricing {
  my $pnr = shift;
  
  my $onlinepricing = '';
  
  foreach (@{$pnr->{PNRData}}) {
    if ($_->{Data} =~ /^RM \*ONLINE PRICING LINE FOR TAS: (.*)/) {
      $onlinepricing = $1;
      last;
    }
  }
  
  return $onlinepricing;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@


# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# This sub manages the BCODE.
# We check the conditions.
# If the conditions aren't met, we do nothing.
# If the conditions are met, we do either :
#   - Update FOP
#   - Or add BCODE in FE lines
sub _manageBCODE {
  my $params = shift;
  
  my $market        = $params->{market};
  my $ab            = $params->{ab};
  my $lwdPos        = $params->{lwdPos};
  my $pnr           = $params->{pnr};
  my $fop           = $params->{fop};
  my $fpec          = $params->{fpec};
  my $nbPax         = $params->{nbPax};
  my $del           = $params->{del};
  my $add           = $params->{add};
  
  # Market = HK ?
  unless ($market eq 'HK') {
    return 1;
  }
  
  # BCODE ?
  my $bcode;
  my $contracts = $ab->getTravelDossierContracts({lwdPos => $lwdPos});
  foreach my $contract (@$contracts) {
    if ($contract->{ContractType} eq 'TRACKING' &&
        $contract->{SupplierCode} =~ /^(CX|KA)$/) {
      $bcode = $contract->{CorporateNumber};
      last;
    }
  }
  unless (defined($bcode) && $bcode ne '') {
    debug('No BCODE');
    return 1;
  }
  notice('BCODE : '.$bcode);
  
  # Airline = CX or KA only ?
  my $hasAirlineBcode = 0;
  my $hasAirlineOther = 0;
  my $airSegments = $ab->getAirSegments({lwdPos => $lwdPos});
  foreach my $airSegment (@$airSegments) {
    if ($airSegment->{VendorCode} =~ /^(CX|KA)$/) {
      $hasAirlineBcode = 1;
    } else {
      $hasAirlineOther = 1;
    }
  }
  unless ($hasAirlineBcode == 1) {
    debug('No BCODE airline');
    return 1;
  }
  unless ($hasAirlineOther == 0) {
    debug('Other airline !');
    debug('### TAS MSG TREATMENT 70 ###');
    $pnr->{TAS_ERROR} = 70;
    return 1;
  }
  
  # Fare Type ?
  my $onlinePricing = getPnrOnlinePricing($pnr);
  notice('Online pricing : '.$onlinePricing);
  if ($onlinePricing =~ /^FXP\/R,U\d.*$/) {
  
    # Fare type : Corporate
    debug('Fare type : Corporate');
    
    # Update FOP
    $$fop = 'FPINVAGT';
    notice('Update FOP : '.$$fop);
    
  } elsif ($onlinePricing =~ /^FXP\/R,UP?$/) {
  
    # Fare type : Private or Net
    debug('Fare type : Private or Net');
    
    # Update FOP
    $$fop = 'FPMSINV'.$bcode;
    notice('Update FOP : '.$$fop);
  
  } elsif ($onlinePricing =~ /^FXP$/) {
  
    # Fare type : Published
    debug('Fare type : Published');
    
    # MonoPax ?
    unless ($nbPax == 1) {
      # MultiPax
      debug('MultiPax !');
      debug('### TAS MSG TREATMENT 70 ###');
      $pnr->{TAS_ERROR} = 70;
      return 1;
    }
    
    # FOP Type ?
    if (!defined($$fop)) {
      
      # No FOP
      debug('No FOP');
      return 1;
      
    } elsif ($$fop eq $fpec) {
      
      # FOP type : On Account
      debug('FOP type : On Account');
    
      # Update FOP
      $$fop = 'FPMSINV'.$bcode;
      notice('Update FOP : '.$$fop);
    
    } elsif ($$fop =~ /^FP CC/) {
      
      # FOP type : Credit Card
      debug('FOP type : Credit Card');
      
      # Add BCODE in FE lines
      debug('Add BCODE in FE lines');
      
      # Add BCODE in existing FE lines
      my $hasFELine = 0;
      foreach my $pnrData (@{$pnr->{PNRData}}) {
        my $data = $pnrData->{Data};
        if ($data =~ /^FE /) {
          $hasFELine = 1;
          notice('Delete FE line : '.$data);
          push (@$del, $pnrData->{LineNo});
          $data =~ s/PAX/$bcode/;
          notice('Add FE line : '.$data);
          push (@$add, {Data => $data});
        }
      }
      
      if ($hasFELine == 0) {
        # No existing FE line, we have to add a FE line
        debug('No existing FE line, we have to add a FE line');
        
        # Build segments string
        my $segmentsString = '';
        my $nbSegments = scalar(@{$pnr->{Segments}});
        if ($nbSegments >= 1) {
          $segmentsString .= '/S'.$pnr->{Segments}->[0]->{LineNo};
        }
        if ($nbSegments >= 2) {
          $segmentsString .= '-'.$pnr->{Segments}->[$nbSegments - 1]->{LineNo};
        }
        
        # Add FE line
        my $FELine = 'FE '.$bcode.$segmentsString;
        notice('Add FE line : '.$FELine);
        push (@$add, {Data => $FELine});
      }
      
    }
  
  } else {
  
    # Fare type : Other
    debug('Fare type : Other !');
    debug('### TAS MSG TREATMENT 70 ###');
    $pnr->{TAS_ERROR} = 70;
    return 1;
    
  }
  
  return 1;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@


1;
