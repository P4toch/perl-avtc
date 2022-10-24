package Expedia::Modules::SYN::Synchro;
#-----------------------------------------------------------------
# Package Expedia::Modules::SYN::Synchro
#
# $Id: Synchro.pm 686 2011-04-21 12:33:02Z pbressan $
#
# (c) 2002-2010 Expedia.                            www.egencia.eu
#-----------------------------------------------------------------

use strict;
use XML::LibXML;
use Data::Dumper;
use POSIX qw(strftime);

use Expedia::GDS::Profile qw(&profCreate);
use Expedia::Tools::Logger qw(&debug &notice &warning &error);
use Expedia::Tools::GlobalFuncs qw(&stringGdsOthers &stringGdsPaxName &stringGdsCompanyName &fielddate2amaddate &fielddate2srdocdate &cleanXML);
use Expedia::Tools::GlobalVars qw($cardTypes $cardCodes $h_context $h_titleSex $h_titleToAmadeus $h_AmaMonths $cnxMgr $intraUrl);
use Expedia::XML::UserProfile;
use Expedia::XML::MsgGenerator;
use Expedia::XML::CompanyProfile;
use Expedia::Databases::MidSchemaFuncs qw(&insertIntoAmadeusSynchro &isInAmadeusSynchro &deleteFromAmadeusSynchro &getInfosOnPerCode &getBillingEntityLabel &getUpComCodebycountry &getCountrybyUpComCode);
use Expedia::Databases::WorkflowManager qw(&insertAmadeusIdMsg);
use LWP::UserAgent;
use HTTP::Request::Common;

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Méthode principale
sub run {
  my $self   = shift;
  my $params = shift;
  
  my $item   = $params->{Item};
  
  my $type   = $item->{MSG_TYPE};
  my $action = $item->{ACTION};
  
  $params->{ISINHOUSE} = 0;
  $params->{ISINHOUSE_RUN}=0;
  $params->{flag_no_comcode}=0;
  $params->{flag_from_update}=0;
  
  my $res = 0;
  
  # -----------------------------------------------------------------------------------
  # Si l'action est CREATE on va tout de même vérifier en AMADEUS_SYNCHRO l'existence !
  if    (($action eq 'CREATE') && ($type eq 'USER')) {
    my $xmlDatas = Expedia::XML::UserProfile->new($item->{XML});
    my $amadSync = isInAmadeusSynchro({CODE => $xmlDatas->getUserPerCode(),
                                       TYPE => $type});
    $action = 'UPDATE' if ((defined $amadSync) && (defined $amadSync->[2]));
  }
  elsif (($action eq 'CREATE') && ($type eq 'COMPANY')) {
    my $xmlDatas = Expedia::XML::CompanyProfile->new($item->{XML});
    my $amadSync = isInAmadeusSynchro({CODE => $xmlDatas->getCompanyComCode(),
                                       TYPE => $type});
    $action = 'UPDATE' if ((defined $amadSync) && (defined $amadSync->[2]));    
  }
  # -----------------------------------------------------------------------------------

  $res= runSynchro($params,$action,$type);
  
  # Checking For INHOUSE Profiles and setting global param inhouse variables
  #------------------------------------------------------------------------------------  
  my $inHouseOID = checkForInHouseOID($params);
  if ( defined $inHouseOID ) {
    $params->{ISINHOUSE} = 1;
	$params->{INHOUSE_OID} = $inHouseOID;
  }  
  #------------------------------------------------------------------------------------
  
  # Running Synchro for In House Profiles
  #------------------------------------------------------------------------------------
  if ( $params->{ISINHOUSE} ) {
    my $inhOID = $params->{INHOUSE_OID};
	my $inh_GDS  = getConnection_amadeus_ihoid($inhOID);
	if ((!$inh_GDS) || (ref($inh_GDS) ne 'Expedia::Databases::Amadeus')) {
       error('A valid AMADEUS connection must be provided to this constructor. Aborting.');
       return undef;
    } else {
	   $params->{GDS} = $inh_GDS;
	   $params->{ISINHOUSE_RUN} = 1;
       $res = runSynchro($params,$action,$type);
	   $inh_GDS->disconnect();
    }
  }
  
  #--------------------------------------------------------------------------------------

  $params->{ISINHOUSE} = 0;
  $params->{ISINHOUSE_RUN} = 0;
  return $res;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Run Synchro actions
sub runSynchro {
   my ($params,$action,$type) = @_;
   my $res = 0;
   $res = _userCreate($params) if (($action eq 'CREATE') && ($type eq 'USER'));
   $res = _userUpdate($params) if (($action eq 'UPDATE') && ($type eq 'USER'));
   $res = _userDelete($params) if (($action eq 'DELETE') && ($type eq 'USER'));
   $res = _compCreate($params) if (($action eq 'CREATE') && ($type eq 'COMPANY'));
   $res = _compUpdate($params) if (($action eq 'UPDATE') && ($type eq 'COMPANY'));
   $res = _compDelete($params) if (($action eq 'DELETE') && ($type eq 'COMPANY'));
   return $res;
   
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Création d'un profil voyageur dans AMADEUS
sub _userCreate {
  my $params = shift;
  
  my $globalParams = $params->{GlobalParams};
  my $moduleParams = $params->{ModuleParams};
  my $item         = $params->{Item};
  my $GDS  				 = $params->{GDS};
  
  my $xmlDatas = Expedia::XML::UserProfile->new($item->{XML});
     $xmlDatas->_trace; # Ecriture dans les logs
     
  my $market = &getCountrybyUpComCode($xmlDatas->getPOSCompanyComCode()); 
  
  my $userNameDatas = stringGdsPaxName($xmlDatas->getUserLastName(), $market).'/'.
											stringGdsPaxName($xmlDatas->getUserFirstName().' '.$h_titleToAmadeus->{$xmlDatas->getUserTitle()}, $market);

	# Extraction du nom de compagnie	 
	my $userNameCompanyDatas = isInAmadeusSynchro({CODE => $xmlDatas->getCompanyComCode(), TYPE => 'COMPANY'})->[0][3]; 
	
	if (!$userNameCompanyDatas) {
		$params->{flag_no_comcode} =1 ;
		notice('Company not available in Amadeus : We will try to process in the next run');
		return 1;
		
	}
	
  
  $params->{Params}->{xmlDatas}             = $xmlDatas;
  $params->{Params}->{userNameDatas}        = $userNameDatas;
  $params->{Params}->{userNameCompanyDatas} = $userNameCompanyDatas;
  
  # Création du Profil
  my $AmadeusId = profCreate(GDS 	 => $GDS, 
  										 			 TNAME => $userNameDatas, 
  										 			 CNAME => $userNameCompanyDatas);
 
  # Cas d'une vraie création d'utilisateur
  my $retour;
  if ($AmadeusId) {
  	 if( $params->{ISINHOUSE} && $params->{ISINHOUSE_RUN} ) {
	  		$retour = updateInHouseAmadeusSynchro({	CODE   => $xmlDatas->getUserPerCode(),
  													  	TYPE   => 'USER', 
  													  	AID    => $AmadeusId
 												  });
	 } else {
 		    $retour = insertIntoAmadeusSynchro({	CODE   => $xmlDatas->getUserPerCode(),
  													  		      	 	TYPE   => 'USER', 
  													  					   	AID    => $AmadeusId,
 																			MARKET => $market
											   });
	 
			# Récuperation du numero de sequence pour le MsgId
			my $dbh = $cnxMgr->getConnectionByName('mid');

			#ON RECHERCHE LE PROCHAIN ID 
			my $query = "DECLARE \@RC INT , \@pNextVal INT  BEGIN EXECUTE \@RC =  WORKFLOW.Message_Seq_Nextval \@pNextVal OUTPUT; select \@pNextVal  END";
			my $msgId = $dbh->sproc($query, []);
			debug("MSGID SYNCHRO:$msgId");
					
			# Construction d'un XML pour insertion dans la table des "MESSAGE"
			my $oMsg = Expedia::XML::MsgGenerator->new({
						  context			  => $h_context,
						  msgId 				=> $msgId,
						  entityType  	=> 'User',
						  entityKey   	=> $xmlDatas->getUserPerCode(),
											properties    => [{	'name' 						=> 	'AdditionalInfo/AmadeusId',
																					'isStringContent' =>	'true',
																					'value'						=>  $AmadeusId
																			 }]
						}, 'UpdatePropertyEntityRQ.tmpl');
				my $msg = $oMsg->getMessage();
				debug('UpdatePropertyEntityRQ = '.$msg);

			# ---------------------------------------------------------------------
				# Insertion du message XML en base
				if (defined $msg) {
					my $row = insertAmadeusIdMsg({TYPE            => 'USER', 
													  CODE            => $xmlDatas->getUserPerCode(), 
														XML             => cleanXML($msg),
												  MESSAGE_ID => $msgId });
			  if ($row == 0) {
					  notice('Problem detected during WORKFLOW insertion. Aborting [...]');
					  return 0;
			  }
				} else {
				  notice("Problem detected during 'updateProperty' message creation.  Aborting [...]");
				  return 0;
				} # Fin if (defined $retourMsg)
			# ---------------------------------------------------------------------
	}

  	if ($retour) { 			
  		_userUpdate($params) unless ($params->{flag_from_update} == 1) ; ## Bypass _userUpdate if we already are in _userUpdate in order not to loop;
  	} else {
  		notice('Problem detected during AMADEUS_SYNCHRO insertion. Aborting [...]') unless $retour;
  		return 0;
  	}
  
  }
  else {
    notice('Problem detected during Amadeus Profile creation.');
    return 0;
  }
  
  return 1;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Modification d'un profil voyageur dans AMADEUS
sub _userUpdate {
  my $params = shift;
  
  my $globalParams = $params->{GlobalParams};
  my $moduleParams = $params->{ModuleParams};
  my $localParams  = $params->{Params};
  my $item         = $params->{Item};
  my $GDS          = $params->{GDS};

  # _____________________________________________________________________
	# Si $xmlDatas est dans la struct globale on ne recalcule pas la valeur ... 
  my $xmlDatas = '';
  if (defined $localParams->{xmlDatas})  {
  	$xmlDatas  = $localParams->{xmlDatas}; 
  } else {
  	$xmlDatas  = Expedia::XML::UserProfile->new($item->{XML});
  	$xmlDatas->_trace; # Ecriture dans les logs
  }
  # _____________________________________________________________________
  
  my $market = &getCountrybyUpComCode($xmlDatas->getPOSCompanyComCode()); 
		
	# - 1 Récupération de l'Identifiant Amadeus
  my $amadId='';
  if ( $params->{ISINHOUSE} && $params->{ISINHOUSE_RUN} ) {
     $amadId = isInAmadeusSynchro({'CODE' => $xmlDatas->getUserPerCode(), 'TYPE' => 'USER'})->[0][6];
  
     if (!$amadId || $amadId eq "" || $amadId eq "NULL" ){
		 # envoyer une variable supplémentaire flag_from_update dans $params
		 $params->{flag_from_update}=1;
		 my $res = _userCreate($params); 
		 return 1 if ($params->{flag_no_comcode} == 1);
		 $amadId = isInAmadeusSynchro({'CODE' => $xmlDatas->getUserPerCode(), 'TYPE' => 'USER'})->[0][6];
	 }
  } else {
     $amadId = isInAmadeusSynchro({'CODE' => $xmlDatas->getUserPerCode(), 'TYPE' => 'USER'})->[0][2];
  }	
	
	# Pas d'amadeusID
	if (!defined $amadId) {
		notice('Cannot update an unexisting profile. PerCode = '.$xmlDatas->getUserPerCode());
		return 0;
	}	
		
	# Structure contenant les données à ajouter et à supprimer
	my @add = ();
	my @del = ();

  # _____________________________________________________________________
  ## - 0 nom company
  debug('0 nom company');
	my $UserNameCompanyDatas = isInAmadeusSynchro({'CODE' => $xmlDatas->getCompanyComCode(),
																								 'TYPE' => 'COMPANY'})->[0][3];
	   $UserNameCompanyDatas = stringGdsCompanyName($xmlDatas->getCompanyName())
	     if (!$UserNameCompanyDatas) ;
  push (@add, {'Data' => 'PCN/'.$UserNameCompanyDatas});
  # _____________________________________________________________________
	
  # _____________________________________________________________________
	## - 1 nom traveler et nom company
  debug('1 - Nom Traveller et Company');
			
	# Extraction et traitement des caractères speciaux
	my $userNameDatas        = '';
	my $userNameCompanyDatas = '';
	
	if (defined $localParams->{userNameDatas}) {
	  $userNameDatas = $localParams->{userNameDatas};
	} else {
	  $userNameDatas = stringGdsPaxName($xmlDatas->getUserLastName(), $market).'/'.
		                 stringGdsPaxName($xmlDatas->getUserFirstName().' '.$h_titleToAmadeus->{$xmlDatas->getUserTitle()}, $market);
	}

	if (defined $localParams->{userNameCompanyDatas}) {
		$userNameCompanyDatas = $localParams->{userNameCompanyDatas};
	} else {
		$userNameCompanyDatas = stringGdsPaxName($xmlDatas->getUserLastName(), $market).'/'.
		  											stringGdsPaxName($xmlDatas->getUserFirstName().' '.$UserNameCompanyDatas, $market);
	}
  # _____________________________________________________________________
	
  # _____________________________________________________________________
	## Numéros de téléphone & Email
	
	my $phoneNumber  = $xmlDatas->getUserPhoneNumberBusiness();
	my $mobileNumber = $xmlDatas->getUserMobileNumber();
	my $faxNumber    = $xmlDatas->getUserFaxNumber();
	my $email        = $xmlDatas->getEmail();
	
	foreach ($phoneNumber, $mobileNumber, $faxNumber) { $_ =~ s/(^\s*|\s*$)//ig if ($_); }
	
	# Numéro de téléphone professionel
	if ($phoneNumber) {
	  push (@add, {'Data' => 'AP '.$phoneNumber.'-B/'.$userNameCompanyDatas, 'TrIndicator' => 'S'});
	  debug('[AP '.$phoneNumber.'-B/'.$userNameCompanyDatas."]['TrIndicator' => 'S']");
	}
		
	# Numéro de téléphone mobile
	if ($mobileNumber) {
	  push (@add, {'Data' => 'APM-'.$mobileNumber, 'TrIndicator' => 'A'});
		debug('[APM-'.$mobileNumber."]['TrIndicator' => 'A']");
	}
		
	# Numéro de fax
	if ($faxNumber) {
	  push (@add, {'Data' => 'AP F-'.$faxNumber, 'TrIndicator' => 'S'});
	  debug('[AP F-'.$faxNumber."]['TrIndicator' => 'S']");
	} 

	
  # _____________________________________________________________________
	
  # _____________________________________________________________________
	## 2 - Adresse
	debug('2 - Adresse');
	
	my @datasToAdd = ();
	my $address    = '';
		
	$address  =  $xmlDatas->getDefaultAddressName();
	_testLengthAdd(\$address, \@datasToAdd);
	$address .= ' '.$xmlDatas->getDefaultAddressStreet1();
	_testLengthAdd(\$address, \@datasToAdd);
	$address .= ' '.$xmlDatas->getDefaultAddressStreet2() if ($xmlDatas->getDefaultAddressStreet2());
	_testLengthAdd(\$address, \@datasToAdd);
	$address .= ' '.$xmlDatas->getDefaultAddressPostalCode();
	_testLengthAdd(\$address, \@datasToAdd);
	$address .= ' '.$xmlDatas->getDefaultAddressCity();
	_testLengthAdd(\$address, \@datasToAdd);
	$address .= ' '.$xmlDatas->getDefaultAddressCountryName();
	_testLengthAdd(\$address, \@datasToAdd);
		
	# Traitement des chars spéciaux
	my @newDatas = map { stringGdsOthers($_); } (@datasToAdd, $address);
		
	if (join ('', @newDatas) !~ /^\s*$/) {
	  @datasToAdd = @newDatas;
		# Construction des commandes amadeus pour l'adresse
		foreach my $line (@datasToAdd) {
		  $line =~ s/\s+/ /ig;
  	  if ($xmlDatas->getPOSCompanyComCode eq getUpComCodebycountry('GB')) {
    	  push (@add, {'Data' => "AM $line", 'TrIndicator' => 'A' });
    		debug('[AM '.$line."]['TrIndicator' => 'A']") if ($line);
   		} else {
     		push (@add, {'Data' => "AM $line", 'TrIndicator' => 'S' });
     		debug('[AM '.$line."]['TrIndicator' => 'S']") if ($line);								
   		}
 		}
	}
  # _____________________________________________________________________

  # _____________________________________________________________________
	## 3 - Adresses Mail
	debug('3 - Adresses Mail');
	
	if ($email) {
	  push (@add, {'Data' => 'AP E-'.uc($email), 'TrIndicator' => 'S' });        #bugzilla #12702   isTravellerShadowUser/passer à A le cas écheant
    debug('[AP E-'.$email."]['TrIndicator' => 'S']");
    if($market eq "FR") {                                                      #bugzilla #12713   isTravellerShadowUser
	     push (@add, {'Data' => 'PPS/R/NMX.X@$M-'.$email, 'TrIndicator' => ''});  
	     debug('[PPS/R/NMX.X@$M-'.$email."]['TrIndicator' => '']");
	  }
	}	
	
  # _____________________________________________________________________
 
  # _____________________________________________________________________
	## 4 - Arrangers
  debug('4 - Arrangers');
  
  my $maxNbOfArrangers = 10;
  my $currentArranger  = 0;
  if ($xmlDatas->getPOSCompanyComCode() ne getUpComCodebycountry('FR')) {
  	ARRANGER: for (my $i = 0; $i < $xmlDatas->getNbArrangers(); $i++) {
  	  my $oneNumber = $xmlDatas->getArrangerOneNumber($i);
  	     $oneNumber =~ s/(^\s*|\s*$)//ig if ($oneNumber);
  		my $datasToInsert = 'AP ASSIST/'.$oneNumber.'/'.
  												             stringGdsPaxName($xmlDatas->getArrangerFirstName($i), $market).' '.
  												             stringGdsPaxName($xmlDatas->getArrangerLastName($i), $market).' - '.
  												             $UserNameCompanyDatas;
  		push (@add, {'Data' => $datasToInsert, 'TrIndicator' => 'S'});
  		debug('['.$datasToInsert."]['TrIndicator' => 'S']");
  		$currentArranger++;
  		last ARRANGER if ($currentArranger eq $maxNbOfArrangers);  				 
  	}
  }
  # _____________________________________________________________________
  
  # _____________________________________________________________________
  ## 5 - Loyalty Subscription Cards
  debug('5 - Loyalty Subscription Cards');

	my $today = (strftime "%Y%m%d", localtime);
	
	for (my $i = 0; $i < $xmlDatas->getNbLoyaltySubscriptionCards(); $i++) {
			
	  my $validTo = 1;
		
		# $validTo est purement numérique pour pouvoir comparer les dates comme on compare les entiers
		if ($xmlDatas->getCardValidTo($i) ne '') {
		  $today   = 0;
			$validTo = join ('', ($xmlDatas->getCardValidTo($i) =~ /^(\d{4})-(\d{2})-(\d{2})/));
		}
	  	
	  # Carte de fidélité compagnie aérienne # && ($today < $validTo)
	  if ( ($xmlDatas->getCardNumber($i))                          &&
	  		 ($xmlDatas->getCardISSupplierService($i, 0) =~ /^AIR$/) &&
	  		 ($xmlDatas->getCardType($i) eq $cardTypes->{'loyalty'}) ) {
	    my $locDatas = 'FFN '.stringGdsOthers($xmlDatas->getCardISSupplierCode($i, 0)).'-'.$xmlDatas->getCardNumber($i);
	  	push (@add, { 'Data' => $locDatas, 'TrIndicator' => 'A' });
			debug('[FFN '.$locDatas."]['TrIndicator' => 'A']");
  	}

	  #EGE-92266 Add subscription card TPC 
	  elsif( ($xmlDatas->getCardNumber($i))                          &&
	  		 ($xmlDatas->getCardISSupplierService($i, 0) =~ /^AIR$/) &&
	  		 ($xmlDatas->getCardType($i) eq $cardTypes->{'subscription'}) &&
			( ($xmlDatas->getCardCode($i) eq  "TPC") || ($xmlDatas->getCardCode($i) eq  "TMU") || ($xmlDatas->getCardCode($i) eq  "TPM") ||	($xmlDatas->getCardCode($i) eq  "TPP") || ($xmlDatas->getCardCode($i) eq  "TPU") ) )  {
	    my $locDatas = 'pps/'.$xmlDatas->getCardCode($i).'  sr*sktp-'.$xmlDatas->getCardNumber($i);
	  	push (@add, { 'Data' => $locDatas, 'TrIndicator' => 'A' });
			debug('[PPS '.$locDatas."]['TrIndicator' => 'A']");
  	}
	
	  # Carte d'abonnement Air France, AirLinair # && ($today < $validTo)	
	  elsif( ($xmlDatas->getCardNumber($i))                               &&
	  			 ($xmlDatas->getCardType($i) eq $cardTypes->{'subscription'}) &&
           ($xmlDatas->getCardISSupplierCode($i, 0) =~ /^(AF|A5)$/) ) {
	    my $locDatas = stringGdsOthers('AF'.$xmlDatas->getCardNumber($i));
	    push (@add, { 'Data' => 'FD'.$locDatas, 'TrIndicator' => 'A'});
		  debug('[FD'.$locDatas."]['TrIndicator' => 'A']");
  	}

  	# Carte de fidélité voiture # && ($today < $validTo)
	  elsif (	($xmlDatas->getCardNumber($i))                          &&
	  				($xmlDatas->getCardISSupplierService($i, 0) =~ /^CAR$/) &&
	  				($xmlDatas->getCardType($i) eq $cardTypes->{'loyalty'}) &&
	  				($xmlDatas->getCardISSupplierCode($i, 0)) ) { 
  		my $locDatas1 = $xmlDatas->getCardISSupplierCode($i,0);
			my $locDatas2 = $xmlDatas->getCardNumber($i);
    	push (@add, { 'Data'        => 'PCI/CO-'.$locDatas1.'/ID-'.$locDatas2,
       			        'TrIndicator' => ''});
  		debug('[PCI/CO-'.$locDatas1.'/ID-'.$locDatas2."]['TrIndicator' => '']")
  		  if($locDatas2);
    }

    # Carte de fidélité hotel # && ($today < $validTo)
    elsif ( ($xmlDatas->getCardNumber($i))                            &&
						($xmlDatas->getCardISSupplierService($i, 0) =~ /^HOTEL$/) &&
						($xmlDatas->getCardISSupplierCode($i, 0))                 &&
						($xmlDatas->getCardType($i) eq $cardTypes->{'loyalty'}) ) {
      my $locDatas1 = $xmlDatas->getCardISSupplierCode($i,0);
	  	my $locDatas2 = $xmlDatas->getCardNumber($i);
    	push (@add, { 'Data'        => 'PHI/CO-'.$locDatas1.'/ID-'.$locDatas2,
    	              'TrIndicator' => ''});
		  debug('[PHI/CO-'.$locDatas1."/ID-".$locDatas2."]['TrIndicator' => '']") 
		    if($locDatas2);
	  }
	  	
	  # Traitement des cartes d'abonnement train
	  elsif ( ($xmlDatas->getCardNumber($i))                               &&
	  				($xmlDatas->getCardType($i) eq $cardTypes->{'subscription'}) &&
						($xmlDatas->getCardISSupplierService($i,0) =~ /^RAIL$/) ) {  			
  	  my $type 		= stringGdsOthers($xmlDatas->getCardName($i));
  		my $class 	= stringGdsOthers($xmlDatas->getCardClass($i));
  		my $parc 		= stringGdsOthers($xmlDatas->getCardItinerary($i));
   		my $dateDeb = $xmlDatas->getCardValidFrom($i);
   		my $dateFin = $xmlDatas->getCardValidTo($i);
			if ($dateDeb) {
   		  my ($locYear, $locMonth, $locDay) = ($dateDeb =~ /(\d{4})-(\d{2})-(\d{2})/);
   			$dateDeb = $locDay.$h_AmaMonths->{$locMonth}.$locYear;
			} else { $dateDeb='01JAN1900'; }
			if ($dateFin) {
   		  my ($locYear, $locMonth, $locDay) = ($dateFin =~ /(\d{4})-(\d{2})-(\d{2})/);
  			$dateFin = $locDay.$h_AmaMonths->{$locMonth}.$locYear;			  
			} else { $dateFin='01JAN2999'; }
			my $msg = "RM R $type $class $parc FROM $dateDeb UNTIL $dateFin";
			   $msg =~ s/\s+/ /ig;
  		push (@add, { 'Data'        => $msg,
  		              'TrIndicator' => 'S'});
			debug("[RM R $type $class $parc FROM $dateDeb UNTIL $dateFin]['TrIndicator' => 'S']");
  	}

  	# Traitement des cartes de fidélité train
  	elsif ( ($xmlDatas->getCardNumber($i))                          &&
	  				($xmlDatas->getCardType($i) eq $cardTypes->{'loyalty'}) &&
						($xmlDatas->getCardISSupplierService($i,0) =~ /^RAIL$/)	) {
			my $num 		= $xmlDatas->getCardNumber($i);
			   $num    .= '29090106'.$num if (($num == 9) && ($xmlDatas->getCardISSupplierCode($i,0) eq '2C'));
			   $num    .= '30840601'.$num if (($num == 9) && ($xmlDatas->getCardISSupplierCode($i,0) eq 'YS'));
			my $dateFin = $xmlDatas->getCardValidTo($i);
			my $percode = $xmlDatas->getUserPerCode($i);
      if ($dateFin) {
   		  my ($locYear, $locMonth, $locDay) = ($dateFin =~ /(\d{4})-(\d{2})-(\d{2})/);
  			$dateFin = $locDay . $h_AmaMonths->{$locMonth} . $locYear;
			}	else { $dateFin = '01JAN2999'; }
			push(@add,{'Data' => 'PPS/R//FID/C-'.$num ,'TrIndicator' => ''} );
			debug('[PPS/R//FID/C-'.$num."]['TrIndicator' => '']");
    }
	  	
    else {
	    debug("cas loyalty/subscription non traité");
	  	debug("[".$xmlDatas->getCardNumber($i)."][".$xmlDatas->getCardISSupplierService($i,0)."][".$xmlDatas->getCardISSupplierCode($i, 0)."]")
	  	  if($xmlDatas->getCardNumber($i));				 
	  }

	}
  # _____________________________________________________________________

  # _____________________________________________________________________
	## 6 - Section documents d'identité
  debug("6 - Section documents d'identité");
  
	my $nbiddoc = $xmlDatas->getNbIDDocuments();
	
	for (my $i = 0; $i < $nbiddoc ;$i++) {
	
	 	my $type = $xmlDatas->getIDDocumentType($i);
	 	next unless ($type =~ /^(PASSPORT|ID|DL)$/);

		my $nr =  stringGdsOthers($xmlDatas->getIDDocumentNumber($i));
		   $nr =~ s/\s*//ig;
		next unless $nr;
		
		my $ex = fielddate2amaddate($xmlDatas->getIDDocumentExpiryDate($i));
		my $is = fielddate2amaddate($xmlDatas->getIDDocumentIssueDate($i));
		my $co = $xmlDatas->getIDDocumentNationalityCode($i);
		
		my $NR = ''; $NR = '/NR-'.$nr;
		my $EX = ''; $EX = '/EX-'.$ex if ($ex);
		my $IS = ''; $IS = '/IS-'.$is if ($is);
		my $CO = ''; $CO = '/CO-'.$co if ($co);		
	
		# PASSEPORT
		if ($type eq 'PASSPORT') {
      push (@add, { 'Data'        => 'PAS'.$CO.$NR.$IS.$EX,
                    'TrIndicator' => '',
                    'NoNormalize' => 0 });
      debug('[PAS'.$CO.$NR.$IS.$EX."]['TrIndicator' => ''][NoNormalize' => 0]");
		}
		
		# CARTE D'IDENTITE
		elsif ($type eq 'ID') {
			push (@add, { 'Data'        => 'PID'.$CO.$NR.$IS.$EX,
                    'TrIndicator' => '',
                    'NoNormalize' => 0 });
		  debug('[PID'.$CO.$NR.$IS.$EX."]['TrIndicator' => ''][NoNormalize' => 0]");
		}
		
		# PERMIS DE CONDUIRE
		elsif ($type eq 'DL') {
			push (@add, { 'Data'        => 'PCE'.$CO.$NR.$IS.$EX,
                    'TrIndicator' => '',
                    'NoNormalize' => 0 });
      debug('[PCE'.$CO.$NR.$IS.$EX."]['TrIndicator' => ''][NoNormalize' => 0]");
		}

	}
  # _____________________________________________________________________
	
  # _____________________________________________________________________
	## 7 - Section Birthdate
	debug('7 - Section Birthdate');
	my $birthDate = $xmlDatas->getBirthDate();
	if ($birthDate) {
	  $birthDate = fielddate2amaddate($birthDate);
	  push (@add, { 'Data'        => 'PBD/'.$birthDate,
	                'TrIndicator' => '' });  
	  debug('[PBD/'.$birthDate."]['TrIndicator' => '']");
	  
	  if($market eq 'FR') {
  	  push (@add, { 'Data'        => 'PPS/R/NMX.X@$D-'.$birthDate,                    #bugzilla #12713
	                 'TrIndicator' => '' });  
	    debug('[PPS/R/NMX.X@$D-'.$birthDate."]['TrIndicator' => '']");
	  }
	}
  # _____________________________________________________________________
	
  # _____________________________________________________________________
	## 8 - Préferences        
	debug('8 - Préferences');
	my $mealPref = $xmlDatas->getUserAirPrefMeal();
	my $seatPref = $xmlDatas->getUserAirPrefSeat();
	if ($mealPref) {
    push (@add, { 'Data' => 'SR '.$mealPref, 'TrIndicator' => 'M' });
 	  debug('[SR '.$mealPref."]['TrIndicator' => 'M']");
	}
 	if ($seatPref) {
    push (@add, { 'Data' => 'ST /'.$seatPref, 'TrIndicator' => 'M' });
    debug('[ST /'.$seatPref."]['TrIndicator' => 'M']");
 	}
  # _____________________________________________________________________
	
  # _____________________________________________________________________
	## 9 - Centre de Coûts
	debug('9 - Centre de Coûts');
  $xmlDatas->extractCCDatas();
  my ($cc1, $cc2) = ('', '');
  my @cc = ($cc1, $cc2);
  
  #### EGE-108911
  my $idcc1 ;
  my $idcc2 ;
	$idcc1 = $xmlDatas->getCC1Code() if ($xmlDatas->getCC1Code() ne '-1');
	$idcc2 = $xmlDatas->getCC2Code() if ($xmlDatas->getCC2Code() ne '-1');
 	$cc1 = stringGdsOthers($xmlDatas->getCC1Value()) if ($xmlDatas->getCC1Flag() and ($xmlDatas->getCC1Code() ne '-1'));
    $cc2 = stringGdsOthers($xmlDatas->getCC2Value()) if ($xmlDatas->getCC2Flag());
  
  # Traitement du cas particulier de decathlon lille & lyon et de sagem
  if (($xmlDatas->getPOSCompanyComCode() eq getUpComCodebycountry('FR')) and
      ($xmlDatas->getCompanyComCode() != 2152)                 and
      ($xmlDatas->getCompanyComCode() != 2151)                 and
      ($xmlDatas->getCompanyComCode() != 2150)                 and 
      ($xmlDatas->getCompanyComCode() != 2153)                 and
      ($xmlDatas->getCompanyComCode() != 864)) {
    push (@add,{'Data' => "RM *CC1 $cc1", 'TrIndicator' => 'S' }) if ($cc1);
   	push (@add,{'Data' => "RM *CC2 $cc2", 'TrIndicator' => 'S' }) if ($cc2);

    debug("[RM *CC1 $cc1]['TrIndicator' => 'S']") if ($cc1);
  	debug("[RM *CC2 $cc2]['TrIndicator' => 'S']") if ($cc2);
  } 
  
  # Traitement CC cas général
  else {
    push (@add,{'Data' => "RM *CC1 $cc1", 'TrIndicator' => 'A' }) if ($cc1);
    push (@add,{'Data' => "RM *CC2 $cc2", 'TrIndicator' => 'A' }) if ($cc2);
	push (@add, {'Data' => "RM *IDCC1 $idcc1", 'TrIndicator' => 'A'}) if ($idcc1) ;	
	push (@add, {'Data' => "RM *IDCC2 $idcc2", 'TrIndicator' => 'A'}) if ($idcc2) ;
	
    debug("[RM *CC1 $cc1]['TrIndicator' => 'A']") if ($cc1);
    debug("[RM *CC2 $cc2]['TrIndicator' => 'A']") if ($cc2);
	debug("[RM *IDCC1 $idcc1]['TrIndicator' => 'A']") if ($idcc1);
	debug("[RM *IDCC2 $idcc2]['TrIndicator' => 'A']") if ($idcc2);
	
  }
  # _____________________________________________________________________
	
  # _____________________________________________________________________
	## 10 - Percode
	debug('10 - Percode');
  push (@add, {'Data' => 'RM *PERCODE '.$xmlDatas->getUserPerCode(), 'TrIndicator' => 'A'});
  debug('[RM *PERCODE '.$xmlDatas->getUserPerCode()."]['TrIndicator' => 'A']")
    if ($xmlDatas->getUserPerCode());
  # _____________________________________________________________________
  
  # _____________________________________________________________________
	## 11 - Status ViP
	debug('11 - Status ViP');
	my $isVip           = $xmlDatas->getIsVIP();
	my $hasVipTreatment = $xmlDatas->getHasVIPTreatment();
	my $vipMsg          = '';
	   $vipMsg         .= 'PAX IS VIP'     if ($isVip eq 'true');
	   $vipMsg         .= ' - VIP SERVICE' if ($hasVipTreatment eq 'true' && $vipMsg ne '');
	   $vipMsg         .= 'VIP SERVICE'    if ($hasVipTreatment eq 'true' && $vipMsg eq '');
  if ($isVip eq 'true') {
	  push (@add, { 'Data' => 'OSYY PAX VIP COMPANY '.$UserNameCompanyDatas, 'TrIndicator'=>'A'} );  	
   	debug('[OSYYPAX VIP COMPANY '.$UserNameCompanyDatas."]['TrIndicator' => 'A']");
  }
  if ($vipMsg ne '') {
  	push (@add, { 'Data' => 'PPR/ ATTENTION !!! '.$vipMsg, 'TrIndicator' => ''});
  }
  # _____________________________________________________________________
	
  # _____________________________________________________________________
	## 12 - Moyens de Paiement -- NOW IN SYNCHRO_FOP, A DIFFERENT SCRIPT
my $message='';
my $userAgent = LWP::UserAgent->new(agent => 'perl post');
my $params_ws=$intraUrl.'/midnew.cgi?action=updatePaymentMeans&country='.$market.'&percode='.$xmlDatas->getUserPerCode().'&cc1=&comcode='.$xmlDatas->getCompanyComCode();
my $response = $userAgent->request(GET $params_ws,
Content_Type => 'text/xml',
Content => $message);

if($response->as_string =~/SUCCESS/){
notice("PaymentMeans------------> SUCCESS");
}
else{
notice("PaymentMeans------------> FAILURE");
}

  
  # _____________________________________________________________________
  ## 13 - Remarques Divers # Concerne exclusivement l'Angleterre
  debug('13 - Remarques Divers');
  if ($xmlDatas->getPOSCompanyComCode() eq getUpComCodebycountry('GB')) {
    
    # Gestion des longueurs > 85 char
    my ($misc_line, @misc_lines) = ('', ());
    
    foreach my $str ( split (/ /, stringGdsOthers($xmlDatas->getUserMiscComment())) ) {
    	if (length($misc_line.' '.$str) > 85){
        push @misc_lines, $misc_line;
        $misc_line = $str;
    	} else {
        $misc_line .= ' '.$str;
    	}
    }
    
    push (@misc_lines, $misc_line) if ($misc_line ne '');
    
    foreach my $misc (@misc_lines) {
      $misc = 'RM MISC '.$misc;
      $misc =~ s/\s+/ /ig;
    	push (@add, {'Data' => $misc, 'TrIndicator' => 'S'});
	    debug('[RM MISC '.$misc."]['TrIndicator' => 'S']") if ($misc);
    }
    
  }
  # _____________________________________________________________________
	
  # _____________________________________________________________________
	## 14 - OSYY User
	debug('14 - OSYY User'); 
	if (stringGdsOthers($xmlDatas->getUserOSIYY())) {
		push (@add, {'Data' =>'OSYY '.stringGdsOthers($xmlDatas->getUserOSIYY()) ,'TrIndicator' => 'A'} );
		debug('[OSYY '. stringGdsOthers($xmlDatas->getUserOSIYY())."]['TrIndicator' => 'A']")
		  if ($xmlDatas->getUserOSIYY());
	}
  # _____________________________________________________________________
	
  # _____________________________________________________________________
	## 15 - SR DOCS
	debug('15 - SR DOCS');

  # Récupération du gendre M = Masculin, F = Féminin
  my $title  = $xmlDatas->getUserTitle();
  my $gender = 'M'; # Par défaut, c'est un mâle !
     $gender = $h_titleSex->{$title} if (exists $h_titleSex->{$title});
  debug('gender = '.$gender);
     
  $birthDate = $xmlDatas->getBirthDate();
  $birthDate = fielddate2srdocdate($birthDate) if ($birthDate);

  if ($birthDate) {
  	for (my $i = 0; $i < $nbiddoc; $i++) {
  	 	my $ty =  $xmlDatas->getIDDocumentType($i);
  	 	next unless ($ty eq 'PASSPORT');
  		my $nr =  stringGdsOthers($xmlDatas->getIDDocumentNumber($i));
  		   $nr =~ s/\s*//ig;
  		my $ex =  fielddate2srdocdate($xmlDatas->getIDDocumentExpiryDate($i));
  		my $co =  $xmlDatas->getIDDocumentNationalityCode($i);
		
		###EGE-107442 
		my $rc = $xmlDatas->getResidenceCountryCode;
		
  	#	my $ic =  $xmlDatas->getIDDocumentIssueCountryCode($i);
  	  next unless ($nr && $ex && $co);
  	#	next unless ($nr && $ex && $co && $ic);
  		my $sr = 'SR DOCS YY HK1-P-'.$rc.'-'.$nr.'-'.$co.'-'.$birthDate.'-'.$gender.'-'.$ex.'-'.
  		         stringGdsOthers($xmlDatas->getUserLastName().'-'.$xmlDatas->getUserFirstName());
      push (@add, {'Data' => $sr, 'TrIndicator' => 'A'});
  	}
  }
  # _____________________________________________________________________
  
  # _____________________________________________________________________
  # Ouverture du Profil et mise à jour ;)
  my $profile = Expedia::GDS::Profile->new(
                  PNR => $amadId,
                  GDS => $GDS,
                  TYPE => 'T');
  
  # Suppression de toutes les lignes du Profil sauf la première
	foreach (@{$profile->{PnrTrData}}) {
	  push @del, $_->{LineNo} unless ($_->{LineNo} eq '1' 
	                                  || $_->{Data} =~ /^RM\s*PLEASE ASK FOR CREDIT CARD/
	                                  || $_->{Data} =~ /^FP /
	                                  || $_->{Data} =~ /^RC\s*CC\s*HOTEL\s*ONLY/
									  || $_->{Data} =~ /^RX /
	                                  );
	}
	
	# Renommage de la personne sauf si l'on vient de la fonction _userCreate()
	push (@add, {'Data' => '1/1'.$userNameDatas}) unless (defined $localParams->{xmlDatas});
	  
	$params->{Params} = undef;
  
  my $res = $profile->update(add => \@add, del => \@del, NoGet => 1);
  # _____________________________________________________________________
    
  notice("Profile '$amadId' updated.") if ($res);
  
  return $res;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Suppression d'un profil voyageur dans AMADEUS
sub _userDelete {
  my $params = shift;
  
  my $globalParams = $params->{GlobalParams};
  my $moduleParams = $params->{ModuleParams};
  my $item         = $params->{Item};
  my $GDS          = $params->{GDS};
  
  my $xmlDatas     = Expedia::XML::UserProfile->new($item->{XML});
  
  # _____________________________________________________________________
  # Récuperation du PerCode
  my $perCode = $xmlDatas->getUserPerCode();
  if (!$perCode) {
    notice('Problem detected during Profile deletion [PERCODE].');
  	return 0;
  } else { debug('PerCode = '.$perCode); }
  # _____________________________________________________________________
  
  # _____________________________________________________________________
  # Récuperation de l'amadeusID
    my $amadId;
  
  my $inHouseOID = checkForInHouseOID($params);
  if ( defined $inHouseOID &&  $params->{ISINHOUSE} == 0 ) {
    $params->{ISINHOUSE} = 1;
  }  
  
  
  if ( ( $params->{ISINHOUSE} == 1 || $params->{ISINHOUSE} == 0 ) && $params->{ISINHOUSE_RUN} == 0 ) {
     $amadId = isInAmadeusSynchro({'CODE' => $perCode, 'TYPE' => 'USER'})->[0][2];
  } elsif ( $params->{ISINHOUSE} == 1 && $params->{ISINHOUSE_RUN} == 1 ) {
     $amadId = isInAmadeusSynchro({'CODE' => $perCode, 'TYPE' => 'USER'})->[0][6];
  } 
  
  notice ("AmadId".$amadId);
  
  if (!$amadId) {
  	notice('Problem detected during Profile deletion [AMADEUS_ID].');
  	return 0;
  } else { debug('amadId = '.$amadId); }
  # _____________________________________________________________________
  
  # _____________________________________________________________________
  # Le profil est desactivé dans Amadeus
  my $res = $GDS->PXRT(PNR => $amadId);
  
  if ($params->{ISINHOUSE} && $res && $params->{ISINHOUSE_RUN}){
     $params->{INHOUSE_DELETED}= "Y";
  }
  if (!$res) {
  	notice("Problem detected during Profile '$amadId' deletion [PXRT].");
  	return 0;
  }
  # _____________________________________________________________________
  
  # _____________________________________________________________________
  # Suppression de Amadeus_Synchro
  if ($params->{ISINHOUSE} == 1 && $params->{INHOUSE_DELETED} eq "Y" && $params->{ISINHOUSE_RUN} == 1) {
    $res = deleteFromAmadeusSynchro({AID  => $amadId, 
  																 CODE => $xmlDatas->getUserPerCode(), 
  																 TYPE => 'USER'});
  } elsif ( $params->{ISINHOUSE} == 0 && $params->{ISINHOUSE_RUN} == 0 && $params->{INHOUSE_DELETED} eq "N" ) {
     $res = deleteFromAmadeusSynchro({AID  => $amadId, 
  																 CODE => $xmlDatas->getUserPerCode(), 
  																 TYPE => 'USER'});
  }
  if (!$res) {
  	notice("Problem detected during Profile '$amadId' deletion [AMD_SYNCHRO].");
  	return 0;
  }
  # _____________________________________________________________________
  
  notice("Profile '$amadId' desactivated.") if ($res);
  
  return 1; 
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Création d'un profil société dans AMADEUS
sub _compCreate {
  my $params = shift;
  
  my $globalParams = $params->{GlobalParams};
  my $moduleParams = $params->{ModuleParams};
  my $item         = $params->{Item};
  my $GDS          = $params->{GDS};
  
  # Extraction des données sur la société
  my $xmlDatas  = Expedia::XML::CompanyProfile->new($item->{XML});
  
  my $AmadeusId = profCreate(GDS   => $GDS, 
  										 			 CNAME => stringGdsCompanyName($xmlDatas->getCompanyName()));
  
  if ($AmadeusId) {
 		
    my $market = &getCountrybyUpComCode($xmlDatas->getPOSCompanyComCode()); 
    
    # =======================================================================
    # Dans le cas spécifique de l'Espagne nous devons insérer dans le
    #   profil société la remarque suivante : RM *CN22236
    # Et dans le cas des Pays-Bas           : RM *ACECLN-103377
    # Et dans le cas de la Suède            : RM *K:769
    if ($market =~ /^(ES|NL|SE)$/) {
      # ---------------------------------------------------------------------
      my @add = ();
      my @del = ();
      
      # Ouverture du Profil et mise à jour ;)
      my $profile = Expedia::GDS::Profile->new(
                      PNR  => $AmadeusId,
                      GDS  => $GDS,
                      TYPE => 'C');
      
    	push (@add, { 'Data' => 'RM *CN22236',       'TrIndicator' => 'A' }) if ($market eq 'ES');
    	push (@add, { 'Data' => 'RM *ACECLN-103377', 'TrIndicator' => 'A' }) if ($market eq 'NL');
    	push (@add, { 'Data' => 'RM *K:769',         'TrIndicator' => 'A' }) if ($market eq 'SE');
      
      my $res = $profile->update(add => \@add, del => \@del, NoGet => 1);
      # ---------------------------------------------------------------------
    }
    # =======================================================================
 	if($params->{ISINHOUSE} && $params->{ISINHOUSE_RUN} ) {
 	  my $updateReturn = updateInHouseAmadeusSynchro({CODE 	=> $xmlDatas->getCompanyComCode(),									
  													  									 TYPE 	=> 'COMPANY',
  													  									 AID  	=> $AmadeusId});
	} else {
	  my $insertReturn = insertIntoAmadeusSynchro({CODE 	=> $xmlDatas->getCompanyComCode(),	
 																						NAME 	=> stringGdsCompanyName($xmlDatas->getCompanyName()),
  													  									 TYPE 	=> 'COMPANY',
  													  									 MARKET => $market,
  													  									 AID  	=> $AmadeusId});
	}
 	my $dbh = $cnxMgr->getConnectionByName('mid');
    
    #ON RECHERCHE LE PROCHAIN ID 
    my $query = "DECLARE \@RC INT , \@pNextVal INT  BEGIN EXECUTE \@RC =  WORKFLOW.Message_Seq_Nextval \@pNextVal OUTPUT; select \@pNextVal  END";
    my $msgId = $dbh->sproc($query, []);
    debug("MSGID _compCreate:$msgId");
     		
    # Construction d'un XML à insérer dans la table des "MESSAGE"
    my $oMsg = Expedia::XML::MsgGenerator->new({
                  context			  => $h_context,
                  msgId					=> $msgId,
                  entityType  	=> 'Company',
  	              entityKey   	=> $xmlDatas->getCompanyComCode(),
									properties	=> [{	'name' 						=> 'CompanyParameters/GDSSetting/AmadeusId',
																		'isStringContent'	=> 'true',
																		'value'						=> $AmadeusId,
																	},
																	{	'name' 						=> 'CompanyParameters/GDSSetting/AmadeusName',
																		'isStringContent'	=> 'true',
																		'value'						=> stringGdsCompanyName($xmlDatas->getCompanyName()),
																	}]
               }, 'UpdatePropertyEntityRQ.tmpl');
  	my $msg = $oMsg->getMessage();
  	
  	if (defined $msg) {
  	  insertAmadeusIdMsg({TYPE            => 'COMPANY',
                          CODE            => $xmlDatas->getCompanyComCode(), 
                          XML             => cleanXML($msg),
                          MESSAGE_ID => $msgId});
  	} else {
  	  error('Error detected during XML message creation.');
  	}

  } else {
    return 0;
  }

  return 1;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Modification d'un profil société dans AMADEUS
sub _compUpdate {
	my $params = shift;

	my $globalParams = $params->{GlobalParams};
	my $moduleParams = $params->{ModuleParams};
	my $item         = $params->{Item};
	my $GDS          = $params->{GDS};
	my $name_local   = '';
	my $name_xml	 = '';
	my $numero       = '';
	
	my $dbh = $cnxMgr->getConnectionByName('mid');

	my $xmlDatas = Expedia::XML::CompanyProfile->new($item->{XML});

	# _____________________________________________________________________
	# Récupération du ComCode
	my $comCode  = $xmlDatas->getCompanyComCode();
	if (!$comCode) {
	notice('Problem detected during Profile update [COMCODE].');
	return 0;
	} else { debug('comCode = '.$comCode); }
	# _____________________________________________________________________

	# _____________________________________________________________________
	# Récuperation de l'amadeusID
	my $amadId='';
	if ( $params->{ISINHOUSE} && $params->{ISINHOUSE_RUN} ) {
	  $amadId = isInAmadeusSynchro({CODE	=> $comCode, TYPE	=> 'COMPANY'})->[0][6];
	} else {
	  $amadId = isInAmadeusSynchro({CODE	=> $comCode, TYPE	=> 'COMPANY'})->[0][2];
	}
	if (!$amadId) {
	notice('Problem detected during Profile update [AMADEUSID].');
	return 0;
	} else { debug('amadId = '.$amadId); }
	# _____________________________________________________________________
	
	# _____________________________________________________________________
	# Get company name in the XML 
	$name_xml = stringGdsCompanyName($xmlDatas->getCompanyName()) ;
	if (!$name_xml) {
	notice('Problem detected during Profile update [COMPNAME].');
	return 0;
	} else { debug('name_xml = '.$name_xml); }
	# _____________________________________________________________________	
	
	# _____________________________________________________________________	
	# Get the name of the company in database
	#my $query = "SELECT AMADEUS_NAME FROM AMADEUS_SYNCHRO WHERE CODE = ? AND TYPE='COMPANY'";
	#$name_local = $dbh->saarBind($query, [$comCode])->[0][0];
		
		$GDS->_command('PM');
		$GDS->{ProfileMode} = 1;
		my    $profile = $GDS->command(Command => 'PDRC/'.$amadId, NoIG=> 1, NoMD => 0, PostIG => 0, ProfileMode => 1);
		
        foreach my $lines (@$profile)
        {
	            if($lines =~/\s*(\d+) PCN\/ (.*)/)
                {
					    $numero     = $1;
						$name_local = $2;
						$name_local =~s/\s+$//;
						notice("NOM LOCAL:".$name_local."|");
						notice("NOM XML  :".$name_xml."|");
				
					#Update the mid table and in Amadeus if the both are different 
					if ( $name_local ne $name_xml ) 
					{
						notice('RENAMING COMPANY : '.$comCode.' - '.$name_xml.' (OLD NAME:'.$name_local.')');
						my $req = "UPDATE AMADEUS_SYNCHRO SET AMADEUS_NAME='$name_xml', TIME=getdate() WHERE CODE=$comCode AND TYPE='COMPANY'";
						$dbh->do($req);
						
						$profile = $GDS->command(Command => $numero.'/'.$name_xml, NoIG=> 1, NoMD => 1, PostIG => 0, ProfileMode => 1);
						#Problème détecté lors de la création ?
						if (grep (/INVALID/, @$profile) || grep (/NON AUTORISE/, @$profile)) {
						  error("Cannot change company name for ".$name_xml.".\nLast screen : ".join("//",@$profile));
						}
					}
				last;
				}
        }
		
		my $lines = $GDS->command(Command => 'PE', NoIG=> 1, NoMD => 1, PostIG => 0, ProfileMode => 1);
		$lines = $GDS->command(Command => 'PME', NoIG=> 1, NoMD => 1, PostIG => 0, ProfileMode => 1);
		$GDS->{ProfileMode} = 0;		

  #RECUPERER LE NOM SOUS AMADEUS 
  #COMPARER AVEC CELUI DANS LA BASE AMADEUS_SYNCHRO
  #METTRE A JOUR DANS AMADEUS
  #METTRE A JOUR DANS AMADEUS_SYNCRHO
  return 1;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Suppression d'un profil société dans AMADEUS
sub _compDelete {
  my $params = shift;

  my $globalParams = $params->{GlobalParams};
  my $moduleParams = $params->{ModuleParams};
  my $item         = $params->{Item};
  my $GDS          = $params->{GDS};

  my $xmlDatas = Expedia::XML::CompanyProfile->new($item->{XML});

  # _____________________________________________________________________
  # Récupération du ComCode
  my $comCode  = $xmlDatas->getCompanyComCode();
  if (!$comCode) {
    notice('Problem detected during Profile deletion [COMCODE].');
  	return 0;
  } else { debug('comCode = '.$comCode); }
  # _____________________________________________________________________

  # _____________________________________________________________________
  # Récuperation de l'amadeusID
  my $amadId ='';
  if ( ( $params->{ISINHOUSE} == 1 || $params->{ISINHOUSE} == 0 ) && $params->{ISINHOUSE_RUN} == 0 ) {
      $amadId = isInAmadeusSynchro({CODE	=> $comCode, TYPE	=> 'COMPANY'})->[0][2];
  } elsif ( $params->{ISINHOUSE} == 1 && $params->{ISINHOUSE_RUN} == 1 ) {
      $amadId = isInAmadeusSynchro({CODE	=> $comCode, TYPE	=> 'COMPANY'})->[0][6];
  } 

  if (!$amadId) {
  	notice('Problem detected during Profile deletion [AMADEUSID].');
  	return 0;
  } else { debug('amadId = '.$amadId); }
  # _____________________________________________________________________

  # _____________________________________________________________________
  # Le profil est desactivé dans Amadeus
  my $res = $GDS->PXRC(PNR => $amadId);
  if (!$res) {
  	notice("Problem detected during Profile '$amadId' deletion [PXRC].");
  	return 0;
  }
  if ($params->{ISINHOUSE} && $res && $params->{ISINHOUSE_RUN} ){
     $params->{INHOUSE_DELETED}= "Y";
  }
  # _____________________________________________________________________

  # _____________________________________________________________________
  # Suppression de Amadeus_Synchro
  if ($params->{ISINHOUSE} == 1 && $params->{INHOUSE_DELETED} eq "Y" && $params->{ISINHOUSE_RUN} == 1) {
    $res = deleteFromAmadeusSynchro({AID  => $amadId, CODE => $comCode, TYPE => 'COMPANY'});
  } elsif ( $params->{ISINHOUSE} == 0 && $params->{ISINHOUSE_RUN} == 0 && $params->{INHOUSE_DELETED} eq "N" ) {
    $res = deleteFromAmadeusSynchro({AID  => $amadId, CODE => $comCode, TYPE => 'COMPANY'});
  }
  if (!$res) {
  	notice("Problem detected during Profile '$amadId' deletion [AMD_SYNCHRO].");
  	return 0;
  }
  # _____________________________________________________________________
  
  notice("Profile '$amadId' desactivated.") if ($res);

  return 1;   
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Reçoit en param une ref sur une chaine adresse et une ref sur un tableau
#   contenant l'adresse sous forme de chaines de moins de 85 caractères.
sub _testLengthAdd {
	my ($refAddr, $refAddLines) = @_;

	my @lettres = split('', ${$refAddr});
	my $chaine  = '';
	my $reste   = '';
	
	if (length(${$refAddr}) > 85) {
		
		for (my $i = 83; $i >= 0; $i--) {
			
			if ($lettres[$i] ne ' ') { 
			  next; 
			} else {
				$chaine = join('', @lettres[0..$i-1]);
				$reste  = join('', @lettres[$i+1..$#lettres]); 
				last;
			}
		}
		push (@{$refAddLines}, $chaine);
		${$refAddr} = $reste;
	}

}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

sub checkForInHouseOID { 
  my $params = shift;
  my $item   = $params->{Item};
  my $market = $item->{MARKET};
  my $type   = $item->{MSG_TYPE};
  my $inHouseOID= 0;
  if ( $type eq 'USER' ) {
    my $xmlDatas = Expedia::XML::UserProfile->new($item->{XML});
	$inHouseOID = $params->{INHOUSE_LST}{ $xmlDatas->getCompanyComCode() } {$market};
	#notice("InHouseOID : ".$inHouseOID );
  }
  elsif ( $type eq 'COMPANY' ) {
    my $xmlDatas = Expedia::XML::CompanyProfile->new($item->{XML});
    $inHouseOID = $params->{INHOUSE_LST}{ $xmlDatas->getCompanyComCode() } {$market};
	#notice("InHouseOID : ".$inHouseOID);								   
  }
  return $inHouseOID;
}

sub updateInHouseAmadeusSynchro {
	my $params = shift;
	
	my $code    = $params->{CODE};
	my $type    = $params->{TYPE};
	my $amadID  = $params->{AID};
	
	if ((!defined $code)   ||
      (!defined $type)   || ($type !~ /^(USER|COMPANY)$/) ||
      (!defined $amadID) || ($amadID !~ /^\w{6}$/)) {
       error('Missing or wrong parameter for this method.');
       return 0;
    }
	
	my $midDB = $cnxMgr->getConnectionByName('mid');

	my $query = "
	  UPDATE AMADEUS_SYNCHRO
	   SET AMADEUS_ID_INHOUSE = ?
	   WHERE CODE = ?
	     AND TYPE = ? ";

    return $midDB->doBind($query, [$amadID, $code, $type]);
}

1;


sub getConnection_amadeus_ihoid {
  my ($ih_oid) = @_;
  my $self;
  my $conns = $cnxMgr->connections;
  my $dbh = $cnxMgr->getConnectionByName('mid');

  my $request= qq^SELECT O.ID
                        ,O.OID
                        ,O.NAME
                        ,O.CORPOID
                        ,O.MODIFSIG
                        ,O.SIGNIN
                        ,O.TCP
                        ,O.PORT
                        ,O.LOGIN
                        ,O.PASSWORD
                        ,O.LANGUAGE
                        ,O.AUTOCONNECT 
                 FROM MO_CFG_OID O 
                 WHERE OID = ?
				 ^;
  notice("CONN inhouseID:".$ih_oid);
  my $connInfo = $dbh->saarBind($request,[$ih_oid]);
  my $officeid    = $connInfo->[0][1];
  my $name        = $connInfo->[0][2];
  my $corpoid     = $connInfo->[0][3];
  my $modifsig    = $connInfo->[0][4];
  my $signin      = $connInfo->[0][5];      
  my $tcp         = $connInfo->[0][6];
  my $port        = $connInfo->[0][7];
  my $login       = $connInfo->[0][8];
  my $password    = $connInfo->[0][9];
  my $language    = $connInfo->[0][10];
  my $autoconnect = $connInfo->[0][11];
  #notice("CONN:".$connInfo->[0][1]);
  #notice("CONN:".$connInfo->[0][2]);
  #notice("CONN:".$connInfo->[0][3]);
  #notice("CONN:".$connInfo->[0][4]);
  #notice("CONN:".$connInfo->[0][5]);
  #notice("CONN:".$connInfo->[0][6]);
  #notice("CONN:".$connInfo->[0][7]);
  #notice("CONN:".$connInfo->[0][8]);
  #notice("CONN:".$connInfo->[0][9]);
  #notice("CONN:".$connInfo->[0][10]);
  #notice("CONN:".$connInfo->[0][11]);
  
  my $connection;
  if (!$name    || !$signin || !$modifsig || !$tcp      || !$port ||
      !$corpoid || !$login  || !$password || !$officeid || !$language) {
      error("Missing parameter for Amadeus connection.");
  } else {
     $connection = Expedia::Databases::Amadeus->new();
     $connection->officeid    ( $officeid );
     $connection->name        ( $name );
     $connection->corpoid     ( $corpoid );
     $connection->modifsig    ( $modifsig );
     $connection->signin      ( $signin );
     $connection->tcp         ( $tcp );
     $connection->port        ( $port );
     $connection->login       ( $login );
     $connection->password    ( $password );
     $connection->language    ( $language );
     $connection->autoconnect ( $autoconnect );
     $connection->type        ('Amadeus');
     $connection->connect();
  }
  my $inH_cnx;
  
  if ((!$connection) || (ref($connection) ne 'Expedia::Databases::Amadeus')) {
     error('A valid AMADEUS connection must be provided to this constructor. Aborting.');
     return undef;
  } else {
	 $inH_cnx = $connection;
  }
    
  #notice("$inH_cnx".Dumper($inH_cnx));
  return $inH_cnx;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@