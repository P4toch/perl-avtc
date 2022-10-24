package Expedia::Modules::FLW::bookingWorkflow;
#-----------------------------------------------------------------
# Package Expedia::Modules::FLW::bookingWorkflow
#
# $Id: bookingWorkflow.pm 589 2010-07-21 08:53:20Z pbressan $
#
# (c) 2002-2010 Expedia.                   www.expediacorporate.fr
#-----------------------------------------------------------------

use strict;
use POSIX qw(strftime);
use DateTime;
use Data::Dumper;
use DateTime::Duration;

use HTTP::Request::Common;
use Expedia::XML::Booking;
use Expedia::Tools::Logger              qw(&debug &notice &warning &error);
use Expedia::Tools::GlobalVars          qw($cnxMgr $h_statusCodes $dummy $serverTest);
use Expedia::Tools::GlobalFuncs         qw(&dateTimeXML);
use Expedia::WS::Commun         		qw(&isAuthorize_LC);
use Expedia::Databases::MidSchemaFuncs  qw(&isInMsgKnowledge &insertIntoMsgKnowledge &updateMsgKnowledge 
                                           &isIntoWorkTable  &insertIntoWorkTable    &updateWorkTableItem
                                           &getAppId &getTravellerTrackingImplicatedComCodesForMarket &getQInfosForComCode);

sub run {
  my $self   = shift;
  my $params = shift;
  my $app  = undef;
  my $tracking= 0;
  my $manual = 0;
  my $x      = undef;
  my $globalParams = $params->{GlobalParams};
  my $moduleParams = $params->{ModuleParams};
  my $changes      = $params->{Changes};
  my $item         = $params->{Item};
  my $mkType  = undef;
  my $subType = undef;
  my $dossierTrainCancelled   = undef;
  my $dossierAirCancelled     = undef;  
  my $nbDossierTrainCancelled = 0;
  my $nbDossierAirCancelled = 0;
  my $market = undef;
  my $comCode = undef;
  
  # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
  # Cet item est de type Booking / Réservation Aérienne ou Ferrovière
  if ($item->{USED_FOR} eq 'BOOKING') {
    
    notice("# PROCESSING module FLW::bookingWorkflow against MSG_ID = '".$item->{MSG_ID}."'");

    # debug('ITEM = '.Dumper($item));
    
    # ----------------------------------------------------------
#    if ($item->{MSG_VERSION} =~ /^(5282)$/) {
#      use XML::LibXML;
#      use File::Slurp;
#      my $parser = XML::LibXML->new();
#      my $doc    = $parser->parse_string($item->{MESSAGE});
#         $doc->indexElements();
#         $doc    = $doc->toString(1);
#      write_file('/home/pbressan/booking'.$item->{MSG_VERSION}.'.xml', $doc);
#    }
    # ----------------------------------------------------------

    # -----------------------------------------------------------------
    # Pour chaque item nous vérifions ce qui doit être fait côté MID
    my $msgId      = $item->{MSG_ID};
    my $msgCode    = $item->{MSG_CODE};
    my $message    = $item->{MESSAGE};
    my $msgVersion = $item->{MSG_VERSION};
    my $evtName    = $item->{EVT_NAME};

    # debug('MSG_VERSION = '.$item->{MSG_VERSION});
    debug('TYPE = BOOKING - EVENT = '.$evtName);

    # -----------------------------------------------------------------
    # TODO Vérifier que le message peut être valider avec son XSL
    # -----------------------------------------------------------------
    
    # -----------------------------------------------------------------
    my $tmp  = ' xmlns="http://www.expediacorporate.fr/newsimages/xsds/v1"';
    #$message =~ s/UTF-8/ISO-8859-1/ig;
    $message =~ s/&euro;/&#8364;/ig;
    $message =~ s/$tmp//ig;
    # -----------------------------------------------------------------

    my $b = Expedia::XML::Booking->new($message);
    return 0 unless (defined $b);
    
    notice('  MdCode       = '.$b->getMdCode);
    notice('  Version      = '.$msgVersion);
    
    #CALCUL DU NOMBRE DE TRAVELDOSSIER
    my $nbDossier      = $b->getNbOfTravelDossiers;
    notice($nbDossier." TravelDossiers ");
    
    #RECUPERATION DE LA STRUCTURE DES DIFFERENTS TRAVELDDOSIERS
    my $Listdossier = $b->getTravelDossierStruct;
    debug(Dumper($Listdossier));

	
    $market      = $b->getCountryCode({trvPos => $b->getWhoIsMain});
    $comCode     = $b->getPerComCode ({trvPos => $b->getWhoIsMain});
    debug('market  = '.$market);
    debug('comCode = '.$comCode);
      
    # IGNORE THE BOOKING CHINA  
    if($market eq 'CN'){notice("Booking CN -- IGNORE"); return 0;}
      
	# ============================== LOWCOST ============================
	# ============================== LOWCOST ============================
	# ============================== LOWCOST ============================
		
	
	# RETRIEVE THE LIST OF LOWCOST AIRLINE  ----- EGE-166771 
	# ALL THE BOOKING WILL BE TRIGGERED EVEN IF THE BOOKING ARE NOT CREATED ON AMADEUS 
	notice("TRACKING LOWCOST LOOP");
	my $list_lc = &isAuthorize_LC("air.light_ticketing_enabled");
	my %h_lowcost={};
    my $x=0;
	my $lc_found=0;
	
	while(1)
	{
		if(!exists($h_lowcost{$list_lc->[$x]->{AIRLINE}}))
		{
				$h_lowcost{$list_lc->[$x]->{AIRLINE}}=1;
				$lc_found=1;
		}

		if(!$list_lc->[$x]->{AIRLINE} || $list_lc->[$x]->{AIRLINE} eq 'undef')
		{
			last;
		}
		
		#ADD a CONTROL TO NOT LOOP ON LC IF NOTHING IS SET 
		$x++;
	}

	if($lc_found == 1)
	{
		#CALCUL DU NOMBRE DE TRAVELDOSSIER LC
		my $nbDossier_LC      = $b->getNbOfTravelDossiers_LC;
		notice($nbDossier_LC." TravelDossiers LOWCOST");
		
		#RECUPERATION DE LA STRUCTURE DES DIFFERENTS TRAVELDDOSIERS
		my $Listdossier_LC = $b->getTravelDossierStruct_LC;
		debug(Dumper($Listdossier_LC));
		
		#ON BOUCLE SUR CHAQUE TRAVELDOSSIER
		for ($x=0; $x < $nbDossier_LC; $x++)
		{
		  my $PNR         =$Listdossier_LC->[$x]->{lwdPnr};

		  notice("PNR:".$PNR);
		  if(!defined($PNR) || $PNR eq ''){notice("ATTENTION PNR VIDE DANS LE XML"); next;}
		  my $mkType      =$Listdossier_LC->[$x]->{lwdType};
		   
		  notice("===========TravelDossier LOWCOST:".$x." -->".$PNR."==========");
		  
		  $subType = 'train' if (($mkType eq 'SNCF_TC'));
		  $subType = 'rail'  if (($mkType eq 'RG_TC'));     
		   
		  $mkType  = 'LOWCOST' if ($mkType =~ /^(SNCF_TC|RG_TC)$/ );
		  $mkType  = 'LOWCOST' if ($mkType =~ /^(GAP_TC|WAVE_TC)$/ );
		  $mkType  = 'LOWCOST' if ($mkType =~ /^(MASERATI_CAR_TC)$/ );
			   
		  #GESTION DU TRACKING POUR LES DOSSIER ANNULES
		  my $DossierStatus =  $Listdossier_LC->[$x]->{lwdStatus};
		  if ($DossierStatus eq 'C')
		  {
			$mkType  = 'TRAIN_CANCELLED' if ( $mkType eq 'TRAIN');
			$mkType  = 'LOWCOST_CANCELLED'   if ( $mkType eq 'AIR');
		  }

		  notice("MKTYPE:".$mkType);
				  
		  #TRACKING UNIQUEMENT POUR AIR POUR LE MOMENT
		  # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
		  # LE CAS PARTICULIER DU TRACKING EST MOINS COMPLEXE                       
		  $app  = 'tracking-'.$market;
			
		  my $h_ttComCodes = $params->{TTComCodes} ;
		  
		  $tracking=1 if (exists $h_ttComCodes->{$comCode});
		  #$tracking=1;
		  if($tracking == 1 && $mkType =~ /^LOWCOST/  )
		  {
				 my $appId  = getAppId($app);
				  my $row = &insertIntoWorkTable(
					{ MESSAGE_ID      => $msgId,
					  MESSAGE_CODE    => $msgCode,
					  MESSAGE_VERSION => $msgVersion,
					  MESSAGE_TYPE    => $mkType,
					  EVENT_VERSION   => '',
					  TEMPLATE_ID     => '',
					  MARKET          => $market,
					  APP_ID          => $appId,
					  ACTION          => 'CREATE',
					  STATUS          => 'NEW',
					  XML             => $message,
					  PNR             => $PNR,
					}
				  );
				  notice ('-----TRACKING LC-----');
		  }
						  
		}
		notice("END TRACKING LOWCOST LOOP");
	}
	# ============================== LOWCOST ============================
	# ============================== LOWCOST ============================
	# ============================== LOWCOST ============================
		
		
    #ON BOUCLE SUR CHAQUE TRAVELDOSSIER
    for ($x=0; $x < $nbDossier; $x++)
    {
      my $PNR         =$Listdossier->[$x]->{lwdPnr};
      notice("PNR:".$PNR);
      if(!defined($PNR) || $PNR eq ''){notice("ATTENTION PNR VIDE DANS LE XML"); next;}
      my $mkType      =$Listdossier->[$x]->{lwdType};
	  
      # --------------------------------------------------------------------------------
      # FICHE JIRA EGE-114873 : Add PNR queuing in Workflow Booking robot for SG and HK
      # FICHE JIRA EGE-120875 : Auto-queuing on NZ AKLEC3100
      # --------------------------------------------------------------------------------
      if($evtName eq 'BOOKING_NEW' && ($market eq 'SG' || $market eq 'HK' || $market eq 'NZ')){
        notice('NEW BOOKING, MARKET : '.$market);
        my $officeID = '';
        my $message  = '';

        if($market eq 'SG'){
            $officeID = 'SINEC3100';
        }elsif($market eq 'HK'){
            $officeID = 'HKGEC3100';
        }elsif($market eq 'NZ'){
            $officeID = 'AKLEC3100';
        }

        my $userAgent = LWP::UserAgent->new(agent => 'perl post');
        my $params_ws = $serverTest.'midnew.cgi?action=HTTPcommand&country='.$market.'&officeid='.$officeID.'&command=RT'.$PNR.'~QE/'.$officeID.'/30C0~RFWORKFLOW~ER';
        my $response  = $userAgent->request(GET $params_ws, Content_Type => 'text/xml', Content => $message);

        if($response->as_string =~/SUCCESS/){
             notice(" SUCCESS BOOKING, PNR : ".$PNR);
        }else{
             notice(" FAILURE BOOKING, PNR : ".$PNR);
             return 0;
        }
      }

      # ----------------------------------------------------------------------------------
      
      notice("===========TravelDossier:".$x." -->".$PNR."==========");
      
      $subType = 'train' if (($mkType eq 'SNCF_TC'));
      $subType = 'rail'  if (($mkType eq 'RG_TC'));     
       
      $mkType  = 'TRAIN' if ($mkType =~ /^(SNCF_TC|RG_TC)$/ );
      $mkType  = 'AIR'   if ($mkType =~ /^(GAP_TC|WAVE_TC)$/ );
      $mkType  = 'CAR'   if ($mkType =~ /^(MASERATI_CAR_TC)$/ );
           
      #GESTION DU TRACKING POUR LES DOSSIER ANNULES
      my $DossierStatus =  $Listdossier->[$x]->{lwdStatus};
      if ($DossierStatus eq 'C')
      {
        $mkType  = 'TRAIN_CANCELLED' if ( $mkType eq 'TRAIN');
        $mkType  = 'AIR_CANCELLED'   if ( $mkType eq 'AIR');
      }

      notice("MKTYPE:".$mkType);
              
      #TRACKING UNIQUEMENT POUR AIR POUR LE MOMENT
      # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
      # LE CAS PARTICULIER DU TRACKING EST MOINS COMPLEXE                       
      $app  = 'tracking-'.$market;
	  	
      my $h_ttComCodes = $params->{TTComCodes} ;
	  
      $tracking=1 if (exists $h_ttComCodes->{$comCode});
      #$tracking=1;
      if($tracking == 1 && $mkType =~ /^AIR/  )
      {
             my $appId  = getAppId($app);
              my $row = &insertIntoWorkTable(
                { MESSAGE_ID      => $msgId,
                  MESSAGE_CODE    => $msgCode,
                  MESSAGE_VERSION => $msgVersion,
                  MESSAGE_TYPE    => $mkType,
                  EVENT_VERSION   => '',
                  TEMPLATE_ID     => '',
                  MARKET          => $market,
                  APP_ID          => $appId,
                  ACTION          => 'CREATE',
                  STATUS          => 'NEW',
                  XML             => $message,
                  PNR             => $PNR,
                }
              );
              notice ('-----TRACKING AIR-----');
      }
	  
      if ($DossierStatus eq 'C')
      {
         #ON EST DANS LE CAS D'UN DOSSIER ANNULE, ON AJOUTE LE XML A LA TABLE WORK_TABLE POUR TRAITEMENT TRACKING ET ON PASSE AU SUIVANT
         notice("DOSSIER ANNULE -- NE RIEN FAIRE");
         next;
      }        
                 
      # On ne s'intéresse qu'aux Dossiers en Status = V ou Q [...]
      if ($DossierStatus !~ /^(V|Q)$/) {
      notice('DossierStatus = '.$DossierStatus);
      notice("Booking '$PNR' is in status '".$h_statusCodes->{$DossierStatus}."'.")
        if (defined $h_statusCodes->{$DossierStatus});
      next;
      }

  # ______________________________________________________________

  push (@{$changes->{add}}, { Data => 'RM @@ BTC-AIR PROCEED @@' });
      
      
      # GESTION DES DOSSIERS CAR
      if($mkType =~ /^CAR/ )
      {
      	      $app  = 'btc-car-'.$market;
              my $appId  = getAppId($app);
              my $row = &insertIntoWorkTable(
                { MESSAGE_ID      => $msgId,
                  MESSAGE_CODE    => $msgCode,
                  MESSAGE_VERSION => $msgVersion,
                  MESSAGE_TYPE    => $mkType,
                  EVENT_VERSION   => '',
                  TEMPLATE_ID     => '',
                  MARKET          => $market,
                  APP_ID          => $appId,
                  ACTION          => 'CREATE',
                  STATUS          => 'NEW',
                  XML             => $message,
                  PNR             => $PNR,
                }
              );
              notice ('-----CAR-----');
              next; #ON SORT IMMEDIATEMENT, le booking 
      }

      #A REVOIR
      #ON GERE LE CAS RAIL OU TRAIN
      debug('evtName = '.$evtName);;
      if (!defined $mkType) {
        notice('<mkType> does not match something known !');
        #return 0;
        next;
      }
      
    # -----------------------------------------------------------------
    # On ne traite que certains dossiers insérés manuellement.
    my $mdCode   = $b->getMdCode;
    my $events   = $b->getMdEvents;
    my $trvCst   = '';
    EVENT: foreach my $event (@$events) {
      if ((exists $event->{EventAction}) &&
          ($event->{EventAction} =~ /^(AIRINSERTION|TRAININSERTION)$/)) {
        $trvCst = $event->{EventAgentLogin};
        notice("Dossier MdCode='$mdCode' manually inserted. Skipped [...]");
        notice(" ~ TravelConsultant Login = '$trvCst'") if ($trvCst !~ /^\s+$/);
        $manual = 1;
        last EVENT;
      }
    }
    
    #SI LE DOSSIER A ETE TRAITE MANUELLEMENT ALORS ON SORT (PAS BESOIN DE FAIRE BTC) 
    if($manual == 1)
    {
       #return 0;
       next;
    }
    # -----------------------------------------------------------------
    
    # -----------------------------------------------------------------
    # On ne traite pas le Low-Cost Aérien
    #if ($nbDossierAir == 1 ) {
    if ($mkType eq 'AIR' ) {
      #my $atds = $b->getAirTravelDossierStruct();
      #my $PNR  = $atds->[0]->{lwdPnr};
      if (length($PNR) != 6) {
        notice("Cannot process AirTravelDossier with PNR's length != 6. Skipped [...]");
        #return 0;
        next;
      }
    }
    # -----------------------------------------------------------------
    
    # -----------------------------------------------------------------
    # On ne traite pas les dossier Trains si la BookDate est > 4H00
    #if ($nbDossierTrain == 1 ) {
     if ($mkType eq 'TRAIN' ) { 
      
      my $bookDate = &dateTimeXML($b->getMdRealBookDate);
      my $currDate = strftime("%Y/%m/%d %H:%M:%S",localtime());
      debug('bookDate = '.$bookDate);
      debug('currDate = '.$currDate);
      
      if ($bookDate ne '') { # Bizarrement, il peut ne pas y avoir de BookDate
      
        my $dtBookDate = DateTime->new(
          year   => substr($bookDate, 0,  4), 
          month  => substr($bookDate, 5,  2), 
          day    => substr($bookDate, 8,  2), 
          hour   => substr($bookDate, 11, 2), 
          minute => substr($bookDate, 14, 2), 
        );
        
        my $dtCurrDate = DateTime->new(
          year   => substr($currDate, 0,  4), 
          month  => substr($currDate, 5,  2), 
          day    => substr($currDate, 8,  2), 
          hour   => substr($currDate, 11, 2), 
          minute => substr($currDate, 14, 2), 
        );
        
        my $DURATION = $dtCurrDate - $dtBookDate;
        debug('DURATION = '.Dumper($DURATION));
        
        if ((abs($DURATION->{minutes}) <= 240) && (abs($DURATION->{days})) == 0) {
          # Le booking a été fait récemment ! C'est bon ...
        } else {
          notice('Cannot process TrainTravelDossier with BookDate > 4H00');
          #return 0;
          next;
        }
      
      } # Fin if ($bookDate ne '')

    } # Fin if ($nbDossierTrain == 1)
    # -----------------------------------------------------------------
    
    
    # _________________________________________________________________
    # On ne traite pas le TRAIN autre que FR
    #if (($nbDossierTrain == 1) && ($market ne 'FR')) {
    if (($mkType eq 'TRAIN') && ($market ne 'FR')) {
      notice('Can process only FR Train bookings. Skipped [...]');
      #return 0;
      next;
    }
    # _________________________________________________________________
        
    # _________________________________________________________________
    my $isMeeting = $b->isMeetingCompany;
    debug('isMeeting = '.$isMeeting);
    # _________________________________________________________________

    # -----------------------------------------------------------------
    # A partir d'ici nous savons que le dossier est valide et peut être traité !
       $app  = 'btc-';            
       $app  = 'meetings-'         if ($isMeeting == 1);

      my $isDummy = $b->isDummyCompany({trvPos => $b->getWhoIsMain});
      my @dummy   = split(',', $dummy);
      foreach (@dummy) { $isDummy = 1 if ($_ eq $comCode); }
       $app .= $subType       if ($mkType eq 'TRAIN');
       $app .= 'air-'.$market if ($mkType eq 'AIR');
       $app .= '-dev'         if ($isDummy);

    my $appId  = getAppId($app);
    debug('app   = '.$app);
    debug('appId = '.$appId);
    # -----------------------------------------------------------------
    
    # -----------------------------------------------------------------
    # Je ne traite que le TRAIN "Français"
    if (($mkType eq 'TRAIN') && ($market ne 'FR')) {
      notice("Type = '$mkType' but Market = '$market'. Skipped [...]");
      return 0;
    }
    # -----------------------------------------------------------------
    
    # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
    # Est-ce que nous connaissons cet objet message dans MSG_KNOWLEDGE ?
    my $mkItem = &isInMsgKnowledge({ PNR => $PNR });

    # $$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$
    # CAS 1 = Ce message est inconnu de la base de connaissance des messages
    # $$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$
    if ((!defined $mkItem) || (scalar(@$mkItem) == 0)) {
      debug('CASE 1');

      # ------------------------------------------------------------------
      # Insertion du message dans la base de connaissance
      my $row = &insertIntoMsgKnowledge({ CODE => $msgCode, TYPE => $mkType, VERSION => $msgVersion, PNR => $PNR, MARKET => $market });
      # return 0 unless $row; Quest-ce qu'on fait si $rows == 0 ?

      # L'action à faire est un CREATE 
      $row = &insertIntoWorkTable(
        { MESSAGE_ID      => $msgId,
          MESSAGE_CODE    => $msgCode,
          MESSAGE_VERSION => $msgVersion,
          MESSAGE_TYPE    => $mkType,
          EVENT_VERSION   => '',
          TEMPLATE_ID     => '',
          MARKET          => $market,
          APP_ID          => $appId,
          ACTION          => 'CREATE',
          STATUS          => 'NEW',
          XML             => $message,
          PNR             => $PNR,
        }
      );
      #return $row; # Quest-ce qu'on fait si $rows == 0 ?
      next;
    }

    # $$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$
    # CAS 2 = Ce message est connu de la base de connaissance des messages
    # $$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$
    elsif (scalar(@$mkItem) == 1) {
      debug('CASE 2');

      # ------------------------------------------------------------------
      # Mise à jour du message dans la base de connaissance
      my $row = &updateMsgKnowledge({ CODE => $msgCode, TYPE => $mkType, VERSION => $msgVersion, PNR => $PNR, MARKET => $market });
      # return 0 unless $row; Quest-ce qu'on fait si $rows == 0 ?

      # ------------------------------------------------------------------
      # Est ce que ce message figure déja dans la table WORK_TABLE ?
      my $wtItem = &isIntoWorkTable({MESSAGE_CODE => $msgCode, MESSAGE_TYPE => $mkType, PNR => $PNR, APP_ID => $appId});

      # ££££££££££££££££££££££££££££££££££££££££££££££££££££££££££££££££££
      # CAS 2.1 = Aucune information dans la table WORK_TABLE
      # ££££££££££££££££££££££££££££££££££££££££££££££££££££££££££££££££££      
      if ((!defined $wtItem) || (scalar @$wtItem == 0)) {
        debug('CASE 2.1');

        # ------------------------------------------------------------------
        # Est ce que ce dossier a déjà été PROCEED ?
        my $isAirProceed   = $mkItem->[0][3];
        my $isTrainProceed = $mkItem->[0][4];
        
        # µµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµ
        # CAS 2.1.1 = Le dossier n'a pas déjà été moulinetté !
        # µµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµ        
        if (($mkType eq 'AIR')   && ($isAirProceed   == 0) ||
            ($mkType eq 'TRAIN') && ($isTrainProceed == 0)) {
          debug('CASE 2.1.1');          
        
          # L'action à faire est bien un CREATE 
          $row = &insertIntoWorkTable(
            { MESSAGE_ID      => $msgId,
              MESSAGE_CODE    => $msgCode,
              MESSAGE_VERSION => $msgVersion,
              MESSAGE_TYPE    => $mkType,
              EVENT_VERSION   => '',
              TEMPLATE_ID     => '',
              MARKET          => $market,
              APP_ID          => $appId,
              ACTION          => 'CREATE',
              STATUS          => 'NEW',
              XML             => $message,
              PNR             => $PNR,
            }
          ); 
          #return $row; # Quest-ce qu'on fait si $rows == 0 ?
          next;
        }
        # µµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµ
        # CAS 2.1.2 = Le dossier a déjà été moulinetté !
        # µµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµ
        elsif (($mkType eq 'AIR')   && ($isAirProceed   == 1) ||
               ($mkType eq 'TRAIN') && ($isTrainProceed == 1)) {
          debug('CASE 2.1.2');
          notice("This '$mkType' booking has already been BTC-PROCEED.");
          #return 0;
          next;
        }
      }
      # ££££££££££££££££££££££££££££££££££££££££££££££££££££££££££££££££££      
      # CAS 2.2 = Une ou plusieurs informations sont associées dans la table WORK_TABLE
      # ££££££££££££££££££££££££££££££££££££££££££££££££££££££££££££££££££      
      elsif (scalar @$wtItem >= 1) {
        debug('CASE 2.2');
        $row = &updateWorkTableItem(
            { ID              => $wtItem->[0]->{ID},
              MESSAGE_ID      => $wtItem->[0]->{MESSAGE_ID},
              MESSAGE_CODE    => $wtItem->[0]->{MESSAGE_CODE},
              MESSAGE_VERSION => $wtItem->[0]->{MESSAGE_VERSION},
              MESSAGE_TYPE    => $wtItem->[0]->{MESSAGE_TYPE},
              STATUS          => $wtItem->[0]->{STATUS},
              TIME            => $wtItem->[0]->{TIME},
              VERSION         => $msgVersion,
              XML             => $message,
              PNR             => $PNR,
            }
        ); 
        #return $row; # Quest-ce qu'on fait si $rows == 0 ?
        next;
      }
    }

    # $$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$
    # CAS 3 = Ce message est connu de la base de connaissance des messages
    # $$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$
    # La requète de récupération a fourni plusieurs résultats alors
    #  que un seul est attendu !    
    else { # Cas normalement impossible car contrainte unique sur la table.
      debug('CASE 3 - mkItem = '.Dumper($mkItem));
      notice('Multiple results returned but only one is expected.');
      #return 0;
      next;
    }
    # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

  } # Fin : if ($item->{USED_FOR} eq 'BOOKING')
  # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@  
  
    }
     


      #my $dossierTrain   = $b->getTrainTravelDossierStruct;
      #my $dossierAir     = $b->getAirTravelDossierStruct;
      #my $nbDossierTrain = scalar(@$dossierTrain);
      #my $nbDossierAir   = scalar(@$dossierAir);
      
      #my $nbTravellers   = $b->getNbOfTravellers;
      #my $nbDossierAirTrainCancelled   = $b->getNbOfAirTrainCancelledTravelDossiers;
      #if($nbDossierAirTrainCancelled == 1) {
      #  $dossierTrainCancelled   = $b->getTrainCancelledTravelDossierStruct;
      #  $dossierAirCancelled     = $b->getAirCancelledTravelDossierStruct;
      #  $nbDossierTrainCancelled = scalar(@$dossierTrainCancelled);
      #  $nbDossierAirCancelled   = scalar(@$dossierAirCancelled);
      #}
  

  
      #notice('nbDossierAirTrainCancelled = '.$nbDossierAirTrainCancelled);
      #if( $nbDossierAirTrainCancelled == 1)
      #{
      #notice('nbDossierTrainCancelled = '.$nbDossierTrainCancelled);
      #notice('nbDossierAirCancelled   = '.$nbDossierAirCancelled);
      #}
      #notice('nbDossierTrain = '.$nbDossierTrain);
      #notice('nbDossierAir   = '.$nbDossierAir);
      #notice('nbTravellers   = '.$nbTravellers);

   

      

    #}
    

         

     
    # -----------------------------------------------------------------
    # On vérifie quels sont les TravelDossier contenus dans ce booking :
    #  - Il peut y avoir une réservation aérienne ou ferrovière.
    #  - Mais pas les 2 à la fois.
    #if ((($nbDossierTrain  > 0) && ($nbDossierAir  > 0)) ||
    #    (($nbDossierTrain == 0) && ($nbDossierAir == 0)) ||
    #     ($nbDossierTrain  > 1)                          ||
    #     ($nbDossierAir    > 1)                          ||
    #     ($nbTravellers    == 0)  ) {
    #  notice('Cannot proceed XML booking containing "1+ Train" and "1+ Air" travel dossiers.') if (($nbDossierTrain  > 0) && ($nbDossierAir  > 0));
    #  notice('Cannot proceed XML booking containing "0" travel dossiers.')                     if (($nbDossierTrain == 0) && ($nbDossierAir == 0));
    #  notice('Cannot proceed XML booking containing "1+ Train" travel dossiers.')              if ($nbDossierTrain   > 1);
    #  notice('Cannot proceed XML booking containing "1+ Air" travel dossiers.')                if ($nbDossierAir     > 1);
    #  notice('Cannot proceed XML booking containing "0" traveller.')                           if ($nbTravellers    == 0);          
    #  return 0;
    #}
    #else {          
    #  debug('evtName = '.$evtName);;
    #  $subType = 'train' if (($mkType eq 'TRAIN') && ($dossierTrain->[0]->{lwdType} eq 'SNCF_TC'));
    #  $subType = 'rail'  if (($mkType eq 'TRAIN') && ($dossierTrain->[0]->{lwdType} eq 'RG_TC'));
    #  debug('mkType = '.$mkType) if defined $mkType;
    #  if (!defined $mkType) {
    #    notice('<mkType> does not match something known !');
    #    return 0;
    #  }
    #}
    # -----------------------------------------------------------------
    


  return 1;
}


1;
