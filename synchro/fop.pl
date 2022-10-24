#!/usr/bin/perl -w
#-----------------------------------------------------------------
# Batch fop.pl
#
# $Id: fop.pl 664 2011-04-13 09:38:50Z pbressan $
#
# (c) 2002-2010 Expedia.                            www.egencia.eu
#-----------------------------------------------------------------

use strict;
use Data::Dumper;
use Getopt::Long;

use lib '../libsperl';

use Expedia::XML::Config;
use Expedia::XML::MsgGenerator;
use Expedia::GDS::Profile;
use Expedia::WS::Back                  qw(&ECTEGetUserBookingPaymentRQ &ECTEGetUserPaymentTypeRQ);
use Expedia::Tools::Logger             qw(&debug &notice &warning &error);
use Expedia::Tools::GlobalVars         qw($cnxMgr $h_context $h_fpec);
use Expedia::Tools::GlobalFuncs        qw(&stringGdsOthers);
use Expedia::Workflow::TasksProcessor;
use Expedia::Databases::MidSchemaFuncs qw(&isInAmadeusSynchro);

my $opt_comcode;
my $opt_percode;
my $opt_help;

GetOptions(
  'comcode=i',  \$opt_comcode,
  'percode=i',  \$opt_percode,
  'help',       \$opt_help,
);

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# La notion de marché est obligatoire
if ((!$opt_comcode || $opt_comcode !~ /^\d+$/) &&
    (!$opt_percode || $opt_percode !~ /^\d+$/)) {
  $opt_help = 1;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Affichage de l'aide
if ($opt_help) {
  print STDERR ("\nUsage: $0 --comcode=123 or --percode=456 or --help\n\n");
  exit(0);
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

my $config = Expedia::XML::Config->new('config.xml');

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Récupération du marché relatif à une société
my $opt_mrkt = '';
   $opt_mrkt = _getMarketFromComCode($opt_comcode) if ($opt_comcode);
   $opt_mrkt = _getMarketFromPerCode($opt_percode) if ($opt_percode);
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

my $GDS = $cnxMgr->getConnectionByName('amadeus-'.$opt_mrkt);
   $GDS->connect;
   
my $compteur = 0;

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Récupération des utilisateurs d'une société donnée
my $comCode = $opt_comcode                     if ($opt_comcode);
   $comCode = _getUserComCode($opt_percode)    if ($opt_percode);
  
notice('@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@');
notice('Récupération des PerCodes des Users à traiter.');
my $perCodes = [];
   $perCodes = _getUsersFromComCode($comCode)  if ($comCode);
   $perCodes = [ { PerCode => $opt_percode } ] if ($opt_percode);
   
notice('   Nombre de Users = '.(scalar @$perCodes));
notice('Filtrage des PerCodes à traiter');
$perCodes   = _perCodesFilter($perCodes);
my $nbUsers =  scalar @$perCodes;
notice('   Nombre de Users = '.$nbUsers);

foreach (@$perCodes) {
  
  $compteur++;
  
  if ($compteur % 100 == 0) { $GDS->disconnect; $GDS->connect; }
  
  my $perCode = $_->{PerCode};
  my $amadId  = $_->{Amadeus};

  notice('~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~');
  notice(" PERCODE = '$perCode' - AMADEUS = '$amadId' - ($compteur/$nbUsers)");
  notice('~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~');
  _userUpdFop({
    PerCode => $perCode,
    ComCode => $comCode,
    Market  => $opt_mrkt,
    GDS     => $GDS,
    Amadeus => $amadId });
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

$GDS->disconnect;

notice('@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@');












# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Récupération de tous les ComCodes relatifs à un Marché donné
sub _getComCodesFromMarket {
  my $market = shift || undef;
  
  if (!defined $market) {
    error('Missing or wrong parameter for this method.');
    return 0;
  }
  
  my $midDB = $cnxMgr->getConnectionByName('mid');
  
  my $query = '
    SELECT C.CODE, C.NAME
      FROM COMP_COMPANY C, OPST_POS O
     WHERE C.IS_ACTIVE = 1
       AND C.IS_TEST_USE = 0
       AND C.IS_COMMERCIAL_USE = 1
       AND C.OPST_POS_ID = O.ID
       AND O.CODE = ?
  ORDER BY C.CODE ASC ';

  my $res = $midDB->saarBind($query, [$market]);
  
  my $comcodes = [];

  push (@$comcodes, { ComCode => $_->[0], ComName => $_->[1] }) foreach (@$res); 
  
  return $comcodes;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Récupération de tous les PerCodes depuis un comCode donné
sub _getUsersFromComCode {
  my $comCode = shift || undef;
  
  if (!defined $comCode) {
    error('Missing or wrong parameter for this method.');
    return 0;
  }
  
  my $midDB = $cnxMgr->getConnectionByName('mid');
  
  my $query = '
    SELECT U.CODE
      FROM USER_USER U, COMP_COMPANY C
     WHERE C.CODE      = ?
       AND C.ID        = U.COMPANY_ID
       AND U.IS_ACTIVE = 1 ';

  my $res = $midDB->saarBind($query, [$comCode]);
  
  my $users = [];

  push (@$users, { PerCode => $_->[0] }) foreach (@$res); 
  
  return $users;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
sub _perCodesFilter {
  my $perCodes = shift;
  
  my $results  = [];
	my $toCreate = [];
  
  foreach (@$perCodes) {
    my $perCode =  $_->{PerCode};
    next unless $perCode;
    my $asItem  =  isInAmadeusSynchro({CODE => $perCode, TYPE => 'USER'});
    if (scalar @$asItem == 1) {
      push @$results, { PerCode => $perCode,
                        Amadeus => $asItem->[0][2] }; 
    } else {
			push @$toCreate, $perCode;
	  }
  }

	notice('PerCodes Missing = '.Dumper($toCreate)) if (scalar(@$toCreate) > 0);
  
  return $results;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Mise à jour des moyens de paiement d'un traveller
sub _userUpdFop {
  my $params = shift;

  my $amadId  = $params->{Amadeus};
  my $GDS     = $params->{GDS};
  my $perCode = $params->{PerCode};
  my $market  = $params->{Market};
  my $comCode = $params->{ComCode};
  
  debug('perCode = '.$perCode);
  debug('comCode = '.$comCode);
  debug('market  = '.$market);
  
	# Structure contenant les données à ajouter et à supprimer
	my @add = ();
	my @del = ();
	
	# ---------------------------------------------------------------------
  # Ouverture du Profil
  my $profile = Expedia::GDS::Profile->new(
                  PNR  => $amadId,
                  GDS  => $GDS,
                  TYPE => 'T');
  return 0 unless defined $profile;
  
  
  # Suppression des lignes de Payment Means
	foreach (@{$profile->{PnrTrData}}) {
	  push @del, $_->{LineNo} if ($_->{Data} =~ /^RM\s*PLEASE ASK FOR CREDIT CARD/);
	  push @del, $_->{LineNo} if ($_->{Data} =~ /^FP\s*CC/);
	  push @del, $_->{LineNo} if ($_->{Data} =~ /^FP\s*O\//);
	  push @del, $_->{LineNo} if ($_->{Data} =~ /^FP\s*NONREF/);
	  push @del, $_->{LineNo} if ($_->{Data} =~ /^FP\s*INVOICE/);
	  push @del, $_->{LineNo} if ($_->{Data} =~ /^FP\s*EC/);
	  push @del, $_->{LineNo} if ($_->{Data} =~ /^FP\s*CASH/);
	  push @del, $_->{LineNo} if ($_->{Data} =~ /^RC\s*CC\s*HOTEL\s*ONLY/);
	}
  # ---------------------------------------------------------------------
  
  # ---------------------------------------------------------------------
  # Récupération des moyens de paiement mis à jour
# SERVICE: foreach my $service ('AIR', 'HOTEL') { # Désactivation pour PCI-DSS, 08 OCT 2010
  SERVICE: foreach my $service ('AIR') { 
    next SERVICE unless (($service =~ /^AIR$/) ||
                        (($service =~ /^HOTEL$/) && ($market eq 'GB')));
    debug("SERVICE => [$service]");
    my $oMsg = Expedia::XML::MsgGenerator->new({
                 context		   => $h_context,
                 comCode       => $comCode,
                 perCode       => $perCode,
								 service       => $service,
								 billingEntity => [],
               }, 'ECTEGetUserPaymentTypeRQ.tmpl');
    my $msg    = $oMsg->getMessage;
    debug('ECTEGetUserPaymentTypeRQ = '.$msg);
    my $hDatas = ECTEGetUserPaymentTypeRQ('BackWebService', { message => $msg });
    next SERVICE if ((!defined $hDatas)                ||
                     (!defined $hDatas->{PaymentType}) ||
                     ($hDatas->{PaymentType} !~ /^(CC|EC)$/));
    next SERVICE if  ($hDatas->{PaymentType} =~ /^EC$/ && ($service =~ /^HOTEL$/));
    if ($hDatas->{PaymentType} =~ /^EC$/ && ($service =~ /^AIR$/)) {
      push (@add, { 'Data' => $h_fpec->{ $market }, 'TrIndicator' => 'A'});
      next SERVICE;
    }
    if ($hDatas->{PaymentType} =~ /^CC$/) {
      my $amadeusMsg = _getDatasFromServiceAndPaymentTypeFop({ paymentType => 'CC',
			       	 																			    			 service     => $service,
			       	 																			    			 market      => $market,
																											         perCode     => $perCode,
																											         comCode     => $comCode, });
      if (scalar(@$amadeusMsg) > 0) {
        push (@add, { 'Data' => $_, 'TrIndicator' => 'A'}) foreach (@$amadeusMsg);
      }
      next SERVICE;
    }
  }  
  # ---------------------------------------------------------------------
  
  my $res = $profile->update(add => \@add, del => \@del, NoGet => 1);
  
  notice("Form of Payment in '$amadId' updated.") if ($res);
  
  return 1; 
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Méthode de récupération des moyens de paiement
#   dans le cadre de UPDATE_FOP [...]
sub _getDatasFromServiceAndPaymentTypeFop {
	my $params = shift;
	
	my $paymentType  = $params->{paymentType};
	my $service			 = $params->{service};
	my $market  		 = $params->{market};
	my $perCode  		 = $params->{perCode};
	my $comCode  		 = $params->{comCode};
	my $billId       = $params->{billId};

	if (($paymentType =~ /^EC$/)          && ($service =~ /^AIR$/)) {
	  return [$h_fpec->{$market}]; 
	} 
	if (($paymentType =~ /^(ICCR|OOCC)$/) && ($service =~ /^AIR$/)) {
    return ['RM PLEASE ASK FOR CREDIT CARD'];
	} 
	if ($paymentType =~ /^CC$/) {
    my $billingEntity = [ {code => 'CC1', value => '__DEFAULT__'} ];
    my $oMsg = Expedia::XML::MsgGenerator->new({
                 context		   => $h_context,
                 comCode       => $comCode,
                 perCode       => $perCode,
								 service       => $service,
								 billingEntity => $billingEntity,
               }, 'ECTEGetUserBookingPaymentRQ.tmpl');
    my $msg    = $oMsg->getMessage();
    debug("ECTEGetUserBookingPaymentRQ = \n".$msg);
		my $hDatas = ECTEGetUserBookingPaymentRQ('BackWebService', { message => $msg });
	
	  my $commonString  = undef;
	  my $datasToReturn = [];
	  
	  $commonString = $hDatas->{CardType}.$hDatas->{CardNumber}.'/'.$hDatas->{CardExpiry}
	    if ($hDatas->{CardType} && $hDatas->{CardNumber} && $hDatas->{CardExpiry});
	    
		if ($service =~ /^AIR$/) {
		  if (defined $commonString) {
			  my $endString = undef;
			  my $infos     = _getInfosOnPerCode($perCode);
			  if    ($hDatas->{CardOrigin} =~ /INDIV/) 	 { $endString = $infos->[2];                         }
			  elsif ($hDatas->{CardOrigin} =~ /COMPANY/) { $endString = $infos->[3];                         } 
			  elsif ($hDatas->{CardOrigin} =~ /ENTITY/ ) { $endString = _getBillingEntityLabel($infos->[4]); } 
			  else                                       { return ['RM PLEASE ASK FOR CREDIT CARD'];         }
			  push (@$datasToReturn, 'FP CC'.$commonString.'/- C'.$hDatas->{CardOrigin}.' -'.stringGdsOthers($endString));
			  push (@$datasToReturn, 'FPO/'.substr($h_fpec->{$market}, 2).'+/CC'.$commonString);
			}
			else {
			  return ['RM PLEASE ASK FOR CREDIT CARD'];
			}
		}
		# Désactivation pour PCI-DSS, 08 OCT 2010
		# elsif ($service =~ /^HOTEL$/) {	
		#   $commonString = '### UNDEFINED ###' unless (defined $commonString);
		#   push (@$datasToReturn, 'RC CC HOTEL ONLY '.$commonString);
		# }
		
		return $datasToReturn;
	};
	
	return [];
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Récupération des Infos depuis une info de "PerCode"
sub _getInfosOnPerCode {
  my $perCode = shift || undef;
  
  if (!defined $perCode) {
    error('Missing or wrong parameter for this method.');
    return 0;
  }
  
  my $midDB = $cnxMgr->getConnectionByName('mid');
  
  my $query = '
    SELECT U.COMPANY_ID, U.FIRSTNAME, U.LASTNAME, C.NAME, U.BILLING_ENTITY_ID
      FROM USER_USER U, COMP_COMPANY C
     WHERE U.CODE = ?
       AND C.ID   = U.COMPANY_ID ';

  return $midDB->saarBind($query, [$perCode])->[0];
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
sub _getBillingEntityLabel {
  my $billingEntityId = shift;
  
  if (!defined $billingEntityId) {
    error('Missing or wrong parameter for this method.');
    return 0;
  }
  
  my $midDB = $cnxMgr->getConnectionByName('mid');
  
  my $query = '
    SELECT LABEL_CODE
      FROM COMP_BILLING_ENTITY
     WHERE ID = ? ';

  return $midDB->saarBind($query, [$billingEntityId])->[0][0];
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Récupération du Marché depuis une info de "ComCode"
sub _getMarketFromComCode {
  my $comCode = shift || undef;
  
  if (!defined $comCode) {
    error('Missing or wrong parameter for this method.');
    return 0;
  }
  
  my $midDB = $cnxMgr->getConnectionByName('mid');
  
  my $query = '
    SELECT O.CODE
      FROM COMP_COMPANY C, OPST_POS O
     WHERE C.CODE = ?
       AND O.ID   = C.OPST_POS_ID ';

  return $midDB->saarBind($query, [$comCode])->[0][0];
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Récupération du Marché depuis une info de "PerCode"
sub _getMarketFromPerCode {
  my $perCode = shift || undef;
  
  if (!defined $perCode) {
    error('Missing or wrong parameter for this method.');
    return 0;
  }
  
  my $midDB = $cnxMgr->getConnectionByName('mid');
  
  my $query = '
    SELECT O.CODE
      FROM USER_USER U, COMP_COMPANY C, OPST_POS O
     WHERE U.CODE       = ?
       AND U.COMPANY_ID = C.ID
       AND O.ID         = C.OPST_POS_ID ';

  return $midDB->saarBind($query, [$perCode])->[0][0];
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Récupération du ComCode depuis une info de "PerCode"
sub _getUserComCode {
  my $perCode = shift || undef;
  
  if (!defined $perCode) {
    error('Missing or wrong parameter for this method.');
    return 0;
  }
  
  my $midDB = $cnxMgr->getConnectionByName('mid');
  
  my $query = '
       SELECT C.CODE
         FROM USER_USER U, COMP_COMPANY C
        WHERE U.CODE       = ?
          AND U.COMPANY_ID = C.ID ';

  return $midDB->saarBind($query, [$perCode])->[0][0];
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
