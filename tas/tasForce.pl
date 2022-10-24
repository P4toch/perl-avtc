#!/usr/bin/perl -w

# ________________________________________________________________
# EN-TETE PAR DEFAUT
use strict;
use Data::Dumper;
use Getopt::Long;

use lib '../libsperl';

use Expedia::XML::Config;
use Expedia::Tools::GlobalVars qw($cnxMgr);
use Expedia::Tools::TasFuncs   qw(&getDeliveryForTas);

my $opt_help;
my $opt_agcy;
my $opt_prdt;
my $opt_tasr;

GetOptions(
  'agency=s',  \$opt_agcy,
  'product=s', \$opt_prdt,
  'reject=s',  \$opt_tasr,
  'help',      \$opt_help
);

$opt_help = 1
  unless (($opt_agcy && $opt_prdt && $opt_tasr)                    &&
          ($opt_prdt =~ /^(air|rail)$/)  &&
          ($opt_tasr =~ /^\d+$/));
          
$opt_help = 1 if (($opt_prdt && $opt_agcy) && ($opt_prdt eq 'rail') && ($opt_agcy ne 'Paris'));

if ($opt_help) {
  print STDERR ("\nUsage: $0 --agency  = [Paris|Manchester|Bruxelles|Munchen|Barcelona|Sydney]\n".
                "                   --product = [air|rail]\n".
                "                   --reject  = [12|47|??]\n\n");
  exit(0);
}

my $task = 'tas-'.$opt_agcy.':'.$opt_prdt;
my $config        = Expedia::XML::Config->new('../libsperl/Expedia/Tools/config_DDB.xml',$task);
my $dbh    = $cnxMgr->getConnectionByName('mid');

my $query    = "SELECT TOP 1 MARKET FROM MO_CFG_TASK WHERE AGENCY=? AND PRODUCT=? AND ATTACH='TAS'";
my $market   = $dbh->saarBind($query, [$opt_agcy,$opt_prdt])->[0][0];
my $tcatId   = &getDeliveryForTas($market,$opt_prdt);

   $query = "
  SELECT DFD.META_DOSSIER_ID, DFD.PNR, DFD.DELIVERY_ID, DFD.TCAT_ID, DFD.MESSAGE_ID, DFD.MESSAGE_VERSION, DFD.BILLING_COMMENTS, TAS_ERROR_CODE
    FROM DELIVERY_FOR_DISPATCH DFD
    LEFT OUTER JOIN TASERROR_FOR_DISPATCH TFD ON TFD.META_DOSSIER_ID = DFD.META_DOSSIER_ID
   WHERE DFD.DELIVERY_STATUS_ID  = 9
     AND DFD.PNR IS NOT NULL
     AND DFD.PNR NOT LIKE 'null'
     AND CONVERT(DATETIME,DFD.EMISSION_DATE,103) >= CONVERT(DATETIME,CONVERT(VARCHAR(10),GETDATE(),103),103) 
     AND CONVERT(DATETIME,DFD.EMISSION_DATE,103) - CONVERT(DATETIME,CONVERT(VARCHAR(10),GETDATE(),103),103) < 1      AND DFD.TCAT_ID IN ( $tcatId )
     AND DFD.MARKET              = '$market'
     AND DFD.BLOCKED_BY_APPROVAL = 0
     AND DFD.ON_HOLD             = 0
     AND LEN(DFD.PNR)         = 6
     AND DFD.MESSAGE_ID IS NOT NULL
     AND DFD.MESSAGE_VERSION IS NOT NULL
     AND TFD.TAS_ERROR_CODE LIKE '$opt_tasr'
ORDER BY DEPARTURE_DATE ASC";

my $res = $dbh->saar($query);

print STDERR 'RES1 = '.(scalar @$res)."\n";

my $compteur = 0;
$opt_prdt='TRAIN' if($opt_prdt eq 'rail');
foreach (@$res) {

  my $mdCode         = $_->[0];
  my $pnr            = $_->[1];
  my $deliveryId     = $_->[2];
  my $messageId      = $_->[4];
  my $messageVersion = $_->[5];

  print STDERR 'PNR = '.$pnr." MDCODE = $mdCode\n";

  my $isTasProceedQuery = "SELECT BTCTAS_PROCEED FROM MSG_KNOWLEDGE WHERE MESSAGE_CODE = ? AND MESSAGE_TYPE='$opt_prdt' ";
  my $resTasProceed     = $dbh->saarBind($isTasProceedQuery, [$mdCode]);

  # print STDERR 'mdCode = '.$mdCode."\n";
  # print STDERR '$resTasProceed = '.Dumper($resTasProceed);

  if ((defined $resTasProceed) && (defined $resTasProceed->[0][0]) && ($resTasProceed->[0][0] == 0)) {

    my $queryToIssue = "
      UPDATE DELIVERY_FOR_DISPATCH 
     SET DELIVERY_STATUS_ID  = 1
       WHERE PNR IS NOT NULL
     AND MARKET              = '$market'
   AND BLOCKED_BY_APPROVAL = 0
   AND ON_HOLD             = 0
   AND LEN(PNR)         = 6
   AND MESSAGE_ID IS NOT NULL
   AND MESSAGE_VERSION IS NOT NULL
   AND META_DOSSIER_ID     = ?
   AND DELIVERY_ID         = ?
   AND MESSAGE_ID          = ?
   AND MESSAGE_VERSION     = ? ";


    my $upd = $dbh->doBind($queryToIssue, [$mdCode, $deliveryId, $messageId, $messageVersion]);
    print STDERR 'PNR Modified = '.$pnr."\n";
    $compteur++;

  }
  else
  {
   print STDERR 'Not Update -- PNR already treated by TAS or not in msg_knowledge'."\n";
  }
}
print STDERR 'HOW MANY PNR UPDATED = '.$compteur."\n";
