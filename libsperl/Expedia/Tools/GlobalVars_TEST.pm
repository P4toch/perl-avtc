package Expedia::Tools::GlobalVars;
#-----------------------------------------------------------------
# Package Expedia::Tools::GlobalVars
#
# $Id: GlobalVars.pm 713 2011-07-04 15:45:26Z pbressan $
#
# (c) 2002-2010 Expedia.                            www.egencia.eu
#-----------------------------------------------------------------

use Exporter 'import';

@EXPORT_OK = qw($cnxMgr
                $h_maxProcDuration
                $logPath $defaultLogFile
                $h_processors
                $proxyFront $proxyBack $proxyBackBis $proxyAustralia $proxyNav $proxyNav_intra
                $sendmailProtocol $sendmailIP $sendmailTimeout
                $h_appIds
                $reportPath
                $cardTypes $cardCodes $h_AmaMonths
                $templatesPath
                $h_context
                $h_titleSex $h_titleToAmadeus
                $h_creditCardTypes
                $soapRetry $soapProblems
                $h_tstNumFstAcCode $h_fvMapping $h_pcc $h_tarifExpedia $h_tasMessages $h_wbmiMessages
                $btcTrainDefaultGdsQueue $btcTrainNormalCategory $btcTrainApprovalCategory
                $h_statusCodes
                $toTcatId                               
                $dummy
                $hashNavisionLogin
                $hashWSLogin
                $N1111
                $WSLogin_back
                $WSLogin_front
                $intraUrl
                $serverTest
                $WSLogin_nav
                $ftp_dir_In
                $ftp_dir_TJQ
                $cds_hours
                $LogMonitoringFile
                $hMarket
                $GetBookingFormOfPayment_errors
                $nav_task
                $tssURL
                $urlToken
                $authorizationToken
                $authToken
                $crypticURL
                $configServiceURL
                $fbsTicketingURL
                $claimURL
                $tssBookingsURL
                $quality_control_serviceURL
                );

no warnings;

     $mauiURL = 'https://wwwegenciacom.int-maui.sb.karmalab.net/';
#$mauiURLforRAIL = 'https://cheijvgect001.karmalab.net:9843/';
	
     $mauiURLforRAIL = 'http://wwwegenciaeu.int-maui.sb.karmalab.net/';

     $tssBookingsURL = $mauiURLforRAIL.'train-supply-service/v1/bookings';

     $claimURL = $mauiURLforRAIL.'train-supply-service/v2/bookings/';

     $configServiceURL = $mauiURL.'config-service/v2/configs/';

     $fbsTicketingURL = $mauiURL.'flight-booking-service/v1/ticketing/';

# ________________________________________________________________
# # # TSS Params
#
    $tssURL = $mauiURLforRAIL.'train-supply-service/v2/bookings/';

# Auth
$urlToken = $mauiURL.'auth-service/v1/tokens/client-credentials';
$authorizationToken = 'ZGVmYTY3ZmYtYmJkNy00YzgxLTk0NzEtMDU0NWUwOGJlYjg0OnpxRktpRFF0Nm5YbkNheUdaM3gySXlmQzhyc01ZT2dp';
$authToken = undef;

    $crypticURL = 'https://wwwegenciacom.int-maui.sb.karmalab.net/amadeus-cryptic-service/v1/execute';
    $quality_control_serviceURL = $mauiURL.'quality-control-service/';

# ________________________________________________________________
# L'objet courant de connexion aux bases de données
$cnxMgr = undef;
# ________________________________________________________________

# ________________________________________________________________
# Variable pour FTP 
$ftp_dir_In  ='/var/egencia/www_';
$ftp_dir_TJQ = '/var/egencia/www_';
# ________________________________________________________________
# Structure liée au context request pour SOAP
$h_context = {
  'language'     => 'FR',
  'userAgent'    => 'MidOffice',
  'application'  => 'RTL'
};
# ________________________________________________________________

# ________________________________________________________________
# Chemin vers les templates "Template Toolkit"
$templatesPath   = '../libsperl/Expedia/XML/Templates/';
# ________________________________________________________________

$N1111 = 'N1111';

# ________________________________________________________________
# Emplacement des fichiers de log & Fichier de log par défaut si aucun n'a été spécifié
$logPath         = '/var/egencia/logs/midbot/';
$defaultLogFile  = 'DEFAULT';
$LogMonitoringFile = 'MONITORING'; 
# ________________________________________________________________

# ________________________________________________________________
# Répertoires utilisés pour toutes les génération de rapports
$reportPath      = './RAPPORTS/';
# ________________________________________________________________

# _____________________________________________________________________
# URL et Titre
$intraUrl        = 'http://10.208.91.9/';
# _____________________________________________________________________

# SERVER FOR TEST
$serverTest = 'http://10.208.91.9/';

# ________________________________________________________________
# Card Codes
$cardCodes = {
  'DOM'   => '382',
  'DOMAF' => '385',
};
# ________________________________________________________________

# ________________________________________________________________
# Cards Types
$cardTypes = {
  'subscription' => 'SC',
  'loyalty'			 => 'LC',
};
# ________________________________________________________________

# ________________________________________________________________
# Les mois dans AMADEUS
$h_AmaMonths = {
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
# ________________________________________________________________

# ________________________________________________________________
# Association du nom de la tâche et du 'Processor' à utiliser
$h_processors   = {
 'btc-air-'                  => 'airProcessor',
 'btc-car-'                  => 'carProcessor',
 'btc-rail'                  => 'gldProcessor',
 'btc-emd'                   => 'comProcessor',
 'rail-errors'               => 'comProcessor',
 'tas-finish-'               => 'tfnProcessor',
 'tas-report-'               => 'trpProcessor',
 'tas-stats-'                => 'tstProcessor',  
 'tas-'                      => 'tasProcessor',
 'synchro-'                  => 'synProcessor',
 'workflow-'                 => 'flwProcessor',
 'tracking-'                 => 'trkProcessor',
 'queuing'                   => 'queProcessor',
 'air-queue-'                => 'aiQProcessor',
 'air-queue-error-handling'  => 'ahaProcessor',
 'launcher'                  => 'lchProcessor', 
 'tjq-'                      => 'tjqProcessor', 
};
# ________________________________________________________________

# ________________________________________________________________
# Association du nom de la tâche et de la durée maximale
#  de traitement en secondes. Relatif à ProcessManager.pm test
$h_maxProcDuration   = {
 'btc-air-'                  => 900,
 'btc-car-'                  => 900,
 'btc-rail'                  => 3600,
 'btc-emd'                   => 6000,
 'rail-errors'               => 900,
 'tas-finish-'               => 3600,
 'tas-report-'               => 600,
 'tas-stats-'                => 600,  
 'tas-'                      => 10800,
 'synchro-'                  => 7200,
 'workflow-'                 => 1800,
 'tracking-'                 => 900,
 'queuing'                   => 900,
 'air-queue-'                => 3600,
 'air-queue-error-handling'  => 3600,
 'launcher'                  => 900,
 'tjq-'                      => 600, 
};
# _____________________________________________________________

# Pour l'appel aux WebServices Front et Back Office
#$proxyFront    = 'http://wsprod.expediacorporate.eu:8080/internal/'; 
#$proxyFront    =  'http://CHEIBATECT001:8080/internal';              
##$proxyFront    =  'http://TESTcheibatect001.karmalab.net:8080/internal/';
$proxyFront    =  'http://cheiwbtect001.karmalab.net:8080/internal/';                                                                      
##$proxyFront    =  'http://cheibatect001.karmalab.net:8080/internal/';                                                                      
##$proxyBack     = 'https://cce-wss.expediacorporate.eu:8004';         
##$proxyBack     = 'https://ccewss-test.lab.sb.karmalab.net:443';
##$proxyBack     = 'http://phel082a9e6d5c3.karmalab.net:4040/wss.asmx';
##$proxyBack = 'https://ccewss-test.lab.sb.karmalab.net/?WSDL';
$proxyBack = 'https://ccewss.int-maui.sb.karmalab.net/wss.asmx?WSDL';
#$proxyBack = 'https://ccewss.int-milan.sb.karmalab.net/wss.asmx?WSDL';
##$proxyBackBis  = 'https://cce-wss2.expediacorporate.eu:8004';         
##$proxyBackBis  = 'https://ccs-wss-test2.expediacorporate.eu:450';   
##$proxyBackBis  = 'http://phel082a9e6d5c3.karmalab.net:4040/wss.asmx';   
##$proxyBackBis  = 'https://ccewss-test.lab.sb.karmalab.net/?WSDL';   
$proxyBackBis  = 'https://ccewss.int-maui.sb.karmalab.net/wss.asmx?WSDL';   
#
$proxyNav        = 'https://navws.int-maui.sb.karmalab.net/NavWebService.asmx?WSDL';   
$proxyNav_intra  = 'http://navws-prd:7047/';   
# 
 $proxyAustralia = 'https://chsxwbsectau001.idx.expedmz.com/Commission.asmx'; 
# # _______________________________________________________________
#
# # ______________________________________________________________
#
 $WSLogin_back = 's-egeccemid-test';
 $WSLogin_nav  = 's-sqlsvc-nav';
# #$WSLogin_nav  = 'svc_dnav_fo_test';
 $WSLogin_front= 'BTC_TAS';
#
 $hashWSLogin = {
     's-egeccemid-test'  =>  'nuC3Se5ujUyE2usp',
         's-sqlsvc-nav'  =>  'JUdr2BRapreP48Ru',
             'svc_dnav_fo_test' => 'Mcs1ap,tesb1f.'
             };

             $hashNavisionLogin = {
                 'Kettle'  =>  'k0t6_',
                     'navupgrd'  =>  'grd0_'
                     };


                     # Configuration SMTP pour l'envoi d'emails
                     $sendmailProtocol = 'smtp';
                     $sendmailIP       = 'Chelsmtp01.karmalab.net';
                     $sendmailTimeout  =  60; # secondes

# _______________________________________________________________
# _______________________________________________________________

# _______________________________________________________________
# Correspondance "Civilité" et "Sexe" M = Masculin, F = Féminin
$h_titleSex = {
  'Mr'             => 'M',
  'Mrs'            => 'F',
  'Miss'           => 'F',
  'Ms'             => 'F',
  'Mr. Dr'         => 'M',
  'Dr Mr'          => 'M',
  'Dr Mrs'         => 'F',
  'Mr. Prof.'      => 'M',
  'Prof Mr'        => 'M',
  'Master'         => 'M',
  'Lady'           => 'F',
  'Lord'           => 'M',
  'Sir'            => 'M',
  'Mr. Dr. Prof.'  => 'M',
  'Prof Dr Mr'     => 'M',
  'Mrs. Dr.'       => 'F',
  'Mrs. Prof.'     => 'F',
  'Prof Mrs'       => 'F',
  'Mrs. Dr. Prof.' => 'F',
  'Prof Dr Mrs'    => 'F',
  'Dr Ms'          => 'F',
  'Ms. Dr.'        => 'F',
  'Ms. Prof.'      => 'F',
  'Prof Ms'        => 'F',
  'Ms. Dr. Prof.'  => 'F',
};
# _______________________________________________________________

# _______________________________________________________________
# Correspondance Civilité XML et Correspondance en Amadeus
$h_titleToAmadeus = {
  'Mr'             => 'MR',
  'Mrs'            => 'MRS',
  'Miss'           => 'MISS',
  'Ms'             => 'MS',
  'Mr. Dr'         => 'DR MR',
  'Dr Mr'          => 'DR MR',
  'Dr Mrs'         => 'DR MRS',
  'Mr. Prof.'      => 'PROF MR',
  'Prof Mr'        => 'PROF MR',
  'Master'         => 'MASTER',
  'Lady'           => 'LADY',
  'Lord'           => 'LORD',
  'Sir'            => 'SIR',
  'Mr. Dr. Prof.'  => 'PROF DR MR',
  'Prof Dr Mr'     => 'PROF DR MR',
  'Mrs. Dr.'       => 'DR MRS',
  'Mrs. Prof.'     => 'PROF MRS',
  'Prof Mrs'       => 'PROF MRS',  
  'Mrs. Dr. Prof.' => 'PROF DR MRS',
  'Prof Dr Mrs'    => 'PROF DR MRS',
  'Dr Ms' 		   => 'DR MS',
  'Ms. Dr.'        => 'DR MS',
  'Ms. Prof.'      => 'PROF MS',
  'Prof Ms'        => 'PROF MS',
  'Ms. Dr. Prof.'  => 'PROF DR MS',
};
# _______________________________________________________________

# _______________________________________________________________
# Utilisé pour les moyens de paiement lorsque c'est CC = Credit Card
$h_creditCardTypes = {
  'Visa'              => 'VI',
  'Mastercard'        => 'CA', # Eurocard/Mastercard
  'American Express'  => 'AX',
  'Diners'            => 'DC',
  'Airplus'           => 'TP',
  'Switch'            => 'SW',
  'Maestro'           => 'SW',
  'En Route'          => 'EN',
  'Discover'          => 'DC',
  'BankCard'          => 'CB',
};
# _______________________________________________________________

# _______________________________________________________________
# Utilisé pour gérer les erreurs SOAP & Appels à changeDeliveryState
$soapRetry    = undef;
$soapProblems = undef;
$cds_hours =-6; # for cds_retry.pl (negative number)
# _______________________________________________________________

# _______________________________________________________________
# BTC-TRAIN paramétrage des Queues par défaut
$btcTrainDefaultGdsQueue  = 'PAREC38DD/62C0';
$btcTrainNormalCategory   = 10;
$btcTrainApprovalCategory = 11;
# _______________________________________________________________

# _______________________________________________________________
# Utilisé pour TAS. Associe le num de TTP au premier AirlineCode
$h_tstNumFstAcCode = {}; 
# _______________________________________________________________

# _______________________________________________________________
# Chargement unitaire des applications
$h_appIds = {}; 
# _______________________________________________________________

# _______________________________________________________________
# Utilisé pour TAS. Chargement unitaire des codes erreur TAS
$h_tasMessages = {}; 
# _______________________________________________________________

# _______________________________________________________________
# Utilisé pour WBMI. Chargement unitaire des codes erreur WBMI
$h_wbmiMessages = {}; 
# _______________________________________________________________

# _______________________________________________________________
# Utilisé dans l'insertion des FV dans les bookings et TAS
$h_fvMapping = {
  'FR' => { 'KL' => 'AF', 'NW' => 'AF', 'KQ' => 'AF', 'MP' => 'AF', 'A5' => 'AF', 'AE' => 'BR', 'KA' => 'CX', 'NE' => 'HR', 'XK' => 'AF' },
  'BE' => { 'UX' => 'IB', 'JK' => 'SK', 'AE' => 'BR', 'KA' => 'CX', 'NE' => 'HR', },
  'GB' => { 'AE' => 'BR', 'KA' => 'CX', 'NE' => 'HR', },
  'DE' => { 'GR' => 'BA', 'AE' => 'BR', 'KA' => 'CX', 'NW' => 'KL', 'NE' => 'HR', },
};
# ________________________________________________________________

# ________________________________________________________________
# Utilisé pour l'insertion des commissions
$h_pcc = {
  'AU' => '0GI6',
  'HK' => 'HK',
  'NZ' => 'NZ',
  'SG' => 'SG'
};
# ________________________________________________________________

# ________________________________________________________________
# Liste des status des lightweightdossiers connus.
$h_statusCodes = {
  'R' => 'Brouillon',
  'V' => 'Réservé',
  'Q' => "En attente d'approbation",
  'J' => "Rejeté par l'approbateur",
  'H' => 'Caché',
  'C' => 'Annulé',
  'T' => 'Voyagé',
  'D' => 'Supprimé',
  'P' => 'Pending',
};
# ________________________________________________________________

# ________________________________________________________________
# Utilisé dans la retarification. Agency Fares Code (TARIF_EXPEDIA)
$h_tarifExpedia = {
  'FR' => { 'AF' => '000774',
            'KL' => '008885', 'AM' => '008885', 'UU' => '008885', 'AP' => '008885',
            'TN' => '008885', 'PS' => '008885', 'NH' => '008885', 'AA' => '008885',
            'OS' => '008885', 'CX' => '008885', 'OK' => '008885', 'DL' => '008885',
            'EK' => '008885', 'EY' => '008885', 'IB' => '008885', 'LO' => '008885',
            'QR' => '008885', 'AT' => '008885', 'RJ' => '008885', 'SV' => '008885',
            'SQ' => '008885', 'LX' => '008885', 'TK' => '008885', 'LA' => '008885',
            'TG' => '003082',           
          },
  'BE' => { 'IB' => '018480' },
  'DE' => { 'BA' => '060356' },
};
# ________________________________________________________________

# ________________________________________________________________
# COMCODE A CONSIDERER COMME COMPAGNIE DE TEST ( POUR BTC-DEV) 
# ________________________________________________________________
$dummy = '';


### Mapping table  "Agency => POS" for TAS
$hMarket = {
        'Paris'                 => 'FR',
        'Manchester'    => 'GB',
        'Munchen'               => 'DE',
        'Bruxelles'     => 'BE',
        'Milan'                 => 'IT',
        'Barcelona'             => 'ES',
        'Dublin'            => 'IE',
        'Amsterdam'             => 'NL',
        'Zurich'                => 'CH',
        'Stockholm'     => 'SE',
        'Sydney'            => 'AU',
        'Delhi'                 => 'IN',
        'Varsovie'      => 'PL',
        'Prague'                => 'CZ',
        'Istanbul'              => 'TR',
        'Copenhague'    => 'DK',
        'Helsinki'              => 'FI',
        'Oslo'                  => 'NO',
        'Hongkong'              => 'HK',
        'Singapour'     => 'SG',
        'Manille'               => 'PH'
};

### Stockage des erreurs lors de l'appel au WS BO_GetBookingFormOfPayment
$GetBookingFormOfPayment_errors=undef;


#EGE-97536 : task qui necessitent une connexion à NAV
$nav_task = ['air-queue','tracking','queuing','workflow'];

#use warnings;

1;
