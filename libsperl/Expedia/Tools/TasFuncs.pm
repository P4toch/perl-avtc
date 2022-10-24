package Expedia::Tools::TasFuncs;
#-----------------------------------------------------------------
# Package Expedia::Tools::TasFuncs
#
# $Id: TasFuncs.pm 713 2011-07-04 15:45:26Z pbressan $
#
# (c) 2002-2009 Expedia.                   www.expediacorporate.fr
#-----------------------------------------------------------------

use DateTime;
use DateTime::Duration;
use File::Slurp;
use Data::Dumper;
use Clone qw(clone);
use Exporter 'import';
use POSIX qw(strftime);

use Expedia::WS::Front                 qw(&changeDeliveryState &addBookingComment);
use Expedia::Tools::Logger             qw(&debug &notice &warning &error &monitore);
use Expedia::Tools::SendMail           qw(&tasSendReport &tasSendSoapPb);
use Expedia::Tools::GlobalVars         qw($cnxMgr $soapRetry $soapProblems $reportPath $h_tasMessages $toTcatId $hMarket);
use Expedia::Databases::Calendar       qw(&getCalId &getMonthCalId &getCalIdwithtz);
use Expedia::Databases::ItemsManager   qw(&tasUnlockItem &tasLockItem);
use Expedia::Databases::MidSchemaFuncs qw(&getAppId &getTZbycountry &getNavCountrybycountry);
use Expedia::GDS::PNR;

@EXPORT_OK = qw(&getTasMessage
                &logTasError &logTasFinishError
                &tasReport &tasDailyStats &tasConsoStats &compileDailyStats
                &soapRetry &soapProblems
                &isTcChecked
                &_getTicketsTotal
                &_getTicketedByTas
                &_getTicketedNotByTas
                &_getOthersTicketsInfos
                &setTimeZone
                &getDeliveryForTas
                &getCurrencyForTas
               );

use strict;

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Récupération d'un TAS_MESSAGE depuis la base DELIVERY à partir
#   d'un "TAS_ERROR Code".
sub getTasMessage {
  my $errorCode = shift;

	if (defined $h_tasMessages->{4}) {
		return $h_tasMessages->{$errorCode};
	}
	else {
		my $dbh   = $cnxMgr->getConnectionByName('mid');
  
	  my $query = 'SELECT ERR_CODE, MESSAGE FROM TAS_MESSAGES';
    my $res   = $dbh->saarBind($query, []);

		foreach (@$res) {
			$h_tasMessages->{$_->[0]} = $_->[1];
		}
	}
  
  return $h_tasMessages->{$errorCode};
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# This function manages ticketing errors [ TAS PROCESS ]
sub logTasError {
  my $params = shift;
  
  my $errorCode        = $params->{errorCode};
	my $errorMesg      = $params->{errorMesg};
	my $pnrId          = $params->{PNRId};
	my $mdCode         = $params->{mdCode};
	my $deliveryId     = $params->{deliveryId};
	my $market         = $params->{market};
	my $productCode    = $params->{PRDCT_TP_ID} || undef;
	my $multi_pnr      = $params->{MULTI_PNR}   || undef;
	my $product		   = $params->{product}   || undef;
	
	# Récupération du TAS_MESSAGE correspondant à la TAS_ERROR
	my $tasMessage = '';
	   $tasMessage = getTasMessage($errorCode) unless ($errorCode == 12);
	   $tasMessage = $errorMesg                    if ($errorCode == 12);
		 
	debug('tasMessage = '.Dumper($tasMessage));
	
	my $soapOut = undef;
	   $soapOut = changeDeliveryState('DeliveryWS', {deliveryId => $deliveryId, deliveryStatus => 9});
	  if (!defined($soapOut)){
	  
		push (@$soapRetry, {deliveryId     => $deliveryId,
                      deliveryStatus => 9,
                      pnrId          => $pnrId,
                      tasCode        => $errorCode,
                      tryNo          => 0});
					  
		&monitore("TAS_TICKETING", "DELIVERY_STATUS_CHANGE","ERROR",$market,$product,$pnrId,'',"WEBSERVICE CALL");

	 }else{
	 
		&monitore("TAS_TICKETING", "DELIVERY_STATUS_CHANGE","INFO",$market,$product,$pnrId,'',"WEBSERVICE CALL");
	 
	 }
    #PLUS DE MISE A JOUR DU DISPATCH POUR LES PNR MULTIPLE 
    #SI LE PNR EST STRICTEMENT PLUS GRAND QUE 6 (PNR AMADEUS = 6), ALORS ON NE METS PAS A JOUR LE DISPATCH
    my $query = undef;
	my $dbh    = $cnxMgr->getConnectionByName('mid'); 
    my $mypnr="'%".$pnrId."%'";   
    $query = "SELECT LEN(PNR)
              FROM DELIVERY_FOR_DISPATCH
              WHERE DELIVERY_ID = $deliveryId 
              AND   PNR    like   $mypnr  "; 
     
    my $rows   = $dbh->saar($query);
    if( ($rows->[0][0] <= 6) || ( defined($productCode) && $productCode == 2 && $rows->[0][0] > 6) ) {    
            # Mise à jour directement dans l'interface DISPATCH\
        my $dpnr = "%".$pnrId."%";
        $query  = "
            UPDATE DELIVERY_FOR_DISPATCH
             SET DELIVERY_STATUS_ID   = 9,
                 DELIVERY_STATUS_TEXT = 'Not issued - TAS rejected'
            WHERE DELIVERY_ID          = ?
            AND MARKET               = ? 
			AND PNR LIKE ?
        ";
        my $rows = $dbh->doBind($query, [$deliveryId, $market, $dpnr]);
    }

	#EGE-90353
	if (defined($multi_pnr)){
		#For multiple PNR : replacing the pnr in error by its error_code and the other pnr by 0, 
		# for example "PNR111, PNR222, PNR333" ---> "0,33,0" means PNR222 is on error 33
		my $multi_error= $multi_pnr;
		$multi_error =~ s/$pnrId/$errorCode/;
		$multi_error =~ s/\w{6}/0/g;
		_setTasError($mdCode, $multi_error, $multi_pnr);
	}
	else 
	{
		_setTasError($mdCode, $errorCode, $pnrId);
    }
  
  # Mise à jour de l'annotation
  $soapOut = undef;
  $soapOut = &addBookingComment('DeliveryWS', {
               language     => 'FR',
               mdCode       => $mdCode,
               eventType    => 9,
               eventDesc    => "PNR $pnrId TAS message : $tasMessage" });
  # Mise à jour de l'annotation
  # &ECTEAddBookingAnnotationRQ('DeliveryWS', 'TAS_REJECT|'.$errorCode.'|'.$tasMessage.'|'.$pnrId);

  return 1;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# This function manages ticketing errors [ TAS FINISH PROCESS ]
#   sensiblement similaire à la précédente mais effectue
#     un contrôle supplémentaire.
sub logTasFinishError {
  my $params = shift;
  
  my $errorCode        = $params->{errorCode};
	my $pnrId          = $params->{PNRId};
	my $mdCode         = $params->{mdCode};
	my $deliveryId     = $params->{deliveryId};
	my $market         = $params->{market};
	my $productCode    = $params->{PRDCT_TP_ID} || undef; 
	my $multi_pnr 	   = undef;
	
	# Récupération du TAS_MESSAGE correspondant à la TAS_ERROR
	my $tasMessage = getTasMessage($errorCode);
	debug('tasMessage = '.$tasMessage);
		
	my $query = undef;
	my $dbres = undef;
	
	my $dbh = $cnxMgr->getConnectionByName('mid');
		
  # ---------------------------------------------------------------------
  # Ajout PBRESSAN Gestion Spec TAS Ticketing Check §4.3
  #TODO SYSDATE -> pas d'interaction avec la timezone.. heure technique 
  if ((defined $errorCode) && ($errorCode == 13)) {
    $query = '
      SELECT REF, PNR, TIME
        FROM IN_PROGRESS 
       WHERE DELIVERY_ID = ?
         AND REF         = ?
         AND PNR         = ? 
         AND TIME       >= DATEADD(minute,-30,GETDATE()) ';
    $dbres = $dbh->saarBind($query, [$deliveryId, $mdCode,$pnrId]);
  }
  # Si on a un résultat, on ne fait pas la suite car les 30 minutes ne sont pas écoulées
  if ((defined $dbres) && (scalar(@$dbres) == 1)) {
    
    notice('logTasFinishError: TAS_ERROR 13 - FA Lines still not here...');
    
    &tasLockItem({ REF => $mdCode, PNR => $pnrId });

  } else {
	
  	my $soapOut = undef;
  	   $soapOut = changeDeliveryState('DeliveryWS', {deliveryId => $deliveryId, deliveryStatus => 9});
  	   
    push (@$soapRetry, {deliveryId     => $deliveryId,
                        deliveryStatus => 9,
                        pnrId          => $pnrId,
                        tasCode        => $errorCode,
                        tryNo          => 0})
      if (!defined($soapOut));
	 
    my $mypnr="'%".$pnrId."%'";   
    my $query = "SELECT LEN(PNR),PNR
              FROM DELIVERY_FOR_DISPATCH
              WHERE DELIVERY_ID = $deliveryId 
              AND   PNR    like   $mypnr  "; 
     
    my $rows   = $dbh->saar($query);
	$multi_pnr  =$rows->[0][1] if ($rows->[0][1]=~ m/,/);
    if( ($rows->[0][0] <= 6) || ( defined($productCode) && $productCode == 2 && $rows->[0][0] > 6 ) ) {    
            # Mise à jour directement dans l'interface DISPATCH\
        my $dpnr = "%".$pnrId."%";
        $query  = "
            UPDATE DELIVERY_FOR_DISPATCH
             SET DELIVERY_STATUS_ID   = 9,
                 DELIVERY_STATUS_TEXT = 'Not issued - TAS rejected'
            WHERE DELIVERY_ID          = ?
            AND MARKET               = ? 
			AND PNR LIKE ?
        ";
        my $rows = $dbh->doBind($query, [$deliveryId, $market, $dpnr]);
    }
	
    #EGE-90353
	if (defined($multi_pnr)){
		#For multiple PNR : replacing the pnr in error by its error_code and the other pnr by 0, 
		# for example "PNR111, PNR222, PNR333" ---> "0,33,0" means PNR222 is on error 33
		my $multi_error= $multi_pnr;
		$multi_error =~ s/$pnrId/$errorCode/;
		$multi_error =~ s/\w{6}/0/g;
		_setTasError($mdCode, $multi_error, $multi_pnr);
	}
	else 
	{
		_setTasError($mdCode, $errorCode, $pnrId);
    }
	
    # Mise à jour de l'annotation
    $soapOut = undef;
    $soapOut = &addBookingComment('DeliveryWS', {
                 language     => 'FR',
                 mdCode       => $mdCode,
                 eventType    => 9,
                 eventDesc    => "PNR $pnrId TAS message : $tasMessage" });
    
    # Mise à jour de l'annotation
    # &ECTEAddBookingAnnotationRQ('DeliveryWS', 'TAS_REJECT|'.$errorCode.'|'.$tasMessage.'|'.$pnrId);
  
  }
  # ---------------------------------------------------------------------

  return 1;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# If we got problems to update status with SOAP,
#   we will try again (5 tries) [changeDeliverState]
sub soapRetry {
  my $soapRetry = shift;
  
  my $newSoapRetry     = [];
  my $soapRetryClone   = clone($soapRetry);
  
  foreach (@$soapRetryClone) {
    # On dépile le tableau @$soapRetry
    my $hash           = shift @$soapRetry;   
    my $deliveryId     = $hash->{deliveryId};
    my $deliveryStatus = $hash->{deliveryStatus};
    my $pnrId          = $hash->{pnrId};
    my $tasCode        = $hash->{tasCode};
    my $try            = $hash->{tryNo};

    # Là on va devoir envoyer un mail :)
    if ($try == 5) {
      push(@{$soapProblems->{$tasCode}}, $pnrId);
      next;
    }
    
    $try += 1;
    
    my $soapOut = undef;
       $soapOut = changeDeliveryState('DeliveryWS', {deliveryId => $deliveryId, deliveryStatus => $deliveryStatus});

    if (!defined($soapOut)) {
      notice("soapRetry: PNR = $pnrId / TRY = $try / UPDATE = ERROR");
	    push (@$newSoapRetry, {deliveryId     => $deliveryId,
	                           deliveryStatus => $deliveryStatus,
                             pnrId          => $pnrId,
                             tasCode        => $tasCode,
                             tryNo          => $try});
      sleep 5; # Dormir 5 secondes
    } else {
      notice("soapRetry: PNR = $pnrId / TRY = $try / UPDATE = OK");
    }
  }

  # Terminal récursif tant que le tableau n'est pas vide ;-)
  soapRetry($newSoapRetry) if (scalar(@$newSoapRetry) > 0);

  return 1;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# This function send an email if I got problems with SOAP...
sub soapProblems {
  my $sTask   = shift; # tas ou tasmeetings
  my $agency  = shift;
  my $product = shift;

  my $tasMsg  = '';

  # Génération du MAIL
  my $mail    = "Hello,\n\n";
     $mail   .= "TAS has not been able to change the status of the folowing bookings :\n\n";
     
  foreach (sort triCroissant (keys %$soapProblems)) {
    $tasMsg   = getTasMessage($_); debug('tasMessage = '.Dumper($tasMsg));
    $mail    .= "---------------------------------------------------------------\n";
    $mail    .= "TAS ERROR $_ ($tasMsg)\n";
    $mail    .= "---------------------------------------------------------------\n";
    foreach my $PNR (@{$soapProblems->{$_}}) {
      $mail  .= '* PNR = '.$PNR."\n";
    }
    $mail    .= "\n";
  }
  $mail      .= "Sherlock & Colombo\n";
  
  &tasSendSoapPb($mail, $sTask, $agency, $product);
  
  return 1;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Fonction de création du mail de statistiques des traitements TAS
sub tasReport {
  my $sTask   = shift; # tas ou tasmeetings
  my $agency  = shift;
  my $product = shift;
  my $items   = shift;
  my $GDS     = shift;
  
  #----------------------------------------------------------------
  # Create an archive if it's needed
  my $day_now     = strftime("%Y%m%d",localtime());
  my $tmp_agency   = $agency;
     $tmp_agency   = 'Meetings_'.$agency if ($sTask =~ /meetings/);
  my $new_archive = $reportPath.$day_now.'_'.$tmp_agency.':'.$product.'.txt';
  my $new_archive_cons = $reportPath.'Consolidated_'.$day_now.'_'.$tmp_agency.':'.$product.'.txt';
  my $newArchive  = 0;
  my $newArchiveCons = 0;
  my $xls_archiveifilename = $day_now.'_'.$tmp_agency.':'.$product.'.xls';
  my $xls_archive = $reportPath.$xls_archiveifilename;
  
  unless (stat($new_archive_cons)) {
    $newArchiveCons = 1;
    `touch $new_archive_cons`;
  }  

  unless (stat($new_archive)) {
    $newArchive = 1;
    `touch $new_archive`;
  }
  #----------------------------------------------------------------
  
  if ($newArchive) {
    debug("Creation of one new REPORT file $new_archive");
    open(ERROR, ">>", $new_archive); # Ouverture en Ecriture
    print ERROR "+-------------------------------------------------------------+\n";
    print ERROR "|                      TAS     STATISTICS                     |\n";
    print ERROR "+-------------------------------------------------------------+\n";
    print ERROR "| Number of PNRs Treated  = 0                                 |\n";
    print ERROR "| Number of TAS OK        = 0                                 |\n";
    print ERROR "| Number of TAS ERROR     = 0                                 |\n";
    print ERROR "+-------------------------------------------------------------+\n";
    close(ERROR);
  }
  
  return 1 if (scalar(@$items) == 0);

  my $globalStats = {};

  open(ERROR, "<", $new_archive); # Ouverture en Lecture
  while (<ERROR>) {
    # debug($_);
    if ($_ =~ /Number\s+of\s+PNRs\s+Treated\s+=\s+(\d+)(\s+)/) {
      $globalStats->{nbOfPNR}->{value} = $1;
      $globalStats->{nbOfPNR}->{lengt} = length($1);
      $globalStats->{nbOfPNR}->{space} = length($2);
    }
    if ($_ =~ /Number\s+of\s+TAS\s+OK\s+=\s+(\d+)(\s+)/) {
      $globalStats->{nbOfTasOk}->{value} = $1;
      $globalStats->{nbOfTasOk}->{lengt} = length($1);
      $globalStats->{nbOfTasOk}->{space} = length($2);
    }
    if ($_ =~ /Number\s+of\s+TAS\s+ERROR\s+=\s+(\d+)(\s+)/) {
      $globalStats->{nbOfTasError}->{value} = $1;
      $globalStats->{nbOfTasError}->{lengt} = length($1);
      $globalStats->{nbOfTasError}->{space} = length($2);
    }
    if ($_ =~ /TAS\s+ERROR\s+(\d+)\s+=\s+(\d+)(\s+)/) {
      $globalStats->{TasErrors}->{$1}->{value} = $2;
      $globalStats->{TasErrors}->{$1}->{lengt} = length($2);
      $globalStats->{TasErrors}->{$1}->{space} = length($3);
      
    }
  }
  close(ERROR);

  # debug('globalStats = '.Dumper($globalStats));
  
  open(ERROR, ">>", $new_archive); # Ouverture en Ecriture
  print ERROR "\n";
  print ERROR "\n";
  print ERROR "+-------------------------------------------------------------+\n";
  print ERROR "|                    ".strftime("%D %T", localtime())."                        |\n";
  print ERROR "+-------------------------------------------------------------+\n";
  print ERROR "\n";
=cut
  print ERROR "\n";
  print ERROR "*"x17;
  print ERROR "\n";
  print ERROR strftime("%D %T", localtime());
  print ERROR "\n";
  print ERROR "*"x17;
  print ERROR "\n";
=cut

  my $no_more     = 0;
  my $tas_error   = 0;
  my $tas_changed = 0;
  my $tas_message = '';

  my $localStats = {nbOfPNR      => {value => 0},
                    nbOfTasOk    => {value => 0},
                    nbOfTasError => {value => 0}};

  my $line = '';

  foreach my $row (@$items) {

    #---------------------------------------------------------------
    # Calcul de Statistiques Locales à ce Traitement
    $localStats->{nbOfPNR}->{value}++;
    if ($row->{TAS_ERROR} == 0) { $localStats->{nbOfTasOk}->{value}++; }
    else                        { $localStats->{nbOfTasError}->{value}++;
                                  $localStats->{TasErrors}->{$row->{TAS_ERROR}}->{value}++;
                                }
    #---------------------------------------------------------------
    
    my $dbh = $cnxMgr->getConnectionByName('mid');

    # Si un Nouveau Message TAS est Détecté.
    # On va chercher le message correspondant dans la table TAS_MESSAGES
    if ($tas_error != $row->{TAS_ERROR}) {
      $tas_error   = $row->{TAS_ERROR};
      $tas_message = getTasMessage($tas_error);
      $tas_changed = 1;
    } else { $tas_changed = 0; }

    if (($tas_error == 0) && ($no_more == 0)) {
      $line .= "\n---------------------------------------------------------------";
      $line .= "\nPNR TREATED WITHOUT ERRORS";
      $line .= "\n---------------------------------------------------------------\n";
      $no_more = 1;
    }

    # Effort de Présentation
    if ($tas_changed) {
      $line .= "\n---------------------------------------------------------------";
      $line .= "\nTAS ERROR ".$tas_error." (".$tas_message.")";
      $line .= "\n---------------------------------------------------------------\n";
    }
    
    # Type de Billet
    my $h_ticketType = {
      'ELECTRONIC_BILLET'    => 'E-BILLET',
      'ELECTRONIC_TICKET'    => 'E-TICKET',
      'PREPAID_TICKET'       => 'PREPAID',
      'THALYS_TICKETLESS'    => 'TICKETLESS',
      'PAPER_TICKET'         => 'PAPER',
    };
    my $ticketType = 'UNKNOWN';
       $ticketType = $h_ticketType->{$row->{TICKET_TYPE}} if (exists $h_ticketType->{$row->{TICKET_TYPE}}); 
    
    $line .= '   '.$row->{PNR}.'   -   '.$row->{COMNAME}.'   -   '.$ticketType."\n";
  }

  print ERROR $line."\n";

  close(ERROR);

  # Ajout des localStats aux globalStats
  $globalStats->{nbOfPNR}->{value}      += $localStats->{nbOfPNR}->{value};
  $globalStats->{nbOfTasOk}->{value}    += $localStats->{nbOfTasOk}->{value};
  $globalStats->{nbOfTasError}->{value} += $localStats->{nbOfTasError}->{value};
  my $key;
  foreach (keys %{$localStats->{TasErrors}}) {
    if (length($_) == 1) { $key = '0'.$_; } else { $key = $_ }
    if (!exists($globalStats->{TasErrors}->{$key})) {
      $globalStats->{TasErrors}->{$key}->{value} = 0;
      $globalStats->{TasErrors}->{$key}->{lengt} = 1;
      $globalStats->{TasErrors}->{$key}->{space} = 33;
    }
    $globalStats->{TasErrors}->{$key}->{value} += $localStats->{TasErrors}->{$_}->{value};
  }

  # debug("Number of TAS OK    : ".$localStats->{nbOfTasOk});
  # debug("Number of TAS ERROR : ".$localStats->{nbOfTasError});
  # debug("localStats = ".Dumper($localStats));
  # debug("globalStats = ".Dumper($globalStats));

  # Ecriture des Stats dans le Fichier
  $line = '';
  my $nbSpaces = 0;

  open(ERROR, "<", $new_archive); # Ouverture en Lecture
  while (<ERROR>) {
    # debug($_);
    if ($_ =~ /Number\s+of\s+PNRs\s+Treated\s+=\s+(\d+)(\s+)/) {
      if (length($globalStats->{nbOfPNR}->{value}) != $globalStats->{nbOfPNR}->{space}) {
        $nbSpaces = $globalStats->{nbOfPNR}->{space} - length($globalStats->{nbOfPNR}->{value}) + $globalStats->{nbOfPNR}->{lengt};
      } else {
        $nbSpaces = $globalStats->{nbOfPNR}->{space};
      }
      $line .= "| Number of PNRs Treated  = ".$globalStats->{nbOfPNR}->{value}.(' 'x$nbSpaces)."|\n";
    }
    elsif ($_ =~ /Number\s+of\s+TAS\s+OK\s+=\s+(\d+)/) {
      if (length($globalStats->{nbOfTasOk}->{value}) != $globalStats->{nbOfTasOk}->{space}) {
        $nbSpaces = $globalStats->{nbOfTasOk}->{space} - length($globalStats->{nbOfTasOk}->{value}) + $globalStats->{nbOfTasOk}->{lengt};
      } else {
        $nbSpaces = $globalStats->{nbOfTasOk}->{space};
      }
      $line .= "| Number of TAS OK        = ".$globalStats->{nbOfTasOk}->{value}.(' 'x$nbSpaces)."|\n";
    }
    elsif ($_ =~ /Number\s+of\s+TAS\s+ERROR\s+=\s+(\d+)/) {
      if (length($globalStats->{nbOfTasError}->{value}) != $globalStats->{nbOfTasError}->{space}) {
        $nbSpaces = $globalStats->{nbOfTasError}->{space} - length($globalStats->{nbOfTasError}->{value}) + $globalStats->{nbOfTasError}->{lengt};
      } else {
        $nbSpaces = $globalStats->{nbOfTasError}->{space};
      }
      $line .= "| Number of TAS ERROR     = ".$globalStats->{nbOfTasError}->{value}.(' 'x$nbSpaces)."|\n";
      
      foreach my $tmpKey (sort triCroissant (keys (%{$globalStats->{TasErrors}}))) {
        if (length($globalStats->{TasErrors}->{$tmpKey}->{value}) != $globalStats->{TasErrors}->{$tmpKey}->{space}) {
          $nbSpaces = $globalStats->{TasErrors}->{$tmpKey}->{space} - length($globalStats->{TasErrors}->{$tmpKey}->{value}) + $globalStats->{TasErrors}->{$tmpKey}->{lengt};
        } else {
          $nbSpaces = $globalStats->{TasErrors}->{$tmpKey}->{space};
        }
        $line .= "|         * TAS ERROR $tmpKey  = ".$globalStats->{TasErrors}->{$tmpKey}->{value}.(' 'x$nbSpaces)."|\n";
      }
    }
    elsif ($_ =~ /TAS\s+ERROR\s+(\d+)\s+=\s+(\d+)/) { next; }
    else { $line .= $_; }
  }
  close(ERROR);

  unlink($new_archive);
  write_file($new_archive, $line);

  my $colsep = ";;;";
  my @columns = ( 'Country'
                  ,'Date'
                  ,'Time'
                  ,'PNR'
                  ,'Client'
                  ,'Module'
                  ,'Reject Code'
                  ,'Reject'
				  ,'Traveler Name'
                  ,'Airline Company'

                );


   open(CONS, ">>", $new_archive_cons);
   my $lastColumn = $columns[$#columns];
  if ($newArchiveCons) {
     foreach my $col(@columns) {
           if ($col eq $lastColumn) {
               print CONS "$col\n";
           } else {
	       print CONS $col.$colsep;
           }
     }
  }
  my $task = $sTask.'-'.$agency;
  my @data = getAddDataForTasReport($task,$GDS);

  foreach my $d(@data) {
         foreach my $col(@columns) {
             if ($col eq 'Date') {
                 if ($d->{Reject}) {
                   print CONS $d->{'Modification Date'}.$colsep;
                   
                 } else {
                   print CONS $d->{'Ticketed Date'}.$colsep;
                   
                 }
             } elsif ($col eq 'Time') {
                 if ($d->{Reject}) {
                    print CONS $d->{'Modification Time'}.$colsep;
                   
                 } else {
                    print CONS $d->{'Ticketed Time'}.$colsep;
                  
                 }

             } elsif ($col eq $lastColumn) {
                print CONS "$d->{$col}\n";
             } else {
                print CONS $d->{$col}.$colsep;
             }
     }
  }  
  createTasExcelReport($sTask.'-'.$agency,$xls_archive,$line,$new_archive_cons,$colsep);

  my $err_status=&tasSendReport($new_archive, $sTask, $agency, $product, $xls_archive, $xls_archiveifilename);
  
  # [EGE-122778] : set single LOG with @message set to “MAILING” in the end of treatment
  if ($err_status == 1) {
	&monitore("TAS_REPORT","SENDING_MAIL","INFO",$hMarket->{$agency},$product,"",'',"MAILING");
    }
  else{
    &monitore("TAS_REPORT","SENDING_MAIL","ERROR",$hMarket->{$agency},$product,"",'',"MAILING");
  }
  
  
  return 1;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Fonction de sauvegarde des résultats TAS // Daily
sub tasDailyStats {
  my $params = shift;
  
  foreach (qw/CAL_ID TASK SUBTASK MARKET ITEMS/) {
    if ((!exists $params->{$_}) || (!defined $params->{$_})) {
      if ($_ =~ /^TASK|SUBTASK|MARKET|ITEMS$/) {
        notice('tasDailyStats: $params->{'.$_.'} is not defined.');
        return 0;
      }
    }
  }
  
  my $appId    = getAppId($params->{TASK});
  my $subappId = getAppId($params->{SUBTASK});
  my $market   = $params->{MARKET};
  my $items    = $params->{ITEMS};
  my $h_Stats  = {};
  my $tasStats = '';
  my $dt_tas   = '';
      
    my $tz = &getTZbycountry($market);
    notice("MARKET:".$market);
    notice("TZ:".$tz);
    if (! $tz) {
    error("No timezone is defined for market '$market'. Aborting.");
    return 0;
   }
   else
   {
     $params->{CAL_ID} = getCalIdwithtz($tz);
     if  (!exists $params->{CAL_ID}){
        notice('tasDailyStats: $params->{CAL_ID} is not defined.');
        return 0;
      };
   }
   
   my $calId    = $params->{CAL_ID};
   debug('calId = '.$calId);
  # _____________________________________________________________________
  # Lecture du résultat des différents dossiers traités par la moulinette 
  foreach my $item (@$items) {
    $h_Stats->{$item->{TAS_ERROR}} += 1; 
	if($item->{TAS_ERROR} eq ''){ notice("PROBLEMSTAT:".Dumper($item));}
  }
  # _____________________________________________________________________
  
  # _____________________________________________________________________
  # Construction de la donnée à stocker en base
  foreach (sort triCroissant (keys %$h_Stats)) {
    $tasStats .= 'TE:'.$_.'='.$h_Stats->{$_}.';';
  }
  chop($tasStats);
  debug('tasStats = '.$tasStats);
  # _____________________________________________________________________

chomp($tasStats);
#my $stats=substr($tasStats,0,80);
#my $stats2=  length $tasStats > 80 ? substr($tasStats,80,80) : " ";
#my $stats3=  length $tasStats > 160 ? substr($tasStats,160,80) : " ";
#my $stats4=  length $tasStats > 240 ? substr($tasStats,240,80) : " ";
#my $stats5=  length $tasStats > 320 ? substr($tasStats,320,80) : " ";

  

  my $res = _insertIntoTasDaily({
    CAL_ID    => $calId,
    APP_ID    => $appId,
    SUBAPP_ID => $subappId,
    MARKET    => $market,
    TAS_STATS => $tasStats,
#    TAS_STATS2 => $stats2,
#    TAS_STATS3 => $stats3,
#    TAS_STATS4 => $stats4,
#    TAS_STATS5 => $stats5,
  });


  return $res;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Fonction de sauvegarde des résultats TAS // Consolidated
sub tasConsoStats {
  my $params = shift;
  
  foreach (qw/CAL_ID TASK SUBTASK MARKET DATE PRODUCT/) {
    if ((!exists $params->{$_}) || (!defined $params->{$_})) {
      if ($_ =~ /^TASK|SUBTASK|MARKET/) {
        notice('tasConsoStats: $params->{'.$_.'} is not defined.');
        return 0;
      }
    }
  }
    
  my $date     = $params->{DATE};
  my $calId    = $params->{CAL_ID};
  my $market   = $params->{MARKET};
  my $tcatId   = &getDeliveryForTas($market,$params->{PRODUCT}); #$toTcatId->{$params->{SUBTASK}.':'.$params->{PRODUCT}};
  my $appId    = getAppId($params->{TASK});
  my $subappId = getAppId($params->{SUBTASK});
  my $tz = '';

   # Calcul de la date avec la timezone du market
   if (!exists $params->{DATE})
   {
     $tz = &getTZbycountry($market);
     if (! $tz) {
     error("No timezone is defined for market '$market'. Aborting.");
     return 0;
     }
     else
     {
       $date = setTimeZone($tz);
       notice("DATE TZ:".$date);
     }
  }
   
  # Calcul de l'id de la date avec la timezone du market 
  if (!exists $params->{CAL_ID})
  {
    $params->{CAL_ID} = getCalIdwithtz($tz);
    $calId    = $params->{CAL_ID};
  }

  my $tt   = &_getTicketsTotal       ({ MARKET => $market, TCAT_ID => $tcatId, DATE => $date });
  my $tbt  = &_getTicketedByTas      ({ MARKET => $market, TCAT_ID => $tcatId, DATE => $date });
  my $ntbt = &_getTicketedNotByTas   ({ MARKET => $market, TCAT_ID => $tcatId, DATE => $date });
  my $oti  = &_getOthersTicketsInfos ({ MARKET    => $market,
                                        TCAT_ID   => $tcatId,
                                        DATE      => $date,
                                        CAL_ID    => $calId,
                                        APP_ID    => $appId,
                                        SUBAPP_ID => $subappId });
  my $rbt  = &_getRejectedByTas      ({ MARKET    => $market,
                                        CAL_ID    => $calId,
                                        APP_ID    => $appId,
                                        SUBAPP_ID => $subappId });
    
  my $res  = _insertIntoTasConso({
    CAL_ID               => $calId,
    APP_ID               => $appId,
    SUBAPP_ID            => $subappId,
    MARKET               => $market,
    TICKETS_TOTAL        => $tt,
    TICKETED_BY_TAS      => $tbt,
    TICKETED_NOT_BY_TAS  => $ntbt,
    REJECTED_BY_TAS      => $rbt,
    OTHERS_TICKETS_INFOS => $oti,
  });

  return $res;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Insertion dans la table TAS_STATS_DAILY.
sub _insertIntoTasDaily {
  my $params = shift;
  
  foreach (qw/CAL_ID APP_ID SUBAPP_ID MARKET TAS_STATS/) {
    if ((!exists $params->{$_}) || (!defined $params->{$_})) {
      if ($_ =~ /^CAL_ID|APP_ID|SUBAPP_ID|MARKET$/) {
        notice('$params->{'.$_.'} is not defined.');
        return 0;
      }
    }
  }
  
    my $dbh    = $cnxMgr->getConnectionByName('mid');
    my $query = "EXEC MIDADMIN.tas_stats_daily_add $params->{CAL_ID}, $params->{APP_ID}, $params->{SUBAPP_ID}, '$params->{MARKET}', '$params->{TAS_STATS}'";
    my $rows = $dbh->sproc($query, []);
    notice("RES:".$rows);


  #my $query  = 'INSERT INTO TAS_STATS_DAILY VALUES (?, ?, ?, ?, ?, GETDATE(), ?, ?, ?, ?)';
  
  #TODO SYSDATE -> pas d'interaction avec la timezone.. heure technique 
  #PAR CONTRE LE CHAMP CAL_ID DOIT CONTENIR LA BONNE DATE AVEC TIMEZONE
  #my $rows   = $dbh->doBind($query, [ $params->{CAL_ID},
  #                                    $params->{APP_ID},
  #                                    $params->{SUBAPP_ID},
  #                                    $params->{MARKET},
  #                                    $params->{TAS_STATS},
  #                                    $params->{TAS_STATS2},
  #                                    $params->{TAS_STATS3},
  #                                    $params->{TAS_STATS4},
  #                                    $params->{TAS_STATS5} ]);


  return $rows;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Insertion dans la table TAS_STATS_CONSO.
sub _insertIntoTasConso {
  my $params = shift;
  
  foreach (qw/CAL_ID APP_ID SUBAPP_ID MARKET TICKETS_TOTAL TICKETED_BY_TAS
              TICKETED_NOT_BY_TAS REJECTED_BY_TAS OTHERS_TICKETS_INFOS/) {
    if ((!exists $params->{$_}) || (!defined $params->{$_})) {
      $params->{CAL_ID} = getCalId() if (($_ eq 'CAL_ID') && (!exists $params->{$_}));
      if ($_ =~ /^APP_ID|SUBAPP_ID|MARKET$/) {
        notice('$params->{'.$_.'} is not defined.');
        return 0;
      }
    }
  }
  
    my $dbh   = $cnxMgr->getConnectionByName('mid');  
    my $query = "EXEC MIDADMIN.TAS_STATS_CONSO_ADD $params->{CAL_ID}, $params->{APP_ID}, $params->{SUBAPP_ID}, '$params->{MARKET}', $params->{TICKETS_TOTAL}, $params->{TICKETED_BY_TAS}, '$params->{TICKETED_NOT_BY_TAS}', '$params->{REJECTED_BY_TAS}', '$params->{OTHERS_TICKETS_INFOS}'";
    my $rows = $dbh->sproc($query, []);
    notice("RES:".$rows);
   

  #my $query = 'INSERT INTO TAS_STATS_CONSO VALUES ( ?, ?, ?, ?, ?, ?, ?, ?, ?, GETDATE())';
  
  #my $rows  = $dbh->doBind($query, [ $params->{CAL_ID},
  #                                   $params->{APP_ID},
  #                                   $params->{SUBAPP_ID},
  #                                   $params->{MARKET},
  #                                   $params->{TICKETS_TOTAL},
  #                                   $params->{TICKETED_BY_TAS},
  #                                   $params->{TICKETED_NOT_BY_TAS},
  #                                   $params->{REJECTED_BY_TAS},
  #                                   $params->{OTHERS_TICKETS_INFOS} ]);
                                     
  return $rows;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Récupération du nombre de billet total présents dans l'interface
#   pour un jour donné.
sub _getTicketsTotal {
  my $params = shift;
  
  my $market = $params->{MARKET};
  my $tcatId = $params->{TCAT_ID};
  my $date   = $params->{DATE};
  
  my $dbh    = $cnxMgr->getConnectionByName('mid');
    
  my $query  = "
    SELECT COUNT(*)
      FROM DELIVERY_FOR_DISPATCH DFD, METADOSSIERS MD
     WHERE DFD.MARKET              = '$market'
       AND DFD.TCAT_ID             in ( $tcatId )
       AND CONVERT(DATETIME,DFD.EMISSION_DATE,103)  = CONVERT(DATETIME,'$date',103)
       AND DFD.BLOCKED_BY_APPROVAL = 0
       AND DFD.ON_HOLD             = 0
       AND LEN(DFD.PNR)         > 0
       AND DFD.META_DOSSIER_ID     = MD.MD_CODE
       AND MD.STATE           NOT IN ('C', 'H') ";
  
  return $dbh->saar($query)->[0][0];
  #return $dbh->saarBind($query, [$market, $tcatId, $date])->[0][0];
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Récupération du nombre de billet total émis par TAS.
#  (+) 2 = Emis // 3 = Dispatché // 4 = Enlevé
sub _getTicketedByTas {
  my $params = shift;
  
  my $market = $params->{MARKET};
  my $tcatId = $params->{TCAT_ID};
  my $date   = $params->{DATE};
  
  my $dbh    = $cnxMgr->getConnectionByName('mid');
  
  my $query  = "
    SELECT COUNT(*)
      FROM DELIVERY_FOR_DISPATCH DFD, METADOSSIERS MD
     WHERE DFD.MARKET              = '$market'
       AND DFD.TCAT_ID             in ( $tcatId )
       AND CONVERT(DATETIME,DFD.EMISSION_DATE,103)  = CONVERT(DATETIME,'$date',103)
       AND DFD.DELIVERY_STATUS_ID IN (2, 3, 4)
       AND DFD.EMITTED_BY          = 'BTC_TAS'
       AND DFD.BLOCKED_BY_APPROVAL = 0
       AND DFD.ON_HOLD             = 0 
       AND LEN(DFD.PNR)         > 0
       AND DFD.META_DOSSIER_ID     = MD.MD_CODE
       AND MD.STATE           NOT IN ('C', 'H') ";
  
  return $dbh->saar($query)->[0][0];
  #return $dbh->saarBind($query, [$market, $tcatId, $date])->[0][0];
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Récupération du détail des billets [ NON ] émis par TAS.
#  Création de la chaîne pour insertion en BDD.
#  (+) 2 = Emis // 3 = Dispatché // 4 = Enlevé
sub _getTicketedNotByTas {
  my $params = shift;
  
  my $market = $params->{MARKET};
  my $tcatId = $params->{TCAT_ID};
  my $date   = $params->{DATE};
  
  my $dbh    = $cnxMgr->getConnectionByName('mid');
   
  my $query  = "
    SELECT DFD.META_DOSSIER_ID, DFD.EMITTED_BY
      FROM DELIVERY_FOR_DISPATCH DFD, METADOSSIERS MD
     WHERE DFD.MARKET              = '$market'
       AND DFD.TCAT_ID             in ( $tcatId )
       AND CONVERT(DATETIME,DFD.EMISSION_DATE,103)  = CONVERT(DATETIME,'$date',103)
       AND DFD.DELIVERY_STATUS_ID IN (2, 3, 4)
       AND DFD.EMITTED_BY         <> 'BTC_TAS'
       AND DFD.BLOCKED_BY_APPROVAL = 0
       AND DFD.ON_HOLD             = 0
       AND LEN(DFD.PNR)         > 0
       AND DFD.META_DOSSIER_ID     = MD.MD_CODE
       AND MD.STATE           NOT IN ('C', 'H') ";

  my $res   = $dbh->saar($query);
  my $total = scalar(@$res);
  my $h_Det = {};
  
  foreach (@$res) { $h_Det->{$_->[1]} += 1; }
  
  my $tasStats = 'TOTAL='.$total.';';  
  # _____________________________________________________________________
  # Construction de la donnée à stocker en base TAS_STATS_CONSO
  foreach (keys %$h_Det) {
    $tasStats .= $_.'='.$h_Det->{$_}.';';
  }
  chop($tasStats);
  debug('tasStats = '.$tasStats);
  # _____________________________________________________________________
  
  return $tasStats;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Récupération du nombre de billet total émis par TAS.
sub _getRejectedByTas {
  my $params = shift;
  
  foreach (qw/CAL_ID APP_ID SUBAPP_ID MARKET/) {
    if ((!exists $params->{$_}) || (!defined $params->{$_})) {
      notice('_getRejectedByTas: $params->{'.$_.'} is not defined.');
      return 0;
    }
  }
  
  my $calId    = $params->{CAL_ID};
  my $appId    = $params->{APP_ID};
  my $subappId = $params->{SUBAPP_ID};
  my $market   = $params->{MARKET};
  
  my $dbh      = $cnxMgr->getConnectionByName('mid');
  my $query    = "
    SELECT ID, ISNULL(TAS_STATS,'') + ISNULL(TAS_STATS2,'') + ISNULL(TAS_STATS3,'') + ISNULL(TAS_STATS4,'') + ISNULL(TAS_STATS5,'')
      FROM TAS_STATS_DAILY
     WHERE CAL_ID    = ?
       AND APP_ID    = ?
       AND SUBAPP_ID = ?
       AND MARKET    = ? ";
  
  my $res      = $dbh->saarBind($query, [$calId, $appId, $subappId, $market]);
  my $total    = 0;
  my $h_Det    = {};
  
  foreach (@$res) {
    my $tasStats = $_->[1];
    my @details   = split /;/, $tasStats;
    foreach my $detail (@details) {
      if ($detail =~ /TE:(\d+)=(\d+)/) {
        my $tasError = $1;
        my $tasNums  = $2;
        $total      += $tasNums unless ($tasError == 0);
        $h_Det->{$tasError} += $tasNums;
      } else {
        notice('_getRejectedByTas: Erreur de formalisme dans le stockage des données.');
        notice(' ID = '.$tasStats->[0].' - TAS_STATS = '.$tasStats);
      }
    }
  }
  
  my $tasStats = 'TOTAL='.$total.';';
  # _____________________________________________________________________
  # Construction de la donnée à stocker en base TAS_STATS_CONSO
  foreach (sort triCroissant (keys %$h_Det)) {
    $tasStats .= 'TE:'.$_.'='.$h_Det->{$_}.';';
  }
  chop($tasStats);
  debug('tasStats = '.$tasStats);
  # _____________________________________________________________________
  
  return $tasStats;
  
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Récupération des autres infos TAS.
#  = Combien sont en ?
#    - TO_ISSUE
#    - ISSUED
#    - REJECTED
#    - TREATED_BY_TAS
sub _getOthersTicketsInfos {
  my $params = shift;
  
  my $market   = $params->{MARKET};
  my $tcatId   = $params->{TCAT_ID};
  my $date     = $params->{DATE};
  my $calId    = $params->{CAL_ID};
  my $appId    = $params->{APP_ID};
  my $subappId = $params->{SUBAPP_ID};
  
  my $dbh      = $cnxMgr->getConnectionByName('mid');
   
  # _____________________________________________________________
  # TO_ISSUE
  my $query  = "
    SELECT COUNT(*)
      FROM DELIVERY_FOR_DISPATCH DFD, METADOSSIERS MD
     WHERE DFD.MARKET              = '$market'
       AND DFD.TCAT_ID             in ( $tcatId )
       AND CONVERT(DATETIME,DFD.EMISSION_DATE,103)  = CONVERT(DATETIME,'$date',103)
       AND DFD.BLOCKED_BY_APPROVAL = 0
       AND DFD.ON_HOLD             = 0
       AND DFD.DELIVERY_STATUS_ID  = 1
       AND LEN(DFD.PNR)         > 0
       AND DFD.META_DOSSIER_ID     = MD.MD_CODE
       AND MD.STATE           NOT IN ('C', 'H') ";
  my $toIssue = $dbh->saar($query)->[0][0];
  debug('toIssue    = '.$toIssue);
  # _____________________________________________________________

  # _____________________________________________________________
  # ISSUED
  $query  = "
    SELECT COUNT(*)
      FROM DELIVERY_FOR_DISPATCH DFD, METADOSSIERS MD
     WHERE DFD.MARKET              = '$market'
       AND DFD.TCAT_ID             in ( $tcatId )
       AND CONVERT(DATETIME,DFD.EMISSION_DATE,103)  = CONVERT(DATETIME,'$date',103)
       AND DFD.BLOCKED_BY_APPROVAL = 0
       AND DFD.ON_HOLD             = 0
       AND DFD.DELIVERY_STATUS_ID IN (2, 3, 4)
       AND LEN(DFD.PNR)         > 0
       AND DFD.META_DOSSIER_ID     = MD.MD_CODE
       AND MD.STATE           NOT IN ('C', 'H') "; #  (+) 2 = Emis // 3 = Dispatché // 4 = Enlevé
  my $issued = $dbh->saar($query)->[0][0];
  debug('Issued     = '.$issued);
  # _____________________________________________________________

  # _____________________________________________________________
  # REJECTED
  $query  = "
    SELECT COUNT(*)
      FROM DELIVERY_FOR_DISPATCH DFD, METADOSSIERS MD
     WHERE DFD.MARKET              = '$market'
       AND DFD.TCAT_ID             in ( $tcatId )
       AND CONVERT(DATETIME,DFD.EMISSION_DATE,103)  = CONVERT(DATETIME,'$date',103)
       AND DFD.DELIVERY_STATUS_ID  = 9
       AND DFD.BLOCKED_BY_APPROVAL = 0
       AND DFD.ON_HOLD             = 0 
       AND LEN(DFD.PNR)         > 0
       AND DFD.META_DOSSIER_ID     = MD.MD_CODE
       AND MD.STATE           NOT IN ('C', 'H') ";
  my $rejected = $dbh->saar($query)->[0][0];
  debug('Rejected   = '.$rejected);
  # _____________________________________________________________

  # _____________________________________________________________
  # DUPLICATES
  # $query  = "
  #   SELECT COUNT(DFD1.PNR)
  #     FROM DELIVERY_FOR_DISPATCH DFD1, DELIVERY_FOR_DISPATCH DFD2
  #    WHERE DFD1.MARKET        = ?
  #      AND DFD1.TCAT_ID       = ? 
  #      AND DFD1.EMISSION_DATE = TO_DATE(?, 'DDMMYYYY')
  #      AND DFD2.MARKET        = ?
  #      AND DFD2.TCAT_ID       = ? 
  #      AND DFD2.EMISSION_DATE = TO_DATE(?, 'DDMMYYYY')
  #      AND UPPER(DFD1.PNR)    = UPPER(DFD2.PNR)
  #      AND DFD1.DELIVERY_ID  <> DFD2.DELIVERY_ID ";
  #   TASK : ON_HOLD & BLOCKED_BY_APPROVAL
  # my $duplicates = $dbh->saarBind($query, [$market, $tcatId, $date, $market, $tcatId, $date])->[0][0];
  #    $duplicates = $duplicates / 2;
  # debug('Duplicates = '.$duplicates);
  # _____________________________________________________________
  
  # _____________________________________________________________
  # TREATED_BY_TAS
  $dbh         = $cnxMgr->getConnectionByName('mid');
  $query       = "
    SELECT ID, ISNULL(TAS_STATS,'') + ISNULL(TAS_STATS2,'') + ISNULL(TAS_STATS3,'') + ISNULL(TAS_STATS4,'') + ISNULL(TAS_STATS5,'')
      FROM TAS_STATS_DAILY
     WHERE CAL_ID    = ?
       AND APP_ID    = ?
       AND SUBAPP_ID = ?
       AND MARKET    = ? ";
  
  my $res      = $dbh->saarBind($query, [$calId, $appId, $subappId, $market]);
  my $total    = 0;
  
  foreach (@$res) {
    my $tasStats = $_->[1];
    my @details   = split /;/, $tasStats;
    foreach my $detail (@details) {
      if ($detail =~ /TE:(\d+)=(\d+)/) {
        my $tasError = $1;
        my $tasNums  = $2;
        $total      += $tasNums;
      } else {
        notice('_getRejectedByTas: Erreur de formalisme dans le stockage des données.');
        notice(' ID = '.$tasStats->[0].' - TAS_STATS = '.$tasStats);
      }
    }
  }
  
  my $treatedByTas = $total;
  # _____________________________________________________________

  my $tasStats = 'TO_ISSUE='       . $toIssue      .';'
                .'ISSUED='         . $issued       .';'
                .'REJECTED='       . $rejected     .';'
                .'TREATED_BY_TAS=' . $treatedByTas   ;

  return $tasStats;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Récupération des infos TAS CONSO // Calendrier Id.
sub _getTasConso {
  my $params = shift;
  
  foreach (qw/CAL_ID TASK SUBTASK/) {
    if ((!exists $params->{$_}) || (!defined $params->{$_})) {
      $params->{CAL_ID} = getCalId() if (($_ eq 'CAL_ID') && (!exists $params->{$_}));
#      if ($_ =~ /^TASK|SUBTASK/) {
#        notice('getTasDaily: $params->{'.$_."} is not defined");
#        return undef;
#      }
    }
  }
  
  my $calId    = $params->{CAL_ID};
  my $appId    = getAppId($params->{TASK});
  my $subappId = getAppId($params->{SUBTASK});
  
  my $dbh      = $cnxMgr->getConnectionByName('mid');
  my $query    = '
    SELECT TICKETS_TOTAL, TICKETED_BY_TAS, TICKETED_NOT_BY_TAS,
           REJECTED_BY_TAS, OTHERS_TICKETS_INFOS
      FROM TAS_STATS_CONSO
     WHERE CAL_ID    = ?
       AND APP_ID    = ?
       AND SUBAPP_ID = ? ';
  my $results  = $dbh->saarBind($query, [$calId, $appId, $subappId]);
  
  return undef if ((!defined $results) || (scalar @$results == 0));
  
  my $h_conso = {};
  
  $h_conso->{TICKETS_TOTAL}    = $results->[0][0];
  $h_conso->{TICKETED_BY_TAS}  = $results->[0][1];
  
  my $totalOk = 0;
  my $totalEr = 0;
  
  # ______________________________________________________________
  # Rejets TAS
  foreach my $res (@$results) {
    my @TE = split /;/, $res->[3];
    foreach my $te (@TE) {
      # debug('TE = '.$te);
      if ($te =~ /^TE:(\d+)=(\d+)$/) {
        my $TAS_ERROR = $1;
        my $TAS_NUMS  = $2;
        $totalOk     += $TAS_NUMS if ($TAS_ERROR == 0);
        $totalEr     += $TAS_NUMS if ($TAS_ERROR != 0);
        $h_conso->{TAS_ERROR}->{$TAS_ERROR}->{VALUE} += $TAS_NUMS
          unless ($TAS_ERROR == 0);
      }
    }
  }
  foreach (keys %{$h_conso->{TAS_ERROR}}) {
    my $mesg = getTasMessage($_);
    $h_conso->{TAS_ERROR}->{$_}->{MESSAGE} = $mesg;
  }
  $h_conso->{TAS_OK}         = $totalOk;
  $h_conso->{TAS_REJECTED}   = $totalEr;
  $h_conso->{TAS_TOTAL}      = $totalEr + $totalOk;
  # ______________________________________________________________
  
  # ______________________________________________________________
  # TICKETED_NOT_BY_TAS && OTHERS_TICKETS_INFOS
  foreach my $res (@$results) {
    my @TC = split /;/, $res->[2];
    my @OT = split /;/, $res->[4];
    foreach my $tc (@TC) {
      if ($tc =~ /^(\w+)=(\d+)$/) {
        $h_conso->{TICKETED_NOT_BY_TAS}->{$1}  = $2;
      }
    }
    foreach my $ot (@OT) {
      if ($ot =~ /^(\w+)=(\d+)$/) {
        $h_conso->{OTHERS_TICKETS_INFOS}->{$1} = $2;
      }
    }
  }
  # ______________________________________________________________
  
  $h_conso->{NOT_ISSUED} =  $h_conso->{TICKETS_TOTAL} - 
    ($h_conso->{TICKETED_BY_TAS} + $h_conso->{TICKETED_NOT_BY_TAS}->{TOTAL});
  
  return $h_conso;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Effectue une consolidation des statistiques d'un jour donné
#   en vue de l'écrire dans un fichier .txt plat
sub compileDailyStats {
  my $params = shift;
  
  foreach (qw/CAL_ID DATE SUBTASK MARKET AGENCY/) {
    if ((!exists $params->{$_}) || (!defined $params->{$_})) {
      $params->{CAL_ID} = getCalId()                      if (($_ eq 'CAL_ID') && (!exists $params->{$_}));
      $params->{DATE}   = strftime("%d/%m/%Y", localtime) if (($_ eq 'DATE')   && (!exists $params->{$_}));
      if ($_ =~ /^SUBTASK|MARKET|AGENCY/) {
        notice('compileDailyStats: $params->{'.$_.'} is not defined.');
        return 0;
      }
    }
  }
  
  my $calId    = $params->{CAL_ID};
  my $appId    = getAppId($params->{TASK});
  my $market   = $params->{MARKET};
  my $agency   = $params->{AGENCY};
  my $subTask  = $params->{SUBTASK};
  
  # ______________________________________________________________
  # Voyons maintenant si nous avons des infos pour le jour demandé
  #  en base de Données.
  my $h_consoAir   = undef;
     $h_consoAir   = _getTasConso({
       'CAL_ID'  => $calId,
       'TASK'    => 'tas-air-etkt',   # TASK Attention ici au PAPER
       'SUBTASK' => $subTask,
     });
  my $h_consoTrain = undef;
     $h_consoTrain = _getTasConso({
       'CAL_ID'  => $calId,
       'TASK'    => 'tas-train-etkt', # TASK Attention ici au PAPER
       'SUBTASK' => $subTask,
     }) if ($agency eq 'Paris');
  # ______________________________________________________________
  
  # ==============================================================
  # La forme des data est la suivante
  my $data = {};
  #   TTA ou TTR => [ TOTAL AIR ou RAIL            ] # INTEGER
  #   TIA ou TIR => [ TAS ISSUED AIR ou RAIL       ] # INTEGER
  #   TRA ou TRR => [ TAS REJECTS AIR ou RAIL      ] # FLOAT
  #   AA  ou AR  => [ % AUTOMATISATION AIR ou RAIL ] # FLOAT
  #   RA  ou RR  => [ % REJECTS AIR ou RAIL        ] # FLOAT
  # ==============================================================
  
  # ______________________________________________________________
  # Préparation des données AIR
  if (defined $h_consoAir) {
    
    my $tATot  = 0; $tATot =  $h_consoAir->{TICKETS_TOTAL}   if (exists $h_consoAir->{TICKETS_TOTAL});
    my $eAVal  = 0; $eAVal =  $h_consoAir->{TICKETED_BY_TAS} if (exists $h_consoAir->{TICKETED_BY_TAS});
    my $xAVal  = 0; $xAVal =  $h_consoAir->{TAS_REJECTED}    if (exists $h_consoAir->{TAS_REJECTED});
    my $yAVal  = 0; $yAVal =  $h_consoAir->{TAS_TOTAL}       if (exists $h_consoAir->{TAS_TOTAL});
    my $perATicketedByTas     = 0;
       $perATicketedByTas     = ($eAVal * 100) / $tATot unless ($tATot == 0);
    my $perATasRejectTasTotal = 0;
       $perATasRejectTasTotal = ($xAVal * 100) / $yAVal unless ($yAVal == 0);
    my $perATasRejectTotal    = ($perATicketedByTas / 100) * ($perATasRejectTasTotal / 100);
    my $rAVal  = 0; $rAVal = ($tATot * $perATasRejectTotal);
  
    my $percA1 = '0.00';
       $percA1 = sprintf("%.2f", (($rAVal * 100 ) / $eAVal)) unless ($eAVal == 0);
    my $percA2 = '0.00';
       $percA2 = sprintf("%.2f", (($rAVal * 100 ) / $tATot)) unless ($tATot == 0);
    if ($percA1 ne '0.00') { $percA1 = sprintf("%.2f", (100 - $percA1)); $percA1 .= ' %' } else { $percA1 = '' };
    if ($percA2 ne '0.00') { $percA2 .= ' %'                                             } else { $percA2 = '' };
    
    $data->{TTA} = $tATot;
    $data->{TIA} = $eAVal;
    $data->{TRA} = sprintf("%.2f", $rAVal);
    $data->{AA}  = $percA1; # % Automatisation TAS
    $data->{RA}  = $percA2; # % Rejets / Total
    
  }
  # ______________________________________________________________
  # Préparation des données TRAIN
  if (defined $h_consoTrain) {
    
    my $tTTot  = 0; $tTTot =  $h_consoTrain->{TICKETS_TOTAL}   if (exists $h_consoTrain->{TICKETS_TOTAL});
    my $eTVal  = 0; $eTVal =  $h_consoTrain->{TICKETED_BY_TAS} if (exists $h_consoTrain->{TICKETED_BY_TAS});
    my $xTVal  = 0; $xTVal =  $h_consoTrain->{TAS_REJECTED}    if (exists $h_consoTrain->{TAS_REJECTED});
    my $yTVal  = 0; $yTVal =  $h_consoTrain->{TAS_TOTAL}       if (exists $h_consoTrain->{TAS_TOTAL});
    my $perTTicketedByTas     = 0;
       $perTTicketedByTas     = ($eTVal * 100) / $tTTot unless ($tTTot == 0);
    my $perTTasRejectTasTotal = 0;
       $perTTasRejectTasTotal = ($xTVal * 100) / $yTVal unless ($yTVal == 0);
    my $perTTasRejectTotal    = ($perTTicketedByTas / 100) * ($perTTasRejectTasTotal / 100);
    my $rTVal  = 0; $rTVal = ($tTTot * $perTTasRejectTotal);
  
    my $percT1 = '0.00';
       $percT1 = sprintf("%.2f", (($rTVal * 100 ) / $eTVal)) unless ($eTVal == 0);
    my $percT2 = '0.00';
       $percT2 = sprintf("%.2f", (($rTVal * 100 ) / $tTTot)) unless ($tTTot == 0);
    if ($percT1 ne '0.00') { $percT1 = sprintf("%.2f", (100 - $percT1)); $percT1 .= ' %' } else { $percT1 = '' };
    if ($percT2 ne '0.00') { $percT2 .= ' %'                                             } else { $percT2 = '' };
    
    $data->{TTR} = $tTTot;
    $data->{TIR} = $eTVal;
    $data->{TRR} = sprintf("%.2f", $rTVal);
    $data->{AR}  = $percT1; # % Automatisation TAS
    $data->{RR}  = $percT2; # % Rejets / Total
    
  }
  # ______________________________________________________________
  
  my $year = (split /\//, $params->{DATE})[2];
  
  debug('compileDailyStats: $params->{DATE} = '.$params->{DATE});
  debug('compileDailyStats: $year = '.$year);
  
  $agency = 'Meetings_'.$agency if ($subTask =~ /meetings/);
  
  _writeData($params->{DATE}, $agency, $data)
    if ((defined $h_consoAir) || (defined $h_consoTrain));
  
  return 1;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Création d'un fichier .txt plat contenant deja toutes les
#  données deja consolidées.
sub _initTxtFile {
	my $year   = shift;
	my $agency = shift;

  my $outputData = '';
	
  foreach (1 .. 12) {
		my $monthNum   = sprintf("%02d", $_);
	  my $calMonthId = getMonthCalId($monthNum, $year);
	  foreach (@$calMonthId) {
		  my $date     = $_->[1];
			my @date     = split /\//, $date;
			$outputData .= $date[0].'/'.$date[1].'/'.$date[2]."\n";
	  }
	}

	write_file($reportPath.'TAS_'.$agency.'_'.$year.'.txt', $outputData);

  return 1;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Ecrire les données au bon endroit du fichier plat .txt en
#  fonction d'une date de calendrier 'DD/MM/YYYY' et d'une agence.
sub _writeData {
  my $date   = shift;
	my $agency = shift;
	my $data   = shift;
	
	debug('_writeData');

	if (!defined $date || $date !~ /^\d{2}\/\d{2}\/\d{4}/) {
	  notice('_writeData: Wrong date format');
	  return 0;
	}

  # =============================================================
  # La forme des data est la suivante
  #   TTA ou TTR => [ TOTAL AIR ou RAIL            ] # INTEGER
  #   TIA ou TIR => [ TAS ISSUED AIR ou RAIL       ] # INTEGER
  #   TRA ou TRR => [ TAS REJECTS AIR ou RAIL      ] # FLOAT
  #   AA  ou AR  => [ % AUTOMATISATION AIR ou RAIL ] # FLOAT
  #   RA  ou RR  => [ % REJECTS AIR ou RAIL        ] # FLOAT
  # =============================================================
	my $TTA = $data->{TTA} || 0; my $TTR = $data->{TTR} || 0;
	my $TIA = $data->{TIA} || 0; my $TIR = $data->{TIR} || 0;
	my $TRA = $data->{TRA} || 0; my $TRR = $data->{TRR} || 0;
	my $AA  = $data->{AA}  || 0; my $AR  = $data->{AR}  || 0;
	my $RA  = $data->{RA}  || 0; my $RR  = $data->{RR}  || 0;

	my $year = (split /\//, $date)[2];

  my $fileName = $reportPath.'TAS_'.$agency.'_'.$year.'.txt';

	# _____________________________________________________________
	# Si ce fichier de rapport n'existe pas, nous le générons vide.
  _initTxtFile($year, $agency) unless (-e $fileName);
	# _____________________________________________________________

	my $d  = '';
	   $d .= "TTA=$TTA;TIA=$TIA;TRA=$TRA;AA=$AA;RA=$RA;";
	   $d .= "TTR=$TTR;TIR=$TIR;TRR=$TRR;AR=$AR;RR=$RR;" if ($agency =~ /Paris/);

	# _____________________________________________________________
  # Nous écrivons au bon endroit dans le document .txt
  #   les données voulues.
  my $output  = '';	
  my @txtFile = read_file($fileName);
  foreach my $line (@txtFile) {
    chop($line);
    my $fstElt = (split(/;/, $line))[0];
		if ($date eq $fstElt) { $output .= $fstElt.';'.$d."\n"; }
		else                  {	$output .= $line."\n";          }
	}
	unlink($fileName);
	write_file($fileName, $output);
	# _____________________________________________________________

	return 1;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# OUTRE-PASSAGE DE LA REGLE TC_CHECKED DE WBMI.
#   Si TC_CHECKED = 'No' et BookDate > 3H00          | Autoriser l'émission
# EXCEPTIONS : Si BookDate est un Samedi ou Dimanche
#              ou BookDate > J-1 après 18H00         | Ne pas autoriser l'émission sauf si CurrentTime >= 11H00
sub isTcChecked {
  my $params     = shift;
  
  my $market     = $params->{MARKET};
  my $mdCode     = $params->{MDCODE};
  my $bookDate   = $params->{BOOKDATE};  debug('isTcChecked: $bookDate = '.$bookDate);
  my $PNR        = $params->{PNR};
  
    #local date from the server 
    my $currDate   = strftime("%Y/%m/%d %H:%M:%S", localtime());
	
	#check from Timezone and apply TZ if needed 
	my $tz = &getTZbycountry($market);
	if (!$tz) {
		error("No timezone is defined for market '$market'. Aborting.");
		return 0;
	}
	else
	{
		$currDate = setTimeZone_wbmi($tz);  
	}
	
   debug('_____ currentDate = '.$currDate);
  
  if  ($bookDate eq '') { # Pas de BookDate !!!
    debug('isTcChecked: PNR = '.$PNR.' - MARKET = '.$market.' - BOOKDATE = '.$bookDate.' - CURRDATE = '.$currDate.' - BookDate empty !');
    return 1;
  }
  
  my $del        = $cnxMgr->getConnectionByName('mid');
  my $query      = 'SELECT IS_CHECKED FROM WBMI_INFOS WHERE MD_CODE = ?';
  my $res        = $del->saarBind($query, [$mdCode]);
  
  debug('  *** IS_CHECKED FROM WBMI_INFOS = '.$res->[0][0]) if (defined $res->[0][0]);
  debug('_____ Est ce qu il y a des regles WBMI ouvertes ?');
  if ((defined $res->[0][0]) && ($res->[0][0] eq '1')) { # TC_CHECKED = 'Yes'
    debug('_____ Non.');
    return 1;
  }
  debug('_____ Oui.');
  
     
  my $dtBookDate = DateTime->new(
          year   => substr($bookDate,  0, 4),
          month  => substr($bookDate,  5, 2),
          day    => substr($bookDate,  8, 2),
          hour   => substr($bookDate, 11, 2),
          minute => substr($bookDate, 14, 2));
        
  my $dtCurrDate = DateTime->new(
          year   => substr($currDate,  0, 4),
          month  => substr($currDate,  5, 2),
          day    => substr($currDate,  8, 2),
          hour   => substr($currDate, 11, 2),
          minute => substr($currDate, 14, 2));
          
  my $duration   = $dtCurrDate - $dtBookDate;

	#EGE-62577
	if ( ((abs($duration->{minutes}) > 60) && (abs($duration->{days})) == 0) || (abs($duration->{days})    > 0  ) ) 
	{ 
	   debug('Booking made more than 1 hour, we force it');
	  return 1;
	}
  
  return 0;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Sauvegarde de la TAS_ERROR dans le dispatch.
#   Obligatoirement dans une table à part pour ne pas que l'information soit perdue.
sub _setTasError {
  my $mdCode   = shift;
  my $tasError = shift;
  my $pnr      = shift;
  
  my $midDB = $cnxMgr->getConnectionByName('mid');
  
  # -----------------------------------------------------------------
  # Est-ce que nous avons déjà une donnée ?
  my $query = "
    SELECT TAS_ERROR_CODE 
      FROM TASERROR_FOR_DISPATCH
     WHERE META_DOSSIER_ID = ? 
     AND   PNR             = ? ";
  # -----------------------------------------------------------------
  
  if (!defined $midDB->saarBind($query, [$mdCode, $pnr])->[0][0]) {
    $query = "
      INSERT INTO TASERROR_FOR_DISPATCH (TAS_ERROR_CODE, META_DOSSIER_ID, PNR) VALUES (?, ?, ?) ";
  } else {
  
	#EGE-90353 Evolution for recording multiple error in case of multiple pnr
	 my $old_error= $midDB->saarBind($query, [$mdCode, $pnr])->[0][0];
	 if ($old_error =~m/,/){
		 my $new_error=$tasError;
		 my @old_error_tab=split(',',$old_error);
		 my @new_error_tab =split(',',$new_error);
		 my $i=0;
		 my @final_error_tab;

		 foreach (@old_error_tab){
			$old_error_tab[$i]=$new_error_tab[$i] if ($new_error_tab[$i] != 0);
			$i++;
		 }

		$tasError=join(',',@old_error_tab);
	}
	
    $query = "
      UPDATE TASERROR_FOR_DISPATCH
         SET TAS_ERROR_CODE  = ?
       WHERE META_DOSSIER_ID = ? 
       AND   PNR             = ?";
  }
  
  my $rows = $midDB->doBind($query, [$tasError, $mdCode, $pnr]);
  
  warning('Problem detected !') if ((!defined $rows) || ($rows != 1));
  
  return 0 unless ((defined $rows) && ($rows == 1));
  return 1;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

sub setTimeZone
{
        my $zone   = shift;
        my $mytime= strftime("%d/%m/%Y %H:%M:%S",localtime());
        my @myDateTime = split(/ /, $mytime);
        my @myDate = split(/\//, $myDateTime[0]);
        my @myTime = split(/:/, $myDateTime[1]);
              
         my $dt = DateTime->new(
         year   => $myDate[2],
         month   => $myDate[1],
         day    => $myDate[0],
         hour   => $myTime[0],
         minute => $myTime[1],
         time_zone => 'Europe/Paris',
         );  

         $dt ->set_time_zone($zone);
         #my $date = sprintf("%02d",$dt->day()).sprintf("%02d",$dt->month()).$dt->year(); 
         #ANCIEN FORMAT MARCHANT SOUS ORACLE DDMMYYYY à passer en DD/MM/YYYY pour msql
         my $date = sprintf("%02d",$dt->day()).'/'.sprintf("%02d",$dt->month()).'/'.$dt->year();
         notice('Date avec la timezone ('.$zone.') = '.$date); 
              
  return $date; 
}

sub setTimeZone_wbmi
{
        my $zone   = shift;
        my $mytime= strftime("%d/%m/%Y %H:%M:%S",localtime());
        my @myDateTime = split(/ /, $mytime);
        my @myDate = split(/\//, $myDateTime[0]);
        my @myTime = split(/:/, $myDateTime[1]);
              
         my $dt = DateTime->new(
         year   => $myDate[2],
         month   => $myDate[1],
         day    => $myDate[0],
         hour   => $myTime[0],
         minute => $myTime[1],
         time_zone => 'Europe/Paris',
         );  

         $dt ->set_time_zone($zone);
         my $date = $dt->year().'/'.sprintf("%02d",$dt->month()).'/'.sprintf("%02d",$dt->day())." ".sprintf("%02d",$dt->hour()).":".sprintf("%02d",$dt->minute()).":".sprintf("%02d",$dt->second());
         notice('Date avec la timezone ('.$zone.') = '.$date); 
              
  return $date; 
}


sub createTasExcelReport {
  my $task = shift;
  my $xlsFile = shift;
  my $data = shift;
  my $new_archive_cons = shift;
  my $colSep = shift;

  
  use Spreadsheet::WriteExcel;

  my $workbook  = Spreadsheet::WriteExcel->new($xlsFile);
  die "Problèmes à la création du fichier excel: $!" unless defined $workbook;

  my $worksheet1 = $workbook->addworksheet();
  my $worksheet2 = $workbook->addworksheet();

  my $row = 0;

  my $format1 = $workbook->addformat();
  my $format2 = $workbook->addformat();
	  
	  
  $format1->set_size(10.5);
  $format1->set_font('Consolas');


  $format2->set_align('center');
  $format2->set_size(10.5);
  $format1->set_font('Consolas');
  $worksheet1->set_column('A:A', 72);
  
  
  
  
  my @lines = split('\n',$data); 
  
  my $i = -1;
  my $lineCount = 0;
  my $linelen;

  foreach my $l(@lines) {
     $linelen = length($l) if ($lineCount == 0 );
     $lineCount++;
     $l = formatDateInExcel($l,$linelen);

     debug("line".$l);
     if ($l) {
        $worksheet1->write(++$i, 0, $l, $format1);
     }
  }
  
  $worksheet2->set_column('A:A', 30);
  $worksheet2->set_column('B:B', 20);
  $worksheet2->set_column('C:C', 30);
  $worksheet2->set_column('D:D', 20);
  $worksheet2->set_column('E:E', 20);
  $worksheet2->set_column('F:F', 20);
  $worksheet2->set_column('G:G', 20);
  $worksheet2->set_column('H:H', 50);
  $worksheet2->set_column('I:I', 20);
 
  open(CONS, "<", $new_archive_cons);  
  
  $i = -1;
  while (<CONS>) {
     my @cols = split($colSep,$_);
     my $c = -1;
     ++$i;
     foreach my $d (@cols) {
         $worksheet2->write($i, ++$c, $d, $format1);
     }
     $c= -1;
  }
  
   
  $workbook->close();
  
}

sub getAddDataForTasReport {
  my $task = shift;
  my $GDS  = shift;
  my $query = qq{
		SELECT 
		          I.REF
			 ,I.PNR
			 ,I.TAS_ERROR
			 ,CONVERT(VARCHAR(10),I.TIME,101) AS DATE
                         ,CONVERT(VARCHAR(10),I.TIME,108) AS TIME
			 ,I.DELIVERY_ID
			 ,D.MODULE
                         ,CONVERT(VARCHAR(10),TICKETED_DATE,101) AS TICKETED_DATE
                         ,CONVERT(VARCHAR(10),TICKETED_DATE,108) AS TICKETED_TIME
                         ,CONVERT(VARCHAR(10),D.MODIFICATION_DATE,101) AS MODIFICATION_DATE
                         ,CONVERT(VARCHAR(10),D.MODIFICATION_DATE,108) AS MODIFICATION_TIME
			 ,(SELECT NAME FROM APPLICATIONS WHERE ID = I.APP_ID) as TASK
			 ,(SELECT NAME FROM APPLICATIONS WHERE ID = I.SUBAPP_ID) as SUBTASK
                         ,D.COM_NAME
                         ,D.MARKET
			 ,CONVERT(VARCHAR(MAX), CONVERT(NVARCHAR(MAX), XML)) as XML
			 ,D.TRAVELLERS
			 
		FROM IN_PROGRESS I,
			 DELIVERY_FOR_DISPATCH D,
			 TAS_MESSAGES M
		WHERE D.PNR LIKE '%' + I.PNR + '%'
		AND M.ERR_CODE = I.TAS_ERROR
		AND I.REF IN (
				SELECT REF
				FROM IN_PROGRESS
				WHERE STATUS = 'TAS_CHECKED'
				AND TYPE = 'GAP_TC'
						
				UNION

				SELECT REF
				FROM IN_PROGRESS
				WHERE STATUS = 'TAS_ERROR'
				AND TAS_ERROR != 13
				AND TYPE = 'GAP_TC'

				UNION

				SELECT REF
				FROM IN_PROGRESS
				WHERE STATUS = 'TAS_ERROR'
				AND (TAS_ERROR = 13 )
				AND TYPE = 'GAP_TC'

		             ) 
		AND I.SUBAPP_ID = (SELECT ID FROM APPLICATIONS WHERE NAME = '$task')
		AND I.TYPE = 'GAP_TC'
		ORDER BY TAS_ERROR ASC, REF DESC
  };
  
   my @res = ();
   my $dbh    = $cnxMgr->getConnectionByName('mid');
   my $res = $dbh->saar($query);
   #print "task $task"; 
   #print "Query = $query";
   #print 'res = '.Dumper($res); 
   foreach (@$res) {
     my $tmp    = undef;

     push @res, { 
		   REF                 => $_->[0],
                   PNR                 => $_->[1],
                   Reject              => getTasMessage($_->[2]),
                   Date                => $_->[3],
                   Time                => $_->[4],
                   'Delivery ID'       => $_->[5],
		   Module              => $_->[6],
		   'Ticketed Date'     => $_->[7],
                   'Ticketed Time'     => $_->[8],
                   'Modification Date' => $_->[9],
		   'Modification Time' => $_->[10],
                   Task                => $_->[11],
                   SubTask             => $_->[12],
                   Client              => $_->[13],
                   Country             => getNavCountrybycountry($_->[14]),
				   'Traveler Name'     => $_->[16],
                   'Airline Company'   => getAirlineCompany({PNR => $_->[1],GDS => $GDS}),
                   'Reject Code'       => $_->[2] 

				};
  }
  return @res;

}

sub getAirlineCompany() {
  my $item = shift;
  my $GDS = $item->{GDS};
  my $pnr = Expedia::GDS::PNR->new(PNR => $item->{PNR}, GDS => $GDS);
  my $retmsg = "";
  if (!defined $pnr) {
     error("Could not read PNR '".$item->{PNR}."' from GDS.");
     $retmsg = "Could not read PNR '".$item->{PNR}."' from GDS.";
  } else {

  $GDS->RT(PNR=>$pnr->{PNRId}, NoIG=>1);
  foreach (@{$pnr->{'PNRData'}}) {

                my $lineData = uc $_->{'Data'};
                my $lineNumb = $_->{'LineNo'};

                if ($lineData =~ /^FV\s+(.*)$/) {
                        if (($lineData =~ /^FV\s+(\w{2})$/) ||
                            ($lineData =~ /^FV\s+(?:(?:PAX|INF)\s+)?(?:\*\w\*)?(\w{2})\/S(?:\d+(?:,|-|\/|$))+/)) {
                                debug('LIGNE '.$lineNumb.' = '.$lineData);
                                my $airCompanyCode = $1;
                                debug('AirCompanyCode = '.$airCompanyCode);
                                $retmsg = $airCompanyCode;
                        }
          else {
            notice('WARNING: FV line does not match regexp [...]');
            notice($lineData);
            $retmsg = "FV line does not match regexp [...]";
          }
                } else { next; }

      } # Fin foreach (@{$pnr->{'PNRData'}})
      if ($retmsg eq "") {
        $retmsg = "No FV Line Found";
      }
   }
   return $retmsg;
}

sub formatDateInExcel {
   my $line = shift;
   my $linelen = shift;
   if ($line =~ /^(\=)+$/) {
        $line = '+';
        $line .= '-' for(1..$linelen-2);
        $line .= '+';
        return $line;
   }

   if ($line =~ /^(0[1-9]|1[012])\/(0[1-9]|[12][0-9]|3[01])\/\d\d\s([0-9]|0[0-9]|1[0-9]|2[0-3]):[0-5][0-9]:[0-5][0-9]/) {
           my $lin = '|';
           my $splen = ($linelen-19)/2;
           $lin .= " " for (1..$splen);
           $lin .= $line;
           $lin .= " " for (1..$splen);
           $lin .= '|';
           $line = $lin;
           return $line;
   }
   return $line;
}


# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Get the delivery information for TAS
sub getDeliveryForTas {
  my $market   = shift;
  my $product  = shift;
  
  my $midDB = $cnxMgr->getConnectionByName('mid');
  
  my $query = "
    SELECT DELIVERY 
      FROM MO_CFG_DELIVERY
     WHERE COUNTRY = ? 
     AND   PRODUCT = ? ";

  my $delivery = $midDB->saarBind($query, [$market, $product])->[0][0];

  return $delivery;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Get the currency for TAS
sub getCurrencyForTas {
  my $market   = shift;
  
  my $midDB = $cnxMgr->getConnectionByName('mid');
  
  my $query = "
    SELECT CURRENCY
      FROM MO_CFG_DIVERS
     WHERE COUNTRY = ? ";

  my $finalRes = $midDB->saarBind($query, [$market])->[0][0];

  return $finalRes;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

#---------------------------------
# Routine de Tri Des Numériques
#---------------------------------
sub triDecroissant { $b <=> $a } 
sub triCroissant   { $a <=> $b }

1;
