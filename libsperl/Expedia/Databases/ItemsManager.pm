package Expedia::Databases::ItemsManager;
#-----------------------------------------------------------------
# Package Expedia::Databases::ItemsManager
#
# $Id: ItemsManager.pm 712 2011-07-04 15:43:55Z pbressan $
#
# (c) 2002-2007 Expedia.                   www.expediacorporate.fr
#-----------------------------------------------------------------

use Data::Dumper;
use Exporter 'import';

use Expedia::WS::Front qw(&changeDeliveryState);
use Expedia::Tools::Logger qw(&debug &notice &warning &error &monitore);
use Expedia::Tools::GlobalVars qw($cnxMgr $soapRetry);
use Expedia::Databases::MidSchemaFuncs qw(&lockWorkTableItem &getAppId);

@EXPORT_OK = qw(&btcLockItem &btcUnlockItem &btcInsertItem &btcUpdateItem &btcGetItems &btcRefreshItemStatus &btcUnlockItemNeedRetry
                &tasLockItem &tasUnlockItem &tasInsertItem &tasUpdateItem &tasGetItems &tasIsItemLocked
                &tasGlobalInsert &tasCheckAndLockItemIntoInProgress &tasUnlockItemInProgress
                &synLockItem &synUnlockItem &updateDispatchAfterReclaim &tasCheckItemInProgress);

use strict;

# TODO - Gestion des items lockés par un process pour les unlock en
#        Cas de plantage de PERL -CLEAN à l'aide d'un END {}

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Lock an item / BTC process
sub btcLockItem {
  my $params     = shift;
  
  my $ref        = $params->{REF}        || undef;
  my $task       = $params->{TASK}       || undef;
  my $pnr        = $params->{PNR}        || undef;
  
  if (!$task || !$ref || $task =~ /^\s*$/ || $ref =~ /^\s*$/ || $ref !~ /^(\d+)$/) {
    error('Missing or wrong parameter for this method.');
    return 0;
  }

  my $dbh   = $cnxMgr->getConnectionByName('mid');
  my $appId = getAppId($task);

  if (!$appId) {
    warning("No appId was found for task '$task' in APPLICATIONS table. Aborting.");
    return 0;
  } else { debug('appId = '.$appId) if ($appId); }

  my $query = "
    SELECT I.LOCKED, I.TRY, I.STATUS, CONVERT(VARCHAR(10),I.TIME,103) + ' ' + CONVERT(VARCHAR(8),I.TIME,8),
           CONVERT(INT,86400 * (CONVERT(DECIMAL(10,5),GETDATE()) - CONVERT(DECIMAL(10,5),CONVERT(DATETIME,I.TIME,103) ) ) ) SECONDES, I.TYPE
      FROM IN_PROGRESS I
     WHERE I.APP_ID = ?
       AND I.REF    = ? 
       AND I.PNR    = ?";
   my $query2 = "
    SELECT I.LOCKED, I.TRY, I.STATUS, I.TIME, 
           CONVERT(INT,86400 * (CONVERT(DECIMAL(10,5),GETDATE()) - CONVERT(DECIMAL(10,5),CONVERT(DATETIME,I.TIME,103) ) ) ) SECONDES, I.TYPE
      FROM IN_PROGRESS I
     WHERE I.APP_ID = ?
       AND I.REF    = ? 
       AND I.PNR    = ?";
  my $result = $dbh->saarBind($query2, [$appId, $ref, $pnr]);
  debug('resu = '.Dumper($result));
  debug('time = '.$result->[0][3]) if (scalar @$result != 0);
  my $exists = 0;
     $exists = 1 if (scalar @$result == 1);

  if ((scalar @$result == 0)     ||                      # Aucun résultat trouvé
      ($result->[0][0] == 1)     ||                      # Item locké
      ($result->[0][1] >= 5)     ||                      # Nombre d'essais déja effectué >= 5
      ($result->[0][2] !~ /^(new|retrieve|process)$/)) { # Le status n'est plus égal à 'new', 'retrieve' ou process
    notice('This item has already been treated.')                if (scalar @$result == 0);
    notice('This item is already locked.')                       if (($exists) && ($result->[0][0] == 1));
    notice('This item has already been tried 5 times.')          if (($exists) && ($result->[0][1] >= 5));
    notice("Item status is not 'new', 'retrieve' or 'process'.") if (($exists) && ($result->[0][2] !~ /^(new|retrieve|process)$/));
    # -----------------------------------------------------------------
    # Si TRY est supérieur à 5 on passe celui ci directement en 'error'
    btcUpdateItem({REF => $ref, TASK => $task, STATUS => 'error', PNR => $pnr})
      if (($exists) && ($result->[0][1] >= 5));
    # -----------------------------------------------------------------      
    return 0;
  } else {
    # -----------------------------------------------------------------
    # Vérifie le nombre de secondes écoulées depuis la dernière prise
    #  en compte d'un enregistrement TRAIN dont le status est en 'retrieve'.
    my $secs = $result->[0][4]; debug('secs = '.$secs.' secondes.');
    my $type = $result->[0][5]; debug('type = '.$type);
    if (($type =~ /^(SNCF_TC|RG_TC)$/) && ($result->[0][2] =~ /^(retrieve)$/) && ($secs < 60) ) {
      notice('Retrieve attempt time have to be superior to 60 secs.');
      notice('System will retry this item later.');
      return 0;
    }
    # -----------------------------------------------------------------
    my $try  = $result->[0][1] + 1; debug('try  = '.$try);
    my $time = $result->[0][3];     debug('time = '.$time);
    $query  = "
      UPDATE IN_PROGRESS SET TRY = $try, LOCKED = 1, TIME = GETDATE()
       WHERE REF    = '$ref'
         AND PNR    = '$pnr'
         AND APP_ID = '$appId'
         AND LOCKED = 0
         AND CONVERT(CHAR(10),GETDATE(),103) + ' ' + CONVERT(CHAR(10),GETDATE(),8) = '$time' "; # LOCK OPTIMISTE
    $query2  = "
      UPDATE IN_PROGRESS SET TRY = $try, LOCKED = 1, TIME = GETDATE()
       WHERE REF    = '$ref'
         AND PNR    = '$pnr'
         AND APP_ID = '$appId'
         AND LOCKED = 0
         AND TIME = '$time' "; # LOCK OPTIMISTE
    unless ($dbh->do($query2)) {
      notice("No row has been updated 'btcLockItem' operation...");
      return 0;
    }
  }

  return 1;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Refresh a BTC item STATUS (used in BTC-TRAIN)
sub btcRefreshItemStatus {
  my $params     = shift;
  
  my $ref        = $params->{REF}        || undef;
  my $task       = $params->{TASK}       || undef;
  my $pnr        = $params->{PNR}        || undef;
  
  if (!$task || !$ref || $task =~ /^\s*$/ || $ref =~ /^\s*$/ || $ref !~ /^(\d+)$/) {
    error('Missing or wrong parameter for this method.');
    return undef;
  }

  my $dbh   = $cnxMgr->getConnectionByName('mid');
  my $appId = getAppId($task);

  if (!$appId) {
    warning("No appId was found for task '$task' in APPLICATIONS table. Aborting.");
    return undef;
  } else { debug('appId = '.$appId) if ($appId); }

  my $query = '
    SELECT STATUS
      FROM IN_PROGRESS
     WHERE APP_ID = ?
       AND REF    = ? 
       AND PNR    = ?';
  my $result = $dbh->saarBind($query, [$appId, $ref,$pnr])->[0][0];
  
  return $result;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Unlock an item / BTC process
sub btcUnlockItem {
  my $params     = shift;
  
  my $ref        = $params->{REF}        || undef;
  my $task       = $params->{TASK}       || undef;
  my $pnr        = $params->{PNR}        || undef;
  

  if (!$task || !$ref || $task =~ /^\s*$/ || $ref =~ /^\s*$/ || $ref !~ /^(\d+)$/) {
    error('Missing or wrong parameter for this method.');
    return 0;
  }

  my $dbh   = $cnxMgr->getConnectionByName('mid');
  my $appId = getAppId($task);

  if (!$appId) {
    warning("No appId was found for task '$task' in APPLICATIONS table. Aborting.");
    return 0;
  } else { debug('appId = '.$appId) if ($appId); }

  my $query = '
    UPDATE IN_PROGRESS
       SET LOCKED = 0
     WHERE REF    = ?
       AND APP_ID = ?
       AND PNR    = ? ';
	unless ($dbh->doBind($query, [$ref, $appId, $pnr])) { warning('No row has been updated'); return 0; }

  return 1;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Unlock an item / BTC process and decrease the number of tries by One
sub btcUnlockItemNeedRetry {
  my $params     = shift;
  
  my $ref        = $params->{REF}        || undef;
  my $task       = $params->{TASK}       || undef;
  my $pnr        = $params->{PNR}        || undef;
  
  if (!$task || !$ref || $task =~ /^\s*$/ || $ref =~ /^\s*$/ || $ref !~ /^(\d+)$/) {
    error('Missing or wrong parameter for this method.');
    return 0;
  }

  my $dbh   = $cnxMgr->getConnectionByName('mid');
  my $appId = getAppId($task);

  if (!$appId) {
    warning("No appId was found for task '$task' in APPLICATIONS table. Aborting.");
    return 0;
  } else { debug('appId = '.$appId) if ($appId); }

  my $query = '
    UPDATE IN_PROGRESS
       SET LOCKED = 0,
           TRY    = (SELECT TRY FROM IN_PROGRESS WHERE REF = ? AND APP_ID = ?) - 1
     WHERE REF    = ?
       AND APP_ID = ?
       AND PNR    = ?  ';
	unless ($dbh->doBind($query, [$ref, $appId, $ref, $appId, $pnr])) { warning('No row has been updated'); return 0; }

  return 1;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Insert a new item in table IN_PROGRESS / BTC process
sub btcInsertItem {
  my $params     = shift;
  
  my $ref        = $params->{REF}        || undef;
  my $task       = $params->{TASK}       || undef;
  my $type       = $params->{TYPE}       || undef;
  my $PNR        = $params->{PNR}        || undef;    

  if (!$task || !$ref || !$type || $task =~ /^\s*$/ || $ref =~ /^\s*$/ || $ref !~ /^(\d+)$/ ||
      $type !~ /^(SNCF_TC|WAVE_TC|GAP_TC|RG_TC|MASERATI_CAR_TC)$/) {
    error('Missing or wrong parameter for this method.');
    return 0;
  }

  my $dbh   = $cnxMgr->getConnectionByName('mid');
  my $appId = getAppId($task);

  if (!$appId) {
    warning("No appId was found for task '$task' in APPLICATIONS table. Aborting.");
    return 0;
  } else { debug('appId = '.$appId) if ($appId); }
  
  # ____________________________________________________________________
  # Vérification de l'existence
  my $query = "
    SELECT REF FROM IN_PROGRESS
     WHERE REF    = ?
       AND TYPE   = ?
       AND PNR    = ?
       AND APP_ID = ? ";
  my $exist = scalar(@{$dbh->saarBind($query, [$ref, $type, $PNR, $appId])});
  
  if ($exist) {
    debug("btcInsertItem: Item REF = $ref already exists in IN_PROGRESS table.");
    return 0;
  }            
  # ____________________________________________________________________
  
  else {
    my $list = [];
    if ($PNR) {
      $query = "
        INSERT INTO IN_PROGRESS (REF, TYPE, APP_ID, PNR, STATUS)
        VALUES (?, ?, ?, ?, 'new') ";
      $list  = [$ref, $type, $appId, $PNR];
    } else {
      $query = "    
        INSERT INTO IN_PROGRESS (REF, TYPE, APP_ID, STATUS)
        VALUES (?, ?, ?, 'new') ";
      $list  = [$ref, $type, $appId];
    }    
  	unless ($dbh->doBind($query, $list)) { warning('No row has been updated'); return 0; }
  }

  return 1;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Update the "status" of an item or delete it if status = finished / BTC process
sub btcUpdateItem {
  my $params     = shift;

  my $ref        = $params->{REF}        || undef;
  my $task       = $params->{TASK}       || undef;
  my $status     = $params->{STATUS}     || undef;
  my $errorId    = $params->{ERROR_ID}   || 0;
  
  if (!$task || !$ref || !$status || $task =~ /^\s*$/ || $status =~ /^\s*$/ || $ref =~ /^\s*$/ || $ref !~ /^(\d+)$/) {
    error('Missing or wrong parameter for this method.');
    return 0;
  }

  my $dbh    = $cnxMgr->getConnectionByName('mid');
  my $query1 = undef;
  my $query2 = undef;
  my $list1  = [];
  my $list2  = [];
  my $appId  = getAppId($task);

  if (!$appId) {
    warning("No appId was found for task '$task' in APPLICATIONS table. Aborting.");
    return 0;
  } else { debug('appId = '.$appId) if ($appId); }

  if ($status eq 'finished') {
    $query1 = '
      DELETE FROM IN_PROGRESS
       WHERE APP_ID = ?
         AND REF    = ? ';
    $list1  = [$appId, $ref];
    $query2 = '
      DELETE FROM WORK_TABLE
       WHERE ID = ? '; # Tout s'est bien déroulé, on supprime la ligne dans WORK_TABLE.
    $list2  = [$ref];
  }
  elsif ($status eq 'error') {
    $query1 = "
      UPDATE IN_PROGRESS
         SET STATUS = 'error', LOCKED = 0
       WHERE APP_ID = ?
         AND REF    = ? ";
    $list1  = [$appId, $ref];
    $query2 = "
      UPDATE WORK_TABLE 
         SET STATUS = 'ERROR', ERROR_ID = ?, TIME = GETDATE()
       WHERE ID = ?"; # On passe le statut en ERROR dans la WORK_TABLE.
    $list2  = [$errorId, $ref];
  }
  else {
    $query1 = '
      UPDATE IN_PROGRESS
         SET STATUS = ?, LOCKED = 0
       WHERE APP_ID = ?
         AND REF    = ? ';
    $list1  = [$status, $appId, $ref];
  }
	unless ($dbh->doBind($query1, $list1)) { warning('No row has been updated'); return 0; }
	
	$dbh->doBind($query2, $list2) if (defined $query2); # Action à mener éventuellement sur la table WORK_TABLE.

  return 1;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Get Items / BTC process
sub btcGetItems {
  my $task = shift;

  if (!$task || $task =~ /^\s*$/) {
    error('Missing or wrong parameter for this method.');
    return 0;
  }

  my $dbh   = $cnxMgr->getConnectionByName('mid');
  my $appId  = getAppId($task);

  if (!$appId) {
    warning("No appId was found for task '$task' in APPLICATIONS table. Aborting.");
    return 0;
  } else { debug('appId = '.$appId) if ($appId); }
  
  my $query = "
    SELECT I.REF, I.PNR, I.STATUS, I.TYPE, 
    --CAST(WT.XML as varchar(max)) as XML
    CONVERT(VARCHAR(MAX), CONVERT(NVARCHAR(MAX), WT.XML)) as XML,
      WT.MESSAGE_CODE, WT.MESSAGE_TYPE, WT.MESSAGE_VERSION, I.TRY
      FROM IN_PROGRESS I, WORK_TABLE WT
     WHERE I.APP_ID = ?
       AND I.STATUS IN ('new','retrieve', 'process')
       AND I.LOCKED = 0
       AND I.TRY   <= 5
       AND WT.ID    = I.REF 
       AND WT.PNR   = I.PNR
  ORDER BY I.TIME ASC, I.REF ASC ";
  
  my $res   = $dbh->saarBind($query, [$appId]);
  my @items = ();

	foreach (@$res) {
	  push (@items, {
      REF         => $_->[0],
		  PNR         => $_->[1],
		  STATUS      => $_->[2],
		  TYPE        => $_->[3],
		  XML         => $_->[4],
		  MSG_CODE    => $_->[5],
		  MSG_TYPE    => $_->[6],
		  MSG_VERSION => $_->[7],
		  TRY         => $_->[8],
		});
  }

  return @items;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@


# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Vérifie si un item est déjà locké ou non.
sub tasIsItemLocked {
  my $params = shift;
  
  my $ref    = $params->{REF} || undef;
  my $PNR    = $params->{PNR} || undef;
  
  if (!$ref || $ref =~ /^\s*$/ || $ref !~ /^\d+$/ ||
      !$PNR || $PNR =~ /^\s*$/) {
    error('Missing or wrong parameter for this method.');
    return 0;
  }
  
  my $dbh   = $cnxMgr->getConnectionByName('mid');
  my $mypnr="'%".$PNR."%'";
  my $query = qq{
  	    SELECT LOCKED_BY 
  	    FROM DELIVERY_FOR_DISPATCH
  	    WHERE META_DOSSIER_ID = ?
  	    AND PNR LIKE $mypnr
  	    AND LOCKED_BY IS NOT NULL
  	    AND LOCKED_BY != ''
  };
  my $res   = $dbh->saarBind($query, [$ref]);

  return [] unless defined $res;
  return $res;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Lock an item / TAS process
sub tasLockItem {
  my $params = shift;
  
  my $ref    = $params->{REF} || undef;
  my $PNR    = $params->{PNR} || undef;

  if (!$ref || $ref =~ /^\s*$/ || $ref !~ /^\d+$/ ||
      !$PNR || $PNR =~ /^\s*$/) {
    error('Missing or wrong parameter for this method.');
    return 0;
  }

  my $dbh   = $cnxMgr->getConnectionByName('mid');
  my $query = "INSERT INTO DELIVERY_LOCK (AGENT_ID, PNR) VALUES ('BTC_TAS', ?)";

  my $rowsAffected = $dbh->doBind($query, [$PNR], 1);
  if (!$rowsAffected || ($rowsAffected && ($rowsAffected == 0))) {
    notice("Failed to lock TAS PNR '".$PNR."' in dispatch interface.");
    my $isItemLocked = tasIsItemLocked($PNR);
    if (scalar(@$isItemLocked) == 1) {
      notice("PNR '".$PNR."' is locked by ".$isItemLocked->[0][0].'.');
      # _________________________________________________________________
      # Crotte de bique ! Si je n'ai pas réussi à locker dans le dispatch
      # ~ je dois unlocker dans mes tables de travail [...]
      if ($isItemLocked->[0][0] ne 'BTC_TAS') {
        $query  = "
          UPDATE IN_PROGRESS SET LOCKED = 0, TIME = GETDATE() 
           WHERE REF    = ?
             AND PNR    = ?
             AND APP_ID = 0
             AND TYPE   = 'EMPTY' ";
        $dbh->doBind($query, [$ref, $PNR]);
      }
      # _________________________________________________________________
    }
    return 0;
  }

  return 1;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

sub tasCheckItemInProgress {
  my $params = shift;

  my $ref = $params->{REF}  || undef;
  my $PNR = $params->{PNR}  || undef;

  if (!$ref  || $ref =~ /^\s*$/ || $ref !~ /^\d+$/ ||
      !$PNR  || $PNR =~ /^\s*$/) {
    error('Missing or wrong parameter for this method.');
    return 0;
  }

  my $dbh = $cnxMgr->getConnectionByName('mid');

  my $query = "
    SELECT REF
      FROM IN_PROGRESS
     WHERE REF    = ?
       AND PNR    = ?
       AND LOCKED = 1";
  my $result = $dbh->saarBind($query, [$ref, $PNR]);
  if (scalar @$result > 0) {
    notice('The treatment of this item is already in progress.');
    return 1;
  } else {
    return 0;
  }
}

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Lock an item / TAS process - Table IN_PROGRESS.
#   __ Supporte le traitement // [Parallèle] __
# Vérifie également que le dossier n'a pas déjà été traité par un
#   autre processus
sub tasCheckAndLockItemIntoInProgress {
  my $params = shift;
  
  my $ref = $params->{REF}  || undef;
  my $PNR = $params->{PNR}  || undef;

  if (!$ref  || $ref =~ /^\s*$/ || $ref !~ /^\d+$/ ||
      !$PNR  || $PNR =~ /^\s*$/) {
    error('Missing or wrong parameter for this method.');
    return 0;
  }

  my $dbh = $cnxMgr->getConnectionByName('mid');

  # ____________________________________________________________________
  # Utilisé pour vérifier la présence d'une ligne avec la REF
  #   et la tâche.
  my $query = "
    SELECT REF
      FROM IN_PROGRESS
     WHERE REF    = ? 
       AND PNR    = ?
       AND STATUS IN ('new','TAS_TICKETED','TAS_CHECKED','TAS_ERROR','error')
       AND APP_ID IN (SELECT ID
                        FROM APPLICATIONS
                       WHERE NAME IN ('tas-air-etkt',
                                      'tas-air-paper',
                                      'tas-train-etkt',
                                      'tas-train-ebillet',
                                      'tas-train-tless',
                                      'tas-train-paper')) ";
  my $result = $dbh->saarBind($query, [$ref, $PNR]);
  if (scalar @$result > 0) {
    notice('The treatment of this item is already in progress.');
    return 0;
  }
  # ____________________________________________________________________

  # ____________________________________________________________________
  # Je commence par locker dans mes tables de travail pour voir si c'est
  #   possible. Cette fois ci : APP_ID = 'EMPTY'
  $query = "
    SELECT LOCKED, CONVERT(VARCHAR(10),TIME,103) + ' ' + CONVERT(VARCHAR(10),TIME,8)
      FROM IN_PROGRESS
     WHERE APP_ID = 0
       AND TYPE   = 'EMPTY'
       AND PNR    = ?
       AND REF    = ? ";
  $result = $dbh->saarBind($query, [$PNR, $ref]);
# debug('result = '.Dumper($result));
  debug('time = '.$result->[0][1]) if (scalar @$result != 0);
  my $exists = 0;
     $exists = 1 if (scalar @$result == 1);

  if ((scalar @$result == 0) || # Aucun résultat trouvé
      ($result->[0][0] == 1)) { # Item déjà locké
    notice('This item has already been treated.') if (scalar @$result == 0);
    notice('This item is already locked.')        if (($exists) && ($result->[0][0] == 1));    
    return 0;
  } else {
    my $time = $result->[0][1];
    $query  = "
      UPDATE IN_PROGRESS SET LOCKED = 1, TIME = GETDATE()
       WHERE REF    = ?
         AND PNR    = ?
         AND APP_ID = 0
         AND TYPE   = 'EMPTY'
         AND LOCKED = 0
         AND CONVERT(VARCHAR(10),TIME,103) + ' ' + CONVERT(VARCHAR(10),TIME,8) = ? "; # LOCK OPTIMISTE
    unless ($dbh->doBind($query, [$ref, $PNR, $time])) {
      notice("No row has been updated 'tasLockItem' operation...");
      return 0;
    }
  }
  # ____________________________________________________________________
  
  # ____________________________________________________________________
  # Si je suis ici, c'est que j'ai réussi à locker dans mes tables
  # ~ de travail.
  # ____________________________________________________________________

  return 1;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Lock an item / TAS process
sub tasUnlockItem {
  my $params = shift;
  
  my $ref    = $params->{REF} || undef;
  my $PNR    = $params->{PNR} || undef;

  if (!$ref || $ref =~ /^\s*$/ || $ref !~ /^\d+$/ ||
      !$PNR || $PNR =~ /^\s*$/) {
    error('Missing or wrong parameter for this method.');
    return 0;
  }
  
  my $dbh = $cnxMgr->getConnectionByName('mid');
  #TODO SYSDATE -> pas d'interaction avec la timezone.. heure technique 
  my $query  = "
    UPDATE IN_PROGRESS SET LOCKED = 0, TIME = GETDATE()
     WHERE REF    = ?
       AND PNR    = ?
       AND APP_ID = 0
       AND TYPE   = 'EMPTY' ";
  $dbh->doBind($query, [$ref, $PNR]);
 
  $query = "DELETE FROM DELIVERY_LOCK WHERE AGENT_ID = 'BTC_TAS' AND PNR = ?";
  
  my $rowsAffected = $dbh->doBind($query, [$PNR]);
  if (!$rowsAffected || ($rowsAffected && ($rowsAffected == 0))) {
    notice("Failed to unlock TAS PNR '".$PNR."'.");
    return 0;
  }

  return 1;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# // Parallèlisation de TAS - Déverrouillage de la table IN_PROGRESS
#  uniquement.
sub tasUnlockItemInProgress {
  my $params = shift;
  
  my $ref = $params->{REF}  || undef;
  my $PNR = $params->{PNR}  || undef;

  if (!$ref  || $ref =~ /^\s*$/ || $ref !~ /^\d+$/ ||
      !$PNR  || $PNR =~ /^\s*$/) {
    error('Missing or wrong parameter for this method.');
    return 0;
  }

  my $dbh = $cnxMgr->getConnectionByName('mid');
  
  my $query  = "
    UPDATE IN_PROGRESS SET LOCKED = 0, TIME = GETDATE()
     WHERE REF    = ?
       AND PNR    = ?
       AND APP_ID = 0
       AND TYPE   = 'EMPTY' ";
  $dbh->doBind($query, [$ref, $PNR]);
  
  return 1;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Insert a new item in table IN_PROGRESS / TAS process
sub tasInsertItem {
  my $params     = shift;
  
  my $ref        = $params->{REF}         || undef;
  my $task       = $params->{TASK}        || undef;
  my $subTask    = $params->{SUBTASK}     || undef; 
  my $type       = $params->{TYPE}        || undef;
  my $PNR        = $params->{PNR}         || undef;
  my $deliveryId = $params->{DELIVERY_ID} || undef;
  my $xml        = $params->{XML}         || undef;

  if (!$task       || $task =~ /^\s*$/ ||
      !$ref        || $ref  =~ /^\s*$/ || $ref !~ /^\d+$/   ||
      !$type       || $type !~ /^(SNCF_TC|WAVE_TC|GAP_TC|RG_TC)$/ ||
      !$deliveryId || $deliveryId !~ /^\d+$/                ||
      !$subTask) {
    error('Missing or wrong parameter for this method.');
    return 0;
  }

  my $dbh = $cnxMgr->getConnectionByName('mid');

  # ____________________________________________________________________
  my $appId = getAppId($task);
  if (!$appId) {
    warning("No appId was found for task '$task' in APPLICATIONS table. Aborting.");
    return 0;
  } else { debug('appId = '.$appId); }
  my $subAppId = getAppId($subTask);
  if (!$subAppId) {
    warning("No subAppId was found for task '$subTask' in APPLICATIONS table. Aborting.");
    return 0;
  } else { debug('subAppId = '.$subAppId); }
  # ____________________________________________________________________

  $PNR = defined($PNR) ? uc($PNR) : 'NULL';

  # ------------------------------------------------------------------
  # Regardons si l'item n'est pas déjà présent dans le working set
  my $query = "
    SELECT REF FROM IN_PROGRESS
     WHERE APP_ID      = ?
       AND SUBAPP_ID   = ?
       AND REF         = ?
       AND STATUS   IN ('new','TAS_TICKETED','TAS_CHECKED','TAS_ERROR','error')
       AND PNR         = ?
       AND DELIVERY_ID = ? ";
  my $result = $dbh->saarBind($query, [$appId, $subAppId, $ref, $PNR, $deliveryId]);
  my $exist  = 0;
     $exist  = scalar(@$result) if defined($result);
  debug("PNR = '$PNR' already exists in IN_PROGRESS table.") if ($exist >= 1);  
  # -----------------------------------------------------------
  
  if (!$exist) {
    # --------------------------------------------------------------
    # Obligation de passer par une procédure stockée pour pouvoir
    #   intégrer des éléments de type CLOB !
    
    $xml =~ s/'/''''/ig;
    
    my $query = "
        INSERT INTO IN_PROGRESS (
          REF,    TYPE,     APP_ID,        SUBAPP_ID, 
          PNR,    STATUS,   DELIVERY_ID,   XML
        )
        VALUES (
          $ref,  '$type',   $appId,        $subAppId,
         '$PNR', 'new',     $deliveryId,   '$xml'
        ) ";
    eval {
      my $sth = $dbh->handler->prepare($query);
         $sth->execute();
    };
    if ($@ || $DBI::errstr) {
      warning('Problem detected during insert into IN_PROGRESS. '.$@) if ($@);
      warning($DBI::errstr) if ($DBI::errstr);
      return 0;
    }
    # --------------------------------------------------------------
  }

  return 1;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Insère d'un coup tous les items devant être traités par TAS dans la
#  table IN_PROGRESS. Objet // Parallèlisation ;)
# ______________________________________________________________________
# Cette fonction est spécifique et utile aux traitements en parallèle
#  de TAS. Les items insérés auront pour APP_ID = 0 [ empty ] et
#  type [ EMPTY ].
#
# Nous nous servons de la contrainte d'unicité imposée sur la table
#  IN_PROGRESS, CONSTRAINT "UQ_IP_REF_APP_ID" UNIQUE ("REF", "APP_ID").
#
# Le paramètre "1", passé à la fin de doBind permet, quant à lui, de ne
#  pas remonter ce problème d'unicité dans les erreurs (mode silent).
# ______________________________________________________________________
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
sub tasGlobalInsert {
  my $items = shift;
  
  my $dbh   = $cnxMgr->getConnectionByName('mid');
  
  my $query = "
    INSERT INTO IN_PROGRESS (REF, TYPE, APP_ID, PNR, STATUS)
    VALUES (?, 'EMPTY', 0, ?, 'new') ";
  
  my $rowsAffected = 0;
  
  foreach my $item (@$items) {
    if($item->{PNR} =~/,/)
    {
        my @ListPNR = split(/,/, $item->{PNR});
        foreach my $val_pnr (@ListPNR)
        {
          $rowsAffected = $dbh->doBind($query, [$item->{REF}, $val_pnr], 1);
          debug('REF = '.$item->{REF}.' - RowsAffected = '.$rowsAffected.' - PNR = '.$val_pnr);
        }
    }
    else
    { 
    $rowsAffected = $dbh->doBind($query, [$item->{REF}, $item->{PNR}], 1);
    debug('REF = '.$item->{REF}.' - RowsAffected = '.$rowsAffected.' - PNR = '.$item->{PNR});
    }
  }
  
  return 1;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Update a TAS item. Delete it if status == finished.
sub tasUpdateItem {
  my $params     = shift;  

  my $ref        = $params->{REF}         || undef;
  my $task       = $params->{TASK}        || undef;
  my $subTask    = $params->{SUBTASK}     || undef; 
  my $status     = $params->{STATUS}      || undef;
  my $PNR        = $params->{PNR}         || undef;
  my $tasError   = $params->{TAS_ERROR}   || undef;
  my $deliveryId = $params->{DELIVERY_ID} || undef;
  my $market     = $params->{MARKET}      || undef;
  my $productCode=  $params->{PRDCT_TP_ID} || undef;

  if (!$task || !$ref || !$status || $task =~ /^\s*$/ ||
      $ref =~ /^\s*$/ || $ref !~ /^(\d+)$/ || !$subTask) {
    error('Missing or wrong parameter for this method.');
    return 0;
  }
 
  my $dbh = $cnxMgr->getConnectionByName('mid');

  # ____________________________________________________________________
  # Récupération des identifiants "application" et "sous-application"
  my $appId = getAppId($task);
  if (!$appId) {
    warning("No appId was found for task '$task' in APPLICATIONS table. Aborting.");
    return 0;
  } else { debug('appId = '.$appId) if ($appId); }
  my $subAppId = getAppId($subTask);
  if (!$subAppId) {
    warning("No subAppId was found for task '$subTask' in APPLICATIONS table. Aborting.");
    return 0;
  } else { debug('subAppId = '.$subAppId) if ($subAppId); }
  # ____________________________________________________________________
  
  # ____________________________________________________________________
  # Suppression de la ligne utilisée pour la // parallèlisation de TAS
  my $query = "
    DELETE FROM IN_PROGRESS
     WHERE REF    = ?
       AND PNR    = ?
       AND APP_ID = 0
       AND TYPE   = 'EMPTY' ";
  $dbh->doBind($query, [$ref, $PNR]);
  # ____________________________________________________________________

  # ____________________________________________________________________
  # Delete TAS item if status eq 'finished'
  if ($status eq 'finished') {
    $query = "
      DELETE FROM IN_PROGRESS
       WHERE REF       = ?
         AND PNR       = ?
         AND APP_ID    = ?
         AND SUBAPP_ID = ?
         AND STATUS IN ('new','TAS_ERROR','TAS_CHECKED') ";

    my $rows = $dbh->doBind($query, [$ref, $PNR, $appId, $subAppId]);

    warning("Number of deleted lines = $rows (!= 1)") if ($rows != 1);

    return 0 if ($rows != 1);

    return 1;
  }
  # ____________________________________________________________________
     
  # ____________________________________________________________________
  # Si le status est TAS_CHECKED, il faut également changer le statut
  #   du dossier à Emis [...]
  if ($status eq 'TAS_CHECKED') {

    debug("status = 'TAS_CHECKED' ");
    
    $tasError = 0;
    
    my $soapOut = undef;
	   $soapOut = changeDeliveryState('DeliveryWS', {deliveryId => $deliveryId, deliveryStatus => 2});
		 
		 
	my $product=undef;
	   $product=$1 if ($task =~ m/-(\w*)-/);  
	   
	if($product eq 'train'){
        $product = 'rail';
    }   
	
	if (!defined($soapOut)) {
		push (@$soapRetry, {deliveryId     => $deliveryId,
							deliveryStatus => 2,
							pnrId          => $PNR,
							tasCode        => $tasError,
							tryNo          => 0});
		&monitore("TAS_TICKETING", "DELIVERY_STATUS_CHANGE","ERROR",$market,$product,$PNR,'',"WEBSERVICE CALL") if (defined ($productCode)) ; # check condition on defined productcode				
	} else {
		&monitore("TAS_TICKETING", "DELIVERY_STATUS_CHANGE","INFO",$market,$product,$PNR,'',"WEBSERVICE CALL") if (defined ($productCode)); # check condition on defined productcode
	
	}
	
    if ( defined($productCode) && $productCode == 2 ) {
		#THE BELOW QUERY WILL UPDATE IN_PROGRESS BEFORE CHECKING DV RAIL PNR STATUS AS 
		#TAS_CHECKED AND TO MAKE SURE THE CURRENT PNR IS ALSO COUNTED
        $query = "
            UPDATE IN_PROGRESS
               SET STATUS    = ?
           WHERE APP_ID    = ?
           AND SUBAPP_ID = ?
           AND REF       = ?
           AND PNR       = ?";

        my $list = [];
        $list = [$status, $appId, $subAppId, $ref, $PNR];
         unless ($dbh->doBind($query, $list)) { warning('No row has been updated'); return 0; }
		 #THE BELOW QUERY WILL CHECK THE STATUS WHETHER ALL THE DV RAIL PNRS 
		 #ARE TICKETED FOR UPDATING DELIVERY_FOR_DISPATCH TABLE TO TICKETED 
         $query = "SELECT
                      DELIVERY_ID
                     ,(
                        SELECT
                          COUNT(PNR)
                        FROM IN_PROGRESS I WHERE
                        I.DELIVERY_ID = D.DELIVERY_ID
                        AND STATUS IN ('TAS_CHECKED','TAS_TICKETED')
                      ) TOTALPNRCNT
                     ,LEN(D.PNR)-LEN(REPLACE(D.PNR,',',''))+1 RUNPNRCNT
                      FROM DELIVERY_FOR_DISPATCH D
                  WHERE DELIVERY_ID = $deliveryId
           ";
         my $pnrRows = $dbh->saar($query);
         if ($pnrRows->[0][1] > 0 && ($pnrRows->[0][1] == $pnrRows->[0][2] )) {
                      $query   = "
                             UPDATE DELIVERY_FOR_DISPATCH
                              SET DELIVERY_STATUS_ID   =  2,
                              DELIVERY_STATUS_TEXT = 'Emis',
                            EMITTED_BY           = 'BTC_TAS',
                            TICKETED_DATE        =  GETDATE()
                            WHERE DELIVERY_ID          =  ?
                            AND MARKET               =  ?
                ";
            my $res = $dbh->doBind($query, [$deliveryId, $market]);
          }
    } else {
	#PLUS DE MISE A JOUR DU DISPATCH POUR LES PNR MULTIPLE 
    #SI LE PNR EST STRICTEMENT PLUS GRAND QUE 6 (PNR AMADEUS = 6), ALORS ON NE METS PAS A JOUR LE DISPATCH
    my $mypnr="'%".$PNR."%'";  
    $query = "SELECT LEN(PNR)
              FROM DELIVERY_FOR_DISPATCH
              WHERE DELIVERY_ID = $deliveryId 
              AND   PNR    like   $mypnr  "; 
              
    my $rows   = $dbh->saar($query);
    
    if($rows->[0][0] <= 6)      
    {    
      # Mise à jour directement dans l'interface DISPATCH
      #TODO SYSDATE -> pas d'interaction avec la timezone.. heure technique 
      $query   = "
        UPDATE DELIVERY_FOR_DISPATCH
           SET DELIVERY_STATUS_ID   =  2,
               DELIVERY_STATUS_TEXT = 'Emis',
               EMITTED_BY           = 'BTC_TAS',
               TICKETED_DATE        =  GETDATE()   
         WHERE DELIVERY_ID          =  ?
           AND MARKET               =  ? ";
      my $rows = $dbh->doBind($query, [$deliveryId, $market]);
    }
    }
  }
  # ____________________________________________________________________
  
  my $updTasError = '';
     $updTasError = ', TAS_ERROR = ? ' if (defined $tasError);

  $query = "
    UPDATE IN_PROGRESS
       SET STATUS    = ? $updTasError
     WHERE APP_ID    = ?
       AND SUBAPP_ID = ?
       AND REF       = ? 
       AND PNR       = ?";
  
  my $list = [];

  if (defined $tasError) { $list = [$status, $tasError, $appId, $subAppId, $ref, $PNR]; }
  else                   { $list = [$status, $appId, $subAppId, $ref, $PNR]; }

  unless ($dbh->doBind($query, $list)) { warning('No row has been updated'); return 0; }

  &tasUnlockItem({ REF => $ref, PNR => $PNR }) if (defined $tasError);

  return 1;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Get Items / TAS process
sub tasGetItems {
  my $task    = shift;

  if (!$task || $task =~ /^\s*$/) {
    error('Missing or wrong parameter for this method.');
    return 0;
  }

  my $dbh   = $cnxMgr->getConnectionByName('mid');
  my $appId = getAppId($task);

  if (!$appId) {
    warning("No appId was found for task '$task' in APPLICATIONS table. Aborting.");
    return 0;
  } else { debug('appId = '.$appId) if ($appId); }
  
  my $query = "
    SELECT I.REF, I.PNR, I.STATUS, I.TYPE, I.DELIVERY_ID, 
    --CAST(XML as varchar(max)) as XML,
    CONVERT(VARCHAR(MAX), CONVERT(NVARCHAR(MAX), XML)) as XML,
           (SELECT NAME FROM APPLICATIONS A WHERE A.ID = I.APP_ID) AS TASK
      FROM IN_PROGRESS I
     WHERE I.SUBAPP_ID = ?
       AND I.STATUS    = 'new'
       AND I.LOCKED    = 0
       AND I.TRY      <= 5
  ORDER BY I.TIME ASC, I.REF ASC ";
  
  my $res   = $dbh->saarBind($query, [$appId]);
  my @items = ();

	foreach (@$res) {
	  
	  my $isItemLocked = &tasIsItemLocked($_->[1]);
	  next if (scalar @$isItemLocked > 0);
	  
	  push (@items, {
      REF         => $_->[0],
		  PNR         => $_->[1],
		  STATUS      => $_->[2],
		  TYPE        => $_->[3],
		  DELIVERY_ID => $_->[4],
		  XML         => $_->[5],
		  TASK        => $_->[6],
		  SUBTASK     => $task,
		});
  }

  return @items;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Lock an item / SYNCHRO process
sub synLockItem {
  my $item = shift;

  my $res = lockWorkTableItem({
    ID              => $item->{ID},
    MESSAGE_ID      => $item->{MSG_ID},
    MESSAGE_CODE    => $item->{MSG_CODE},
    MESSAGE_TYPE    => $item->{MSG_TYPE},
    MESSAGE_VERSION => $item->{MSG_VERSION},
    STATUS          => $item->{STATUS},
    TIME            => $item->{TIME},
    PNR             => $item->{PNR},
  });

  return $res;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Unlock an item / SYNCRO process
sub synUnlockItem {
	my $params = shift;
	
	my $msgId = $params->{ITEM}{ID};
	
	my $dbh = $cnxMgr->getConnectionByName('mid');
	
	# Cas où il faut effacer les données
	if ($params->{STATUS} eq 'DELETE') {
  	my $rows  = $dbh->doBind('DELETE FROM WORK_TABLE WHERE ID = ?', [$msgId]);
  	warning("No deletion of the record with ID = $msgId.")
  		if ((!defined $rows) || ($rows != 1));
 	 	return 0 unless ((defined $rows) && ($rows == 1));
	}
	
	# Cas où il faut juste changer l'état du message
	elsif ($params->{STATUS} eq 'ERROR') {
		my $rows  = $dbh->doBind("UPDATE WORK_TABLE SET STATUS = 'ERROR' WHERE ID = ?", [$msgId]);
  	warning("No update of the record with ID = $msgId.")
  		if ((!defined $rows) || ($rows != 1));
 	 	return 0 unless ((defined $rows) && ($rows == 1));
	}
	
	elsif ($params->{STATUS} eq 'NEW' ) {
		my $rows  = $dbh->doBind("UPDATE WORK_TABLE SET STATUS = 'NEW' WHERE ID = ?", [$msgId]);
  	warning("No update of the record with ID = $msgId.")
  		if ((!defined $rows) || ($rows != 1));
 	 	return 0 unless ((defined $rows) && ($rows == 1));
	}
	
	# Cas STATUS "non traité"
	else { notice('Unknown value of STATUS parameter.'); }
	 
  return 1;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

sub updateDispatchAfterReclaim {

	my $pnrGds     	= shift;
	my $currentPnr	= shift;
	my $reference  	= shift;

	if (!$pnrGds || !$reference || $pnrGds =~ /^\s*$/ || $reference =~ /^\s*$/) {
		error('Missing or wrong parameter for this method.');
		return 0;
	}

	my $dbh   = $cnxMgr->getConnectionByName('mid');

	my $query = '
		SELECT PNR
		FROM DELIVERY_FOR_DISPATCH
		WHERE META_DOSSIER_ID = ?';
		
	my $result = $dbh->saarBind($query, [$reference])->[0][0];

	my $newPnr = $result;
	$newPnr =~ s/$currentPnr/$pnrGds/;
    
	$query = '
        	UPDATE DELIVERY_FOR_DISPATCH
        	SET PNR = ?
        	WHERE META_DOSSIER_ID = ?';

    unless ($dbh->doBind($query, [$newPnr, $reference])) { warning('No row has been updated'); return 0; }

	return 1;
}

1;
