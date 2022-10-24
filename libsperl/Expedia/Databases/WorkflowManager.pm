package Expedia::Databases::WorkflowManager;
#-----------------------------------------------------------------
# Package Expedia::Databases::WorkflowManager
#
# $Id: WorkflowManager.pm 686 2011-04-21 12:33:02Z pbressan $
#
# (c) 2002-2008 Expedia.                   www.expediacorporate.fr
#-----------------------------------------------------------------

use Data::Dumper;
use Exporter 'import';

use Expedia::Tools::Logger             qw(&debug &notice &warning &error);
use Expedia::Tools::GlobalVars         qw($cnxMgr);
use Expedia::Databases::MidSchemaFuncs qw(&getHighWaterMark &setHighWaterMark);

@EXPORT_OK = qw(&getNewMsgRelatedToSynchro &getNewMsgRelatedToBookings
                &searchIntoEventHistory &insertAmadeusIdMsg &getMessageFromIdVersion
                &insertWbmiMsg &getNewMsgRelatedToSynchro_Debug);

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Récupération des nouveaux messages du journal relativement à la
#   tâche de synchro.
sub getNewMsgRelatedToSynchro {
  
  my $dbh = $cnxMgr->getConnectionByName('mid');

  # -----------------------------------------------------------------
  # Requète pour connaitre à quelle "version" nous nous étions arretés
  #   en ce qui concerne la synchro-profils.
  my $version = &getHighWaterMark('synchro');
  if (!defined $version) {
    warning('Problem detected during get of lasts treated versions.');
    return [];
  }
  # -----------------------------------------------------------------
  
  # -----------------------------------------------------------------
  # Sproc to retrieve all the xml not treated 
  my $query = "EXEC WORKFLOW.JOURNAL_LST_BY_CTVERSION \@LAST_CT_DBVER = $version, \@FUNCTIONAL_DOMAIN_REF_NAME_LST = 'COMPANY,USER', \@EVENT_NAME_LST = 'USER_NEW,USER_UPDATED,USER_DELETED,COMPANY_NEW,COMPANY_UPDATED,COMPANY_DATA_FIELD_VALUES_UPDATED,COMPANY_CLOSED', \@MAXROWS = 10000";
  my $results= $dbh->sproc_array($query, []);
	
  # debug('results = '.Dumper($results));
  # -----------------------------------------------------------------

  return [] unless ((defined $results) && (scalar @$results > 0));

  my @finalRes = ();

  RES: foreach my $res (@$results) {
    my $tmpXML =  $res->[11];
       $tmpXML =~ s/'/''''/ig;
       $tmpXML = '<?xml version="1.0" encoding="ISO-8859-1" standalone="yes"?>'.$tmpXML;
    my $tmp  = ' xmlns="http://www.expediacorporate.fr/newsimages/xsds/v1"';
    $tmpXML =~ s/$tmp//ig;

    push @finalRes, {
      MSG_ID      => $res->[2],
      MSG_CODE    => $res->[13],
      MESSAGE     => $tmpXML,
      MSG_VERSION => $res->[1],
      EVT_NAME    => $res->[4],
      EVT_VERSION => '', 
      MSG_TMPLID  => '', 
      EVT_TMPLID  => '', 
      LOCATION    => '', 
      USED_FOR    => 'SYNCHRO',
      EVT_ID      => $res->[3],
    };
    $version = $res->[0];
  }

  &setHighWaterMark('synchro', $version);

  return \@finalRes;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@


# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Debug function in order to fetch old data from synchro 
#   
sub getNewMsgRelatedToSynchro_Debug {
    my $start_version = shift;
    my $stop_version = shift || undef;
  my $query_stop_version="";
   if (!defined $start_version) {
    warning('Problem detected : start version number mandatory ');
    return [];
  }
  
  my $dbh = $cnxMgr->getConnectionByName('mid');

  
  								  
  # -----------------------------------------------------------------
  # Requète d'extraction de tous les éléments de
  #   la table JOURNAL que l'on ne connait pas.
  my $query = "
    SELECT J.MESSAGE_ID                  AS MSG_ID,
           M.CODE                        AS MSG_CODE,
           --CAST(M.MESSAGE as varchar(max)) COLLATE SQL_Latin1_General_Cp1_CI_AS AS MESSAGE,
            CONVERT(VARCHAR(MAX), CONVERT(NVARCHAR(MAX), M.MESSAGE)) AS MESSAGE, 
           J.MESSAGE_VERSION             AS MSG_VERSION,
           EC.EVENT_NAME                 AS EVT_NAME,
           ET.VERSION                    AS EVT_VERSION,
           M.TEMPLATE_ID                 AS MSG_TMPLID,
           ET.TEMPLATE_ID                AS EVT_TMPLID,
           T.URL                         AS LOCATION,
           J.EVENTS_TYPE_ID              AS EVT_ID
      FROM JOURNAL J, MESSAGE M, EVENTS_TYPE ET, TEMPLATE T, EVENT_CONFIG EC
     WHERE J.MESSAGE_VERSION > ?";
	 
	  
	 $query_stop_version=" AND J.MESSAGE_VERSION < $stop_version" if (defined($stop_version)) ;
	 
      my $end_query=" AND J.MESSAGE_ID      = M.ID
       AND J.MESSAGE_VERSION = M.VERSION
       AND J.EVENTS_TYPE_ID IN (SELECT ID
                                  FROM EVENTS_TYPE
                                 WHERE EVENT_CONFIG_ID IN (SELECT ID
                                                            FROM EVENT_CONFIG
                                                           WHERE FUNCTIONAL_DOMAIN_ID IN (SELECT ID
                                                                                            FROM FUNCTIONAL_DOMAIN_REF
                                                                                           WHERE NAME IN ('COMPANY','USER'))
                                                           AND EVENT_NAME IN ('USER_NEW','USER_UPDATED','USER_DELETED','COMPANY_NEW','COMPANY_UPDATED','COMPANY_DATA_FIELD_VALUES_UPDATED','COMPANY_CLOSED')))
       AND ET.EVENT_CONFIG_ID = EC.ID
       AND M.FUNCTIONAL_DOMAIN_ID IN (SELECT ID FROM FUNCTIONAL_DOMAIN_REF WHERE NAME IN ('COMPANY','USER'))
       AND T.ID = M.TEMPLATE_ID
       AND J.EVENTS_TYPE_ID = ET.ID
       AND M.MODIFICATION_DATE < GETDATE() - 1 / 1440
  ORDER BY J.MESSAGE_VERSION ASC ";
  
my $final_query= $query.$query_stop_version.$end_query;
  my $results = $dbh->saarBind($final_query, [$start_version]);
  # debug('results = '.Dumper($results));
  # -----------------------------------------------------------------

  return [] unless ((defined $results) && (scalar @$results > 0));
  
  my @finalRes = ();
  
  RES: foreach my $res (@$results) {
    my $tmpXML =  $res->[2];
       $tmpXML =~ s/'/''''/ig;
       $tmpXML = '<?xml version="1.0" encoding="ISO-8859-1" standalone="yes"?>'.$tmpXML;
    my $tmp  = ' xmlns="http://www.expediacorporate.fr/newsimages/xsds/v1"';
    $tmpXML =~ s/$tmp//ig;

    push @finalRes, {
      MSG_ID      => $res->[0],
      MSG_CODE    => $res->[1],
      MESSAGE     => $tmpXML,
      MSG_VERSION => $res->[3],
      EVT_NAME    => $res->[4],
      EVT_VERSION => '', 
      MSG_TMPLID  => '', 
      EVT_TMPLID  => '', 
      LOCATION    => '', 
      USED_FOR    => 'SYNCHRO',
      EVT_ID      => $res->[9],
    };
   
  }


  return \@finalRes;
}


# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Récupération des nouveaux messages du journal relativement à la
#   tâche des réservations.
sub getNewMsgRelatedToBookings {

  my $dbh = $cnxMgr->getConnectionByName('mid');

  # -----------------------------------------------------------------
  # Requète pour connaitre à quelle "version" nous nous étions arretés
  #   en ce qui concerne la synchro-profils.
  my $version = &getHighWaterMark('booking');
  if (!defined $version) {
    warning('Problem detected during get of last treated version');
    return [];
  }
  # -----------------------------------------------------------------

  # -----------------------------------------------------------------
  # Sproc to retrieve all the xml not treated 
	my $query = "EXEC WORKFLOW.JOURNAL_LST_BY_CTVERSION \@LAST_CT_DBVER = $version, \@FUNCTIONAL_DOMAIN_REF_NAME_LST = 'BOOKING', \@EVENT_NAME_LST = 'BOOKING_CANCELLED,BOOKING_NEW,BOOKING_UPDATED,BOOKING_CONFIRMED,BOOKING_APPROVED', \@MAXROWS = 10000";
    my $results= $dbh->sproc_array($query, []);

  # debug('results = '.Dumper($results));
  # -----------------------------------------------------------------

  return [] unless ((defined $results) && (scalar @$results > 0));

  my @finalRes = ();

  RES: foreach my $res (@$results) {
    my $tmpXML =  $res->[11];
       $tmpXML =~ s/'/''''/ig;
       $tmpXML = '<?xml version="1.0" encoding="ISO-8859-1" standalone="yes"?>'.$tmpXML;

    my $tmp  = ' xmlns="http://www.expediacorporate.fr/newsimages/xsds/v1"';
    $tmpXML =~ s/$tmp//ig;	

    push @finalRes, {
      MSG_ID      => $res->[2],
      MSG_CODE    => $res->[13],
      MESSAGE     => $tmpXML,
      MSG_VERSION => $res->[1],
      EVT_NAME    => $res->[4],
      EVT_VERSION => '', 
      MSG_TMPLID  => '', 
      EVT_TMPLID  => '', 
      LOCATION    => '', 
      USED_FOR    => 'BOOKING',
      EVT_ID      => $res->[3],
    };
    $version = $res->[0];
  }

  &setHighWaterMark('booking', $version);

  return \@finalRes;  
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
sub insertAmadeusIdMsg {
	my $params = shift;
	
	my $XML   = $params->{XML};
	my $code  = $params->{CODE};
	my $type  = $params->{TYPE};            # USER ou COMPANY
	my $msgId      = undef;
	my $msgVersion = undef;
	   $msgId = $params->{MESSAGE_ID} if (exists $params->{MESSAGE_ID});
	
	my $eventName  = undef;
	my $funcDomRef = undef;
	
	if    ((defined $type) && ($type =~ /^USER$/))    { $eventName  = 'USER_AMADEUS_ID';      $funcDomRef = 'UPDATE ORDER'; }
	elsif ((defined $type) && ($type =~ /^COMPANY$/)) { $eventName 	= 'COMPANY_AMADEUS_DATA'; $funcDomRef = 'UPDATE ORDER'; }
	else                                              { notice('Unknown TYPE'); return undef;	}
	if (!defined $code) { notice('CODE undefined [...]'); return undef; }
	if (!defined $XML)  { notice('XML undefined [...]');  return undef; }
		
	my $dbh = $cnxMgr->getConnectionByName('mid');

if    (!defined $msgId)    
{
    my $query = "DECLARE \@RC INT , \@pNextVal INT  BEGIN EXECUTE \@RC =  WORKFLOW.Message_Seq_Nextval \@pNextVal OUTPUT; select \@pNextVal  END";
    $msgId = $dbh->sproc($query, []);
    debug("MSGID_insertAmadeusIdMsg:$msgId");
}

  #ON RECUPERE LA VERSION
  if    (!defined $msgVersion)    
  {
      my $query = "DECLARE \@RC INT , \@pNextVal INT  BEGIN EXECUTE \@RC =  WORKFLOW.MESSAGE_VERSION_Seq_Nextval \@pNextVal OUTPUT; select \@pNextVal  END";
      $msgVersion = $dbh->sproc($query, []);
      debug("msgVersion:$msgVersion");
  }
  	
  $query = "
      INSERT INTO MESSAGE (
        ID,
        TEMPLATE_ID,
        FUNCTIONAL_DOMAIN_ID,
        CODE,
        VERSION,
        MESSAGE,
        CREATED_BY,
        CREATION_DATE,
        MODIFIED_BY,
        MODIFICATION_DATE
      )
      VALUES (
        $msgId,
       (SELECT ID FROM TEMPLATE
         WHERE EVENT_CONFIG_ID = (SELECT ID
                                    FROM EVENT_CONFIG
                                   WHERE EVENT_NAME = '$eventName'
                                     AND FUNCTIONAL_DOMAIN_ID = (SELECT ID
                                                                   FROM FUNCTIONAL_DOMAIN_REF
                                                                  WHERE NAME='$funcDomRef'))),
       (SELECT ID FROM FUNCTIONAL_DOMAIN_REF WHERE NAME='$funcDomRef'),
        '$code',
        '$msgVersion',
        '$XML',
        'MID',
        GETDATE(),
        'MID',
        GETDATE()
      )";

	my $handler = $dbh->handler;
	my $sth     = $handler->prepare($query);

	if (!$sth) { error($DBI::errstr); return undef; }

  $sth->execute or notice('Insertion Failure !');
	
  #$query = " SELECT IDENT_CURRENT('WORKFLOW.MESSAGE') as CURR_IDENT"; 
  #$msgVs = $dbh->saarBind($query, []);
  #$msgVs = $msgVs->[0][0];
  #debug ("MSGVS:$msgVs");
  
  $query = "
    INSERT INTO JOURNAL (
      MESSAGE_ID,
      MESSAGE_VERSION,
      EVENTS_TYPE_ID,
      STATUS_ID,
      CREATED_BY,
      CREATION_DATE,
      MODIFIED_BY,
      MODIFICATION_DATE
    )
    VALUES (
      ?,
      ?,
     (SELECT ID FROM EVENTS_TYPE
       WHERE EVENT_CONFIG_ID = (SELECT ID FROM EVENT_CONFIG
                                 WHERE EVENT_NAME = ?
                                   AND FUNCTIONAL_DOMAIN_ID = (SELECT ID
                                                                 FROM FUNCTIONAL_DOMAIN_REF
                                                                WHERE NAME = ?))
         AND TEMPLATE_ID = (SELECT ID FROM TEMPLATE
                             WHERE EVENT_CONFIG_ID = (SELECT ID FROM EVENT_CONFIG
                                                       WHERE EVENT_NAME = ?
                                                         AND FUNCTIONAL_DOMAIN_ID = (SELECT ID
                                                                                       FROM FUNCTIONAL_DOMAIN_REF
                                                                                      WHERE NAME = ?)))),
     (SELECT ID FROM STATUS_REF WHERE NAME = 'NEW'),
     'MID',
     GETDATE(),
     'MID',
     GETDATE()
    ) ";

  return $dbh->doBind($query, [$msgId, $msgVersion, $eventName, $funcDomRef, $eventName, $funcDomRef]);
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Fonction de récupération d'un message dans le schema WORKFLOW
#   à partir d'un MESSAGE_ID et d'un MESSAGE_VERSION + MESSAGE_CODE
sub getMessageFromIdVersion {
  my $params = shift;
  
  my $msgId   = $params->{MESSAGE_ID};
  my $msgVs   = $params->{MESSAGE_VERSION};
  my $msgCode = $params->{MESSAGE_CODE};
  
  notice($msgId);
  notice($msgVs);
  notice($msgCode);
  # TODO - Faire les vérifications sur les arguments
  
  my $dbh = $cnxMgr->getConnectionByName('mid');
  
  my $query = "
      SELECT cast(MESSAGE as varchar(max)) COLLATE French_CI_AS
      FROM MESSAGE
      WHERE ID      = ?
        AND VERSION = ?
        AND CODE    = ?
        AND FUNCTIONAL_DOMAIN_ID IN (SELECT ID FROM FUNCTIONAL_DOMAIN_REF WHERE NAME IN ('BOOKING')) ";
        
  my $result = $dbh->saarBind($query, [$msgId, $msgVs, $msgCode]);
  
  # ____________________________________________________________________
  # Si on a pas de résultat, on va voir si on a pas un message équivalent
  #  qui traîne avec un MESSAGE_VERSION différent (plus élevé).
  if ((!defined $result) || (scalar @$result != 1)) {
    $query = "
        SELECT cast(MESSAGE as nvarchar(max)) COLLATE French_CI_AS
        FROM MESSAGE
        WHERE ID      = ?
          AND CODE    = ?
          AND FUNCTIONAL_DOMAIN_ID IN (SELECT ID FROM FUNCTIONAL_DOMAIN_REF WHERE NAME IN ('BOOKING'))
     ORDER BY VERSION DESC ";
    $result = $dbh->saarBind($query, [$msgId, $msgCode]);
    return undef unless ((defined $result) && (scalar @$result >= 1));
  }
  # ____________________________________________________________________

  return $result->[0][0];
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Insertion d'un XML dans MESSAGE a destination de l'application WBMI
sub insertWbmiMsg {
	my $params = shift;
	my $msgVersion = undef;
	
	my $XML   = $params->{XML};  $XML =~ s/'/''/ig;
	my $code  = $params->{CODE};
	
	my $eventName  = 'BTC_PROCESSED';
	my $funcDomRef = 'WBMI';
	
	if (!defined $code) { notice('CODE undefined [...]'); return undef; }
	if (!defined $XML)  { notice('XML undefined [...]');  return undef; }
		
	my $dbh = $cnxMgr->getConnectionByName('mid');
	
	my $query = "SELECT MAX(ID) FROM MESSAGE WHERE CODE= ? AND FUNCTIONAL_DOMAIN_ID= (SELECT ID FROM FUNCTIONAL_DOMAIN_REF WHERE NAME = ? )";
  my $msgId = $dbh->saarBind($query, [$code,$funcDomRef])->[0][0] || undef;
	
  if (!defined $msgId) {
    $query = "DECLARE \@RC INT , \@pNextVal INT  BEGIN EXECUTE \@RC =  WORKFLOW.Message_Seq_Nextval \@pNextVal OUTPUT; select \@pNextVal  END";
    $msgId = $dbh->sproc($query, []);
    debug("MSGID_insertWbmiMsg:$msgId");
  }

  #ON RECUPERE LA VERSION
  if    (!defined $msgVersion)    
  {
      my $query = "DECLARE \@RC INT , \@pNextVal INT  BEGIN EXECUTE \@RC =  WORKFLOW.MESSAGE_VERSION_Seq_Nextval \@pNextVal OUTPUT; select \@pNextVal  END";
      $msgVersion = $dbh->sproc($query, []);
      debug("msgVersion:$msgVersion");
  }
  
  $query = "
      INSERT INTO MESSAGE (
        ID,
        TEMPLATE_ID,
        FUNCTIONAL_DOMAIN_ID,
        CODE,
        VERSION,
        MESSAGE,
        CREATED_BY,
        CREATION_DATE,
        MODIFIED_BY,
        MODIFICATION_DATE
      )
      VALUES (
        $msgId,
       (SELECT ID FROM TEMPLATE
         WHERE EVENT_CONFIG_ID = (SELECT ID
                                    FROM EVENT_CONFIG
                                   WHERE EVENT_NAME = '$eventName'
                                     AND FUNCTIONAL_DOMAIN_ID = (SELECT ID
                                                                   FROM FUNCTIONAL_DOMAIN_REF
                                                                  WHERE NAME='$funcDomRef'))),
       (SELECT ID FROM FUNCTIONAL_DOMAIN_REF WHERE NAME='$funcDomRef'),
        '$code',
        '$msgVersion',
        '$XML',
        'MID',
        GETDATE(),
        'MID',
        GETDATE()
      ); ";

	my $handler = $dbh->handler;
	my $sth     = $handler->prepare($query);

	if (!$sth) { error($DBI::errstr); return undef; }

  $sth->execute or notice('Insertion Failure !');

  #$query = " SELECT IDENT_CURRENT('WORKFLOW.MESSAGE') as CURR_IDENT"; 
  #my $msgVs = $dbh->saarBind($query, []);
  #$msgVs = $msgVs->[0][0];
  
  $query = "
    INSERT INTO JOURNAL (
      MESSAGE_ID,
      MESSAGE_VERSION,
      EVENTS_TYPE_ID,
      STATUS_ID,
      CREATED_BY,
      CREATION_DATE,
      MODIFIED_BY,
      MODIFICATION_DATE
    )
    VALUES (
      ?,
      ?,
     (SELECT ID FROM EVENTS_TYPE
       WHERE EVENT_CONFIG_ID = (SELECT ID FROM EVENT_CONFIG
                                 WHERE EVENT_NAME = ?
                                   AND FUNCTIONAL_DOMAIN_ID = (SELECT ID
                                                                 FROM FUNCTIONAL_DOMAIN_REF
                                                                WHERE NAME = ?))
         AND TEMPLATE_ID = (SELECT ID FROM TEMPLATE
                             WHERE EVENT_CONFIG_ID = (SELECT ID FROM EVENT_CONFIG
                                                       WHERE EVENT_NAME = ?
                                                         AND FUNCTIONAL_DOMAIN_ID = (SELECT ID
                                                                                       FROM FUNCTIONAL_DOMAIN_REF
                                                                                      WHERE NAME = ?)))),
     (SELECT ID FROM STATUS_REF WHERE NAME = 'NEW'),
     'MID',
     GETDATE(),
     'MID',
     GETDATE() 
    ) ";

  return $dbh->doBind($query, [$msgId, $msgVersion, $eventName, $funcDomRef, $eventName, $funcDomRef]);
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

1;
