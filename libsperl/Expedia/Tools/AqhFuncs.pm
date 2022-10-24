package Expedia::Tools::AqhFuncs;
#-----------------------------------------------------------------
# Package Expedia::Tools::AqhFuncs
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

@EXPORT_OK = qw(&aqh_reporting &getMailForAqh);

sub aqh_reporting
{

my $pos = shift;
my $email = shift;
my $mytime_gen= strftime("%Y-%m-%dT00:00:00",localtime());
  
# ===================================================================
# G�n�ration du fichier EXCEL
# ===================================================================
my $xlsFile = "/var/tmp/AQH_REPORTING_".$pos.".xls";

my $workbook  = Spreadsheet::WriteExcel->new($xlsFile);
die "Probl�mes � la cr�ation du fichier excel: $!" unless defined $workbook;

my $worksheet = $workbook->addworksheet();

my $row = 0;

my $format1 = $workbook->addformat();
my $format2 = $workbook->addformat();
my $format3 = $workbook->addformat();

    $format1->set_border(1);
    $format1->set_bottom; 
    $format1->set_top;
    $format1->set_align('center');
    $format1->set_size(8);
    $format1->set_text_wrap();
        
    $format2->set_border(1);
    $format2->set_bottom; 
    $format2->set_top;
    $format2->set_bold;
    $format2->set_align('center');
    $format2->set_size(12);
    $format2->set_fg_color('silver'); 

    #CAS EN ERREUR - ROUGE ET GRAS
    $format3->set_border(1);
    $format3->set_bottom; 
    $format3->set_top;
    $format3->set_bold;
    $format3->set_align('vjustify');
    $format3->set_size(8);
    $format3->set_text_wrap();
    $format3->set_fg_color('red'); 
    
      
		$worksheet->set_column('A:A', 5);
		$worksheet->set_column('B:B', 5);
		$worksheet->set_column('C:C', 10);
		$worksheet->set_column('D:D', 10);
		$worksheet->set_column('E:E', 15);
		$worksheet->set_column('F:F', 25);
		$worksheet->set_column('G:G', 25);
		$worksheet->set_column('H:H', 15);
		$worksheet->set_column('I:I', 80);
		$worksheet->set_column('J:J', 80);
        $worksheet->set_column('K:K', 50);

$worksheet->set_column(1, 1, 30); # Column B width set to 30
    
$worksheet->write(0, 0, 'POS', $format2);
$worksheet->write(0, 1, 'OID', $format2);
$worksheet->write(0, 2, 'QUEUE', $format2);
$worksheet->write(0, 3, 'PNR', $format2);
$worksheet->write(0, 4, 'TEAM', $format2);
$worksheet->write(0, 5, 'MID_ACTION', $format2);
$worksheet->write(0, 6, 'RESULT_FO', $format2);
$worksheet->write(0, 7, 'DATE', $format2);
$worksheet->write(0, 8, 'LINE', $format2);
$worksheet->write(0, 9, 'PARAMS', $format2);
$worksheet->write(0, 10, 'RULE_MATCHED', $format2);

  my $dbh = $cnxMgr->getConnectionByName('navision');
  $request="SELECT * FROM AQH_REPORT WHERE DATE_CREATION > '".$mytime_gen."' AND POS='".$pos."' AND OFFICE_ID != 'CHECK' ORDER BY DATE_CREATION DESC";
  my $results = $dbh->saar($request);

$row++;
foreach $res_report (@$results)
{
   my @myreport = ();
   my $libelle_error = "";
   my $compteur_report = 1;
   my $params = $res_report->[7];
   my $rule_matched = "";

   $format = $format1;

   # create a column in worksheet by splitting the text from params column of the DB
   if ($res_report->[7] =~ /\|RULE\:/) {
       @params_array = split(/\|RULE\:/, $res_report->[7]);
       $params = $params_array[0];
       $rule_matched = $params_array[1];
   }

   if($res_report->[5] =~ /\|/ )
   {
     @myreport = split(/\|/, $res_report->[5]);
   }
   else
   {
      push @myreport, $res_report->[5];
   }
   
   foreach $tmp_report (@myreport)
   {
    	 if($tmp_report == -1){$libelle_error.="WS DOWN\n";$format=$format3;}
    	 elsif($tmp_report == -3){$libelle_error.="NOK WBMI - Schedule Change\n";$format=$format3;}
    	 elsif($tmp_report == -6){$libelle_error.="NOK WBMI - Flight Cancellation\n";$format=$format3;}
    	 elsif($tmp_report == -9){$libelle_error.="NOK WBMI - Check Seat\n";$format=$format3;}
    	 elsif($tmp_report == -5){$libelle_error.="NOK WBMI - Check Meal\n";$format=$format3;}
    	 elsif($tmp_report == -21){$libelle_error.="NOK WBMI - Misc Service\n";$format=$format3;}
    	 elsif($tmp_report == -23){$libelle_error.="NOK WBMI - WaitList\n";$format=$format3;}
    	 elsif($tmp_report == -13){$libelle_error.="NOK WBMI - Unidentified\n";$format=$format3;}
    	 elsif($tmp_report == -2){$libelle_error.="NOK WBMI - Ticketing Deadline\n";$format=$format3;}
    	 elsif($tmp_report == -42){$libelle_error.="NOK WBMI - CAR Unidentified\n";$format=$format3;}
    	 elsif($tmp_report == 3){$libelle_error.="WBMI - Schedule Change\n";}
    	 elsif($tmp_report == 6){$libelle_error.="WBMI - Flight Cancellation\n";}
    	 elsif($tmp_report == 9){$libelle_error.="WBMI - Check Seat\n";}
    	 elsif($tmp_report == 5){$libelle_error.="WBMI - Check Meal\n";}
    	 elsif($tmp_report == 21){$libelle_error.="WBMI - Misc Service\n";}
    	 elsif($tmp_report == 23){$libelle_error.="WBMI - WaitList\n";}
    	 elsif($tmp_report == 13){$libelle_error.="WBMI - Unidentified\n";}
    	 elsif($tmp_report == 42){$libelle_error.="WBMI - CAR Unidentified\n";}
    	 elsif($tmp_report == 2){$libelle_error.="WBMI - Ticketing Deadline\n";}
    	 elsif($tmp_report == -8){$libelle_error.="NOK - Mail\n";$format=$format3;}
    	 elsif($tmp_report == 8){$libelle_error.="Mail\n";}
    	 elsif($tmp_report == -18){$libelle_error.="NOK - Replan\n";$format=$format3;}
    	 elsif($tmp_report == 18){$libelle_error.="Replan\n";}
    	 elsif($tmp_report == 19){$libelle_error.="FO No Action\n";}
    	 else { $libelle_error.="";}
     
  	 $compteur_report++;
   }
   
   #CAS OU LE CODE EST DIFFERENT DE CE QU'IL Y AU DESSUS, ON RETOURNE JUSTE LE CODE
   if(!defined($libelle_error)){$libelle_error= $res_report->[5];}
   	 
   $worksheet->write($row, 0, $res_report->[0], $format);
   $worksheet->write($row, 1, $res_report->[1], $format);
   $worksheet->write($row, 2, $res_report->[2], $format);
   $worksheet->write($row, 3, $res_report->[3], $format);
   $worksheet->write($row, 4, $res_report->[6], $format);
   $worksheet->write($row, 5, $res_report->[4], $format);
   $worksheet->write($row, 6, $libelle_error, $format);
   $worksheet->write($row, 7, $res_report->[9], $format);
   $worksheet->write($row, 8, $res_report->[8], $format);
   $worksheet->write($row, 9, $params, $format);
   $worksheet->write($row, 10, $rule_matched, $format);
   $row++;
}
$workbook->close();

# ===================================================================
# Envoi email
# ===================================================================
eval
{
$subject = 'Airline queue reporting: '.$pos;
$aqh_mail='aqh-'.$pos;

my $var_mail="AQH_TO";
my $my_from = 'noreply@egencia.eu';
my $my_to = "";

# override if present in the script arguments
if($email){
   $my_to = $email;
} else {
   $my_to = &getMailForAqh($pos,$var_mail);
}
debug("SENDING EMAIL TO: ".Dumper($my_to));

my $my_cc   = '';

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
};
  if ($@) {
    error('Problem during email send process. '.$@);
  }
  
unlink($xlsFile);

  #AJOUT D'UN CONTROLE POUR QUE LES ALERTES SURVEILLENT QUE LE JOB A TOURNE JUSQU'A LA FIN
  $dbh = $cnxMgr->getConnectionByName('navision');
  $request="UPDATE AQH_REPORT SET DATE_CREATION = getdate() WHERE POS=? AND OFFICE_ID = 'CHECK'";
  $dbh->doBind($request, [$pos]);  
  
}

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Get mail for AQH
sub getMailForAqh {
  my $market    = shift;
  my $champ     = shift;
  
  my $midDB = $cnxMgr->getConnectionByName('mid');
  my $query = "
    SELECT ".$champ."
        FROM MO_CFG_MAIL
     WHERE COUNTRY= ?  ";

  my $finalRes = $midDB->saarBind($query, [$market])->[0][0];

  return $finalRes;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@


1;
