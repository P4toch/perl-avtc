package Expedia::Modules::GAP::Apis;
#-----------------------------------------------------------------
# Package Expedia::Modules::GAP::Apis
#
# $Id: Apis.pm 713 2011-07-04 15:45:26Z pbressan $
#
# (c) 2002-2010 Egencia.                            www.egencia.eu
#-----------------------------------------------------------------

use strict;
use Data::Dumper;

use Expedia::Tools::Logger qw(&debug &notice &warning &error);
use Expedia::Tools::GlobalFuncs qw(&stringGdsPaxName &stringGdsOthers &dateXML);
use Expedia::Tools::GlobalVars qw($h_titleSex);

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

  my $market       = $ab->getCountryCode({trvPos => $ab->getWhoIsMain});
  
  my @add          = (); # Elements à ajouter en Amadeus.
  my @del          = (); # Numéros de lignes à supprimer en Amadeus.
  
  # On sort sauf si on a de l'API à faire.
  my $apiToDo      = $ab->isApisBooking; debug('apiToDo = '.$apiToDo);
  return 1 unless ($apiToDo);
  
  # ----------------------------------------------------------
  my $segSrDocs = {};
  debug('segments = '.Dumper(\@{$pnr->{'Segments'}}));
  
  SEGMENT: foreach my $segment (@{$pnr->{'Segments'}}) {

    # Récupération du Pays de destination + Compagnie aérienne
		my $lineNo = $segment->{'LineNo'};
    my $data   = $segment->{'Data'};

    next unless defined ($data);

    if ($data =~ /^(\w{2})\s?\d+\s+\w\s+\w+\s+\d(?:\s+|\*)(\w{3})(\w{3}).*$/) {
      my $cie  = $1;
      debug("Compagnie aérienne = $cie");
      $segSrDocs->{"S$lineNo"} = $cie;
    } else {
      warning('One segment line does not match regexp !');
      warning(' * line = '.$data);
      next SEGMENT;
    }
  
  } # Fin SEGMENT: foreach my $segment (@{$pnr->{'Segments'}})
  # ----------------------------------------------------------
  
  # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
  # On commence par recharger le PNR
  $pnr->reload;
  # $pnr->{_GDS}->RT(PNR=>$pnr->{PNRId}, NoIG=>1);
  # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
    
  my $travellers = $pnr->{Travellers};
    
  # ----------------------------------------------------------
  # Pour chacun des PAX on récupère les informations API
  foreach my $traveller (@$travellers) {

    my $apisInfos = $ab->getApisInfos({trvPos => $traveller->{Position}});
    debug('apisInfos = '.Dumper($apisInfos)) if (defined $apisInfos);
    next unless (defined $apisInfos);
      
    # ----------------------------------------------------------
	  # Recupération du passeportCountry et du destinationCountry
	  my $nationality        = $apisInfos->{Nationality};
	  my $destinationCountry = $apisInfos->{DestinationCountry};
	  my $residenceCountry   = $apisInfos->{ResidenceCountry};		
 	  # ----------------------------------------------------------
  	  
		# ----------------------------------------------------------
 		# Récupération du gendre M = Masculin, F = Féminin
 		my $title  = $traveller->{Title};
 		my $gender = 'M'; # Par défaut, c'est un mâle !
 		   $gender = $h_titleSex->{$title} if (exists $h_titleSex->{$title});
 		debug('gender = '.$gender);
 		# ----------------------------------------------------------
 		
 		# ----------------------------------------------------------
 		# Récupération du Type de Document (Passeport ou Carte d'Identité
 		my $idType = 'P'; # Passeport par défaut
 		   $idType = 'I' if ($apisInfos->{IdentityCardNumber} ne '');
 		my $idNum  = $apisInfos->{PassportNumber};
 		   $idNum  = $apisInfos->{IdentityCardNumber} if ($idType eq 'I');
 		   $idNum  =~ s/(^\s*|\s*$)//ig;
 		# ----------------------------------------------------------
  		
		my $firstName = stringGdsPaxName($traveller->{FirstName}, $market);
 		my $lastName  = stringGdsPaxName($traveller->{LastName}, $market);
  		
 		# ----------------------------------------------------------
 		# SR DOCS
        my $srDocs  = "SR DOCS__HK1-$idType".'/'; 
           $srDocs .= $residenceCountry.'/'; 
           $srDocs .= $idNum.'/'; 
           $srDocs .= $nationality.'/'; 
           $srDocs .= _dateConvert($apisInfos->{BirthDate}).'/'.$gender.'/'; 
           $srDocs .= _dateConvert($apisInfos->{ExpiryDate}).'/'; 
           $srDocs .= $lastName.'/'.$firstName;
   	debug('SR DOCS = '.$srDocs);
   	# ----------------------------------------------------------
  		
 		# Ajout de la SR DOCS dans Amadeus...
   	my @temp_ = ();
#    SR: foreach my $cie (values %$segSrDocs) {
#      foreach my $tmp_ (@temp_) { next SR if ($tmp_ eq $cie); }
#      push @temp_, $cie;
      my $tmp  = $srDocs;
         $tmp  =~ s/__/YY/; #bugzilla 11287 Mettre YY à la place de la compagnie et ajouter la ligne une seule fois
         $tmp .= '/'.$traveller->{PaxNum};
      push @add, { Data => $tmp, PerCode => $traveller->{PerCode}, PaxNumber => $traveller->{PaxNum} };
#    }
    	
    # Si la condition suivante est remplie, c'est que nous devons
  	#  fournir des informations API supplémentaires
  	next unless ($apisInfos->{SSRType} eq 'Docx');
    	
    # ----------------------------------------------------------
    # Récupération du numéro de téléphone portable
    my $phone = $traveller->{MobPhoneNo};
       $phone = s/\s+|\(|\)|\+|-|\.//ig if ($phone);
    # ----------------------------------------------------------
    	
    my $destinationAddress = stringGdsOthers($apisInfos->{DestinationAddress});
    my $destinationCity    = stringGdsOthers($apisInfos->{DestinationCity});
    my $destinationState   = stringGdsOthers($apisInfos->{DestinationState});
    my $destinationZipCode = stringGdsOthers($apisInfos->{DestinationZipCode});
       $destinationAddress = 'ADRESS DETAILS' if ($destinationAddress eq '');
  		
  	# ----------------------------------------------------------
    # SR DOCA
    # EGE-60315
	  my $srDoca1  = 'SR DOCA__HK1-D/';
		   $srDoca1 .= $destinationCountry || 'XXX';
       $srDoca1 .= '/';
       $srDoca1 .= $destinationAddress.'/';
       $srDoca1 .= $destinationCity.'/';
       $srDoca1 .= $destinationState.'/';
       $srDoca1 .= $destinationZipCode;
		my $srDoca2  = 'SR DOCA__HK1-R/'.$apisInfos->{ResidenceCountry};
		debug('SR DOCA 1 = '.$srDoca1);
		debug('SR DOCA 2 = '.$srDoca2);
    # ----------------------------------------------------------
    	
    # ----------------------------------------------------------
    # SR PCTC
  	my $srPctc  = 'SR PCTC __ HK /';
  	   $srPctc .= $lastName.' '.$firstName.' /';
  	   $srPctc .= $destinationCountry;
  	   $srPctc .= ($phone eq '') ? '1.' : $phone.'.';
       $srPctc .= $destinationAddress;
    if (($destinationCity    ne '')  ||
        ($destinationState   ne '')  ||
        ($destinationZipCode ne '')) {
  	   $srPctc .= ' ';
       $srPctc .= $destinationCity.' '   if ($destinationCity    ne '');
       $srPctc .= $destinationState.' '  if ($destinationState   ne '');
       $srPctc .= $destinationZipCode    if ($destinationZipCode ne '');
    }
    debug('SR PCTC = '.$srPctc);
    # ----------------------------------------------------------
  		
  	# Ajout des autres SR dans Amadeus...
    foreach my $temp ($srDoca1, $srDoca2, $srPctc) {
      @temp_ = ();
     # SR: foreach my $cie (values %$segSrDocs) {
     #   foreach my $tmp_ (@temp_) { next SR if ($tmp_ eq $cie); }
     #   push @temp_, $cie;
        my $tmp = $temp;
           $tmp  =~ s/__/YY/;  #bugzilla 11287 Mettre YY à la place de la compagnie et ajouter la ligne une seule fois
  		     $tmp .= '/'.$traveller->{PaxNum};
  		  push @add, { Data => $tmp, PerCode => $traveller->{PerCode}, PaxNumber => $traveller->{PaxNum} };
     # }
    }
  		
  } # Fin foreach my $traveller (@$travellers)
  
  # Appliquer les changements en Amadeus.
  _applyChanges($pnr, \@del, \@add, $WBMI);
  
  return 1;  
}

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Conversion des dates vers format APIS Amadeus
sub _dateConvert {
  my $date =  shift;
  
  return '' if ((!defined $date) || ($date eq ''));
  
  my $months = {
    '01' => 'JAN',
    '02' => 'FEB',
    '03' => 'MAR',
    '04' => 'APR',
    '05' => 'MAY',
    '06' => 'JUN',
    '07' => 'JUL',
    '08' => 'AUG',
    '09' => 'SEP',
    '10' => 'OCT',
    '11' => 'NOV',
    '12' => 'DEC',
  };
  
  $date =  dateXML($date);
  $date =~ s/\///ig;
  
  my $day   = substr($date, 6, 2);
  my $month = substr($date, 4, 2);
  my $year  = substr($date, 2, 2);
  
  return $day.$months->{$month}.$year;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Effectue des suppressions dans Amadeus + Envoi éventuellement d'une
#  ou plusieurs commandes + Rechargement du PNR.
sub _applyChanges {
  my $pnr           = shift;
  my $linesToDelete = shift;
  my $amadCommands  = shift;
  my $WBMI          = shift; # WBMI
  
  @$linesToDelete = sort {$b <=> $a} (@$linesToDelete);
  my $ER1 = []; my $ER2 = []; my $CMD = [];
  my $GDS = $pnr->{_GDS};
  
  RETRY: {{
    $GDS->command(Command=>'XE'.$_, NoIG=>1, NoMD=>1) foreach (@$linesToDelete);
    
    # ---------------------------------------------------------------------
    # On scrute le résultat de l'envoi des commandes APIS
    CMD: foreach my $cmd (@$amadCommands) {
      $CMD = $GDS->command(Command=>$cmd->{Data}, NoIG=>1, NoMD=>1);
      if  ( (grep(/DONNEES TEXTE ERRONEES/, @$CMD)) || (grep(/INVALID TEXT DATA/, @$CMD)) ) {
        my $addWbmiMesg =  $cmd->{Data};
           $addWbmiMesg =~ s/^(.*)(\/P\d)$/$1/ig; # Suppression des /P1 a la fin pour affichage dans WBMI
        $WBMI->addReport({
          Code        => 26,
          PnrId       => $pnr->{_PNR},
          AmadeusMesg => 'DONNEES TEXTE ERRONEES',
          PaxNumber   => $cmd->{PaxNumber},
          PerCode     => $cmd->{PerCode},
          AddWbmiMesg => $addWbmiMesg });
      }
    }
    # ---------------------------------------------------------------------
    
    # ---------------------------------------------------------------------  
    # Validation des modifications
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
		 ) {
      $pnr->reload;
      # $GDS->RT(PNR=>$pnr->{PNRId}, NoIG=>1);
      $linesToDelete  = [];
      @$linesToDelete = sort {$b <=> $a} (@$linesToDelete);
      goto RETRY;
    }
  }};
  
  # ---------------------------------------------------------------------
  # Puis reloadage de PNR
  # $pnr->reload;
  # $GDS->RT(PNR=>$pnr->{PNRId}, NoIG=>1);
  # ---------------------------------------------------------------------
  
  return 1;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

1;