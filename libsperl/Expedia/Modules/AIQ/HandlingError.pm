package Expedia::AIQ::HandlingError;
#-----------------------------------------------------------------
# Package Expedia::AIQ::HandlingError
#
# $Id: GlobalFuncs.pm 586 2010-04-07 09:26:34Z pbressan $
#
# (c) 2002-2008 Expedia.                   www.expediacorporate.fr
#-----------------------------------------------------------------

use Data::Dumper;
use Exporter 'import';
use MIME::Lite;
use POSIX qw(strftime);

use Expedia::Tools::GlobalVars  qw($sendmailProtocol $sendmailIP $sendmailTimeout);
use Expedia::Tools::GlobalVars qw($cnxMgr);
use Expedia::Tools::Logger qw(&debug &notice &warning &error);
use Expedia::WS::Front          qw(&aqh_ticketingdeadline &aqh_unidentified &aqh_serviceconfirmation &aqh_schedulechange &aqh_waitlistfeedback &aqh_flightcancellation);
use Expedia::Tools::AqhFuncs  qw(&getMailForAqh);

use Spreadsheet::WriteExcel;

#@EXPORT_OK = qw(&aqh_reporting);

  my $dbh = $cnxMgr->getConnectionByName('navision');
  my $request="SELECT * FROM AQH_WS_ERROR WHERE TRY < 3";
  my $results = $dbh->saar($request);
  
  foreach $tab (@$results)
  {
      $ID                 =$tab->[0];
      $TRY                =$tab->[1];
      $RES_WS             =$tab->[2];
      $TEAM								=$tab->[3];
      $NAME               =$tab->[4];
      $SERVICE            =$tab->[5];
      $PERCODE            =$tab->[6]; 
      $PNRId              =$tab->[7];
      $POS                =$tab->[8];
      $CODE_SERVICE       =$tab->[9];
      $MADATE             =$tab->[10];
      $HEURE              =$tab->[11];
      $UNIDENTIFIED       =$tab->[12];
 
    if($NAME eq 'handleFlightCancellation' ) 
    {
       $soapOut = aqh_flightcancellation('AirlineQueueWS', {percode => $PERCODE, pnr => $PNRId, pos => $POS});
       $param_ws = 'FlightCancellation|'.$PERCODE."|".$PNRId."|".$POS;
       notice(" WS FLIGHT CANCELLATION:".$param_ws);
    }
    elsif($NAME eq 'handleWaitListFeedback' ) 
    {        
        $soapOut = aqh_waitlistfeedback('AirlineQueueWS', { percode => $PERCODE, pnr => $PNRId, pos => $POS});
        $param_ws = 'WaitListFeedBack|'.$PERCODE."|".$PNRId."|".$POS;
        notice(" WS WAITLIST FEEDBACK:".$param_ws);
    }
    elsif($NAME eq 'handleUnidentifiedAirlineMessage' ) 
    {               
        $soapOut = aqh_unidentified('AirlineQueueWS', { percode => $PERCODE, pnr => $PNRId, pos => $POS, unidentified => $UNIDENTIFIED } );
        $param_ws = 'unidentifiedmessage|'.$PERCODE."|".$PNRId."|".$POS."|".$UNIDENTIFIED;
        notice(" WS UNIDENTIFIED:".$param_ws);
    }
    elsif($NAME eq 'handleScheduleChange' ) 
    {
      $soapOut = aqh_schedulechange('AirlineQueueWS', {percode => $PERCODE, pnr => $PNRId, pos => $POS});
      $param_ws = 'ScheduleChange|'.$PERCODE."|".$PNRId."|".$POS;
      notice(" WS SCHEDULE CHANGE:".$param_ws);
    }
     elsif($NAME eq 'handleServiceConfirmation' ) 
    { 
      $soapOut = aqh_serviceconfirmation('AirlineQueueWS', {service => $WS_OPTION, percode => $PERCODE, pnr => $PNRId, codeservice => $CODE_SERVICE, pos => $POS});
      $param_ws = $WS_OPTION.'|'.$PERCODE."|".$PNRId."|".$POS."|".$CODE_SERVICE;
      notice(" WS SERVICE CONFIRMATION:".$param_ws);
    }
    else
    {
  	  if(!defined($HEURE)){$HEURE=0;}
  	  $soapOut = aqh_ticketingdeadline('AirlineQueueWS', { percode => $PERCODE, pnr => $PNRId, pos => $POS, date => $MADATE, heure => $HEURE});
      $param_ws = 'TicketingDealdline|'.$PERCODE."|".$PNRId."|".$POS."|".$MADATE."|".$HEURE;
      notice(" WS TICKETING DEADLINE:".$param_ws);  
    }
    
    my $code_retour_ws =$soapOut->{status}->[0];
    my $team           =$soapOut->{team};
            
		 if (defined($code_retour_ws)) {notice("RETOUR DU WS:".$code_retour_ws);}
		 else{notice("RETOUR DU WS: -1");$code_retour_ws=-1;}

    if (($code_retour_ws eq -1) || ($code_retour_ws eq -3) || ($code_retour_ws eq -6) || ($code_retour_ws eq -9)  ||
    ($code_retour_ws eq -5) || ($code_retour_ws eq -21) || ($code_retour_ws eq -23) || ($code_retour_ws eq -13) || ($code_retour_ws eq -2))
    {
       $TRY=$TRY+1;
       $request="UPDATE AQH_WS_ERROR SET RESULTAT_WS=?, TRY=? WHERE ID=?"; 
       $rows  = $dbh->doBind($request, [$code_retour_ws, $TRY, $ID]);
       notice("UPDATE WS ID=".$ID." TRY=".$TRY);
    }
    else
    {
        #SI PAS D'ERREUR ON SUPPRIME LA LIGNE
        $request="DELETE FROM AQH_WS_ERROR WHERE ID=?"; 
        $rows  = $dbh->doBind($request, [$ID]);
        warning('Problem detected !') if ((!defined $rows) || ($rows < 1));  
        notice("DELETE WS ID=".$ID." RETOUR WS=".$code_retour_ws." TEAM=".$team);  
    }
  }
      
  $request="SELECT DISTINCT(POS) FROM AQH_WS_ERROR WHERE TRY >= 3";
  $results_pos = $dbh->saar($request);
      
  foreach $res_pos (@$results_pos)
  {
   
    $request="SELECT count(*) FROM AQH_WS_ERROR WHERE TRY >= 3 AND POS='".$res_pos->[0]."'";
    $results = $dbh->saar($request);
    my $nb_res = $results->[0][0];
    notice("IL Y A ".$nb_res." ERREURS A ENVOYER POUR LE POS:".$res_pos->[0]);   
            
    if($nb_res > 0)
    {  
      # ===================================================================
      # Génération du fichier EXCEL
      # ===================================================================
      #my $xlsFile = "/home/Pbressan/Projets/TMP/test/test1.xsl";
      my $xlsFile = "/var/tmp/AQH_REPORTING_ERROR_".$res_pos->[0].".xls";
      
      my $workbook  = Spreadsheet::WriteExcel->new($xlsFile);
      die "Problèmes à la création du fichier excel: $!" unless defined $workbook;
      
      my $worksheet = $workbook->addworksheet();
      
      my $row = 0;
      
      my $format1 = $workbook->addformat();
      my $format2 = $workbook->addformat();
  
      $format1->set_border(1);
      $format1->set_bottom; 
      $format1->set_top;
      $format1->set_align('center');
      $format1->set_size(8);
      
      $format2->set_border(1);
      $format2->set_bottom; 
      $format2->set_top;
      $format2->set_bold;
      $format2->set_align('center');
      $format2->set_size(12);
      $format2->set_fg_color('silver'); 
  
      $worksheet->set_column(1, 1, 30); # Column B width set to 30
         
  		$worksheet->set_column('A:A', 10);
  		$worksheet->set_column('B:B', 22);
  		$worksheet->set_column('C:C', 20);
  		$worksheet->set_column('D:D', 20);
  		$worksheet->set_column('E:E', 30);
  		$worksheet->set_column('F:F', 80);
  		$worksheet->set_column('G:G', 80);

      $worksheet->write(0, 0, 'OID', $format2);
      $worksheet->write(0, 1, 'BOOKING REF', $format2);
      $worksheet->write(0, 2, 'TEAM', $format2);
      $worksheet->write(0, 3, 'ERROR TYPE', $format2);
      $worksheet->write(0, 4, 'MID ACTION', $format2);
      $worksheet->write(0, 5, 'LINE', $format2);
      $worksheet->write(0, 6, 'PARAMETERS', $format2);
  
      $request="SELECT OID, PNR, RESULTAT_WS, TEAM, NAME, PARAMS, LIGNE FROM AQH_WS_ERROR WHERE TRY >= 3 AND POS='".$res_pos->[0]."'";
      $results = $dbh->saar($request);
      
      $row++;
      foreach $res_report (@$results)
      {
  			   if($res_report->[2] == -1){$libelle_error="WS DOWN";}
  				 if($res_report->[2] == -3){$libelle_error="NOK WBMI - Schedule Change";}
  				 if($res_report->[2] == -6){$libelle_error="NOK WBMI - Flight Cancellation";}
  				 if($res_report->[2] == -9){$libelle_error="NOK WBMI - Check Seat";}
  				 if($res_report->[2] == -5){$libelle_error="NOK WBMI - Check Meal";}
  				 if($res_report->[2] == -21){$libelle_error="NOK WBMI - Misc Service";}
  				 if($res_report->[2] == -23){$libelle_error="NOK WBMI - WaitList";}
  				 if($res_report->[2] == -13){$libelle_error="NOK WBMI - Unidentified";}
  				 if($res_report->[2] == -2){$libelle_error="NOK WBMI - Ticketing Deadline";}
  																																		        
         $worksheet->write($row, 0, $res_report->[0], $format1);
         $worksheet->write($row, 1, $res_report->[1], $format1);
         $worksheet->write($row, 2, $res_report->[3], $format1);
         $worksheet->write($row, 3, $libelle_error, $format1);
         $worksheet->write($row, 4, $res_report->[4], $format1);
         $worksheet->write($row, 5, $res_report->[5], $format1);
         $worksheet->write($row, 6, $res_report->[6], $format1);  
  
         $row++;
      }
      $workbook->close();
      
      # ===================================================================
      # Envoi email
      # ===================================================================
      $subject='Airline queues handling failure: Bookings to handle country: '.$res_pos->[0];
      $aqh_mail='aqh-'.$res_pos->[0];
      $my_from = 'noreply@egencia.eu';
      $my_to   = &getMailForAqh($res_pos->[0],'AQH_ERROR_TO');
      $my_cc   = '';
      my $msg = MIME::Lite->new(
        From     => $my_from,
      	To       => $my_to,
      	Cc       => $my_cc,
      	Subject  => $subject,
        Type     => 'application/vnd.ms-excel',
        Encoding => 'base64',
      	Path     => $xlsFile);
      
      MIME::Lite->send($sendmailProtocol, $sendmailIP, Timeout => $sendmailTimeout);
      $msg->send;
      
      unlink($xlsFile);
      
      notice("MAIL ENVOYE POS:".$res_pos->[0]);
      
      }
      
      $request="DELETE FROM AQH_WS_ERROR WHERE TRY=3"; 
      $rows  = $dbh->doBind($request,[]);
      notice("SUPPRESSION DES LIGNES");
    }



1;

