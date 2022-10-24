package Expedia::Databases::MidSchemaFuncs;
#-----------------------------------------------------------------
# Package Expedia::Databases::MidSchemaFuncs
#
# $Id: MidSchemaFuncs.pm 686 2011-04-21 12:33:02Z pbressan $
#
# (c) 2002-2008 Expedia.                   www.expediacorporate.fr
#-----------------------------------------------------------------

use Data::Dumper;
use Exporter 'import';

use Expedia::Tools::Logger qw(&debug &notice &warning &error);
use Expedia::Tools::GlobalVars qw($cnxMgr $h_processors $h_appIds);
use Expedia::Tools::GlobalFuncs        qw(&getNavisionConnForAllCountry &setNavisionConnection);

@EXPORT_OK = qw(&getHighWaterMark     &setHighWaterMark         &getAppId
                &isInMsgKnowledge     &insertIntoMsgKnowledge   &updateMsgKnowledge  &deleteMsgKnowledge
                &isInAmadeusSynchro   &insertIntoAmadeusSynchro                      &deleteFromAmadeusSynchro
                &getPnrIdFromDv2Pnr   &insertIntoDv2Pnr                              &deleteFromDv2Pnr
                &isIntoWorkTable      &insertIntoWorkTable      &updateWorkTableItem &lockWorkTableItem
                &btcAirProceed        &btcTrainProceed          &btcTasProceed
                &cleanItems           &unlockItems
                &getMarketFromComCode &getMarketFromPerCode     &getUsersFromComCode &getInfosOnPerCode
                &getBillingEntityLabel
                &getQInfosAllMarkets  &getQInfosForMarket       &getQInfosForComCode
                &updateTravellerTrackingNavisionDate   &getTravellerTrackingImplicatedComCodesForMarket &getUserComCode &getTZbycountry
                &getFpec &getNavCountrybycountry &getUpComCodebycountry &getCountrybyUpComCode
				&getTravellerTrackingImplicatedComCodesForMarket_new);

use strict;

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Recuperation de la version la plus haute dejà traitee
sub getHighWaterMark {
  my $appName = shift;

  return undef unless (defined $appName);

  debug('appName = '.$appName);

  my $midDB = $cnxMgr->getConnectionByName('mid');

  # -----------------------------------------------------------------
  # Requète pour connaitre à quelle "version" nous nous etions arretes.
  my $query = '
    SELECT MESSAGE_VERSION
      FROM HIGHWATERMARK
     WHERE APP_ID = (SELECT ID FROM APPLICATIONS WHERE NAME = ?) ';
  
  my $version = $midDB->saarBind($query, [$appName])->[0][0];
  debug('version = '.$version) if (defined $version);
  # -----------------------------------------------------------------
  
  return undef unless (defined $version);
  return $version;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Sauvegarde de la version la plus haute dejà traitee
sub setHighWaterMark {
  my $appName = shift;
  my $version = shift;
  
  return undef unless (defined $appName);
  
  debug('appName = '.$appName);
  debug('version = '.$version);
  
  my $midDB = $cnxMgr->getConnectionByName('mid');
  
  # -----------------------------------------------------------------
  # Requète pour sauvegarder la dernière "version" où nous nous etions arretes.
  my $query = "
    UPDATE HIGHWATERMARK
       SET MESSAGE_VERSION  = ?,
	       TIME 			= getdate() 
     WHERE APP_ID = (SELECT ID FROM APPLICATIONS WHERE NAME = ?) ";
  # -----------------------------------------------------------------
  
  my $rows = $midDB->doBind($query, [$version, $appName]);
  
  warning('Problem detected !') if ((!defined $rows) || ($rows != 1));
  
  return 0 unless ((defined $rows) && ($rows == 1));
  return 1;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Recuperation de l'identifiant correspondant à une taskName dans APPLICATIONS.
sub getAppId {
  my $appName = shift;
  
  return 0 unless (defined $appName);
  
  debug('appName = '.$appName);
  
  if (defined $h_appIds->{'empty'}) {
		return $h_appIds->{$appName} if exists $h_appIds->{$appName};
		return 0;
	}
	else {
    my $midDB = $cnxMgr->getConnectionByName('mid');

    my $query = 'SELECT NAME, ID FROM APPLICATIONS';
    my $res   = $midDB->saarBind($query, []);
    
    foreach (@$res) {
			$h_appIds->{$_->[0]} = $_->[1];
		}
		$h_appIds->{'tas-rail-etkt'} = 24;
    #debug('$h_appIds = '.Dumper($h_appIds)) if (defined $h_appIds);
  
		return $h_appIds->{$appName} if exists $h_appIds->{$appName};
	}
  
  return 0;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Un objet est-il dejà connu de la table MSG_KNOWLEDGE ?
#   On se base uniquement sur son CODE et son TYPE
sub isInMsgKnowledge {
  my $params = shift;
  
  my $code        = $params->{CODE} || undef;
  my $type        = $params->{TYPE} || undef;
  my $pnr         = $params->{PNR}  || undef;
	if ((!defined ($pnr)) && 
	  ((!defined $code) ||
		(!defined $type) || ($type !~ /^(AIR|TRAIN|USER|COMPANY)$/)) ) {
		error('Missing or wrong parameter for this method.');
		return undef;
	}
	
  my $midDB = $cnxMgr->getConnectionByName('mid');

    if(!defined($pnr))
    { 
      my $query = '
        SELECT MESSAGE_CODE, MESSAGE_VERSION, MESSAGE_TYPE,
						BTCAIR_PROCEED, BTCTRAIN_PROCEED, BTCTAS_PROCEED,
						TIME
          FROM MSG_KNOWLEDGE
         WHERE MESSAGE_CODE = ?
           AND MESSAGE_TYPE = ?  '; 
        
      return $midDB->saarBind($query, [$code, $type]);   
    } elsif (defined($pnr) && (!defined($code) || !defined($type))) {
        my $query = '
        SELECT MESSAGE_CODE, MESSAGE_VERSION, MESSAGE_TYPE,
						BTCAIR_PROCEED, BTCTRAIN_PROCEED, BTCTAS_PROCEED,
						TIME
          FROM MSG_KNOWLEDGE
         WHERE PNR = ? '; 
         return $midDB->saarBind($query, [$pnr]);   
    } else {
        my $query = '
        SELECT MESSAGE_CODE, MESSAGE_VERSION, MESSAGE_TYPE,
						BTCAIR_PROCEED, BTCTRAIN_PROCEED, BTCTAS_PROCEED,
						TIME
          FROM MSG_KNOWLEDGE
         WHERE MESSAGE_CODE = ?
           AND MESSAGE_TYPE = ? 
           AND PNR          = ? ';       
      return $midDB->saarBind($query, [$code, $type, $pnr]);   
    } 

}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Insertion d'un nouveau code de message dans la base de connaissance
sub insertIntoMsgKnowledge {
  my $params  = shift;
  
  my $code        = $params->{CODE}    || undef;
  my $version     = $params->{VERSION} || undef;
  my $type        = $params->{TYPE}    || undef;
  my $pnr         = $params->{PNR}     || undef;
  my $market      = $params->{MARKET}  || undef;
  my $aqhProceed  = $params->{AQHProceed} || undef;
  
  if (
     ( (!defined $pnr) && 
     ( (!defined $code) || (!defined $version)  || ($version !~ /\d+/) ) ) ||
     ( (!defined $type) || ($type !~ /^(AIR|TRAIN|USER|COMPANY)$/) )
     ) {
    error('Missing or wrong parameter for this method.');
    return 0;
  }
  

  my $midDB = $cnxMgr->getConnectionByName('mid');
   
  my $query='';
  my $rows;
  if ( (defined $code) && (defined $version) ) {
  	    $query = '
          INSERT INTO MSG_KNOWLEDGE (MESSAGE_CODE, MESSAGE_VERSION, MESSAGE_TYPE, PNR, MARKET)
          VALUES (?, ?, ?, ?, ?) ';
      $rows  = $midDB->doBind($query, [$code, $version, $type, $pnr, $market]);      
   } else {
      $query = '
          INSERT INTO MSG_KNOWLEDGE (MESSAGE_TYPE, PNR, MARKET, AQH_PROCEED)
          VALUES (?, ?, ?, ?) ';
      $rows  = $midDB->doBind($query, [ $type, $pnr, $market, $aqhProceed]);
   }
 
  
   warning('Problem detected !') if ((!defined $rows) || ($rows != 1));
  
   return 0 unless ((defined $rows) && ($rows == 1));
   return 1;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@


# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Mise à jour d'un message (VERSION) dans la base de connaissance
sub updateMsgKnowledge {
  my $params  = shift;
  
  my $code        = $params->{CODE}    || undef;
  my $version     = $params->{VERSION} || undef;
  my $type        = $params->{TYPE}    || undef;
  my $pnr         = $params->{PNR}     || undef;
  my $market      = $params->{MARKET}  || undef;
  my $aqhProceed  = $params->{AQHProceed} || 1;
   
  my $setMarket  = ",MARKET = '$market'" if defined($market);
  my $setAqhProceed  = ",AQH_PROCEED = $aqhProceed" if defined($aqhProceed);
  
  my $setMarket  = ",MARKET = '$market'" if defined($market);
    
  if ( ((!defined $pnr) && (!defined $code)) || 
   (!defined $type) || ($type !~ /^(AIR|TRAIN|USER|COMPANY)$/)) {
    error('Missing or wrong parameter for this method.');
    return 0;
  }
  
  my $rows = undef;
  my $midDB = $cnxMgr->getConnectionByName('mid');
  
  
  if ( defined($version)  &&  ($version =~ /\d+/) && defined($code) && !defined($pnr) ) {
  	 
    		my $query = '
      			UPDATE MSG_KNOWLEDGE
         		SET MESSAGE_VERSION = ?, TIME = GETDATE()
      			WHERE MESSAGE_CODE    = ?
         		AND MESSAGE_TYPE    = ?
           ';
         $rows  = $midDB->doBind($query, [$version, $code, $type]);
    
   } elsif ( defined($version)  &&  ($version =~ /\d+/) && defined($pnr) && !defined($code) ) {
  	       my $query = "
    	    UPDATE MSG_KNOWLEDGE
       		   SET MESSAGE_VERSION = ?, TIME = GETDATE()
     		   WHERE MESSAGE_TYPE    = ? 
       	   AND PNR     = ?";  
       $rows  = $midDB->doBind($query, [$version, $type, $pnr]);
   } elsif (defined($pnr) && !defined($version) && !defined($code) ) {
  	        my $query = "
    	          UPDATE MSG_KNOWLEDGE
       				SET TIME = GETDATE()
		   			$setMarket
		   			$setAqhProceed
     				WHERE MESSAGE_TYPE    = ? 
       				AND PNR     = ?"; 
             $rows  = $midDB->doBind($query, [$type, $pnr]);
  } elsif (defined($pnr) && defined($code) &&  defined($version)  &&  ($version =~ /\d+/)) {
      	    my $query = "
    				UPDATE MSG_KNOWLEDGE
      				 SET MESSAGE_VERSION = ?, TIME = GETDATE()
           				,MESSAGE_CODE    = ?
           				$setMarket
     					WHERE MESSAGE_TYPE    = ? 
       				AND PNR     = ?"; 
            $rows  = $midDB->doBind($query, [$version, $code, $type, $pnr]);
  } else {}
  
  warning('Problem detected !') if ((!defined $rows) || ($rows != 1));
  
  return 0 unless ((defined $rows) && ($rows == 1));
  return 1;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Suppression d'un code de message dans la base de connaissance
#fonction utilise uniquement pour la suppression des societes/users 
#pas d'obligation de passer le PNR 
sub deleteMsgKnowledge {
  my $params  = shift;
  
  my $code    = $params->{CODE}    || undef;
  my $type    = $params->{TYPE}    || undef;

  if ((!defined $code) ||
      (!defined $type) || ($type !~ /^(AIR|TRAIN|USER|COMPANY)$/)) {
    error('Missing or wrong parameter for this method.');
    return 0;
  }

  my $midDB = $cnxMgr->getConnectionByName('mid');
  
  my $query = '
    DELETE FROM MSG_KNOWLEDGE
     WHERE MESSAGE_CODE = ?
       AND MESSAGE_TYPE = ? ';
  my $rows  = $midDB->doBind($query, [$code, $type]);
  
  warning('Problem detected !') if ((!defined $rows) || ($rows < 1));
  
  return 0 unless ((defined $rows) && ($rows == 1));
  return 1;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Mise à jour du champ BTCAIR_PROCEED d'un element de la table MSG_KNOWLEDGE
sub btcAirProceed {
  my $params  = shift;
  
  my $type    = $params->{TYPE} || undef;
  my $pnr     = $params->{PNR}  || undef;
  
  if ((!defined $pnr) ||
      (!defined $type) || ($type !~ /^(AIR|TRAIN|USER|COMPANY)$/)) {
    error('Missing or wrong parameter for this method.');
    return 0;
  }
  
  my $midDB = $cnxMgr->getConnectionByName('mid');
  
  my $query = '
    UPDATE MSG_KNOWLEDGE
       SET BTCAIR_PROCEED = 1, TIME = GETDATE()
     WHERE MESSAGE_TYPE   = ? 
       AND PNR            = ?';
  my $rows  = $midDB->doBind($query, [$type, $pnr]);
  
  warning('Problem detected !') if ((!defined $rows) || ($rows != 1));
  
  return 0 unless ((defined $rows) && ($rows == 1));
  return 1;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Mise à jour du champ BTCTRAIN_PROCEED d'un element de la table MSG_KNOWLEDGE
sub btcTrainProceed {
  my $params = shift;
  
  my $type    = $params->{TYPE} || undef;
  my $pnr     = $params->{PNR}  || undef;
    
  if ((!defined $pnr) ||
      (!defined $type) || ($type !~ /^(AIR|TRAIN|USER|COMPANY)$/)) {
    error('Missing or wrong parameter for this method.');
    return 0;
  }
  
  my $midDB = $cnxMgr->getConnectionByName('mid');
  
  my $query = '
    UPDATE MSG_KNOWLEDGE
       SET BTCTRAIN_PROCEED = 1, TIME = GETDATE()
     WHERE MESSAGE_TYPE     = ? 
       AND PNR              = ?';
  my $rows  = $midDB->doBind($query, [$type, $pnr]);
  
  warning('Problem detected !') if ((!defined $rows) || ($rows != 1));
  
  return 0 unless ((defined $rows) && ($rows == 1));
  return 1;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Mise à jour du champ BTCTAS_PROCEED d'un element de la table MSG_KNOWLEDGE
sub btcTasProceed {
  my $params  = shift;
  
  my $type    = $params->{TYPE} || undef;
  my $pnr     = $params->{PNR}  || undef;
  
  my $rows    = undef;
  
  if ((!defined $pnr) ||
      (!defined $type) || ($type !~ /^(AIR|TRAIN|USER|COMPANY)$/)) {
    error('Missing or wrong parameter for this method.');
    return 0;
  }
  
  my $midDB = $cnxMgr->getConnectionByName('mid');
  

  my $query = '
    UPDATE MSG_KNOWLEDGE
       SET BTCTAS_PROCEED = 1, TIME = GETDATE()
     WHERE MESSAGE_TYPE   = ? 
       AND PNR            = ?';
  $rows  = $midDB->doBind($query, [$type, $pnr]);
  
  warning('Problem detected !') if ((!defined $rows) || ($rows != 1));
  
  return 0 unless ((defined $rows) && ($rows == 1));
  return 1;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Cette fonction verifie l'existence d'un element dans la table WORK_TABLE
# -> Elle renvoie une reference de tableau vide si une erreur est detectee.
# -> Sinon elle renvoie le tableau des elements correspondants.
sub isIntoWorkTable {
  my $params   = shift;

  my $msgCode     = $params->{MESSAGE_CODE} || undef;
  my $msgType     = $params->{MESSAGE_TYPE} || undef;
  my $pnr         = $params->{PNR}          || undef;
  my $appId 	  = $params->{APP_ID} 		|| undef;
    
  if ((!defined $msgCode) ||
      (!defined $msgType)) {
    error('Missing or wrong parameter for this method.');
    return [];
  }
  
  my $dbres = undef;
  my $midDB = $cnxMgr->getConnectionByName('mid');

#LE PNR EST DEFINI SEULEMENT DANS LE CAS DES BOOKINGS
if(!defined($pnr))
{
  my $query = "
    SELECT ID,
           MESSAGE_ID,    MESSAGE_CODE, MESSAGE_VERSION, MESSAGE_TYPE,
           EVENT_VERSION, TEMPLATE_ID,  MARKET,          APP_ID,
           ACTION,        STATUS,       ERROR_ID,        CONVERT(CHAR(10),TIME,103) + ' ' + CONVERT(CHAR(8),TIME,8), PNR
      FROM WORK_TABLE
     WHERE MESSAGE_CODE    = ?
       AND MESSAGE_TYPE    = ?
       AND STATUS         IN ('NEW','RETRY','ERROR','OK','LOCKED')
  ORDER BY TIME DESC ";

  $dbres   = $midDB->saarBind($query, [$msgCode, $msgType]);
}
else
{
    my $query = "
    SELECT ID,
           MESSAGE_ID,    MESSAGE_CODE, MESSAGE_VERSION, MESSAGE_TYPE,
           EVENT_VERSION, TEMPLATE_ID,  MARKET,          APP_ID,
           ACTION,        STATUS,       ERROR_ID,        CONVERT(CHAR(10),TIME,103) + ' ' + CONVERT(CHAR(8),TIME,8), PNR
      FROM WORK_TABLE
     WHERE MESSAGE_CODE    = ?
       AND MESSAGE_TYPE    = ?
       AND PNR             = ?
       AND STATUS         IN ('NEW','RETRY','ERROR','OK','LOCKED')
	   AND APP_ID   	   = ?
  ORDER BY TIME DESC ";

  $dbres   = $midDB->saarBind($query, [$msgCode, $msgType, $pnr,$appId]);
}

  my @results = ();

  return [] unless ((defined $dbres) && (scalar @$dbres > 0));

  foreach (@$dbres) {
    push @results, { ID              => $_->[0],
                     MESSAGE_ID      => $_->[1],
                     MESSAGE_CODE    => $_->[2],
                     MESSAGE_VERSION => $_->[3],
                     MESSAGE_TYPE    => $_->[4],
                     EVENT_VERSION   => $_->[5],
                     TEMPLATE_ID     => $_->[6],
                     MARKET          => $_->[7],
                     APP_ID          => $_->[8],
                     ACTION          => $_->[9],
                     STATUS          => $_->[10],
                     ERROR_ID        => $_->[11],
                     TIME            => $_->[12],
                     PNR             => $_->[13],
                   };
  }
  
  return \@results;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Insertion d'un nouveau message dans la table de travail WORK_TABLE
sub insertIntoWorkTable {
  my $params = shift;

  # --------------------------------------------------------------
  # Verification de l'existence des paramètres obligatoires
  foreach (qw(MESSAGE_ID    MESSAGE_CODE  MESSAGE_VERSION MESSAGE_TYPE
              MARKET          APP_ID
              ACTION        XML   PNR)) {
    error("Missing parameter '$_' for this method.") unless (exists  $params->{$_});
    error("Parameter '$_' cannot be undefined.")     unless (defined $params->{$_});
    return 0 unless ((exists $params->{$_}) && (defined $params->{$_})); 
  };
  
  my $msgId      = $params->{MESSAGE_ID};
  my $msgCode    = $params->{MESSAGE_CODE};
  my $msgVersion = $params->{MESSAGE_VERSION};
  my $msgType    = $params->{MESSAGE_TYPE};
  my $market     = $params->{MARKET};
  my $appId      = $params->{APP_ID};
  my $action     = $params->{ACTION};
  my $xml        = $params->{XML};
  my $pnr        = $params->{PNR};
  
  if (($msgId      !~ /^\d+$/)                          ||
      ($msgVersion !~ /^\d+$/)                          ||
      ($msgType    !~ /^(COMPANY|USER|TRAIN|AIR|LOWCOST|LOWCOST_CANCELLED|TRAIN_CANCELLED|AIR_CANCELLED|CAR)$/)     ||
      ($market     !~ /^\D{2}$/) ||
      ($appId      !~ /^\d+$/)                          ||
      ($action     !~ /^(CREATE|UPDATE|DELETE)$/)) {
    error('Missing or wrong parameter for this method.');
    return 0;
  };
  # --------------------------------------------------------------

  my $query = undef;
  my $midDB = $cnxMgr->getConnectionByName('mid')->handler();

  # --------------------------------------------------------------
  # Obligation de passer par une procedure stockee pour pouvoir
  #   integrer des elements de type CLOB !
  
if(!defined($pnr))
{
 $query = "
      DECLARE \@MY_XML XML;
      SELECT \@MY_XML = MESSAGE FROM MESSAGE WHERE ID='$msgId' AND CODE='$msgCode' AND VERSION='$msgVersion'; 
      INSERT INTO MIDADMIN.WORK_TABLE (
        MESSAGE_ID,    MESSAGE_CODE,    MESSAGE_VERSION,    MESSAGE_TYPE,
        EVENT_VERSION, TEMPLATE_ID,     MARKET,             APP_ID,
        ACTION,        STATUS,          XML,                TIME)
      VALUES (
        $msgId,       '$msgCode',       $msgVersion,       '$msgType',
        '',   '',        '$market',           $appId,
       '$action',     'NEW',           \@MY_XML ,                  GETDATE() ) ";
}
else
{
 $query = "
      DECLARE \@MY_XML XML;
      SELECT \@MY_XML = MESSAGE FROM MESSAGE WHERE ID='$msgId' AND CODE='$msgCode' AND VERSION='$msgVersion'; 
      INSERT INTO MIDADMIN.WORK_TABLE (
        MESSAGE_ID,    MESSAGE_CODE,    MESSAGE_VERSION,    MESSAGE_TYPE,
        EVENT_VERSION, TEMPLATE_ID,     MARKET,             APP_ID,
        ACTION,        STATUS,          XML,                TIME,   PNR)
      VALUES (
        $msgId,       '$msgCode',       $msgVersion,       '$msgType',
        '',   '',        '$market',           $appId,
       '$action',     'NEW',           \@MY_XML ,                  GETDATE()  , '$pnr') ";
}

  eval {
    my $sth = $midDB->prepare($query);
       $sth->execute();
  };
  if ($@ || $DBI::errstr) {
    warning('Problem detected during insert into WORK_TABLE. '.$@) if ($@);
    warning($DBI::errstr) if ($DBI::errstr);
    return 0;
  }
  # --------------------------------------------------------------

  return 1;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Permet de passer le statut d'un item à LOCKED dans la table WORK_TABLE
# Les paramètres TIME et VERSION sont très importants pour savoir si
#   la ligne que l'on essaye de locker est bien strictement la même que
#   celle recuperee lors du isIntoWorkTable
sub lockWorkTableItem {
  my $params     = shift;
  
  my $id         = $params->{ID}              || undef;
  my $msgId      = $params->{MESSAGE_ID}      || undef;
  my $msgCode    = $params->{MESSAGE_CODE}    || undef;
  my $msgType    = $params->{MESSAGE_TYPE}    || undef;
  my $msgVersion = $params->{MESSAGE_VERSION} || undef;
  my $status     = $params->{STATUS}          || undef;
  my $time       = $params->{TIME}            || undef;
  
  if ((!defined $id)         || ($id         !~ /\d+/) ||
      (!defined $msgCode)    ||
      (!defined $msgVersion) || ($msgVersion !~ /\d+/) ||
      (!defined $time)       ||
      (!defined $msgType)    || ($msgType    !~ /^(AIR|TRAIN|USER|COMPANY|TRACKING|LOWCOST|LOWCOST_CANCELLED|AIR_CANCELLED|TRAIN_CANCELLED)$/)) {
    error('Missing or wrong parameter for this method.');
    return 0;
  }
  
  my $midDB = $cnxMgr->getConnectionByName('mid');
  
  my $query = "
    UPDATE WORK_TABLE
       SET STATUS = 'LOCKED'
     WHERE ID                                   = ?
       AND MESSAGE_ID                           = ?
       AND MESSAGE_TYPE                         = ?
       AND MESSAGE_CODE                         = ?
       AND MESSAGE_VERSION                      = ?
       AND STATUS                               = ?
       AND CONVERT(CHAR(10),TIME,103) + ' ' + CONVERT(CHAR(8),TIME,8) = ? ";
  my $list  = [$id, $msgId, $msgType, $msgCode, $msgVersion, $status, $time];

  
  my $rows  = $midDB->doBind($query, $list);
  
  notice("Worktable item has changed compared to 'select' statement.")
    if ((!defined $rows) || ($rows != 1));
  
  return 0 unless ((defined $rows) && ($rows == 1));
  return 1;       
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Mise à jour d'un message dans la table de travail WORK_TABLE
#   Peut inclure les elements suivants uniquement : 
#     * TIME : Attention l'ancien time recupere depuis le SELECT
sub updateWorkTableItem {
  my $params     = shift;
  
  my $id         = $params->{ID}              || undef;
  my $msg        = $params->{XML}             || undef; # Le nouveau message XML
  my $msgId      = $params->{MESSAGE_ID}      || undef;
  my $msgCode    = $params->{MESSAGE_CODE}    || undef;
  my $msgType    = $params->{MESSAGE_TYPE}    || undef;
  my $msgVersion = $params->{MESSAGE_VERSION} || undef; # Ancienne version
  my $version    = $params->{VERSION}         || undef; # Nouvelle version
  my $status     = $params->{STATUS}          || undef;
  my $time       = $params->{TIME}            || undef;
  my $pnr        = $params->{PNR}             || undef;  

  if ((!defined $id)         || ($id         !~ /\d+/) ||
      (!defined $msgCode)    ||
      (!defined $msgVersion) || ($msgVersion !~ /\d+/) ||
      (!defined $time)       ||
      (!defined $msg)        ||
      (!defined $msgType)    || ($msgType    !~ /^(AIR|TRAIN|LOWCOST|LOWCOST_CANCELLED|USER|COMPANY)$/)) {
    error('Missing or wrong parameter for this method.');
    return 0;
  }
  
  my $midDB = $cnxMgr->getConnectionByName('mid')->handler();
  
  # --------------------------------------------------------------
  # Obligation de passer par une procedure stockee pour pouvoir
  #   integrer des elements de type CLOB !
  my $rows  = 0;
  my $query = "
      UPDATE MIDADMIN.WORK_TABLE
         SET XML             = '$msg',
             MESSAGE_VERSION = $version,
             TIME            = GETDATE()
       WHERE ID                                   =  $id
         AND MESSAGE_ID                           =  $msgId
         AND MESSAGE_TYPE                         = '$msgType'
         AND MESSAGE_CODE                         = '$msgCode'
         AND MESSAGE_VERSION                      =  $msgVersion
         AND STATUS                               = '$status'
         AND CONVERT(CHAR(10),TIME,103) + ' ' + CONVERT(CHAR(8),TIME,8) = '$time'
         AND PNR                                  =  '$pnr' ";

  eval {
    my $sth = $midDB->prepare($query);
    $rows = $sth->execute();
  };
  if ($@ || $DBI::errstr || !defined $rows) {
    warning('Problem detected during WORK_TABLE update. '.$@) if ($@);
    warning($DBI::errstr) if ($DBI::errstr);
    return 0;
  }
  # --------------------------------------------------------------

  notice("Worktable item has changed compared to 'select' statement.")
    if ((defined $rows) && ($rows == 0));
  
  return 0 unless ((defined $rows) && ($rows == 1));
  return 1;   
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Verifie la presence de cet element dans la table AMADEUS_SYNCHRO
sub isInAmadeusSynchro {
  my $params = shift;

  my $code   = $params->{CODE} || undef;
  my $type   = $params->{TYPE} || undef;

  if ((!defined $code) ||
      (!defined $type) || ($type !~ /^(USER|COMPANY)$/)) {
    error('Missing or wrong parameter for this method.');
    return undef;
  }

  my $midDB = $cnxMgr->getConnectionByName('mid');

  my $query = '
    SELECT CODE, TYPE, AMADEUS_ID, AMADEUS_NAME, TIME, MARKET, AMADEUS_ID_INHOUSE
      FROM AMADEUS_SYNCHRO
     WHERE CODE = ?
       AND TYPE = ? ';

  return $midDB->saarBind($query, [$code, $type]);
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Insertion d'un element dans la table AMADEUS_SYNCHRO
sub insertIntoAmadeusSynchro {
	my $params = shift;
	
	my $code    = $params->{CODE};
	my $type    = $params->{TYPE};
	my $amadID  = $params->{AID};
	my $amaName = $params->{NAME}   || '';
	my $market  = $params->{MARKET} || '';
	my $amadId_inH  = "NULL"; 
	
	if ((!defined $code)   ||
      (!defined $type)   || ($type   !~ /^(USER|COMPANY)$/) ||
      (!defined $amadID) || ($amadID !~ /^\w{6}$/)) {
    error('Missing or wrong parameter for this method.');
    return 0;
  }
	
	my $midDB = $cnxMgr->getConnectionByName('mid');

	my $query = '
	  INSERT INTO AMADEUS_SYNCHRO (CODE, TYPE, AMADEUS_ID, AMADEUS_NAME, MARKET, AMADEUS_ID_INHOUSE) 
		                     VALUES (?, ?, ?, ?, ?, ?) ';
		 
  return $midDB->doBind($query, [$code, $type, $amadID, $amaName, $market, $amadId_inH]);
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Suppression d'un element dans la table AMADEUS_SYNCHRO
sub deleteFromAmadeusSynchro {
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
	  DELETE FROM AMADEUS_SYNCHRO
	   WHERE AMADEUS_ID = ?
	     AND       CODE = ?
	     AND       TYPE = ? ";

  return $midDB->doBind($query, [$amadID, $code, $type]);
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Insertion d'un element dans la table DV2PNR
sub insertIntoDv2Pnr {
	my $params = shift;
	
  my $mdCode = $params->{MDCODE};
	my $dvId   = $params->{DVID};
	my $pnrId  = $params->{PNRID};
	
	if ((!defined $mdCode) ||
	    (!defined $dvId)   ||
      (!defined $pnrId)) {
    error('Missing or wrong parameter for this method.');
    return 0;
  } else {
    $dvId  = uc($dvId);
    $pnrId = uc($pnrId);
  }
	
	my $midDB = $cnxMgr->getConnectionByName('mid');

	my $query = 'INSERT INTO DV2PNR (MDCODE, DVID, PNRID) VALUES (?, ?, ?)';
		 
  return $midDB->doBind($query, [$mdCode, $dvId, $pnrId], 1);
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Suppression d'un element dans la table DV2PNR
sub deleteFromDv2Pnr {
	my $params = shift;
	
	my $mdCode = $params->{MDCODE};
	my $dvId   = $params->{DVID};
	
	if ((!defined $mdCode) || (!defined $dvId)) {
    error('Missing or wrong parameter for this method.');
    return 0;
  }
	
	my $midDB = $cnxMgr->getConnectionByName('mid');

	my $query = 'DELETE FROM DV2PNR WHERE MDCODE = ? AND DVID = ? ';
		 
  return $midDB->doBind($query, [$mdCode, $dvId]);
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Recuperation d'un PNR Identifier à partir DV Identifier
sub getPnrIdFromDv2Pnr {
	my $params = shift;
	
	my $mdCode = $params->{MDCODE};
	my $dvId   = $params->{DVID};
	
	if ((!defined $mdCode) || (!defined $dvId)) {
    error('Missing or wrong parameter for this method.');
    return 0;
  }
	
	my $midDB = $cnxMgr->getConnectionByName('mid');

	my $query = 'SELECT PNRID FROM DV2PNR WHERE MDCODE = ? AND DVID = ? ';
		 
  return $midDB->saarBind($query, [$mdCode, $dvId])->[0][0];
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Clean Items because 'ERROR' status
sub cleanItems {
    
  my $dbh = $cnxMgr->getConnectionByName('mid');
  
  # ____________________________________________________________________
  # Relative to BTC process
  notice('|  * BTC-AIR et BTC-TRAIN                                     |');
  my $query = "
    SELECT REF, APP_ID, STATUS
      FROM IN_PROGRESS
     WHERE APP_ID IN (SELECT ID FROM APPLICATIONS WHERE NAME LIKE ('btc%'))
       AND STATUS IN ('new','process','retrieve','error')
       AND CONVERT(VARCHAR(10),TIME,103) <> CONVERT(VARCHAR(10),GETDATE(),103)
       AND CONVERT(VARCHAR(10),TIME,103) <> CONVERT(VARCHAR(10),GETDATE() -1 ,103)";
  my $res = $dbh->saarBind($query, []);
  debug('Number of items to delete = '.scalar(@$res));
  foreach (@$res) {
    # Suppression des tables IN_PROGRESS et WORK_TABLE
    $query = '
      DELETE FROM IN_PROGRESS
       WHERE    REF = ?
         AND APP_ID = ?
         AND STATUS = ? ';
    $dbh->doBind($query, [$_->[0], $_->[1], $_->[2]]);
    $query = '
      DELETE FROM WORK_TABLE
       WHERE     ID = ?
         AND APP_ID = ? ';
    $dbh->doBind($query, [$_->[0], $_->[1]]);
  }
  # ____________________________________________________________________
  
  # ____________________________________________________________________
  # Nettoyage de DV2PNR
  #   On conserve desormais une trace plus longue des dossiers THALYS
  notice('|  * DV2PNR                                                   |');
   $query = "
    SELECT MDCODE, DVID, PNRID
      FROM DV2PNR
     WHERE CONVERT(DATETIME,CONVERT(VARCHAR(10),TIME,103),103) < ( CONVERT(DATETIME,CONVERT(VARCHAR(10),GETDATE(),103),103) - 150) ";
  $res = $dbh->saarBind($query, []);
  debug('Number of items to delete = '.scalar(@$res));
  foreach (@$res) {
    $query = '
      DELETE FROM DV2PNR
       WHERE MDCODE = ?
         AND DVID   = ?
         AND PNRID  = ? ';
    $dbh->doBind($query, [$_->[0], $_->[1], $_->[2]]);
  }
  # ____________________________________________________________________
  
  # ____________________________________________________________________
  # Nettoyage de FIELDS
  notice('|  * FIELDS                                                   |');
  $query = "
    SELECT ID
      FROM FIELDS
       WHERE CONVERT(VARCHAR(10),TIME,103) <> CONVERT(VARCHAR(10),GETDATE(),103)
       AND CONVERT(VARCHAR(10),TIME,103) <> CONVERT(VARCHAR(10),GETDATE() -1 ,103) 
       AND [KEY] = 'TRAIN_FID_CARD' ";
  $res = $dbh->saarBind($query, []);
  debug('Number of items to delete = '.scalar(@$res));
  foreach (@$res) {
    $query = 'DELETE FROM FIELDS WHERE ID = ? ';
    $dbh->doBind($query, [$_->[0]]);
  }
  # ____________________________________________________________________
  
  # ____________________________________________________________________
  # Nettoyage de TAS_STATS_DAILY
  notice('|  * TAS_STATS_DAILY                                          |');
  $query = "
    SELECT ID
      FROM TAS_STATS_DAILY
    WHERE CONVERT(VARCHAR(10),TIME,103) <> CONVERT(VARCHAR(10),GETDATE(),103)
       AND CONVERT(VARCHAR(10),TIME,103) <> CONVERT(VARCHAR(10),GETDATE() -1 ,103) 
       AND CONVERT(VARCHAR(10),TIME,103) <> CONVERT(VARCHAR(10),GETDATE() -2 ,103)
       AND CONVERT(VARCHAR(10),TIME,103) <> CONVERT(VARCHAR(10),GETDATE() -3 ,103)
       AND CONVERT(VARCHAR(10),TIME,103) <> CONVERT(VARCHAR(10),GETDATE() -4 ,103)
       AND CONVERT(VARCHAR(10),TIME,103) <> CONVERT(VARCHAR(10),GETDATE() -5 ,103) ";
  $res = $dbh->saarBind($query, []);
  debug('Number of items to delete = '.scalar(@$res));
  foreach (@$res) {
    $query = 'DELETE FROM TAS_STATS_DAILY WHERE ID = ? ';
    $dbh->doBind($query, [$_->[0]]);
  }
  # ____________________________________________________________________

  # ____________________________________________________________________
  # Relative to SYNCHRO process
  notice('|  * SYNCHRO                                                  |');
  $query = "
    SELECT ID, APP_ID, MESSAGE_TYPE, STATUS
      FROM WORK_TABLE
     WHERE APP_ID IN (SELECT ID FROM APPLICATIONS WHERE NAME LIKE ('synchro%'))
       AND STATUS IN ('ERROR', 'LOCKED')
       AND MESSAGE_TYPE IN ('USER', 'COMPANY')
       AND CONVERT(VARCHAR(10),TIME,103) <> CONVERT(VARCHAR(10),GETDATE(),103)
       AND CONVERT(VARCHAR(10),TIME,103) <> CONVERT(VARCHAR(10),GETDATE() -1 ,103) 
       AND CONVERT(VARCHAR(10),TIME,103) <> CONVERT(VARCHAR(10),GETDATE() -2 ,103)
       AND CONVERT(VARCHAR(10),TIME,103) <> CONVERT(VARCHAR(10),GETDATE() -3 ,103)
       AND CONVERT(VARCHAR(10),TIME,103) <> CONVERT(VARCHAR(10),GETDATE() -4 ,103)
       AND CONVERT(VARCHAR(10),TIME,103) <> CONVERT(VARCHAR(10),GETDATE() -5 ,103) ";
  $res = $dbh->saarBind($query, []);
  debug('Number of items to delete = '.scalar(@$res));
  foreach (@$res) {
    # Suppression de la table IN_PROGRESS
    $query = '
      DELETE FROM WORK_TABLE
       WHERE     ID       = ?
         AND APP_ID       = ?
         AND STATUS       = ?
         AND MESSAGE_TYPE = ? ';
    $dbh->doBind($query, [$_->[0], $_->[1], $_->[3], $_->[2]]);
  }
  # ____________________________________________________________________

  # ____________________________________________________________________
  # Relative to TAS process
  notice('|  * TAS                                                      |');
  $query = "
    SELECT REF, APP_ID, SUBAPP_ID
      FROM IN_PROGRESS
     WHERE APP_ID IN (SELECT ID FROM APPLICATIONS WHERE NAME LIKE ('tas%'))
       AND CONVERT(VARCHAR(10),TIME,103) <> CONVERT(VARCHAR(10),GETDATE(),103)
       AND CONVERT(VARCHAR(10),TIME,103) <> CONVERT(VARCHAR(10),GETDATE() -1 ,103) 
     UNION
    SELECT REF, APP_ID, SUBAPP_ID
      FROM IN_PROGRESS
     WHERE APP_ID = 0
       AND TYPE   = 'EMPTY'
       AND CONVERT(VARCHAR(10),TIME,103) <> CONVERT(VARCHAR(10),GETDATE(),103)
       AND CONVERT(VARCHAR(10),TIME,103) <> CONVERT(VARCHAR(10),GETDATE() -1 ,103) ";
  $res = $dbh->saarBind($query, []);
  debug('Number of items to delete = '.scalar(@$res));
  foreach (@$res) {
    # Suppression de la table IN_PROGRESS
    $query = '
      DELETE FROM IN_PROGRESS
       WHERE       REF = ?
         AND    APP_ID = ?
         AND SUBAPP_ID = ? ';
    $dbh->doBind($query, [$_->[0], $_->[1], $_->[2]]);
  }
  # ____________________________________________________________________
  
  # ____________________________________________________________________
  # Relative to MSG_KNOWLEDGE table
  #  On considère qu'au dela de 150 jours un booking est "expire" !
  #  Egalement les USER / COMPANY qui n'ont plus de relation en AMADEUS_SYNCHRO !
  notice('|  * MSG_KNOWLEDGE                                            |');
  $query = "
    SELECT MESSAGE_CODE, MESSAGE_VERSION, MESSAGE_TYPE
      FROM MSG_KNOWLEDGE
     WHERE CONVERT(DATETIME,CONVERT(VARCHAR(10),TIME,103),103) < CONVERT(DATETIME,CONVERT(VARCHAR(10),GETDATE(),103),103) - 150
       AND MESSAGE_TYPE IN ('TRAIN', 'AIR')
     UNION
    SELECT MK.MESSAGE_CODE, MK.MESSAGE_VERSION, MK.MESSAGE_TYPE
      FROM MSG_KNOWLEDGE MK
      LEFT OUTER JOIN AMADEUS_SYNCHRO AMS ON MK.MESSAGE_TYPE = AMS.TYPE AND MK.MESSAGE_CODE = AMS.CODE
     WHERE MK.MESSAGE_TYPE IN ('USER','COMPANY')
       AND CONVERT(VARCHAR(10),MK.TIME,103) <> CONVERT(VARCHAR(10),GETDATE(),103)
       AND AMS.CODE IS NULL ";
  $res = $dbh->saarBind($query, []);
  debug('Number of items to delete = '.scalar(@$res));
  foreach (@$res) {
    # Suppression de la table IN_PROGRESS
    $query = '
      DELETE FROM MSG_KNOWLEDGE
       WHERE MESSAGE_CODE    = ?
         AND MESSAGE_VERSION = ?
         AND MESSAGE_TYPE    = ? ';
    $dbh->doBind($query, [$_->[0], $_->[1], $_->[2]]);
  }
  # ____________________________________________________________________
  
  # ____________________________________________________________________
  # Il apparait que le rattachement n'est pas systematique
  notice('|  * FINAL                                                    |');  
  $query = "
    SELECT ID, MESSAGE_ID, MESSAGE_CODE, MESSAGE_VERSION
      FROM WORK_TABLE
     WHERE CONVERT(VARCHAR(10),TIME,103) <> CONVERT(VARCHAR(10),GETDATE(),103)
       AND CONVERT(VARCHAR(10),TIME,103) <> CONVERT(VARCHAR(10),GETDATE() -1 ,103) ";
  $res = $dbh->saarBind($query, []);
  debug('Number of items to delete = '.scalar(@$res));
  foreach (@$res) {
    # Suppression de la table WORK_TABLE
    $query = '
      DELETE FROM WORK_TABLE
       WHERE              ID = ?
         AND      MESSAGE_ID = ?
         AND    MESSAGE_CODE = ?
         AND MESSAGE_VERSION = ? ';
    $dbh->doBind($query, [$_->[0], $_->[1], $_->[2], $_->[3]]);
  }
  # ____________________________________________________________________

  return 1;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Unlock Items when Lock Time > 15 mins
sub unlockItems {

  my $dbh = $cnxMgr->getConnectionByName('mid');

  # ____________________________________________________________________
  # Relative to BTC process  
  notice('|  * BTC-AIR et BTC-TRAIN                                     |');
  my $query = "
    SELECT REF, APP_ID
      FROM IN_PROGRESS
     WHERE APP_ID IN (SELECT ID FROM APPLICATIONS WHERE NAME LIKE ('btc%'))
       AND LOCKED = 1
       AND GETDATE() - CONVERT(DATETIME,TIME) > 0.0125
  ORDER BY TIME ASC ";
  my $res = $dbh->saarBind($query, []);
  debug('Number of items to unlock = '.scalar(@$res));
  foreach (@$res) {
    $query = '
      UPDATE IN_PROGRESS
         SET LOCKED = 0
       WHERE LOCKED = 1
         AND    REF = ?
         AND APP_ID = ? ';
    $dbh->doBind($query, [$_->[0], $_->[1]]);
  }
  # ____________________________________________________________________
  
  # ____________________________________________________________________
  # Relative to TAS process
  notice('|  * TAS                                                      |');
  $query = "
      SELECT REF, APP_ID
        FROM IN_PROGRESS
       WHERE APP_ID = 0
         AND LOCKED = 1
         AND GETDATE() - CONVERT(DATETIME,TIME) > 0.0125
    ORDER BY TIME ASC ";
  $res = $dbh->saarBind($query, []);
  debug('Number of items to unlock = '.scalar(@$res));
  foreach (@$res) {
    $query = '
      UPDATE IN_PROGRESS
         SET LOCKED = 0
       WHERE LOCKED = 1
         AND    REF = ?
         AND APP_ID = ? ';
    $dbh->doBind($query, [$_->[0], $_->[1]]);
  }
  # ____________________________________________________________________

  return 1;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Recuperation du Marche depuis une info de "ComCode"
sub getMarketFromComCode {
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
# Recuperation du Marche depuis une info de "PerCode"
sub getMarketFromPerCode {
  my $perCode = shift || undef;
  
  if (!defined $perCode) {
    error('Missing or wrong parameter for this method.');
    return 0;
  }
  
  my $midDB = $cnxMgr->getConnectionByName('mid');
  
  my $query = '
    SELECT O.CODE
      FROM USER_USER U, COMP_COMPANY C, OPST_POS O
     WHERE U.CODE = ?
       AND C.ID   = U.COMPANY_ID
       AND O.ID   = C.OPST_POS_ID ';

  return $midDB->saarBind($query, [$perCode])->[0][0];
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Recuperation des Infos depuis une info de "PerCode"
sub getInfosOnPerCode {
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
# Recuperation de tous les PerCodes depuis un comCode donne
sub getUsersFromComCode {
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
sub getBillingEntityLabel {
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
# Fonction liees au TravellerTracking / Toutes les infos - Tous les marches
sub getQInfosAllMarkets {

  my $market = shift;
  
  $market = getNavCountrybycountry($market);
   
 notice("MARKET:".$market);
 
  my $dbh_nav = $cnxMgr->getConnectionByName('navision');
    
  my $query = "SELECT [No. ] COMCODE, [Name] COMNAME, [Country] COUNTRY, [Dest_Queue] DEST_QUEUE, 
  [DEST_OFFICE_ID] DEST_OFFICE_ID, [DEST_SECURITY_ELEMENT] DEST_SECURITY_ELEMENT, 
  CONVERT(CHAR(17),RTRIM(CONVERT(CHAR,[DEST_DATE],112))+' '+CONVERT(CHAR,[DEST_DATE],14)) DEST_DATE, 
  CONVERT(CHAR(17),RTRIM(CONVERT(CHAR,[DEST_DATE],112))+REPLACE(CONVERT(CHAR,[DEST_DATE],14),':','')) DEST_DATE_2_NAV
  from customer_queue where country=?";
   
  my $res = $dbh_nav->saarBind($query, [$market]);


  my $ret = [];
  
  foreach (@$res) {
    push @$ret, { ComCode         => $_->[0],
                  ComName         => $_->[1],
                  Country         => $_->[2],
                  DestQueue       => $_->[3],
                  DestOfficeId    => $_->[4],
                  SecurityElement => $_->[5],
                  NavisionDate    => $_->[6],
                  NavisionDate2nav=> $_->[7] };

  }
  
  return $ret;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Fonction liees au TravellerTracking / Toutes les infos d'1 marche donne
#sub getQInfosForMarket {
#  my $market = shift;
#  
#  debug('market = '.$market);
#
#  my $dbh_nav = $cnxMgr->getConnectionByName('navision');
#  
#  my $query = '
#    SELECT COMCODE, COMNAME,
#           NAVISION_TABLE, NAVISION_DATE,
#           DEST_QUEUE, DEST_OFFICE_ID, SECURITY_ELEMENT
#      FROM QUEUE_PNR
#     WHERE MARKET = ?';
#  my $query = 'SELECT [No. ] COMCODE, [Name] COMNAME, [Country] COUNTRY, [Dest_Queue] DEST_QUEUE, [DEST_OFFICE_ID] DEST_OFFICE_ID, [DEST_SECURITY_ELEMENT] DEST_SECURITY_ELEMENT
#               from customer_queue WHERE COUNTRY= ? ';
#
#  my $res = $midDB->saarBind($query, [$market]);
#  my $ret = [];
#  
#  foreach (@$res) {
#    push @$ret, { ComCode         => $_->[0],
#                  ComName         => $_->[1],
#                  NavisionTable   => $_->[2],
#                  NavisionDate    => $_->[3],
#                  DestQueue       => $_->[4],
#                  DestOfficeId    => $_->[5],
#                  SecurityElement => $_->[6] };
#  }
#  
#  return $ret;
#}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Fonction liees au TravellerTracking / Toutes les infos d'1 COMCODE donne
sub getQInfosForComCode {
  my $comCode = shift;
  
  debug('comCode = '.$comCode);

  my $dbh_nav = $cnxMgr->getConnectionByName('navision');
    
  my $query = 'SELECT [No. ] COMCODE, [Name] COMNAME, [Country] COUNTRY, [Dest_Queue] DEST_QUEUE, [DEST_OFFICE_ID] DEST_OFFICE_ID, [DEST_SECURITY_ELEMENT] DEST_SECURITY_ELEMENT
               from customer_queue WHERE ([No.] = ?) ';
   
  my $res = $dbh_nav->saarBind($query, [$comCode]);
  
  return undef if ((!defined $res) || (scalar @$res != 1));
     
  my $ret = {
    ComCode         => $res->[0][0],
    ComName         => $res->[0][1],
    Country         => $res->[0][2],
    DestQueue       => $res->[0][3],
    DestOfficeId    => $res->[0][4],
    SecurityElement => $res->[0][5] };
  
  return $ret;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Fonction liees au TravellerTracking / Hash des ComCodes impliques
#   pour un marche donne.
sub getTravellerTrackingImplicatedComCodesForMarket {
  my $market = shift;
  
     $market = getNavCountrybycountry($market);
  
  my $dbh_nav = $cnxMgr->getConnectionByName('navision');
  
  my $query = "SELECT [No.] COMCODE FROM customer_queue WHERE ([Country] = '$market')";

  my $res = $dbh_nav->saar($query, []);
  my $ret = {};
     $ret->{$_->[0]} = 1 foreach (@$res);
  
  return $ret;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Fonction liees au TravellerTracking / Hash des ComCodes impliques
#   pour un marche donne.
sub getTravellerTrackingImplicatedComCodesForMarket_new {
    my $task = shift;
	
	#connexion to major nav (FR and other) 
	my $dbh_nav = $cnxMgr->getConnectionByName('navision');
	my $query = "SELECT [No.] COMCODE FROM customer_queue";
	my $res = $dbh_nav->saar($query, []);
	my $ret = {};
    $ret->{$_->[0]} = 1 foreach (@$res);
  
	#connexion to VIA nav 
	#Get the connexion information by country
	my $nav_conn = &getNavisionConnForAllCountry();

	#Get the complete name of the market VIA (FI but could be NO SE DK)
	my $country = &getNavCountrybycountry('FI');

	#Set the nav connexion 
	&setNavisionConnection($country,$nav_conn,$task);

	$dbh_nav = $cnxMgr->getConnectionByName('navision');
	$query = "SELECT [No.] COMCODE FROM customer_queue ";
	$res = $dbh_nav->saar($query, []);
    $ret->{$_->[0]} = 1 foreach (@$res);
	
  return $ret;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@


# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Fonction liees au TravellerTracking / Update Navision Date for a given
#   company !
sub updateTravellerTrackingNavisionDate {
  my $country = shift;
  my $navDate = shift;
  my $comcode = shift; 
  
  my $dbh_nav = $cnxMgr->getConnectionByName('navision');
  
  my $query = "UPDATE [EGENCIA $country\$customer information] SET DEST_DATE = '$navDate' WHERE [No_] = '$comcode'";
  
  my $rows  = $dbh_nav->do($query);
  
  return $rows;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Get the Country for an upcomcode
sub getCountrybyUpComCode {
  my $upcomcode   = shift;

  my $midDB = $cnxMgr->getConnectionByName('mid');

  my $query = "
    SELECT COUNTRY
      FROM MO_CFG_DIVERS
     WHERE UPCOMCODE = ? ";

  my $finalRes = $midDB->saarBind($query, [$upcomcode])->[0][0];

  return $finalRes;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Get the upcomcode for a country
sub getUpComCodebycountry {
  my $country   = shift;

  my $midDB = $cnxMgr->getConnectionByName('mid');

  my $query = "
    SELECT UPCOMCODE
      FROM MO_CFG_DIVERS
     WHERE COUNTRY = ? ";

  my $finalRes = $midDB->saarBind($query, [$country])->[0][0];

  return $finalRes;
}

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Get the nav country for a country
sub getNavCountrybycountry {
  my $country   = shift;

  my $midDB = $cnxMgr->getConnectionByName('mid');

  my $query = "
    SELECT NAV_COUNTRY
      FROM MO_CFG_DIVERS
     WHERE COUNTRY = ? ";

  my $finalRes = $midDB->saarBind($query, [$country])->[0][0];

  return $finalRes;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Get the nav country for a country
sub getTZbycountry {
  my $country   = shift;

  my $midDB = $cnxMgr->getConnectionByName('mid');

  my $query = "
    SELECT TZ
      FROM MO_CFG_DIVERS
     WHERE COUNTRY = ? ";

  my $finalRes = $midDB->saarBind($query, [$country])->[0][0];

  return $finalRes;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Get the fpec
sub getFpec {
  my $market    = shift;
  
  my $midDB = $cnxMgr->getConnectionByName('mid');
  
  my $query = "
    SELECT FPEC
      FROM MO_CFG_DIVERS
      WHERE COUNTRY = ?  ";

  my $finalRes = $midDB->saarBind($query, [$market])->[0][0];

  return $finalRes;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Recuperation du ComCode depuis une info de "PerCode"
sub getUserComCode {
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

1;
