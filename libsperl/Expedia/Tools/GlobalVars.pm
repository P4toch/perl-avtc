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

# ________________________________________________________________

	$EGE_URL = 'https://www.egencia.com/';

    $tssBookingsURL = $EGE_URL.'train-supply-service/v1/bookings';

    $claimURL = $EGE_URL.'train-supply-service/v2/bookings/';

	$configServiceURL = $EGE_URL.'config-service/v2/configs/';

	$fbsTicketingURL = $EGE_URL.'flight-booking-service/v1/ticketing/';


# # TSS Params

	$tssURL = $EGE_URL.'train-supply-service/v2/bookings/';

# Auth
$urlToken = $EGE_URL.'auth-service/v1/tokens/client-credentials';
$authorizationToken = 'YTRmN2U4OTMtYjk3My00NDg2LTgzY2EtY2M5Nzg0YjZiZWU2OmF5bTA3Z1FFc0duMlJVYmxYY2RNWlpmcUZuRzVhZkVP';
$authToken = undef;

    $crypticURL = $EGE_URL.'amadeus-cryptic-service/v1/execute';

	## quality-control-service 
	$quality_control_serviceURL = $EGE_URL.'quality-control-service/';
	
# ________________________________________________________________
# L'objet courant de connexion aux bases de donn�es
$cnxMgr = undef;
# ________________________________________________________________

# ________________________________________________________________
# Variable pour FTP 
$ftp_dir_In='/www_fileridx_In/';
$ftp_dir_TJQ='/www_fileridx_TJQ/';
# ________________________________________________________________
# Structure li�e au context request pour SOAP
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
# Emplacement des fichiers de log & Fichier de log par d�faut si aucun n'a �t� sp�cifi�
$logPath         = '/var/egencia/logs/midbots/';
$defaultLogFile  = 'DEFAULT';
$LogMonitoringFile = 'MONITORING'; 
# ________________________________________________________________

# ________________________________________________________________
# R�pertoires utilis�s pour toutes les g�n�ration de rapports
$reportPath      = './RAPPORTS/';
# ________________________________________________________________

# _____________________________________________________________________
# URL et Titre
$intraUrl        = 'https://tas.eu.expeso.com/';
$serverTest		=  'https://tas.eu.expeso.com/';
# _____________________________________________________________________

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
# Association du nom de la t�che et du 'Processor' � utiliser
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
# Association du nom de la t�che et de la dur�e maximale
#  de traitement en secondes. Relatif � ProcessManager.pm test
$h_maxProcDuration   = {
 'btc-air-'                  => 900,
 'btc-car-'                  => 900,
 'btc-rail'                  => 3600,
 'btc-emd'                   => 60,
 'rail-errors'               => 900,
 'tas-finish-'               => 3600,
 'tas-report-'               => 600,
 'tas-stats-'                => 600,  
 'tas-'                      => 10800,
 'synchro-'                  => 7200,
 'workflow-'                 => 10800,
 'tracking-'                 => 900,
 'queuing'                   => 900,
 'air-queue-'                => 3600,
 'air-queue-error-handling'  => 3600,
 'launcher'                  => 900,
 'tjq-'                      => 600, 
};
# ________________________________________________________________

# ________________________________________________________________
# Pour l'appel aux WebServices Front et Back Office
$proxyFront     = 'http://wsprod.eu.expeso.com/internal/';              
                                                                      
$proxyBack      = 'https://cce-wss.eu.expeso.com:8004/wss.asmx';  
$proxyBackBis   = 'https://cce-wss.eu.expeso.com:8004/wss.asmx'; 

$proxyNav       =   'https://navws.eu.expeso.com:7047';
$proxyNav_intra =  'http://navws-prd:7047/';
 
$proxyAustralia = 'https://chsxwbsectau001.idx.expedmz.com/Commission.asmx';
# ________________________________________________________________

# ______________________________________________________________

$WSLogin_back  = 's-egeccemid';
$WSLogin_front = 'BTC_TAS';
$WSLogin_nav = 's-sqlsvc-nav'; 

$hashWSLogin = {
    's-egeccemid'  =>  '7LAR/MFHvO/=Z=Lc',
    's-sqlsvc-nav' =>  'dQpa9VLEfTpszR2'
};

$hashNavisionLogin = {
    's-sql-ketbo'  =>  'R@bCb3510',
    's-sql-navup'  =>  'R@bCb3512'
};


# Configuration SMTP pour l'envoi d'emails
$sendmailProtocol = 'smtp';
$sendmailIP       = 'phsmtp.expeso.com';
$sendmailTimeout  =  60; # secondes
# ________________________________________________________________

# ________________________________________________________________
# Correspondance "Civilit�" et "Sexe" M = Masculin, F = F�minin
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
# ________________________________________________________________

# ________________________________________________________________
# Correspondance Civilit� XML et Correspondance en Amadeus
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
# ________________________________________________________________

# ________________________________________________________________
# Utilis� pour les moyens de paiement lorsque c'est CC = Credit Card
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
# ________________________________________________________________

# ________________________________________________________________
# Utilis� pour g�rer les erreurs SOAP & Appels � changeDeliveryState
$soapRetry    = undef;
$soapProblems = undef;
$cds_hours =-6; # for cds_retry.pl (negative number)
# ________________________________________________________________

# ________________________________________________________________
# BTC-TRAIN param�trage des Queues par d�faut
$btcTrainDefaultGdsQueue  = 'PAREC38DD/62C0';
$btcTrainNormalCategory   = 10;
$btcTrainApprovalCategory = 11;
# ________________________________________________________________

# ________________________________________________________________
# Utilis� pour TAS. Associe le num de TTP au premier AirlineCode
$h_tstNumFstAcCode = {}; 
# ________________________________________________________________

# ________________________________________________________________
# Chargement unitaire des applications
$h_appIds = {}; 
# ________________________________________________________________

# ________________________________________________________________
# Utilis� pour TAS. Chargement unitaire des codes erreur TAS
$h_tasMessages = {}; 
# ________________________________________________________________

# ________________________________________________________________
# Utilis� pour WBMI. Chargement unitaire des codes erreur WBMI
$h_wbmiMessages = {}; 
# ________________________________________________________________

# ________________________________________________________________
# Utilis� dans l'insertion des FV dans les bookings et TAS
$h_fvMapping = {
  'FR' => { 'KL' => 'AF', 'NW' => 'AF', 'KQ' => 'AF', 'MP' => 'AF', 'A5' => 'AF', 'AE' => 'BR', 'KA' => 'CX', 'NE' => 'HR', 'XK' => 'AF' },
  'BE' => { 'UX' => 'IB', 'JK' => 'SK', 'AE' => 'BR', 'KA' => 'CX', 'NE' => 'HR', },
  'GB' => { 'AE' => 'BR', 'KA' => 'CX', 'NE' => 'HR', },
  'DE' => { 'GR' => 'BA', 'AE' => 'BR', 'KA' => 'CX', 'NW' => 'KL', 'NE' => 'HR', },
};
# ________________________________________________________________

# ________________________________________________________________
# Utilis� pour l'insertion des commissions
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
# Utilis� dans la retarification. Agency Fares Code (TARIF_EXPEDIA)
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
$dummy = '2,2006,5311,140,2305,5387,5388,964,5378,5379,1027,5402,4703,6233,500156,6251,2034,500068,7747,500318,500317,6250';


### Mapping table  "Agency => POS" for TAS
$hMarket = {
        'Paris'                 => 'FR',
        'Manchester'    		=> 'GB',
        'Munchen'               => 'DE',
        'Bruxelles'     		=> 'BE',
        'Milan'                 => 'IT',
        'Barcelona'             => 'ES',
        'Dublin'            	=> 'IE',
        'Amsterdam'             => 'NL',
        'Zurich'                => 'CH',
        'Stockholm'     		=> 'SE',
        'Sydney'            	=> 'AU',
        'Delhi'                 => 'IN',
        'Varsovie'      		=> 'PL',
        'Prague'                => 'CZ',
        'Istanbul'              => 'TR',
        'Copenhague'    		=> 'DK',
        'Helsinki'              => 'FI',
        'Oslo'                  => 'NO',
        'Hongkong'              => 'HK',
        'Singapour'     		=> 'SG',
        'Manille'               => 'PH',
		'Auckland'              => 'NZ',
		'Johannesburg'          => 'ZA',
		'Dubai'            	    => 'AE'
};

### Stockage des erreurs lors de l'appel au WS BO_GetBookingFormOfPayment
$GetBookingFormOfPayment_errors=undef;


#EGE-97536 : task qui necessitent une connexion � NAV
$nav_task = ['air-queue','tracking','queuing','workflow'];

#use warnings;

1;
