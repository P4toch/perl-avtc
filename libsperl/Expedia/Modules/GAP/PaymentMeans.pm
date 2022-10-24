package Expedia::Modules::GAP::PaymentMeans;
#-----------------------------------------------------------------
# Package Expedia::Modules::GAP::PaymentMeans
#
# $Id: PaymentMeans.pm 713 2011-07-04 15:45:26Z pbressan $
#
# (c) 2002-2009 Expedia.                   www.expediacorporate.fr
#-----------------------------------------------------------------
use Exporter 'import';
use strict;
use Data::Dumper;

use Expedia::WS::Back           qw(&BO_GetBookingFormOfPayment);
use Expedia::Tools::Logger      qw(&debug &notice &warning &error);
use Expedia::Tools::GlobalVars  qw($h_context $N1111);
use Expedia::Databases::Payment qw(&getCreditCardData);
use Expedia::Tools::GlobalVars  qw($cnxMgr);
use Expedia::Databases::MidSchemaFuncs  qw(&getFpec);
use Expedia::XML::MsgGenerator;
use Expedia::Tools::GlobalFuncs   qw(&getRTUMarkup &check_TQN_markup);

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

  my $h_pnr        = $params->{Position};
  my $refpnr       = $params->{RefPNR};
  
  my $position        = $h_pnr->{$refpnr};

  my $atds          = $ab->getTravelDossierStruct; 

  my $lwdPos       = $atds->[$position]->{lwdPos};
  my $lwdCode      = $atds->[$position]->{lwdCode};
  my $lwdHasMarkup = $atds->[$position]->{lwdHasMarkup};
  my $lwdHasMarkup_TQN = "";
  my $travellers   = $pnr->{Travellers};
  my $nbPax        = scalar @$travellers;

  debug(' PNR TRAVALLERS = '.Dumper($travellers));
  debug(' lwdCode = '.$lwdCode);
        
  my $countryCode  = $ab->getCountryCode({trvPos => $ab->getWhoIsMain});
  my $fpec         = &getFpec($countryCode);
  
  my @add          = (); # Elements à ajouter en Amadeus.
  my @del          = (); # Numéros de lignes à supprimer en Amadeus.
  
  # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
  # On commence par recharger le PNR
  $pnr->reload;
  # $pnr->{_GDS}->RT(PNR=>$pnr->{PNRId}, NoIG=>1);
  # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
    
  my $fstSegComp   = $pnr->{'Segments'}->[0]->{'Data'};
     $fstSegComp   = '' unless (defined $fstSegComp);
     $fstSegComp   = substr($fstSegComp, 0, 2) if ($fstSegComp ne '');

  # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
  # Récupération des numéros de lignes à supprimer
  my @fpLinesToDel = _getFpLinesNoToDelete($pnr);
  push @del, $_ foreach (@fpLinesToDel);
  # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

  # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
  # GESTION DU MARKUP   
  my $market    = $ab->getCountryCode({trvPos => $ab->getWhoIsMain});
  debug('segment = '.$ab->getAirSegments({lwdPos => $lwdPos}));
  my $vendors1  = _formatSegments($ab->getAirSegments({lwdPos => $lwdPos}), 1);
  my $DBCarrier = '';
  $DBCarrier = _getMarkupPerPos($vendors1,$market);
  my $airFare = _getPnrAirFareEgencia($pnr);
  debug('market = '.$market);
  debug('vendors1 = '.$vendors1);
  if(defined($DBCarrier)){debug('DBCarrier = '.$DBCarrier);}
  debug('airFare = '.$airFare);

  

  
  
    # ----------------------------------------------------------------------------
    # Pour chacun des voyageurs du dossier, nous allons récupérer les moyens de paiement [...]
    PAX: foreach my $traveller (@$travellers) {

    
	my $ccId= $ab->getCcUsedCode({trvPos => $traveller->{Position}});
    my $ComCode  = $ab->getPerComCode({trvPos => $traveller->{Position}});
    my $paymentMean = $ab->getPaymentMean({trvPos => $traveller->{Position}, lwdCode => $lwdCode});
	my $percode= $traveller->{PerCode};
	my $tmp_lc      = '';
    my $cc;
		
	$cc=undef                                             if (!exists $paymentMean->{PaymentType});
	my $type= $paymentMean->{PaymentType};

		
	
	if (getRTUMarkup($market) && $type !~ /EC/ ) 
	{
		my $GDS    = $pnr->{_GDS};	
		my $lines        = $GDS->command(Command => 'RT'.$pnr->{_PNR}, NoIG => 1, NoMD => 0);
		my $lines_tqn    = $GDS->command(Command => 'TQN', NoIG => 1, NoMD => 0);
		$lwdHasMarkup_TQN= check_TQN_markup($lines_tqn, $pnr, $market);
		notice('RTU MARKUP :'.$lwdHasMarkup_TQN);				
	}	
	
	if ($lwdHasMarkup eq 'true' || $lwdHasMarkup_TQN eq 'true' )
	{   
		$cc=$fpec;
		$type= 'EC';
		debug('THIS IS A MARKUP FILE: '.$lwdHasMarkup);
	}
	
	
	if(defined($DBCarrier) && defined($airFare))
    {
    

	 if( ($airFare eq 1) and ($DBCarrier eq 1) )
      {
		 debug('THIS IS A MARKUP FILE: '.$airFare.' / '.$DBCarrier); 
		 $cc=$fpec;
		 $type= 'EC';
      }
    }
	
	my $cToken = undef;
	  
	if ($type =~  /^(CC|OOCC|ICCR)$/) {
	
		my $service = $paymentMean->{Service};
		my $token   = $paymentMean->{CcCode};
		my $CC1     = undef;
		$CC1           = $ccId->{CC1} if ((exists $ccId->{CC1}) && ($ccId->{CC1} ne ''));
		my $res = BO_GetBookingFormOfPayment('BackWebService', $countryCode,$ComCode, $token,$percode,$service,$fstSegComp,$CC1,$pnr->{_PNR});
		
		
		
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
	elsif ($type eq 'EC') {
		$cc=$fpec;
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
      
      if(defined($cToken))
      {
		my $tokenFlag="N";
		if(length($cToken) eq 16)
	    {	
			$cToken=substr($cToken,0,8)."___".substr($cToken,8,16);
		}
		foreach ( @{$pnr->{PNRData}} ) {
			my $lineData = $_->{Data};
			if ( $lineData =~ /RM \*TOKEN\s.*/) {
				if( $lineData !~/RM \*TOKEN\s$cToken\/$traveller->{PaxNum}/ )
				{
						push (@del, $_->{'LineNo'});
						last;
				} 
				else 
				{
						$tokenFlag="Y";
						last;
				}
			}
		}

		if ( $tokenFlag eq "N" ) {
			push (@add, { Data => 'RM *TOKEN '.$cToken.'/'.$traveller->{PaxNum}});
		}
      }
    }

  #}
  # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
  
  # Appliquer les changements en Amadeus.
  _applyChanges($pnr, \@del, \@add, $WBMI);

  return 1;
}



# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Récupérer les numéros des lignes FP à supprimer d'Amadeus.
sub _getFpLinesNoToDelete {
  my $pnr = shift;
  
  my @linesNo = ();
  
  # Suppression des lignes FP fictives [ FP CCVI4444333322221111 ]
  DATA: foreach (@{$pnr->{'PNRData'}}) {
    if (($_->{'Data'} =~ /^FP\s+CCVI(?:,)?4444333322221111(.*)$/) ||
        ($_->{'Data'} =~ /^FP\s+CCVI(?:,)?XXXXXXXXXXXX1111(.*)$/) ||
        ($_->{'Data'} =~ /^FP\s+VI(?:,)?XXXXXXXXXXXX1111(.*)$/)   ||
        ($_->{'Data'} =~ /^FP\s+VI(?:,)?4444333322221111(.*)$/) ) {
      push (@linesNo, $_->{'LineNo'});
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
  
   my @del2          = (); # Numéros de lignes à supprimer en Amadeus.
  #EGE-59830
  # ADD A LOOP TO REMOVE THE DOUBLON ! SHOULD not happends, trick but could not find why ! 
  my %deja_vu =();

  foreach my $elt (@$del) {
      unless ($deja_vu{$elt})
      {
      $deja_vu{$elt} = 1;
      push(@del2,$elt);
      }
   }
  
  @del2 = sort {$b <=> $a} (@del2);
  my $ER1 = []; my $ER2 = []; my $FP = []; my @supAdd = ();
  my $GDS = $pnr->{_GDS};
  
  RETRY: {{
    $GDS->command(Command=>'XE'.$_, NoIG=>1, NoMD=>1) foreach (@del2);
    
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
  
    if ( (grep(/CHANGTS SIMULT DANS PNR/, @$ER1)) ||
         (grep(/CHANGTS SIMULT DANS PNR/, @$ER2)) ||
        (grep (/VERIFIER LE PNR ET REESSAYER/ ,   @$ER1)) ||
		     (grep (/VERIFIER LE CONTENU DU PNR/ ,   @$ER1))  ||
			 (grep (/VERIFIER LE PNR ET REESSAYER/ ,   @$ER2)) ||
		     (grep (/VERIFIER LE CONTENU DU PNR/ ,   @$ER2))  
		 ) {
         notice("CHANGTS SIMULT IN PNR, will retry");
      $pnr->reload;
      # $GDS->RT(PNR=>$pnr->{PNRId}, NoIG=>1);
      my @newDel = _getFpLinesNoToDelete($pnr);
      my $del2      = \@newDel;
      @$del2      = sort {$b <=> $a} (@$del2);
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



1;
