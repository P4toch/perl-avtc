package Expedia::Workflow::TasksProcessor;
#-----------------------------------------------------------------
# Package Expedia::Workflow::TasksProcessor
#
# $Id: TasksProcessor.pm 686 2011-04-21 12:33:02Z pbressan $
#
# (c) 2002-2010 Expedia.                   www.expediacorporate.fr
#-----------------------------------------------------------------

use strict;
use DateTime;
use Data::Dumper;
use POSIX qw(strftime);
use DateTime::Duration;

use Expedia::GDS::DV;
use Expedia::GDS::PNR;
use Expedia::Databases::Amadeus;
use Expedia::XML::Booking;
use Expedia::Tools::Logger              qw(&debug &notice &warning &error &monitore);
use Expedia::Tools::TasFuncs            qw(&logTasError &logTasFinishError &tasReport &getTasMessage &soapRetry &soapProblems &tasDailyStats &tasConsoStats &compileDailyStats &isTcChecked);
use Expedia::Tools::GlobalVars          qw($h_processors $cnxMgr $soapRetry $soapProblems $proxyNav $GetBookingFormOfPayment_errors);
use Expedia::Tools::TssErrorCode        qw($listOfCodeRetryTssWS $listOfCodeNoRetryTssWS);
use Expedia::Tools::GlobalFuncs         qw(&dateTimeXML  &getNavisionConnForAllCountry &setNavisionConnection);
use Expedia::Workflow::WbmiManager;
use Expedia::Workflow::ModuleLoader;
use Expedia::Workflow::ProcessManager;
use Expedia::WS::Commun 				qw(&getToken &claim &getTssRecLoc);
use Expedia::WS::Front                  qw(&getDeliveryStatus &wsTSSCall);
use Expedia::WS::Back                   qw(&GetUnusedCreditsActivatedCust);
use Expedia::Databases::WorkflowManager qw(&getMessageFromIdVersion);
#use Expedia::Tools::SendMail			qw(&BackWSSendError);
use Expedia::Databases::MidSchemaFuncs  qw(&btcAirProceed &btcTrainProceed &btcTasProceed &isInMsgKnowledge &insertIntoMsgKnowledge &getTravellerTrackingImplicatedComCodesForMarket_new &getNavCountrybycountry &updateMsgKnowledge &getPnrIdFromDv2Pnr);
use Expedia::Databases::ItemsManager    qw(&btcInsertItem &btcGetItems &btcLockItem &btcUnlockItem &btcUpdateItem btcUnlockItemNeedRetry &btcRefreshItemStatus
    &tasInsertItem              &tasLockItem &tasUnlockItem &tasIsItemLocked &tasUpdateItem &tasGlobalInsert
    &tasCheckAndLockItemIntoInProgress &tasUnlockItemInProgress
    &synLockItem &synUnlockItem &updateDispatchAfterReclaim);
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# CONSTRUCTEUR
sub new {
    my ($class, $taskName, $config, $pnr, $queue, $oid, $server,$start_version,$stop_version) = @_;

    if ((!$taskName) || ($taskName =~ /^\s*$/) ||
        (!$config)   || (ref($config) ne 'Expedia::XML::Config')) {
        error('A valid taskName and a config object are needed. Aborting. ('.$taskName.' - '.$config.')');
        return 0;
    }

    my $h_tasks     = $config->tasks();
    my $h_sources   = $config->sources();
    my $h_processes = $config->processes(); # Sp�ficit�AS
    my $product     = '';

    # ________________________ Autre sp�ficit�AS _______________________
    if (($taskName =~ /^tas(?:meetings)?-/) &&
        ($taskName =~ /^(tas(?:meetings?)?-\D+):(air|rail)/)) {
        $taskName = $1;
        $product  = $2;
    }
    # ______________________________________________________________________

    if (!exists $h_tasks->{$taskName}) {
        error("Taskname '$taskName' is not a key of hash h_tasks. Aborting.");
        return 0;
    }


    my $self = {};
    bless ($self, $class);

  $self->{_TASK}        = $taskName;
  $self->{_AMADEUS}     = $h_tasks->{$taskName}->{amadeus};  
  $self->{_H_TASK}      = $h_tasks->{$taskName}; 
  $self->{_H_SOURCES}   = $h_sources->{$h_tasks->{$taskName}->{source}};
  $self->{_H_PROCESSES} = $h_tasks->{$taskName};   # Sp�cificit� TAS
  $self->{_PRODUCT}     = $product;       # Sp�cificit� TAS
  $self->{_PNR}         = $pnr;      #PARAM SUPPLEMENTAIRE POUR AIRLINEQUEUING
  $self->{_QUEUE}       = $queue;    #PARAM SUPPLEMENTAIRE POUR AIRLINEQUEUING
  $self->{_OID}         = $oid;      #PARAM SUPPLEMENTAIRE POUR AIRLINEQUEUING
  $self->{_SERVER}      = $server;   #PARAM SUPPLEMENTAIRE POUR LAUNCHER  
  $self->{_START_VERSION} = $start_version ;  # PARAM SUPPLEMENTAIRE POUR WORKFLOW SYNCHRO DEBUG  
  $self->{_STOP_VERSION} = $stop_version ;  # PARAM SUPPLEMENTAIRE POUR WORKFLOW SYNCHRO DEBUG 
  $self->{_MARKET}      = $h_tasks->{$taskName}->{market};
  $self->{_AGENCY}      = $h_tasks->{$taskName}->{agency};
  $self->{_NAME}        = $h_tasks->{$taskName}->{name};

  #use to get the right processors with the _NAME (ex: tracking-FR in parameters, as to be catch with tracking- ) 
  foreach my $key (reverse sort keys %$h_processors) {
     if ( $self->{_NAME} =~ /^$key/) { 
       $h_processors->{$self->{_NAME}} = $h_processors->{$key}; 
       last ; 
     };
 
  }
  
  if (!exists $h_processors->{$taskName}) {
    error("No processor is defined for task '$taskName'. Aborting.");
    return 0;
  }
  
  # ---------------------------------------------------------------
  # Initialisation du LOGGER ;)
  my $logFile = $h_tasks->{$taskName}->{logFile};
  Expedia::Tools::Logger->logFile($logFile) if ($logFile);
  # ---------------------------------------------------------------

  my $process = $self->process($taskName);
  return 0 unless (defined $process);

  return $self;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
sub process {
  my $self = shift;
  my $task = shift;
  
  # Connecter l'AMADEUS qui est param�tr� pour cette t�che
  my $gds = $cnxMgr->getConnectionByName($self->{_AMADEUS});
     $gds->connect() unless ($h_processors->{$task} eq 'flwProcessor'); # Sauf si task = workflow !
  # Si cela ne fonctionne pas, sortir [...]
  return undef if (($gds->connected() == 0) && ($h_processors->{$task} ne 'flwProcessor'));
  
  $_ = $h_processors->{$task};
  SWITCH: {
    if (/^airProcessor$/) { $self->airProcessor($task); last SWITCH; } # BTC-AIR
    if (/^gldProcessor$/) { $self->gldProcessor($task); last SWITCH; } # BTC-RAIL
    if (/^tasProcessor$/) { $self->tasProcessor($task); last SWITCH; } # TAS
    if (/^tfnProcessor$/) { $self->tfnProcessor($task); last SWITCH; } # TAS-FINISH
    if (/^trpProcessor$/) { $self->trpProcessor($task); last SWITCH; } # TAS-REPORT
    if (/^tstProcessor$/) { $self->tstProcessor($task); last SWITCH; } # TAS-STATS
    if (/^synProcessor$/) { $self->synProcessor($task); last SWITCH; } # SYNCHRO
    if (/^flwProcessor$/) { $self->flwProcessor($task); last SWITCH; } # WORKFLOW
    if (/^trkProcessor$/) { $self->trkProcessor($task); last SWITCH; } # TRACKING
    if (/^queProcessor$/) { $self->queProcessor($task); last SWITCH; } # QUEUE-PNR
    if (/^aiQProcessor$/) { $self->aiQProcessor($task); last SWITCH; } # AIR-QUEUE
    if (/^ahaProcessor$/) { $self->ahaProcessor($task); last SWITCH; } # AIR-QUEUE HANDLING ERROR
    if (/^lchProcessor$/) { $self->lchProcessor($task); last SWITCH; } # LAUNCHER
    if (/^tjqProcessor$/) { $self->tjqProcessor($task); last SWITCH; } # TJQ
    if (/^comProcessor$/) { $self->comProcessor($task); last SWITCH; } # RAIL-ERRORS 
    if (/^carProcessor$/) { $self->carProcessor($task); last SWITCH; } # CAR    
  };

  return $self;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# AIR-QUEUE Processor
sub aiQProcessor {
  my $self = shift;

	my $params = {};
	my $test_queue = ''; 
	   $params->{TaskName} = $self->{_TASK};

  # ----------------------------------------------------------------
  # V�rification qu'un process similaire n'est pas d�j� en cours de traitement
  my $pm = Expedia::Workflow::ProcessManager->new($self->{_TASK});
  return 1 if ($pm->isRunning() == 1);
  # ----------------------------------------------------------------

  $params->{GlobalParams}->{_PNR}   = $self->{_PNR};
  $params->{GlobalParams}->{_QUEUE} = $self->{_QUEUE};
  $params->{GlobalParams}->{_OID}   = $self->{_OID};

  # R�cup�ration des param�tres globaux du contexte li�s � cette t�che
  foreach my $key (keys %{$self->{_H_TASK}}) {
    $params->{GlobalParams}->{$key} = $self->{_H_TASK}->{$key}
      unless ($key =~ /modules|logFile|amadeus|source/);
  }
    
  # ----------------------------------------------------------------
  # Ex�cution du/des modules de r�cup�ration des items � traiter
  my @items      = ();
  my @modulesSrc = @{$self->{_H_SOURCES}->{modules}};
  foreach my $h_mod (@modulesSrc) {
    foreach my $module (keys %$h_mod) {
      $params->{ModuleParams} = {};
      notice("# PROCESSING module $module");
      foreach my $param (keys %{$h_mod->{$module}}) {
        $params->{ModuleParams}->{$param} = $h_mod->{$module}->{$param};
      }
      eval {
        my $modSrc = Expedia::Workflow::ModuleLoader->new($module);
			  push (@items, $modSrc->run($params));
      };
      error("Error during run of module $module : ".$@) if ($@);
    }
  }
  
  my $GDS      = $cnxMgr->getConnectionByName($self->{_AMADEUS});
  
  #SI IL Y A UNE QUEUE DE DEFINI EN PARAMETRE, ON SHUNT LE PROGRAMME
  if(defined($self->{_QUEUE}) || defined($self->{_PNR} ))
  {
      my $dbh = $cnxMgr->getConnectionByName('navision');
      
      my $query = "
      SELECT QUEUE, TYPE, WBMI_RULES, AO.POS 
      FROM AQH_QUEUE AQ, AQH_OFFICE_ID AO
      WHERE AO.POS= AQ.POS
      AND   AQ.QUEUE='$self->{_QUEUE}' 
      AND   AO.OFFICE_ID='$self->{_OID}'
      AND   AO.ACTIF=1
      AND   AQ.ACTIF=1";

      my $results = $dbh->saarBind($query, []);

      @items=();
      
      foreach my $res (@$results) {
        
        push @items, {
          QUEUE          => $res->[0],
          TYPE           => $res->[1],
          WBMI_RULES     => $res->[2],
          POS            => $res->[3],
        };
      }
      $test_queue=" DE TEST ";
  }
  
  #ON DOIT BOUCLER SUR LA LISTE DES QUEUES TROUVES PAR OFFICE_ID
  foreach my $item (@items) 
  {
      notice ("##############################################################################");
      notice ("#                     TRAITEMENT DE LA QUEUE".$test_queue."= '".$item->{QUEUE}."'           #");
      notice ("##############################################################################");
      
     # notice("ITEM:".$item->{QUEUE});
	   # notice("WBMI_RULE:".$item->{WBMI_RULES});
	   # notice("TYPE:".$item->{TYPE});
	
	    #AFFECTATION DES PARAMETRES DE LA TABLE POUR PASSAGE EN PARAMETRE
	    $params->{Item}     = $item;	
	    $params->{GDS}      = $GDS; 
	       	     
      my @modules  = @{$self->{_H_TASK}->{modules}};  # Modules "NON INTERACTIFS"
  	     	     	     
  	  # MODULES [NON INTERACTIFS]
      my $status = 0;
      foreach my $h_mod (@modules) {
        MODULE: foreach my $module (keys %$h_mod) {
          $params->{ModuleParams} = {};
          #notice("################ PROCESSING QUEUE = '".$item->{QUEUE}."' with module $module");
          foreach my $param (keys %{$h_mod->{$module}}) {
    			  $params->{ModuleParams}->{$param} = $h_mod->{$module}->{$param};
          }
          eval {
            my $mod = Expedia::Workflow::ModuleLoader->new($module);
            $status = $mod->run($params);
            debug('status = '.$status);
          };
          if (($status == 0) || ($@)) {
            notice("Error during run of module $module : ".$@) if ($@);
            #$params->{WBMI}->status('FAILURE');
            #$params->{WBMI}->sendXmlReport();
            next ITEM;
          }
        } # Fin MODULE: foreach my $module (keys %$h_mod)
      } # Fin foreach my $h_mod (@modules)
    
    #  debug('params = '.Dumper($params->{Changes}));
    
  }
	   
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# AIR-QUEUE ERROR HANDLING Processor
sub ahaProcessor {
  my $self = shift;

	my $params = {};
	my $test_queue = ''; 
	   $params->{TaskName} = $self->{_TASK};

  # ----------------------------------------------------------------
  # V�rification qu'un process similaire n'est pas d�j� en cours de traitement
  my $pm = Expedia::Workflow::ProcessManager->new($self->{_TASK});
  return 1 if ($pm->isRunning() == 1);
  # ----------------------------------------------------------------

  $params->{GlobalParams}->{_PNR}   = $self->{_PNR};
  $params->{GlobalParams}->{_QUEUE} = $self->{_QUEUE};
  $params->{GlobalParams}->{_OID}   = $self->{_OID};

  # R�cup�ration des param�tres globaux du contexte li�s � cette t�che
  foreach my $key (keys %{$self->{_H_TASK}}) {
    $params->{GlobalParams}->{$key} = $self->{_H_TASK}->{$key}
      unless ($key =~ /modules|logFile|amadeus|source/);
  }
   
  # ----------------------------------------------------------------
  # Ex�cution du/des modules de r�cup�ration des items � traiter
  my @items      = ();
  my @modulesSrc = @{$self->{_H_TASK}->{modules}};
  foreach my $h_mod (@modulesSrc) {
    foreach my $module (keys %$h_mod) {
      $params->{ModuleParams} = {};
      notice("# PROCESSING module $module");
      foreach my $param (keys %{$h_mod->{$module}}) {
        $params->{ModuleParams}->{$param} = $h_mod->{$module}->{$param};
      }
      eval {
        my $modSrc = Expedia::Workflow::ModuleLoader->new($module);
       # notice("ZEFZEF:".Dumper($modSrc));
			  push (@items, $modSrc->run($params));
      };
      error("Error during run of module $module : ".$@) if ($@);
    }
  }

}

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# BTC-AIR Processor
sub airProcessor {
  my $self = shift;

	my $params = {};
	   $params->{TaskName} = $self->{_TASK};
	   $params->{onePNR}   = $self->{_PNR};

  my %h_pnr=();
  
  # ----------------------------------------------------------------
  # Vérification qu'un process similaire n'est pas déjà en cours de traitement
  my $pm = Expedia::Workflow::ProcessManager->new($self->{_TASK});
  return 1 if ($pm->isRunning() == 1);
  # ----------------------------------------------------------------

  # Récupération des paramètres globaux du contexte liés à cette tâche
  foreach my $key (keys %{$self->{_H_TASK}}) {
    $params->{GlobalParams}->{$key} = $self->{_H_TASK}->{$key}
      unless ($key =~ /modules|logFile|amadeus|source/);
  }

  # ----------------------------------------------------------------
  # Exécution du/des modules de récupération des items à traiter
  my @items      = ();
  my @modulesSrc = @{$self->{_H_SOURCES}->{modules}};
  foreach my $h_mod (@modulesSrc) {
    foreach my $module (keys %$h_mod) {
      $params->{ModuleParams} = {};
      notice("# PROCESSING module $module");
      foreach my $param (keys %{$h_mod->{$module}}) {
        $params->{ModuleParams}->{$param} = $h_mod->{$module}->{$param};
      }
      eval {
        my $modSrc = Expedia::Workflow::ModuleLoader->new($module);
			  push (@items, $modSrc->run($params));
      };
      error("Error during run of module $module : ".$@) if ($@);
    }
  }
  
  # Record items into IN_PROGRESS table
  foreach (@items) {
    my $b   = Expedia::XML::Booking->new($_->{XML});
    my $x=0;
    my $mktype = undef;
    my $Listdossier = undef;
    my $tmp = undef;
    
    #CALCUL DU NOMBRE DE TRAVELDOSSIER
    my $nbDossier      = $b->getNbOfTravelDossiers;
    notice($nbDossier." TravelDossiers ");
    
    if($nbDossier == 1)
    {
        notice("UN SEUL TRAVELDOSSIER");
        $Listdossier = $b->getTravelDossierStruct;
        $mktype = $Listdossier->[0]->{lwdType};
        if(!exists($h_pnr{$Listdossier->[0]->{lwdPnr}}))
        {
          $h_pnr{$Listdossier->[0]->{lwdPnr}}=$Listdossier->[0]->{lwdPos};
        }
        notice($Listdossier->[0]->{lwdPnr}." est en position:".$h_pnr{$Listdossier->[0]->{lwdPnr}});
    }
    else
    {
        #RECUPERATION DE LA STRUCTURE DES DIFFERENTS TRAVELDDOSIERS
        $Listdossier = $b->getTravelDossierStruct;

        debug("LISTDOSSIER:".Dumper($Listdossier));

        #ON BOUCLE SUR CHAQUE TRAVELDOSSIER
        for ($x=0; $x < $nbDossier; $x++)
        {
          if($Listdossier->[$x]->{lwdPnr} eq  $_->{PNR})
          {
            notice("PNR:".$Listdossier->[$x]->{lwdPnr}." TROUVE EN POSITION:".$x); 
            $mktype = $Listdossier->[$x]->{lwdType};
            if(!exists($h_pnr{$Listdossier->[$x]->{lwdPnr}}))
            {
              $h_pnr{$Listdossier->[$x]->{lwdPnr}}=$x;
            }
            last;
          }
          else
          {notice("PNR:".$Listdossier->[$x]->{lwdPnr}." ne corresponds pas en position pas ".$x);}
        }
        
        
        notice($Listdossier->[$x]->{lwdPnr}." est en position:".$h_pnr{$Listdossier->[$x]->{lwdPnr}});
    }

        my $res = &btcInsertItem({ REF  => $_->{ID},
                                   TASK => $self->{_TASK},
                                   TYPE => $mktype,
                                   PNR  => $_->{PNR} }); # Sous-entendu identifiant de PNR                               
        notice('Problem during call of btcInsertItem method.')
          if (!$res || $res != 1);
  }

  # Récupération finale des items à traiter
  @items = &btcGetItems($self->{_TASK});
  my $nbItems = scalar @items;
  # ----------------------------------------------------------------

debug("H_PNR:".Dumper(%h_pnr));


  # ----------------------------------------------------------------
  # Exécution du/des modules de traitement sur chaque item
  my $PNR      = undef;
  my $GDS      = $cnxMgr->getConnectionByName($self->{_AMADEUS});
  my $lock     = 0;
  my $unlock   = 0;   
  my $count    = 0;
  my @modules  = @{$self->{_H_TASK}->{modules}};  # Modules "NON INTERACTIFS"
  my @imodules = @{$self->{_H_TASK}->{imodules}}; # Modules "INTERACTIFS"
  my $changes  = { add => [], del => [], mod => [] };
  
  ITEM: foreach my $item (@items) {
    $count += 1;
    
    #our use to transfert the variable to the others package
    our $log_id= '';

    $log_id=$item->{MSG_CODE};
    
    # ---------------------------------------------------------------------
    # Vidage des actions à effectuer
    $changes = { add => [], del => [], mod => [] };
    $params->{Changes} = $changes;
    # ---------------------------------------------------------------------

    notice('---------------------------------------------------------------');
    notice(' Working on item REF = '.$item->{REF}." PNR = '".$item->{PNR}."' ($count/$nbItems)") if ($item->{REF} && $item->{PNR});
    notice('---------------------------------------------------------------');
    
    my $tmpXML =  $item->{XML};
    $tmpXML =~ s/'/''''/ig;
    $tmpXML = '<?xml version="1.0" encoding="ISO-8859-1" standalone="yes"?>'.$tmpXML;

    my $tmp  = ' xmlns="http://www.expediacorporate.fr/newsimages/xsds/v1"';
    $tmpXML =~ s/$tmp//ig;
    
    &btcAirProceed({ TYPE => $item->{MSG_TYPE}, PNR => $item->{PNR} });
    
    
	$params->{ParsedXML} = Expedia::XML::Booking->new($tmpXML);
    $params->{WBMI}      = Expedia::Workflow::WbmiManager->new({batchName => 'BTC_AIR', mdCode => $params->{ParsedXML}->getMdCode});
    
    notice('MdCode  = '.$params->{ParsedXML}->getMdCode);
    notice('Version = '.$item->{MSG_VERSION});

    # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
    # Verrouillage de l'ITEM
    $lock = &btcLockItem({REF => $item->{REF}, TASK => $self->{_TASK}, PNR => $item->{PNR} });
    # Si nous en sommes à notre dernier essai [...]
    #    [...] notification dans WBMI (Problème du 18 Juillet 2008) !
    if ($item->{TRY} == 5) {
      $params->{WBMI}->status('FAILURE');
      $params->{WBMI}->addReport({ Code => 29, PnrId => $item->{PNR} });
      $params->{WBMI}->sendXmlReport();
    }
    next ITEM unless $lock;
    # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

    # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
    # Vérification que le PNR existe encore dans AMADEUS.

	$PNR = Expedia::GDS::PNR->new(PNR => $item->{PNR}, GDS => $GDS);
	if (!defined $PNR) {
		$unlock = &btcUnlockItem({REF => $item->{REF}, TASK => $self->{_TASK}, PNR => $item->{PNR}});
		error("Could not read PNR '".$item->{PNR}."' from GDS.");

		next ITEM;
	}
	$params->{PNR}  = $PNR;  # Sous-entendu l'objet PNR
	$params->{Item} = $item;

    #ON PASSE LA REFERENCE DU TABLEAU DE HASHAGE    
    $params->{Position} = \%h_pnr;
    $params->{RefPNR}   = $item->{PNR};
    debug('XML = '.$params->{ParsedXML}->doc->toString(1)); # On log dans la TRACE
    # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
 
    unless ( grep { $_->{Data} =~ /RM \*METADOSSIER/ } @{$PNR->{PNRData}} ) {
               push (@{$params->{Changes}->{add}}, { Data => 'RM *METADOSSIER '.$params->{ParsedXML}->getMdCode });
    }
        
    # MODULES [NON INTERACTIFS]
    my $status = 0;
    foreach my $h_mod (@modules) {
      MODULE: foreach my $module (keys %$h_mod) {
        $params->{ModuleParams} = {};
        notice("# PROCESSING PNR = '".$item->{PNR}."' with module $module");
        foreach my $param (keys %{$h_mod->{$module}}) {
  			  $params->{ModuleParams}->{$param} = $h_mod->{$module}->{$param};
        }
        eval {
          my $mod = Expedia::Workflow::ModuleLoader->new($module);
          $status = $mod->run($params);
          debug('status = '.$status);
        };
        if (($status == 0) || ($@)) {
          notice("Error during run of module $module : ".$@) if ($@);
          &btcUpdateItem({REF => $item->{REF}, TASK => $self->{_TASK}, STATUS => 'error', PNR => $item->{PNR}});
          $params->{WBMI}->status('FAILURE');
          $params->{WBMI}->sendXmlReport();
          next ITEM;
        }
      } # Fin MODULE: foreach my $module (keys %$h_mod)
    } # Fin foreach my $h_mod (@modules)
    
    debug('params = '.Dumper($params->{Changes}));

    # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
    # On aplique les modifications sur l'ITEM [Fin des Modules "NON INTERACIFS"]
    my $update = 0;
    notice('Applying changes on PNR [...]');
    $update = $PNR->update(
       add   => $params->{Changes}->{add},
       del   => $params->{Changes}->{del},
       mod   => $params->{Changes}->{mod},
       NoGet => 1,
    );
    if ($update == 0) {
      notice('Problem during call of PNR update function !');
      &btcUnlockItem({REF => $item->{REF}, TASK => $self->{_TASK}, PNR => $item->{PNR}});
      $params->{WBMI}->status('FAILURE');
      $params->{WBMI}->addReport({ Code => 18, PnrId => $item->{PNR} });
      $params->{WBMI}->sendXmlReport();
      next ITEM;
    }
    # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
    
    # MODULES [INTERACTIFS]
    if (scalar @imodules > 0) {
      debug("IL Y A DES MODULES INTERACTIFS !");
      foreach my $h_mod (@imodules) {
        MODULE: foreach my $module (keys %$h_mod) {
          $params->{ModuleParams} = {};
          notice("# PROCESSING PNR = '".$item->{PNR}."' with module $module");
          foreach my $param (keys %{$h_mod->{$module}}) {
    			  $params->{ModuleParams}->{$param} = $h_mod->{$module}->{$param};
          }
          eval {      
            my $mod = Expedia::Workflow::ModuleLoader->new($module);
            $status = $mod->run($params);
          };
          if (($status == 0) || ($@)) {
            notice("Error during run of module $module : ".$@) if ($@);
            &btcUpdateItem({REF => $item->{REF}, TASK => $self->{_TASK}, STATUS => 'error', PNR => $item->{PNR}});
            $params->{WBMI}->status('FAILURE');
            $params->{WBMI}->sendXmlReport();
            next ITEM;
          } 
        } # Fin MODULE: foreach my $module (keys %$h_mod)
      } # Fin foreach my $h_mod (@imodules)
    } # Fin if (scalar @imodules > 0)
    
    # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
    # Déverrouillage de l'ITEM + "WBMI"
    $unlock = &btcUnlockItem({REF => $item->{REF}, TASK => $self->{_TASK}, PNR => $item->{PNR}});
    $params->{WBMI}->sendXmlReport();
    # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
	
    &btcUpdateItem({REF => $item->{REF}, TASK => $self->{_TASK}, STATUS => 'finished', PNR => $item->{PNR}});
    
  } # Fin ITEM: foreach my $item (@items)
  # ----------------------------------------------------------------
  
	#if ((defined(@$GetBookingFormOfPayment_errors)) && (scalar(@$GetBookingFormOfPayment_errors) > 0))  
	#{			
	#	BackWSSendError($params->{GlobalParams}->{market},$params->{TaskName});  
	#}
	
  # $pm->xmlProcessed($count); # Pour NAGIOS

  return 1;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# BTC-RAIL Processor - Ravel Gold System
sub gldProcessor {
  my $self = shift;

	my $params = {};
	   $params->{TaskName} = $self->{_TASK};
	   
  # ----------------------------------------------------------------
  my $pm = Expedia::Workflow::ProcessManager->new($self->{_TASK});
  # ----------------------------------------------------------------

  # R�cup�ration des param�tres globaux du contexte li�s � cette t�che
  foreach my $key (keys %{$self->{_H_TASK}}) {
    $params->{GlobalParams}->{$key} = $self->{_H_TASK}->{$key}
      unless ($key =~ /modules|logFile|amadeus|source/);
  }

  # ----------------------------------------------------------------
  # Ex�cution du/des modules de r�cup�ration des items � traiter
  my @items      = ();
  my @modulesSrc = @{$self->{_H_SOURCES}->{modules}};
  foreach my $h_mod (@modulesSrc) {
    foreach my $module (keys %$h_mod) {
      $params->{ModuleParams} = {};
      notice("# PROCESSING module $module");
      foreach my $param (keys %{$h_mod->{$module}}) {
        $params->{ModuleParams}->{$param} = $h_mod->{$module}->{$param};
      }
      eval {
        my $modSrc = Expedia::Workflow::ModuleLoader->new($module);
			  push (@items, $modSrc->run($params));
      };
      error("Error during run of module $module : ".$@) if ($@);
    }
  }
  
  # Record items into IN_PROGRESS table
  # Modification for EGE-87684
  my $compteur=0;
  my $flag=0;
  my $last_dossier;
  foreach (@items) {
		
		my $ref=$_->{ID};
		my $task=$self->{_TASK};
		my $b   = Expedia::XML::Booking->new($_->{XML});
		my $ttd = $b->getTravelDossierStruct;
		my $nb_dossier= @$ttd ; # can also be retrieved by getNbDossier

		
		if ($nb_dossier == 1){
			$compteur=0;
			$flag=0;
			my $pnr = $ttd->[0]->{lwdPnr};
			my $res = &btcInsertItem({ REF  => $ref,
									   TASK => $task,
									   TYPE => $ttd->[0]->{lwdType},
									   PNR  => $pnr }); # Sous-entendu liste des identifiants de DVS
			notice('Problem during call of btcInsertItem method.') if (!$res || $res != 1);
		}
		
		else {
			my @tt=@$ttd;
			$last_dossier=$#tt;
			foreach my $dossier (@$ttd) {
				
				### We are leaving if the type is different than RAIL. 
				do {      $compteur++ unless $flag;	next;	} unless ($dossier->{lwdType} =~ /^(SNCF_TC|RG_TC)$/ );
				
				
				if ($compteur == $dossier->{lwdPos} ){
				
					my $pnr = $dossier->{lwdPnr};
					my $res = &btcInsertItem({    REF  => $ref,  
										   TASK => $task,
										   TYPE => $dossier->{lwdType},
										   PNR  => $pnr }); # Sous-entendu liste des identifiants de DVS
					notice('Problem during call of btcInsertItem method.') if (!$res || $res != 1);
					if($dossier->{lwdPos}== $last_dossier) {
					
						## Here, we already processed every dossier, so we will reset the counter and the flag
						$compteur=0;
						$flag=0;
					}
					else {
                          ## We are waiting for another dossier in another item
						  $flag=1;
                   }
					
				last ; ## We are leaving the loop because only 1 Dossier is processed by item
			  }		
			} # end foreach dossier loop
			$compteur++ if $flag;
		}
	
	}  # end foreach item loop
	
  # R�cup�ration finale des items � traiter & Calcul du nombre total d'item � traiter
  @items = &btcGetItems($self->{_TASK});
  my $nbItems = scalar @items;
  # ----------------------------------------------------------------
  
  # ----------------------------------------------------------------
  # Ex�cution du/des modules de traitement sur chaque item
  my $count   = 0;
  my $lock    = 0;
  my $unlock  = 0;   
  my @modules = @{$self->{_H_TASK}->{modules}};
  my $changes = { add => [], del => [], mod => [] };
  my $GDS     = $cnxMgr->getConnectionByName($self->{_AMADEUS});
  
  ITEM: foreach my $item (@items) {
    
    $count++;
    
    #our use to transfert the variable to the others package
    our $log_id= '';

    $log_id=$item->{MSG_VERSION};
    
    # ---------------------------------------------------------------------
    # Vidage des actions � effectuer
    $changes = { add => [], del => [], mod => [] };
    $params->{Changes} = $changes;
    # ---------------------------------------------------------------------
    
    &btcTrainProceed({ TYPE => $item->{MSG_TYPE}, PNR => $item->{PNR} })
      if ($item->{STATUS} eq 'new'); # Pas n�cessaire de le faire � chaque fois =). 08 JUIN 2009.

    notice('---------------------------------------------------------------');
    notice(' Working on item REF = '.$item->{REF}." PNR = '".$item->{PNR}."' ($count/$nbItems)") if ($item->{REF} && $item->{PNR});
    notice('---------------------------------------------------------------');
   
    my $tmpXML =  $item->{XML};
    $tmpXML =~ s/'/''''/ig;
    $tmpXML = '<?xml version="1.0" encoding="ISO-8859-1" standalone="yes"?>'.$tmpXML;

    my $tmp  = ' xmlns="http://www.expediacorporate.fr/newsimages/xsds/v1"';
    $tmpXML =~ s/$tmp//ig;
    $item->{XML}=$tmpXML;
    
    # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
    # Verrouillage de l'ITEM
    $lock = &btcLockItem({REF => $item->{REF}, TASK => $self->{_TASK}, PNR => $item->{PNR}});
    next ITEM unless $lock;
    # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

    # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
    # Rafra�chissement du STATUS de l'item
    debug('Item Status = '.$item->{STATUS});
    $item->{STATUS} = &btcRefreshItemStatus({REF => $item->{REF}, TASK => $self->{_TASK}, PNR => $item->{PNR}});
    debug('Item Status = '.$item->{STATUS}) if (defined $item->{STATUS});
    next ITEM unless (defined $item->{STATUS});
    # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

    # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
    $params->{GDS}       = $GDS;
    $params->{Item}      = $item;
    $params->{ParsedXML} = Expedia::XML::Booking->new($item->{XML});
    $params->{WBMI}      = Expedia::Workflow::WbmiManager->new({batchName => 'BTC_TRAIN', mdCode => $params->{ParsedXML}->getMdCode});
    debug('XML = '.$params->{ParsedXML}->doc->toString(1)); # On log dans la TRACE
    # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@


    # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
    # WBMI specific nous devons identifier de quelle phase il s'agit !
    my $newStatus = '';
    my $oldStatus = $item->{STATUS};
    $params->{WBMI}->currentPhase(1) if ($oldStatus eq 'new');
    $params->{WBMI}->currentPhase(2) if ($oldStatus eq 'retrieve');
    $params->{WBMI}->currentPhase(3) if ($oldStatus eq 'process');
    # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
    
	
	if($params->{ParsedXML}->getTravelDossierStruct->[0]->{lwdTssRecLoc} eq '' ){
	
		notice('MdCode  = '.$params->{ParsedXML}->getMdCode);
		notice('Version = '.$item->{MSG_VERSION});
		
		my $status = 0;
		foreach my $h_mod (@modules) {
		  MODULE: foreach my $module (keys %$h_mod) {
			$params->{ModuleParams} = {};
			notice("# PROCESSING PNR = '".$item->{PNR}."' with module $module");
			foreach my $param (keys %{$h_mod->{$module}}) {
				  $params->{ModuleParams}->{$param} = $h_mod->{$module}->{$param};
			}
			eval {      
			  my $mod = Expedia::Workflow::ModuleLoader->new($module);
			  $status = $mod->run($params);
			};
			if (($status == 0) || ($@)) {
			  notice("Error during run of module $module : ".$@) if ($@);
			  $_ = $module;
			  SWITCH: {
				if ($@)                         { $newStatus = 'error';    last SWITCH; }
				if (/^GLD::AnalyseDV$/)         { $newStatus = 'error';    last SWITCH; }
				if (/^GLD::InsertRM/)           { $newStatus = 'retrieve'; last SWITCH; }
				if (/^GLD::RetrieveInAmadeus$/) { $newStatus = 'retrieve'; last SWITCH; }
				if (/^GLD::ProcessPNR$/)        { $newStatus = 'process';  last SWITCH; }
			  };
			  &btcUpdateItem({REF => $item->{REF}, TASK => $self->{_TASK}, STATUS => $newStatus, PNR => $item->{PNR}});
			  $params->{WBMI}->sendXmlReport() if ($newStatus ne $oldStatus);
			  &btcUnlockItemNeedRetry({REF => $item->{REF}, TASK => $self->{_TASK}, PNR => $item->{PNR}})
				if (($newStatus ne 'error') && ($newStatus ne $oldStatus));
			  next ITEM;
			} elsif ($status == -1) { # CAS D'UNE MAUVAISE LECTURE DE LA DV ... Merci RAVEL :(
			  notice('Rollback [...]');
			  &btcUnlockItemNeedRetry({REF => $item->{REF}, TASK => $self->{_TASK}, PNR => $item->{PNR}});
			  next ITEM;
			} elsif ($status == -2) { # CAS SPECIAL DU ITINERARY EMPTY, du ALREADY ISSUED et du SECURED PNR
			  &btcUpdateItem({REF => $item->{REF}, TASK => $self->{_TASK}, STATUS => 'finished', PNR => $item->{PNR}});
			  $params->{WBMI}->status('FAILURE');
			  $params->{WBMI}->sendXmlReport();
			  next ITEM;
			} elsif ($status == -3) { # CAS SPECIAL : Finir Traitement.
			  &btcUpdateItem({REF => $item->{REF}, TASK => $self->{_TASK}, STATUS => 'finished', PNR => $item->{PNR}});
			  $params->{WBMI}->status('SUCCESS');
			  $params->{WBMI}->sendAll(1); # Envoi de tous les messages WBMI restants
			  $params->{WBMI}->sendXmlReport();
			  next ITEM;
			}
		  } # Fin MODULE: foreach my $module (keys %$h_mod)
		} # Fin foreach my $h_mod (@modules)
	}else{
		notice('TssRecLoc exist in XML => Do nothing.');
	}
    
    # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
    # D�verrouillage de l'ITEM + "WBMI"
    #   Le d�verrouillage n'est pas n�cessaire ici. Il est source de bug dans la parall�lisation //.
    #   De plus, il est �galement pris en charge par btcUpdateItem. 08 JUIN 2009.
    # $unlock = &btcUnlockItem({REF => $item->{REF}, TASK => $self->{_TASK}});
    $params->{WBMI}->sendXmlReport();
    # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

    &btcUpdateItem({REF => $item->{REF}, TASK => $self->{_TASK}, STATUS => 'finished', PNR => $item->{PNR}});

  } # Fin ITEM: foreach my $item (@items)
  # ----------------------------------------------------------------
  
  # $pm->xmlProcessed($count); # Pour NAGIOS

  return 1;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# TAS Main Processor
sub tasProcessor {
  my $self = shift;

	my $params = {};
	   $params->{TaskName} = $self->{_TASK};

  #PARAMETERS ARE NOW IN DATABASE OR OPTIONNAL IN THE SCRIPT 
  $params->{GlobalParams}->{market}   = $self->{_MARKET};
  $params->{GlobalParams}->{agency}   = $self->{_AGENCY};
  $params->{GlobalParams}->{pnr}      = $self->{_PNR}; 
  $params->{GlobalParams}->{name}     = $self->{_NAME};
  $params->{GlobalParams}->{product}  = $self->{_PRODUCT};  
  	
  # ----------------------------------------------------------------
  # V�rification qu'un process similaire n'est pas d�j� en cours de traitement
  my $pm = Expedia::Workflow::ProcessManager->new($self->{_TASK}.':'.$self->{_PRODUCT});
  # return 1 if ($pm->isRunning() == 1);
  # ----------------------------------------------------------------

  
  # ----------------------------------------------------------------
  # Ex�cution du/des modules de r�cup�ration des items � traiter
  my @items      = ();
  my @modulesSrc = @{$self->{_H_SOURCES}->{modules}};
  foreach my $h_mod (@modulesSrc) {
    foreach my $module (keys %$h_mod) {
      notice("# PROCESSING module $module");
      eval {
        my $modSrc = Expedia::Workflow::ModuleLoader->new($module);
			  push (@items, $modSrc->run($params));
      };
      error("Error during run of module $module : ".$@) if ($@);
    }
  }
  # ----------------------------------------------------------------
  
  my $nbItems = scalar @items;
    
  # ----------------------------------------------------------------
  # Affichage du r�sultat des ITEMS � traiter
  # my $display = "\n";
  # foreach my $item (@items) { $display .= $item->{PNR}.','; }
  # $display = 'None.' if ($nbItems == 0);
  # notice('Dossiers to be TAS processed: '.$display);
  # return 1;
  # ----------------------------------------------------------------
  
  tasGlobalInsert(\@items); # Utilis� pour la // parall�lisation de TAS
  
  # ________________________________________________________________
  # Ajout� pour MEETINGS. 12 Mars 2009.
  my $agency  =  $self->{_AGENCY};                  notice('AGENCY  = '.$agency);
  my $product =  $self->{_PRODUCT};                 notice('PRODUCT = '.$product);
  my $tmpTask =  $self->{_TASK};
     $tmpTask =~ s/^(tas(?:meetings)?)-.*/$1/;      notice('TMPTASK = '.$tmpTask);
  # ________________________________________________________________

  # ----------------------------------------------------------------
  # Ex�cution du/des modules de traitement sur chaque item
  my $PNR     = undef;
  my $message = undef;
  my $Listdossier = undef;
  my $count   = 0;
  my $lock    = 0;
  my $unlock  = 0;
  my @modules = ();
  my @results = ();  
  my %h_pnr=();
  my $mktype = undef;
  my $x       = undef;
  my $changes = { add => [], del => [], mod => [] };
  my $dbh     = $cnxMgr->getConnectionByName('mid');
  my $GDS     = $cnxMgr->getConnectionByName($self->{_AMADEUS});
  
  my $sauv_self_amadeus= '';
  my $sauv_task        = '';
  
  #GET ALL THE aIrlINE from a country who dosnt want the YR tax
  my $query="SELECT AIRLINECODE FROM TASYR WHERE POSCODE=?";
  my $h_YR = $dbh->saarBind($query, [$self->{_MARKET}]);

  $params->{GlobalParams}->{TASYR} = $h_YR;

  #GET ALL THE aIrlINE from a country who dosnt want the YR tax
  my $query="SELECT DISTINCT(FPEC) FROM MO_CFG_DIVERS";
  my $h_FPEC = $dbh->saarBind($query, []);

  $params->{GlobalParams}->{FPEC} = $h_FPEC;

  #GET ALL THE COMCODE TO BLOCK FOR THE UNUSED
  my @liste_comcode = &GetUnusedCreditsActivatedCust($proxyNav,$self->{_MARKET});

  $params->{GlobalParams}->{UNUSED} = \@liste_comcode;
  
  ITEM: foreach my $item (@items) {

     #check if the saipem connection is on, if it is, we change to the previous connection XXXX38DD
     if ($GDS->saipem() == 1) {
        $GDS->disconnect;
		#notice("SAUVTASK:".$sauv_task);
        #notice("SAUVAMADEUS:".$sauv_self_amadeus);
        $sauv_task=$sauv_task.":".$params->{GlobalParams}->{product};
        #notice("SAUVTASK:".$sauv_task);
        my  $config        = Expedia::XML::Config->new('/var/egencia/libsperl/Expedia/Tools/config_DDB.xml',$sauv_task);
        $GDS = $cnxMgr->getConnectionByName($sauv_self_amadeus);
        $GDS->saipem(0);
        return 1 unless $GDS->connect;
      }
	  
     #check if the psa1 connection is on, if it is, we change to the previous connection XXXX38DD
     if ($GDS->psa1() == 1) {
        $GDS->disconnect;
		#notice("SAUVTASK:".$sauv_task);
        #notice("SAUVAMADEUS:".$sauv_self_amadeus);
        $sauv_task=$sauv_task.":".$params->{GlobalParams}->{product};
        #notice("SAUVTASK:".$sauv_task);
        my  $config        = Expedia::XML::Config->new('/var/egencia/libsperl/Expedia/Tools/config_DDB.xml',$sauv_task);
        $GDS = $cnxMgr->getConnectionByName($sauv_self_amadeus);
        $GDS->psa1(0);
        return 1 unless $GDS->connect;
      }
	  
    #our use to transfert the variable to the others package
    our $log_id= '';

    $log_id=$item->{REF};
    
    $count++;
    my $tasError = 0;

    # Afin de pr�venir des d�connections de l'API !
    if ($count % 100 == 0) { $GDS->disconnect; return 1 unless ($GDS->connect); }
    
    # ---------------------------------------------------------------------
    # Vidage des actions � effectuer
    $changes = { add => [], del => [], mod => [] };
    $params->{Changes} = $changes;
    # ---------------------------------------------------------------------
   
    #SI LE PNR EST MULTIPLE ALORS ON NE PRENDS QUE LA PREMIERE PARTIE
    #LES AUTRES PNR SONT PLACES DANS ITEMS POUR TRAITEMENT ULTERIEUR
    if($item->{PNR} =~ /,/)
    {
        my @ListPNR = split(/,/, $item->{PNR});      
        notice('---------------------------------------------------------------');
        notice(' PNR MULTIPLE PNR = '.$item->{PNR}."' ($count/$nbItems)") if ($item->{REF} &&  $item->{PNR});
        notice('---------------------------------------------------------------');
        $nbItems--;
        $count--;
        foreach my $val_pnr (@ListPNR)
        {
           $nbItems++;
           push @items, { 
                   REF             => $item->{REF},
                   PNR             => $val_pnr,
                   DELIVERY_ID     => $item->{DELIVERY_ID},
                   TCAT_ID         => $item->{TCAT_ID},
                   MESSAGE_ID      => $item->{MESSAGE_ID},
                   MESSAGE_VERSION => $item->{MESSAGE_VERSION},
                   DELIVERY        => $item->{DELIVERY},
                   MARKET          => $item->{MARKET},
                   AGENCY          => $item->{AGENCY},
                   BILLING_COMMENT => $item->{BILLING_COMMENT},
                   PRDCT_TP_ID     => $item->{PRDCT_TP_ID},
				   MULTI_PNR	   => $item->{PNR}
                 };
        }
        next ITEM;
    }

    
    notice('---------------------------------------------------------------');
    notice(' Working on item REF = '.$item->{REF}." PNR = '".$item->{PNR}."' ($count/$nbItems)") if ($item->{REF} &&  $item->{PNR});
    notice('---------------------------------------------------------------');
    
    &monitore("TAS_TICKETING","PNR_ISSUE","INFO",$item->{MARKET},$product,$item->{PNR},'',"START");

    # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
    # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
    # LE TRAITEMENT DE TROP DE XML PREND TROP DE TEMPS - LE TRAITEMENT DES DOSSIERS
    #  EST EFFECTUE DESORMAIS AU COUP PAR COUP. PB DU MERCREDI 31 OCTOBRE 2007.
    # __________________________________________________________________________
    # SECTION DEPLACEE DE GetTas.pm
    my $pnr = $item->{PNR}; debug('PNR = '.$pnr);

    # -----------------------------------------------------------------
    # Mise � jour du 28 F�vrier 2008 pour traitements en // dans TAS.
    #   On essaye de locker dans mes tables de travail [ IN_PROGRESS ].
	my $isIpOk = tasCheckAndLockItemIntoInProgress({ REF => $item->{REF}, PNR => $pnr });
	next unless $isIpOk;
    # -----------------------------------------------------------------

    # -----------------------------------------------------------------
    # On regarde si l'item est d�j� lock� dans dispatch.
    my $isLocked = &tasIsItemLocked({ REF => $item->{REF}, PNR => $pnr});
    if (scalar(@$isLocked) > 0) {
      notice(" ~ PNR = '".$pnr."' est lock� par '".$isLocked->[0][0]."'. Skipping [...]");
      tasUnlockItemInProgress({ REF => $item->{REF}, PNR => $pnr });
	  &monitore("TAS_TICKETING", "PNR_ISSUE", "INFO", $item->{MARKET}, $product, $item->{PNR}, "QC-Lock PNR issue", "END");
      next ITEM;
    }
    # -----------------------------------------------------------------
    
    # -----------------------------------------------------------------
    # On exclut si on ne trouve pas le message dans la base de donn�es de WORKFLOW
    my $msgId = $item->{MESSAGE_ID};
    my $msgVs = $item->{MESSAGE_VERSION};
    $message  = getMessageFromIdVersion({
                  MESSAGE_ID      => $msgId,
                  MESSAGE_VERSION => $msgVs,
                  MESSAGE_CODE    => $item->{REF} });
    if (!defined $message) {
      notice('No XML message founded in WORKFLOW.MESSAGE.');
      notice("Message [ Id = '$msgId'; Version = '$msgVs' ] Skipped [...]");
      tasUnlockItemInProgress({ REF => $item->{REF}, PNR => $pnr });
	  &monitore("TAS_TICKETING", "PNR_ISSUE", "INFO", $item->{MARKET}, $product, $item->{PNR}, "QC-XML issue", "END");
      next ITEM;
    }
    # -----------------------------------------------------------------
    
    $message = '<?xml version="1.0" encoding="ISO-8859-1" standalone="yes"?>'.$message;
    # -----------------------------------------------------------------
    my $tmp  = ' xmlns="http://www.expediacorporate.fr/newsimages/xsds/v1"';
    $message =~ s/UTF-8/ISO-8859-1/ig;
    $message =~ s/&euro;/&#8364;/ig;
    $message =~ s/$tmp//ig;
    # -----------------------------------------------------------------
    
    my $b;

        eval
        {
                $b = Expedia::XML::Booking->new($message);
        };
        if ($@)
        {
                notice('Problem with XML message founded in WORKFLOW.MESSAGE.');
				tasUnlockItemInProgress({ REF => $item->{REF}, PNR => $pnr });
				&monitore("TAS_TICKETING", "PNR_ISSUE", "INFO", $item->{MARKET}, $product, $item->{PNR}, "QC-XML issue", "END");
				next ITEM;
        }

        eval
		{
			notice('MdCode  = '.$b->getMdCode);
		};
        if ($@)
        {
            notice('Problem with XML message founded in WORKFLOW.MESSAGE -- too big');
			tasUnlockItemInProgress({ REF => $item->{REF}, PNR => $pnr });
			&monitore("TAS_TICKETING", "PNR_ISSUE", "INFO", $item->{MARKET}, $product, $item->{PNR}, "QC-XML issue", "END");
			next ITEM;
        }
		
    notice('Version = '.$item->{MESSAGE_VERSION});
    # _________________________________________________________________
    # V�rification Sp�ciale "Complete Checked" - WBMI
    debug('V�rification dossier "Complete Checked".');
    my $market    = $item->{MARKET};                debug('market    = '.$market);
    my $isOffline = $b->hasBeenManualyInserted();   debug('isOffline = '.$isOffline);
    if (!$isOffline) {
      my $bookDate    = &dateTimeXML($b->getMdRealBookDate);
      my $isTcChecked = isTcChecked({
                           MARKET   => $market,
                           MDCODE   => $item->{REF},
                           BOOKDATE => $bookDate,
                           PNR      => $item->{PNR} });
      if (!$isTcChecked) {
        notice('~ This booking is not complete checked. Skipping [...]');
        tasUnlockItemInProgress({ REF => $item->{REF}, PNR => $pnr });
		&monitore("TAS_TICKETING", "PNR_ISSUE", "INFO", $item->{MARKET}, $product, $item->{PNR}, "QC-Missing TC check", "END");
        next ITEM;
      }
    }
    # _________________________________________________________________

	# ------------------------------------------------------------------------------------------
    # 
    # ------------------------------------------------------------------------------------------
    my $PNR = $item->{PNR};
	
    # -----------------------------------------------------------------
    # R�cup�ration des TCAT_TYPE_ID (E-ticket / Papier) correspondants
    #  aux identifiants des TOURNEES s�lectionn�es dans la config.
    my $h_ticketTypes  = { 1 => 'etkt', 3 => 'paper', 5 => 'ebillet', 6 => 'ttless' };
    my $delivery       = $item->{DELIVERY};
       $delivery       =~ s/\s*//ig;            # On supprime les espacements inutiles
    my @tcatIds        = split(/,/, $delivery); # On d�coupe par ,
    my $h_delivery     = {};
    foreach my $tcatId (@tcatIds) {
      my $requete      = 'SELECT et.TCKT_TP_ID FROM TOURNEE_CATEGORY tc, ELIGIBLE_TICKET et WHERE tc.TCAT_ID = ? AND tc.TCAT_ID = et.TCAT_ID';
      my $ticketTypeId = $dbh->saarBind($requete, [$tcatId])->[0][0];
      notice("tickettype:".Dumper($ticketTypeId));
      $h_delivery->{$tcatId} = $h_ticketTypes->{$ticketTypeId};
    }
    # -----------------------------------------------------------------
    
    # -----------------------------------------------------------------
    # On regarde s'il s'agit de train ou d'avion, paper ou eticket !
    #my $tdt  = $b->getTrainTravelDossierStruct; # Travel Dossier Train
    #my $tda  = $b->getAirTravelDossierStruct;   # Travel Dossier A�rien
    #my $sTdt = scalar @$tdt; debug('sTdt = '.$sTdt);
    #my $sTda = scalar @$tda; debug('sTda = '.$sTda);

    ###############RECUPERATION DE LA STRUCTURE DES DIFFERENTS TRAVELDDOSIERS###############
           
    #CALCUL DU NOMBRE DE TRAVELDOSSIER
    my $nbDossier      = $b->getNbOfTravelDossiers;
    notice($nbDossier." TravelDossiers ");
    

    #RECUPERATION DE LA STRUCTURE DES DIFFERENTS TRAVELDDOSIERS
    $Listdossier = $b->getTravelDossierStruct;

    debug("LISTDOSSIER:".Dumper($Listdossier));

    #ON BOUCLE SUR CHAQUE TRAVELDOSSIER
    for ($x=0; $x < $nbDossier; $x++)
    {
		#crap crap crap !!! no time 
		if( $Listdossier->[$x]->{lwdPnrGds} ne '' && defined($Listdossier->[$x]->{lwdPnrGds}))
		{
			if($Listdossier->[$x]->{lwdPnrGds} eq  $item->{PNR})
			  {
				notice("PNR:".$Listdossier->[$x]->{lwdPnrGds}." TROUVE EN POSITION:".$x); 
				$mktype = $Listdossier->[$x]->{lwdType};
				if(!exists($h_pnr{$Listdossier->[$x]->{lwdPnrGds}}))
				{
				  $h_pnr{$Listdossier->[$x]->{lwdPnrGds}}=$x;
				}
				last;
			  }
			  else
			  {notice("PNR:".$Listdossier->[$x]->{lwdPnrGds}." ne corresponds pas en position pas ".$x);}
		}
		else
		{ 
			  if($Listdossier->[$x]->{lwdPnr} eq  $item->{PNR})
			  {
				notice("PNR:".$Listdossier->[$x]->{lwdPnr}." TROUVE EN POSITION:".$x); 
				$mktype = $Listdossier->[$x]->{lwdType};
				if(!exists($h_pnr{$Listdossier->[$x]->{lwdPnr}}))
				{
				  $h_pnr{$Listdossier->[$x]->{lwdPnr}}=$x;
				}
				last;
			  }
			  else
			  {notice("PNR:".$Listdossier->[$x]->{lwdPnr}." ne corresponds pas en position pas ".$x);}
		}
	}

    ###############RECUPERATION DE LA STRUCTURE DES DIFFERENTS TRAVELDDOSIERS###############
       
    my $std   = scalar @$Listdossier; debug('sTd = '.$std);
    if ( $std == 0 ) {   # Ce n'est pas un dossier T/A
      notice('Booking with no Train and no Air. Skipping [...]');
      # tasUnlockItemInProgress({ REF => $item->{REF}, PNR => $pnr });
      # next ITEM;
      $tasError = 53;
    }
    
    # On ne s'int�resse pas aux dossier TPC FARE
    if ($Listdossier->[$x]->{lwdFareType} eq 'TARIF_TPC') {
      notice('TPCFare Booking.');
      tasUnlockItemInProgress({ REF => $item->{REF}, PNR => $pnr });
	  &monitore("TAS_TICKETING", "PNR_ISSUE", "INFO", $item->{MARKET}, $product, $item->{PNR}, "QC-PNR in exclusion list", "END");
      next ITEM;
    }
    
    # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    # On v�rifie que ce mdCode est connu de notre base de connaissance
    my $msgType =  uc($product);
       $msgType = 'AIR' if ($mktype =~ /^(GAP_TC|WAVE_TC)$/);
       $msgType = 'TRAIN'   if ($mktype =~ /^(SNCF_TC|RG_TC)$/);
    debug('msgType = '.$msgType);
    if ($msgType !~ /^(AIR|TRAIN)$/) {
      notice("PNR = '".$pnr."' Can't determine 'msgType'. Skipping [...]");
      tasUnlockItemInProgress({ REF => $item->{REF}, PNR => $pnr });  
	  &monitore("TAS_TICKETING", "PNR_ISSUE", "INFO", $item->{MARKET}, $product, $item->{PNR}, "QC-PNR in exclusion list", "END");
      next ITEM;
    }
    my $mkItem  = &isInMsgKnowledge({ PNR => $item->{PNR} });
    if ((!defined $mkItem) || (scalar(@$mkItem) == 0)) {
      &insertIntoMsgKnowledge({ PNR => $item->{PNR}, CODE => $item->{REF}, TYPE => $msgType, VERSION => $item->{MESSAGE_VERSION}, MARKET => $item->{MARKET} });
    }
    
    if($mkItem->[0][0] eq '' && scalar(@$mkItem) == 1) {
    	my $row = &updateMsgKnowledge({PNR => $item->{PNR}, CODE => $item->{REF}, TYPE => $msgType, VERSION => $item->{MESSAGE_VERSION}, MARKET => $item->{MARKET} });
    }
  
    # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    my $ctd  = undef;                          # Current Travel Dossier

    if (!defined $Listdossier->[$x]->{lwdType}) {
       $Listdossier->[$x]->{lwdType} = 'GAP_TC'  if ($msgType eq 'AIR');
       $Listdossier->[$x]->{lwdType} = 'SNCF_TC' if ($msgType eq 'TRAIN');
    }

    my $ticketType = $h_delivery->{$item->{TCAT_ID}}; # Initialisation par d�faut
    if ($tasError == 0) {
	
 	  my $tType = undef;
	
	  $tType = 'etkt'  if ($Listdossier->[$x]->{lwdTicketType} eq 'ELECTRONIC_TICKET');
	  $tType = 'paper'  if ($Listdossier->[$x]->{lwdTicketType} eq 'PAPER_TICKET');
	  $tType = 'ebillet' if ($Listdossier->[$x]->{lwdTicketType} eq 'ELECTRONIC_BILLET'); 
	  $tType = 'ttless' if ($Listdossier->[$x]->{lwdTicketType} eq 'THALYS_TICKETLESS');  
	  debug('tType              = '.$tType);
         
      my $tcatId = $item->{TCAT_ID}; debug('tcatId              = '.$tcatId);

      if ((!defined $tType) || (!exists $h_delivery->{$tcatId})) {
        notice("PNR = '".$pnr."' Can't determine 'TicketType'. Skipping [.2.]");
        $tasError = 37;
        # tasUnlockItemInProgress({ REF => $item->{REF}, PNR => $pnr });
        # next ITEM;
      }
      else {
        if ((defined $tType) && (exists $h_delivery->{$tcatId})) {
          if ($tType ne $h_delivery->{$tcatId}) {
            notice("PNR = '".$pnr."' Wrong 'TicketType' compared to 'Queue'. Skipping [...]");
            $tasError = 37;
          } else {
            $item->{TICKET_TYPE} = $tType;
          }
        }
      }
    } # if ($tasError == 0)
    # -----------------------------------------------------------------
   
    # -----------------------------------------------------------------
    # On exclut si le booking pr�sente un COMMENT_TO_TICKETING
    my $hasTicketingComment = $b->hasTicketingComment;
    if (($hasTicketingComment) && ($tasError == 0)) {
      notice('This Booking has a Ticketing Comment !');
      notice('Ticketing Comment:'.$hasTicketingComment);
      $tasError = 46;
    }
    # -----------------------------------------------------------------
    
    # -----------------------------------------------------------------
    # Dossier comportant un BILLING_COMMENT // Commentaire Navision.
     if ((length($item->{BILLING_COMMENT}) > 0) && ($tasError == 0)) {
      notice('This Booking has a Billing Comment !');
      notice('Billing Comment:'.$item->{BILLING_COMMENT}."(".length($item->{BILLING_COMMENT}).")");
      $tasError = 47;
    }
    # -----------------------------------------------------------------
    
    # -----------------------------------------------------------------
    # On ne traite pas les OnHold et UnderBlockingApproval
    my $isOnHold            = $b->getDeliveryIsOnHold;
    my $isBlockedByApproval = $b->getDeliveryIsBlockedByApproval;
    debug('isOnHold            = '.$isOnHold);
    debug('isBlockedByApproval = '.$isBlockedByApproval);
    if ($isOnHold || $isBlockedByApproval) {
      notice("PNR = '".$pnr."' is OnHold. Skipping [...]")            if ($isOnHold);
      notice("PNR = '".$pnr."' is BlockedByApproval. Skipping [...]") if ($isBlockedByApproval);
      tasUnlockItemInProgress({ REF => $item->{REF}, PNR => $pnr });
	  &monitore("TAS_TICKETING", "PNR_ISSUE", "INFO", $item->{MARKET}, $product, $item->{PNR}, "QC-Booking on hold or pending approval", "END");
      next ITEM;
    }
    # -----------------------------------------------------------------
           
    # Ajout d'un WS pour aller r�cup�rer le dernier �tat onHold et isBlockedByApprouval
    # dans la BDD ECTWeb 31/10/11. En cas de non r�ponse, on passe 
    # -----------------------------------------------------------------
    # On ne traite pas les OnHold et UnderBlockingApproval
    my $soapOut = undef;
    my $WS_isOnHold = undef;
    my $WS_isBlockedByApproval = undef;
    
	  $soapOut = getDeliveryStatus('DeliveryWS', {deliveryId => $item->{DELIVERY_ID}});
 
    if (!defined($soapOut))
    {
      $WS_isOnHold            = 0;
      $WS_isBlockedByApproval = 0;      
    }
    else
    {
      $WS_isOnHold            = $soapOut->{isOnHold};
      $WS_isBlockedByApproval = $soapOut->{isBlockedByApproval};
    }
    debug('WS_isOnHold            = '.$WS_isOnHold);
    debug('WS_isBlockedByApproval = '.$WS_isBlockedByApproval);
    if ($WS_isOnHold || $WS_isBlockedByApproval) {
      notice("PNR = '".$pnr."' is OnHold (WS). Skipping [...]")            if ($WS_isOnHold);
      notice("PNR = '".$pnr."' is BlockedByApproval (WS). Skipping [...]") if ($WS_isBlockedByApproval);
      tasUnlockItemInProgress({ REF => $item->{REF}, PNR => $pnr });
	  &monitore("TAS_TICKETING", "PNR_ISSUE", "INFO", $item->{MARKET}, $product, $item->{PNR}, "QC-Booking on hold or pending approval", "END");
      next ITEM;
    }
    # -----------------------------------------------------------------

    # __________________________________________________________________________
    # Sp�cificit� SAIPEM, un de nos clients.
    #  - Utilisation d'1 OfficeID sp�cifique mais que pour l'a�rien.
    if (($b->getPerComCode({trvPos => $b->getWhoIsMain}) == 820452) && ($msgType eq 'AIR')) {
      if ($GDS->saipem() == 0) {
        $GDS->disconnect;
        $sauv_self_amadeus= $self->{_AMADEUS};
        $sauv_task        = $params->{TaskName};
        #notice("SAUV AMADEUS:".$sauv_self_amadeus);
        #notice("SAUV TASK:".$sauv_task);
        my $temp_task="tas-SAIPEM:AIR";
        my  $config        = Expedia::XML::Config->new('/var/egencia/libsperl/Expedia/Tools/config_DDB.xml',$temp_task);
        $GDS = $cnxMgr->getConnectionByName('amadeus-SAIPEM');
        return 1 unless $GDS->connect;
      }
      $GDS->saipem(1);
    } else {
      if ($GDS->saipem() == 1) {
        $GDS->disconnect;
        my  $config        = Expedia::XML::Config->new('/var/egencia/libsperl/Expedia/Tools/config_DDB.xml',$sauv_task);
        $GDS = $cnxMgr->getConnectionByName($sauv_self_amadeus);
        return 1 unless $GDS->connect;
      }
      $GDS->saipem(0);
    }
    # __________________________________________________________________________

    # __________________________________________________________________________
    # Sp�cificit� PSA1, un de nos clients.
    #  - Utilisation d'1 OfficeID sp�cifique mais que pour l'a�rien.
    if (($b->getPerComCode({trvPos => $b->getWhoIsMain}) == 821033) || ($b->getPerComCode({trvPos => $b->getWhoIsMain}) == 821109)) {
      if ($GDS->psa1() == 0) {
        $GDS->disconnect;
		$sauv_self_amadeus= $self->{_AMADEUS};
        $sauv_task        = $params->{TaskName};
        #notice("SAUV AMADEUS:".$sauv_self_amadeus);
        #notice("SAUV TASK:".$sauv_task);
        my $temp_task="tas-PSA1:AIR";
        my  $config        = Expedia::XML::Config->new('/var/egencia/libsperl/Expedia/Tools/config_DDB.xml',$temp_task);
        $GDS = $cnxMgr->getConnectionByName('amadeus-PSA1');
        return 1 unless $GDS->connect;
      }
      $GDS->psa1(1);
    } else {
      if ($GDS->psa1() == 1) {
        $GDS->disconnect;
        my  $config        = Expedia::XML::Config->new('/var/egencia/libsperl/Expedia/Tools/config_DDB.xml',$sauv_task);
        $GDS = $cnxMgr->getConnectionByName($sauv_self_amadeus);
        return 1 unless $GDS->connect;
      }
      $GDS->psa1(0);
    }
    # __________________________________________________________________________
    
    my $tmpTask =  $self->{_TASK};                    
       $tmpTask =~ s/^(tas(?:meetings)?)-.*/$1/;
    
    my $tmpItem = {
      REF         => $item->{REF},
      TASK        => 'tas-'.lc($msgType).'-'.$ticketType,
      SUBTASK     => $tmpTask.'-'.$item->{AGENCY},
      TYPE        => $Listdossier->[$x]->{lwdType},
      PNR         => $pnr,
      DELIVERY_ID => $item->{DELIVERY_ID},
      MARKET      => $item->{MARKET},
      XML         => $message,
      TAS_ERROR   => $tasError,
      TICKET_TYPE => $item->{TICKET_TYPE},
      PRDCT_TP_ID => $item->{PRDCT_TP_ID}, 
	  MULTI_PNR   => $item->{MULTI_PNR}
    };
    # __________________________________________________________________________
    # SECTION DEPLACEE DE TasksProcessor.pm
    my $resInsert = &tasInsertItem(
      { REF         => $tmpItem->{REF},
        TASK        => $tmpItem->{TASK},
        SUBTASK     => $tmpItem->{SUBTASK},
        TYPE        => $tmpItem->{TYPE},
        PNR         => $tmpItem->{PNR},
        DELIVERY_ID => $tmpItem->{DELIVERY_ID},
        XML         => $tmpItem->{XML}, }
    );
    if ($resInsert == 0) {
      notice('Problem during call of tasInsertItem method.');
      tasUnlockItemInProgress({ REF => $item->{REF}, PNR => $pnr });
	  &monitore("TAS_TICKETING", "PNR_ISSUE", "INFO", $item->{MARKET}, $product, $item->{PNR}, "QC-DB Insertion or Technical issue", "END");
      next ITEM;
    }
    # -----------------------------------------------------------------
    # Si on � d�tect� une erreur TAS
    if ($tmpItem->{TAS_ERROR} != 0) {
	  &monitore("TAS_TICKETING","PNR_ISSUE","ERROR",$item->{MARKET},$product,$item->{PNR},$tmpItem->{TAS_ERROR},"END");
      notice('TAS_ERROR = '.$tmpItem->{TAS_ERROR});
      notice('TAS_MESSG = '.&getTasMessage($tmpItem->{TAS_ERROR}));
      &logTasError(
        { errorCode  => $tmpItem->{TAS_ERROR},
          PNRId      => $tmpItem->{PNR},
          mdCode     => $tmpItem->{REF},
          deliveryId => $tmpItem->{DELIVERY_ID},
          market     => $tmpItem->{MARKET},
          PRDCT_TP_ID => $tmpItem->{PRDCT_TP_ID},
		  MULTI_PNR   => $tmpItem->{MULTI_PNR} 
		}		  
      );
      &tasUpdateItem(
        { REF        => $tmpItem->{REF},
          TASK       => $tmpItem->{TASK},
          SUBTASK    => $tmpItem->{SUBTASK},
          STATUS     => 'TAS_ERROR',
          PNR        => $tmpItem->{PNR},
          TAS_ERROR  => $tmpItem->{TAS_ERROR},
          PRDCT_TP_ID     => $tmpItem->{PRDCT_TP_ID}, } 
      );
      next ITEM;
    }
    # -----------------------------------------------------------------    
    # __________________________________________________________________________
    # Modification finale pour changer le moins de code possible ;)
    $item = {};
    $item = $tmpItem;
    # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
    # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
   
    # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
    # Verrouillage de l'ITEM
    $lock = &tasLockItem({ REF => $item->{REF}, PNR => $item->{PNR} });
    next ITEM unless $lock;
    # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
    
    # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
    $params->{Item}      = $item;
    $params->{ParsedXML} = $b;
    $params->{GDS}       = $GDS;
    debug('XML = '.$params->{ParsedXML}->doc->toString(1)); # On log dans la TRACE
    # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
    
    # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
    # D�termine quels modules doivent �tre utilis�s sur l'item.
    my $key = $item->{TASK}.'|'.$item->{SUBTASK};
    debug('key = '.$key);
    @modules = @{$self->{_H_PROCESSES}->{modules}}
      if (exists $self->{_H_PROCESSES}->{modules});
    # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
 
    # $$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$ #
    # $$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$ #
    #      TAS-AIR-ETKT - TAS-AIR-ETKT - TAS-AIR-ETKT -TAS-AIR-ETKT       #
    # $$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$ #
    # $$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$ #
    
    if ($item->{TASK} eq 'tas-air-etkt') {
    
      # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
      # V�rification que le PNR existe encore dans AMADEUS.
      $PNR = Expedia::GDS::PNR->new(PNR => $item->{PNR}, GDS => $GDS);
      if (!defined $PNR) {
        notice("Could not read PNR '".$item->{PNR}."' from GDS.");
		&monitore("TAS_TICKETING", "PNR_ISSUE", "INFO", $item->{MARKET}, $product, $item->{PNR}, "QC-PNR not found in GDS", "END");
        &tasUnlockItem({ REF => $item->{REF}, PNR => $item->{PNR} });
        &tasUpdateItem({
          REF       => $item->{REF},
          TASK      => $item->{TASK},
          SUBTASK   => $item->{SUBTASK},
          STATUS    => 'finished',
          PNR       => $item->{PNR},
        });
        next ITEM;
      }
      $params->{PNR} = $PNR;
          
    #ON PASSE LA REFERENCE DU TABLEAU DE HASHAGE    
    $params->{Position} = \%h_pnr;
    $params->{RefPNR}   = $item->{PNR};
      # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
     
      # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
      # BookDate est sup�rieure � 3 H 00 => Traitement quand m�me !
		  #  V�rification de BOOKSOURCE WEB et AIR PROCEED.
      my $bookSourceWeb = 0;
		  my $btcAirProceed = 0;
		  
		  foreach (@{$PNR->{'PNRData'}}) {
		    $bookSourceWeb  = 1 if ($_->{'Data'} =~ /BOOKSOURCE WEB/);
		    $btcAirProceed  = 1 if ($_->{'Data'} =~ /AIR PROCEED/);
				last if ($bookSourceWeb && $btcAirProceed);
      }
  		  
		  # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
		  # Ajout de la Notion de BTC PROCEED et ONLINE // OFFLINE
		  $params->{BtcProceed}    = $btcAirProceed;
		  $params->{OnlineBooking} = $bookSourceWeb ? 1 : 0;
		  notice('~ Dossier '.($bookSourceWeb ? 'Online' : 'Offline').' [...]');
		  # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@      
      my $status = 0;
      foreach my $h_mod (@modules) {
        MODULE: foreach my $module (keys %$h_mod) {
          $params->{ModuleParams} = {};
          notice("# PROCESSING PNR = '".$item->{PNR}."' with module $module");
          foreach my $param (keys %{$h_mod->{$module}}) {
    			  $params->{ModuleParams}->{$param} = $h_mod->{$module}->{$param};
          }
          eval {      
            my $mod = Expedia::Workflow::ModuleLoader->new($module);
            $status = $mod->run($params);
          };
          if (($status == 0) || ($@)) {
            notice("Error during run of module $module : ".$@) if ($@);
			&monitore("TAS_TICKETING", "PNR_ISSUE", "INFO", $item->{MARKET}, $product, $item->{PNR}, "QC-DB Insertion or Technical issue", "END");
            &tasUnlockItem({ REF => $item->{REF}, PNR => $item->{PNR} });
            &tasUpdateItem({ # Permet la suppression de l'item de la table IN_PROGRESS
              REF       => $item->{REF},
              TASK      => $item->{TASK},
              SUBTASK   => $item->{SUBTASK},
              STATUS    => 'finished',
              PNR       => $item->{PNR},
            });
            next ITEM;
          }
          # _________________________________________________________________
          # Si on � d�tect� une erreur TAS
          if (defined $PNR->{TAS_ERROR}) {
		    &monitore("TAS_TICKETING","PNR_ISSUE","ERROR",$item->{MARKET},$product,$item->{PNR},$PNR->{TAS_ERROR},"END");	  
            notice('TAS_ERROR = '.$PNR->{TAS_ERROR});
			#EGE-87369
			#notice('EMD_ERROR = '.$PNR->{EMD_ERROR});
            notice('TAS_MESSG = '.&getTasMessage($PNR->{TAS_ERROR})) unless ($PNR->{TAS_ERROR} == 12);
            notice('TAS_MESSG = '.$PNR->{TAS_MESSG})                     if ($PNR->{TAS_ERROR} == 12);
            &logTasError({
              errorCode  	=> $PNR->{TAS_ERROR},
			  #EGE-87369
			  #errorCodeEmd  => $PNR->{EMD_ERROR},
              errorMesg  	=> $PNR->{TAS_MESSG},
              PNRId      	=> $item->{PNR},
              mdCode     	=> $item->{REF},
              deliveryId 	=> $item->{DELIVERY_ID},
              market     	=> $params->{GlobalParams}->{market},
              PRDCT_TP_ID   => $item->{PRDCT_TP_ID},
			  product 		=> $product,
			  MULTI_PNR   	=> $item->{MULTI_PNR}			  
            });
            &tasUpdateItem({
              REF        => $item->{REF},
              TASK       => $item->{TASK},
              SUBTASK    => $item->{SUBTASK},
              STATUS     => 'TAS_ERROR',
              PNR        => $item->{PNR},
              TAS_ERROR  => $PNR->{TAS_ERROR},
              PRDCT_TP_ID     => $item->{PRDCT_TP_ID}, 
            });
            next ITEM;
          }
          # _________________________________________________________________
          
        } # Fin MODULE: foreach my $module (keys %$h_mod)

      } # Fin foreach my $h_mod (@modules)
      
      &tasUpdateItem({
        REF       => $item->{REF},
        TASK      => $item->{TASK},
        SUBTASK   => $item->{SUBTASK},
        STATUS    => 'TAS_TICKETED',
        PNR       => $item->{PNR},
        MARKET    => $params->{GlobalParams}->{market},
        PRDCT_TP_ID     => $item->{PRDCT_TP_ID}, 
      });


      &btcTasProceed({ PNR => $item->{PNR}, TYPE => 'AIR' });

	  &monitore("TAS_TICKETING","PNR_ISSUE","INFO",$item->{MARKET},$product,$item->{PNR},'',"END");
	  
      next ITEM;
    
    } # Fin : if ($item->{TASK} eq 'tas-air-etkt')
    
    # $$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$ #
    # $$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$ #
    #   TAS-TRAIN-ETKT - TAS-TRAIN-ETKT - TAS-TRAIN-ETKT -TAS-TRAIN-ETKT  #
    # $$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$ #
    # $$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$ #
    
    elsif ( ($item->{TASK} eq 'tas-train-etkt')    ||
            ($item->{TASK} eq 'tas-train-ebillet') ||
            ($item->{TASK} eq 'tas-train-ttless') ) {

		notice('Using Rail WS');
		my $tssRecLoc = $b->getTravelDossierStruct->[$x]->{lwdTssRecLoc};
		# reclaim
		if(!$b->getTravelDossierStruct->[$x]->{lwdPnrGds} && $b->getTravelDossierStruct->[$x]->{lwdPnrGds} eq ''){
			notice('Start re-claim processing');
			my $token = getToken();
			if($token){
				if(!$tssRecLoc && $tssRecLoc eq ''){
					notice('No TssRecLoc found in XML => get a new TssRecLoc from TSS');
					my $tssRecLocResponse = getTssRecLoc($token);
					if($tssRecLocResponse->{'recordLocator'}){
						notice('New TssRecLoc create by TSS WS : '.$tssRecLocResponse->{'recordLocator'});
						&monitore("TAS_TICKETING", "RETRIEVE_TSSRECLOC", "INFO", $item->{MARKET}, $product, $item->{PNR}, '', "WEBSERVICE CALL");
						$tssRecLoc = $tssRecLocResponse->{'recordLocator'};
					}else{
						notice('Error when creation a new TssRecLoc : '.$tssRecLocResponse->{'error'}->[0]->{'display_message'});
						&monitore("TAS_TICKETING", "RETRIEVE_TSSRECLOC", "ERROR", $item->{MARKET}, $product, $item->{PNR}, $tssRecLocResponse->{'error'}->[0]->{'display_message'}, "WEBSERVICE CALL");
						setTasError('200', '', $item, $product);
						next ITEM;
					}
				}
				
				# Recherche de percode
				my $ttds         = $params->{ParsedXML}->getTrainTravelDossierStruct;
				my $lwdPos       = $ttds->[$x]->{lwdPos};
				my $paxInfos     = $params->{ParsedXML}->getPaxPnrInformations({lwdPos => $lwdPos});
				my $perCode = '';
				foreach my $paxInfo (@$paxInfos) {
					if(uc($paxInfo->{'DV'}) eq uc($pnr)){
						$perCode = $paxInfo->{'PerCode'};
					}
				}

				notice('PnrGds : '.$b->getTravelDossierStruct->[$x]->{lwdPnrGds});
				notice('TssRecLoc : '.$tssRecLoc);
				notice('Supplier reference : '.$pnr);
				notice('MdCode : '.$params->{ParsedXML}->getMdCode);
				notice('PerCode : '.$perCode);
				notice('Pnrs : '.$b->getTravelDossierStruct->[$x]->{lwdListPnr});

				my $resultClaim = claim($tssRecLoc,
					$pnr, 
					$item->{REF},
					$params->{ParsedXML}->getMdCode, 
					$perCode,
					$b->getTravelDossierStruct->[$x]->{lwdListPnr}, 
					$token);
				
				notice(Dumper($resultClaim));

				if ($resultClaim->{'error_code'}) {
					notice($resultClaim->{'error_code'}.' : '.$resultClaim->{'error_description'});
					&monitore("TAS_TICKETING", "RECLAIM_PNR", "ERROR", $item->{MARKET}, $product, $pnr, $resultClaim->{'error_description'}, "WEBSERVICE CALL");
					setTasError('111', 'Re-Claim attempt failed, please process manually', $item, $product);
					next ITEM;
				} else {
					notice('Re-claim success, PNRGds : '.$resultClaim->{'amadeus_reference'});
					&monitore("TAS_TICKETING", "RECLAIM_PNR", "INFO", $item->{MARKET}, $product, $item->{PNR}, '', "WEBSERVICE CALL");
					&updateDispatchAfterReclaim($resultClaim->{'amadeus_reference'}, $item->{PNR}, $item->{REF});
					$item->{PNR} = $resultClaim->{'amadeus_reference'};
				}
				
				notice('End of re-claim processing with TssRecLoc : '.$resultClaim->{'amadeus_reference'});
			}else{
				notice('Error when getting token => claim interruption');
				&monitore("TAS_TICKETING", "RECLAIM_PNR", "ERROR", $item->{MARKET}, $product, $item->{PNR}, "Error occurred when getting token", "WEBSERVICE CALL");
				setTasError('200', '', $item, $product);
				next ITEM;
			}
		}
		#--------------------------------------------------------------------------------------------
		
		my $tssResponse = wsTSSCall($params->{GlobalParams}->{market}, $tssRecLoc); 
		notice('CODE TSS WS : '.Dumper($tssResponse));
		
		if($tssResponse eq ""){
			# Error case 1 : we have a problem when we call TSS WS
			notice('We have a communication problem with TSS WS');
			&monitore("TAS_TICKETING", "TST_ISSUE_USING_SUPPLY_LAYER", "ERROR", $item->{MARKET}, $product, $item->{PNR}, "Error occurred when connexion with TSS",  "WEBSERVICE CALL");
			setTasError('200', '', $item, $product);
			next ITEM;
		}else{
			# check the response of the Rail WS
			if($tssResponse->{'ticket_number'}){
				# Succes case
				notice("Ticket sent success with number : ".$tssResponse->{'ticket_number'});
				&monitore("TAS_TICKETING", "TST_ISSUE_USING_SUPPLY_LAYER", "INFO", $item->{MARKET}, $product, $item->{PNR}, '', "WEBSERVICE CALL");
			}elsif ($tssResponse->{'error_code'}){
				# Error cases
				# Error case 2 : we have an error code
				&monitore("TAS_TICKETING", "TST_ISSUE_USING_SUPPLY_LAYER", "ERROR", $item->{MARKET}, $product, $item->{PNR}, $tssResponse->{'error_description'}, "WEBSERVICE CALL");
				if ($listOfCodeRetryTssWS->{$tssResponse->{'error_code'}}) {
					notice($tssResponse->{'error_code'} . " is in the list of Retry TSS error codes but the Retry is not implemented yet. The error is handled as a no Retry TSS error");
					setTasError($listOfCodeRetryTssWS->{$tssResponse->{'error_code'}}, $tssResponse->{'error_description'}, $item, $product);
				} elsif($listOfCodeNoRetryTssWS->{$tssResponse->{'error_code'}}) {
					notice($tssResponse->{'error_code'}. " is in the list of no Retry TSS error codes");
					setTasError($listOfCodeNoRetryTssWS->{$tssResponse->{'error_code'}}, $tssResponse->{'error_description'}, $item, $product);
				} else {
					notice($tssResponse->{'error_code'}. " is NOT in any list of TSS error codes");
					setTasError('200', '', $item, $product);
				}
				next ITEM;
			}else{
				# Error case 3 : we don't have an error code
				notice('We don t have any TSS error code');
				setTasError('200', '', $item, $product);
				&monitore("TAS_TICKETING", "TST_ISSUE_USING_SUPPLY_LAYER", "ERROR", $item->{MARKET}, $product, $item->{PNR}, "Error occurred when connexion with TSS", "WEBSERVICE CALL");
				next ITEM;
			}
		}

		&tasUpdateItem({
			REF         => $item->{REF},
			TASK        => $item->{TASK},
			SUBTASK     => $item->{SUBTASK},
			STATUS      => 'TAS_CHECKED',
			PNR         => $item->{PNR},
			DELIVERY_ID => $item->{DELIVERY_ID},
			MARKET      => $params->{GlobalParams}->{market},
			PRDCT_TP_ID => $item->{PRDCT_TP_ID},       
		});
      
		&btcTasProceed({ PNR => $item->{PNR}, TYPE => 'TRAIN' });
	  
		&monitore("TAS_TICKETING","PNR_ISSUE","INFO",$item->{MARKET},$product,$item->{PNR},'',"END");

		next ITEM; 
      
    } # Fin : if ($item->{TASK} eq 'tas-train-etkt')

  } # Fin ITEM: foreach my $item (@items)
  # ----------------------------------------------------------------
  
    #if ((defined(@$GetBookingFormOfPayment_errors)) && (scalar(@$GetBookingFormOfPayment_errors) > 0))  
	#{		
	#	BackWSSendError($params->{GlobalParams}->{market},$params->{TaskName});
	#}
	
  # ----------------------------------------------------------------
  # Retry First and Send Email if I Got Problems whit SOAP (changeDeliveryState)
  if ((defined($soapRetry)) && (scalar(@$soapRetry) > 0)) {
    my $soapPbNb = scalar(@$soapRetry);
    notice("TAS has encountered '$soapPbNb' problems with SOAP. Retrying [...]");
    &soapRetry($soapRetry);
  }
  &soapProblems($tmpTask, $agency, $product)
    if (defined($soapProblems) && (scalar(keys %$soapProblems) > 0));
  # ----------------------------------------------------------------

  return 1;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

sub setTasError{

   my $tssErrorCode = shift;
   my $tssErrorMesg = shift;
   my $tssItem = shift;
   my $product = shift;

   &monitore("TAS_TICKETING", "PNR_ISSUE", "ERROR", $tssItem->{MARKET}, $product, $tssItem->{PNR}, $tssErrorCode, "END");

   notice('TAS_ERROR = '.$tssErrorCode);
   notice('TAS_MESSG = '.$tssErrorMesg);
   
   &logTasError({
       errorCode   => $tssErrorCode,
       errorMesg   => $tssErrorMesg,
       PNRId       => $tssItem->{PNR},
       mdCode      => $tssItem->{REF},
       deliveryId  => $tssItem->{DELIVERY_ID},
       market      => $tssItem->{MARKET},
       PRDCT_TP_ID => $tssItem->{PRDCT_TP_ID},
       product     => $product,
       MULTI_PNR   => $tssItem->{MULTI_PNR}
   });

   &tasUpdateItem({
       REF         => $tssItem->{REF},
       TASK        => $tssItem->{TASK},
       SUBTASK     => $tssItem->{SUBTASK},
       STATUS      => 'TAS_ERROR',
       PNR         => $tssItem->{PNR},
       TAS_ERROR   => $tssErrorCode,
       PRDCT_TP_ID => $tssItem->{PRDCT_TP_ID},
  });
}

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# TAS Finish Processor
sub tfnProcessor {
  my $self = shift;

	my $params = {};
	   $params->{TaskName} = $self->{_TASK};
	
	#PARAMETERS ARE NOW IN DATABASE OR OPTIONNAL IN THE SCRIPT 
  $params->{GlobalParams}->{agency}   = $self->{_AGENCY};
  $params->{GlobalParams}->{market}   = $self->{_MARKET};
  # ----------------------------------------------------------------
  # V�rification qu'un process similaire n'est pas d�j� en cours de traitement
  my $pm = Expedia::Workflow::ProcessManager->new($self->{_TASK}.':'.$self->{_PRODUCT});
  return 1 if ($pm->isRunning() == 1);
  # ----------------------------------------------------------------

  # ----------------------------------------------------------------
  # Ex�cution du/des modules de r�cup�ration des items � traiter
  my @items      = ();
  my @modulesSrc = @{$self->{_H_SOURCES}->{modules}};
  foreach my $h_mod (@modulesSrc) {
    foreach my $module (keys %$h_mod) {
      $params->{ModuleParams} = {};
      notice("# PROCESSING module $module");
      foreach my $param (keys %{$h_mod->{$module}}) {
        $params->{ModuleParams}->{$param} = $h_mod->{$module}->{$param};
      }
      eval {
        my $modSrc = Expedia::Workflow::ModuleLoader->new($module);
   
			  push (@items, $modSrc->run($params));
      };
      error("Error during run of module $module : ".$@) if ($@);
    }
  }
  # ----------------------------------------------------------------
  
  my $nbItems = scalar @items;
  
  # ________________________________________________________________
  # Ajout� pour MEETINGS. 12 Mars 2009.
  my $agency  =  $params->{GlobalParams}->{agency}; notice('AGENCY  = '.$agency);
  my $product =  $self->{_PRODUCT};                 notice('PRODUCT = '.$product);
  my $tmpTask =  $self->{_TASK};
     $tmpTask =~ s/^(tas(?:meetings)?)-.*/$1/;      notice('TMPTASK = '.$tmpTask);
  # ________________________________________________________________
  
  # ----------------------------------------------------------------
  # Ex�cution du/des modules de traitement sur chaque item
  my $PNR     = undef;
  my $count   = 0;  
  my $lock    = 0;
  my $unlock  = 0;
  my @modules = @{$self->{_H_TASK}->{modules}};
  my $changes = { add => [], del => [], mod => [] };
  my $GDS     = $cnxMgr->getConnectionByName($self->{_AMADEUS});
  my $sauv_self_amadeus= '';
  my $sauv_task        = '';
  
  ITEM: foreach my $item (@items) {
  
     if ($GDS->saipem() == 1) { 
        $GDS->disconnect;
        $sauv_task=$sauv_task.":".$self->{_PRODUCT};
        my  $config        = Expedia::XML::Config->new('/var/egencia/libsperl/Expedia/Tools/config_DDB.xml',$sauv_task);
        $GDS = $cnxMgr->getConnectionByName($sauv_self_amadeus);
        $GDS->saipem(0);
        return 1 unless $GDS->connect;
      } 

     if ($GDS->psa1() == 1) { 
        $GDS->disconnect;
        $sauv_task=$sauv_task.":".$self->{_PRODUCT};
        my  $config        = Expedia::XML::Config->new('/var/egencia/libsperl/Expedia/Tools/config_DDB.xml',$sauv_task);
        $GDS = $cnxMgr->getConnectionByName($sauv_self_amadeus);
        $GDS->psa1(0);
        return 1 unless $GDS->connect;
      } 
      
    #our use to transfert the variable to the others package
    our $log_id= '';

    $log_id=$item->{REF};
        
    $count++;
    
    # Afin de pr�venir des d�connections de l'API !
    if ($count % 100 == 0) { $GDS->disconnect; return 1 unless ($GDS->connect); }
    
    # ---------------------------------------------------------------------
    # Vidage des actions � effectuer
    $changes = { add => [], del => [], mod => [] };
    $params->{Changes}   = $changes;
    $params->{ParsedXML} = Expedia::XML::Booking->new($item->{XML});
    # ---------------------------------------------------------------------
    
    notice('---------------------------------------------------------------');
    notice(" Working on item REF = '".$item->{REF}."' PNR = '".$item->{PNR}."' ($count/$nbItems)") if ($item->{REF} &&  $item->{PNR});
    notice('---------------------------------------------------------------');
    
    # ---------------------------------------------------------------------
    # V�rifie que l'item est toujours lock� par BTC_TAS dans DELIVERY.
    my $isItemLocked = undef;
       $isItemLocked = &tasIsItemLocked({ REF => $item->{REF}, PNR => $item->{PNR}});
    if ((scalar(@$isItemLocked) == 1) && ($isItemLocked->[0][0] eq 'BTC_TAS')) {
      notice("PNR '".$item->{PNR}."' is still locked by BTC_TAS.");
    } else {
      notice("Something strange detected concerning the lock on PNR '".$item->{PNR}."'.");
      notice(' * Locked by Multiples Agents.') if (scalar(@$isItemLocked) > 1);
      notice(' * Locked by Nobody.')           if (scalar(@$isItemLocked) == 0);
      notice(' * Locked by '.$isItemLocked->[0][0].'.')
        if ((scalar(@$isItemLocked) > 1) && ($isItemLocked->[0][0] ne 'BTC_TAS'));
    }
    # ---------------------------------------------------------------------
      
    #_____________________________________________________________________
    #     # Sp�cificit� PS SAIPEM, un de nos clients.
    #         #  - Utilisation d'1 OfficeID sp�cifique mais que pour l'a�rien.
                 if ($params->{ParsedXML}->getPerComCode({trvPos => $params->{ParsedXML}->getWhoIsMain}) == 820452) {
    	             if ($GDS->saipem() == 0) { 
                   	$GDS->disconnect;
                        $sauv_self_amadeus= $self->{_AMADEUS};
                        $sauv_task        = $params->{TaskName};
                        my $temp_task="tas-finish-SAIPEM:AIR";
                        my  $config        = Expedia::XML::Config->new('/var/egencia/libsperl/Expedia/Tools/config_DDB.xml',$temp_task);
                        $GDS = $cnxMgr->getConnectionByName('amadeus-SAIPEM');
                        return 1 unless $GDS->connect;
                     }
                     $GDS->saipem(1);
                     } else {
                     if ($GDS->saipem() == 1) {
                     $GDS->disconnect;
                     my  $config        = Expedia::XML::Config->new('/var/egencia/libsperl/Expedia/Tools/config_DDB.xml',$sauv_task);
                     $GDS = $cnxMgr->getConnectionByName($sauv_self_amadeus);
                     return 1 unless $GDS->connect;
                     }
                     $GDS->saipem(0);
                 }
    
    #_____________________________________________________________________
    #     # Sp�cificit� psa1, un de nos clients.
    #         #  - Utilisation d'1 OfficeID sp�cifique mais que pour l'a�rien.
                 if ( ($params->{ParsedXML}->getPerComCode({trvPos => $params->{ParsedXML}->getWhoIsMain}) == 821033) ||
				   	($params->{ParsedXML}->getPerComCode({trvPos => $params->{ParsedXML}->getWhoIsMain}) == 821109)	)  {
    	             if ($GDS->psa1() == 0) { 
                   	$GDS->disconnect;
                        $sauv_self_amadeus= $self->{_AMADEUS};
                        $sauv_task        = $params->{TaskName};
                        my $temp_task="tas-finish-PSA1:AIR";
                        my  $config        = Expedia::XML::Config->new('/var/egencia/libsperl/Expedia/Tools/config_DDB.xml',$temp_task);
                        $GDS = $cnxMgr->getConnectionByName('amadeus-PSA1');
                        return 1 unless $GDS->connect;
                     }
                     $GDS->psa1(1);
                     } else {
                     if ($GDS->psa1() == 1) {
                     $GDS->disconnect;
                     my  $config        = Expedia::XML::Config->new('/var/egencia/libsperl/Expedia/Tools/config_DDB.xml',$sauv_task);
                     $GDS = $cnxMgr->getConnectionByName($sauv_self_amadeus);
                     return 1 unless $GDS->connect;
                     }
                     $GDS->psa1(0);
                 }
    # _____________________________________________________________________
        
    # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
    # V�rification que le PNR existe encore dans AMADEUS.
    $PNR = Expedia::GDS::PNR->new(PNR => $item->{PNR}, GDS => $GDS);
    if (!defined $PNR) {
      notice("Could not read PNR '".$item->{PNR}."' from GDS.");
      &tasUnlockItem({ REF => $item->{REF}, PNR => $item->{PNR} });
      next ITEM;
    }
    $params->{PNR}  = $PNR;  # Sous-entendu l'objet PNR
    $params->{Item} = $item;
    $params->{GDS}  = $GDS;
    # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
    
    # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
		# V�rification de BOOKSOURCE WEB et AIR PROCEED.
		# ~~~ Soit pr�sence des deux soit aucun des deux ~~~
		my $bookSourceWeb = 0;
		my $btcAirProceed = 0;
		foreach (@{$PNR->{'PNRData'}}) {
		  $bookSourceWeb = 1 if ($_->{'Data'} =~ /BOOKSOURCE WEB/);
		  $btcAirProceed = 1 if ($_->{'Data'} =~ /(AIR|TRAIN) PROCEED/);
		  last if ($bookSourceWeb && $btcAirProceed);
    }
	  # Ajout de la Notion de BTC PROCEED
	  $params->{BtcProceed} = 0;
	  $params->{BtcProceed} = 1 if (($bookSourceWeb == 1) && ($btcAirProceed == 1));
	  notice('~ Dossier Offline [...]') if ($params->{BtcProceed} == 0);
	  notice('~ Dossier Online  [...]') if ($params->{BtcProceed} == 1);
	  # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
    
    my $status = 0;
    foreach my $h_mod (@modules) {
      MODULE: foreach my $module (keys %$h_mod) {
        $params->{ModuleParams} = {};
        notice("# PROCESSING PNR = '".$item->{PNR}."' with module $module");
        foreach my $param (keys %{$h_mod->{$module}}) {
  			  $params->{ModuleParams}->{$param} = $h_mod->{$module}->{$param};
        }
        eval {      
          my $mod = Expedia::Workflow::ModuleLoader->new($module);
          $status = $mod->run($params);
        };
        if (($status == 0) || ($@)) {
          notice("Error during run of module $module : ".$@) if ($@);
          &tasUnlockItem({ REF => $item->{REF}, PNR => $item->{PNR} });
          next ITEM;
        }

        # -----------------------------------------------------------------
        # Si on � d�tect� une erreur TAS
        if (defined $PNR->{TAS_ERROR}) {
		  &monitore("TAS_TICKETING","PNR_ISSUE","ERROR",$item->{MARKET},$product,$item->{PNR},$PNR->{TAS_ERROR},"END");
          notice('TAS_ERROR = '.$PNR->{TAS_ERROR});
          notice('TAS_MESSG = '.&getTasMessage($PNR->{TAS_ERROR}));
          &tasUpdateItem({
            REF        => $item->{REF},
            TASK       => $item->{TASK},
            SUBTASK    => $item->{SUBTASK},
            STATUS     => 'TAS_ERROR',
            PNR        => $item->{PNR},
            TAS_ERROR  => $PNR->{TAS_ERROR},
          });          
          &logTasFinishError({
            errorCode  => $PNR->{TAS_ERROR},
            PNRId      => $item->{PNR},
            mdCode     => $item->{REF},
            deliveryId => $item->{DELIVERY_ID},
            market     => $params->{GlobalParams}->{market},
          });
          next ITEM;
        }
        # -----------------------------------------------------------------
          
      } # Fin MODULE: foreach my $module (keys %$h_mod)
  
    } # Fin foreach my $h_mod (@modules)
    
    &tasUpdateItem({
      REF         => $item->{REF},
      TASK        => $item->{TASK},
      SUBTASK     => $item->{SUBTASK},
      STATUS      => 'TAS_CHECKED',
      PNR         => $item->{PNR},
      DELIVERY_ID => $item->{DELIVERY_ID},
      MARKET      => $params->{GlobalParams}->{market},
    });
    next ITEM;

  } # Fin ITEM: foreach my $item (@items)
  # ----------------------------------------------------------------
  
  # $pm->xmlProcessed($count); # Pour NAGIOS
  
  # ----------------------------------------------------------------
  # Retry First and Send Email if I Got Problems whit SOAP (changeDeliveryState)
  if ((defined($soapRetry)) && (scalar(@$soapRetry) > 0)) {
    my $soapPbNb = scalar(@$soapRetry);
    notice("TAS has encountered '$soapPbNb' problems with SOAP. Retrying...");
    &soapRetry($soapRetry);
  }
  &soapProblems($tmpTask, $agency, $product)
    if (defined($soapProblems) && (scalar(keys %$soapProblems) > 0));
  # ----------------------------------------------------------------
  
  return 1;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# TAS Report Processor
sub trpProcessor {
  my $self = shift;

	my $params = {};
	   $params->{TaskName} = $self->{_TASK};

	#PARAMETERS ARE NOW IN DATABASE OR OPTIONNAL IN THE SCRIPT 
  $params->{GlobalParams}->{agency}   = $self->{_AGENCY};
  $params->{GlobalParams}->{market}   = $self->{_MARKET};
  $params->{GlobalParams}->{pnr}      = $self->{_PNR}; 
  $params->{GlobalParams}->{name}     = $self->{_NAME};
  $params->{GlobalParams}->{product}  = $self->{_PRODUCT}; 
  	
  # ----------------------------------------------------------------
  # V�rification qu'un process similaire n'est pas d�j� en cours de traitement
  my $pm = Expedia::Workflow::ProcessManager->new($self->{_TASK}.':'.$self->{_PRODUCT});
  return 1 if ($pm->isRunning() == 1);
  # ----------------------------------------------------------------

  # ----------------------------------------------------------------
  # Ex�cution du/des modules de r�cup�ration des items � traiter
  my @items      = ();
  my @modulesSrc = @{$self->{_H_SOURCES}->{modules}};
  foreach my $h_mod (@modulesSrc) {
    foreach my $module (keys %$h_mod) {
      $params->{ModuleParams} = {};
      notice("# PROCESSING module $module");
      foreach my $param (keys %{$h_mod->{$module}}) {
        $params->{ModuleParams}->{$param} = $h_mod->{$module}->{$param};
      }
      eval {
        my $modSrc = Expedia::Workflow::ModuleLoader->new($module);
			  push (@items, $modSrc->run($params));
      };
      error("Error during run of module $module : ".$@) if ($@);
    }
  }
  # ----------------------------------------------------------------


  my $agency  =  $params->{GlobalParams}->{agency};
  my $country =  $params->{GlobalParams}->{market};
  my $product =  $self->{_PRODUCT};
  my $tmpTask =  $self->{_TASK};
     $tmpTask =~ s/^(tas(?:meetings)?)-.*/$1/;



  # -----------------------------------------------------------------
  # RECUPERATION DU NOM DU CLIENT + Type de Billet
  #   CLIENT : Demande Catherine DUBOST le 05 Juin 2009 ;)
  #   BILLET : Projet R5 - EBillet, Thalys ThicketLess
  my $tmp  = ' xmlns="http://www.expediacorporate.fr/newsimages/xsds/v1"';
  my $ticketType='UNKNOWN';
	foreach my $item (@items) {
		$item->{XML} =~ s/UTF-8/ISO-8859-1/ig;
		$item->{XML} =~ s/&euro;/&#8364;/ig;
		$item->{XML} =~ s/$tmp//ig;
		my $b = Expedia::XML::Booking->new($item->{XML});
		$item->{COMNAME}     = uc($b->getPerComName({trvPos => $b->getWhoIsMain})) || 'UNKNOWN';
		my $ctd= $b->getTravelDossierStruct;
		my $nb_dossier= @$ctd ; # can also be retrieved by getNbDossier
		if ($nb_dossier == 1) {
			$ticketType = $ctd->[0]->{lwdTicketType};
		} else {
			foreach my $dossier (@$ctd){
				my $lwdpnr = uc($dossier->{lwdPnr});
				my $itemPnr = uc($item->{PNR});
				if($lwdpnr =~ /$itemPnr/) {
					$ticketType = $dossier->{lwdTicketType};
				}
			}
		}
		$item->{TICKET_TYPE} = uc($ticketType);
		debug('ComName    = '.$item->{COMNAME});
		debug('TicketType = '.$ticketType);

	}
  # -----------------------------------------------------------------

  # ________________________________________________________________
  # ENREGISTREMENT DES STATISTIQUES TAS EN BDD (TAS_STATS_DAILY).
  #  TASK Attention ici avec la gestion des billets "PAPER" !
  if (scalar @items > 0) {
    my $tds     =  &tasDailyStats({
      TASK      => 'tas-'.$self->{_PRODUCT}.'-etkt',
      SUBTASK   => $tmpTask.'-'.$agency,
      MARKET    => $params->{GlobalParams}->{market},
      ITEMS     => \@items,
    });
    notice('Problem detected during TasStatsDaily insertion !') unless $tds;
  }
  # ________________________________________________________________
  
  # ****************************************************************
  # Traitement sp�cial pour les rapports.
  #    Toute la liste d'items est pass�e au module.
  # ----------------------------------------------------------------
  # Envoi du rapport par mail.
  
  my $GDS     = $cnxMgr->getConnectionByName($self->{_AMADEUS});  
  &tasReport($tmpTask, $agency, $product, \@items, $GDS, $country);
  # ----------------------------------------------------------------
  # Nettoyage dans la table IN_PROGRESS
  foreach my $item (@items) {
    &tasUpdateItem({
      REF       => $item->{REF},
      TASK      => $item->{TASK},
      SUBTASK   => $item->{SUBTASK},
      STATUS    => 'finished',
      PNR       => $item->{PNR},
    });
  }
  # ****************************************************************
  
  return 1;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# TAS Stats Processor
sub tstProcessor {
  my $self = shift;

	my $params = {};
	   $params->{TaskName} = $self->{_TASK};
	
	#PARAMETERS ARE NOW IN DATABASE OR OPTIONNAL IN THE SCRIPT 
  $params->{GlobalParams}->{agency}   = $self->{_AGENCY};
  $params->{GlobalParams}->{market}   = $self->{_MARKET};
  $params->{GlobalParams}->{product}  = $self->{_PRODUCT};
  
  # ----------------------------------------------------------------
  # V�rification qu'un process similaire n'est pas d�j� en cours de traitement
  my $pm = Expedia::Workflow::ProcessManager->new($self->{_TASK}.':'.$self->{_PRODUCT});
  return 1 if ($pm->isRunning() == 1);
  # ----------------------------------------------------------------

  # ----------------------------------------------------------------
  # Ex�cution du/des modules de r�cup�ration des items � traiter
  my @items      = ();
  my @modulesSrc = @{$self->{_H_SOURCES}->{modules}};
  foreach my $h_mod (@modulesSrc) {
    foreach my $module (keys %$h_mod) {
      $params->{ModuleParams} = {};
      notice("# PROCESSING module $module");
      foreach my $param (keys %{$h_mod->{$module}}) {
        $params->{ModuleParams}->{$param} = $h_mod->{$module}->{$param};
      }
      eval {
        my $modSrc = Expedia::Workflow::ModuleLoader->new($module);
			  push (@items, $modSrc->run($params));
      };
      error("Error during run of module $module : ".$@) if ($@);
    }
  }
  # ----------------------------------------------------------------
  
  return 1 unless (scalar @items > 0);
  
  my $agency  =  $params->{GlobalParams}->{agency};
  my $product =  $self->{_PRODUCT};
  my $tmpTask =  $self->{_TASK};
     $tmpTask =~ s/^(tas(?:meetings)?)-.*/$1/;

  # ________________________________________________________________
  # ENREGISTREMENT DES STATISTIQUES TAS EN BDD (TAS_STATS_CONSO).
  #  TASK Attention ici avec la gestion des billets "PAPER" !
  my $tcs = &tasConsoStats({
    TASK    => 'tas-'.$self->{_PRODUCT}.'-etkt',
    SUBTASK => $tmpTask.'-'.$agency,
    MARKET  => $params->{GlobalParams}->{market},
    PRODUCT => $self->{_PRODUCT},
#   CAL_ID  => 710036,    # Lorsque le Job n'a pas pu s'ex�cuter
#   DATE    => '20120709' # Lorsque le Job n'a pas pu s'ex�cuter - Garder format date ! YYYYMMDD
  });
  notice('Problem detected during tasConsoStats insertion !') unless $tcs;
  # ________________________________________________________________

  # ________________________________________________________________
  # ENREGISTREMENT DES STATISTIQUES TAS DANS UN FICHIER PLAT.
  #   ET ENVOI VIA SSH VERS LE SERVEUR WEB. UTILIS� DANS LES
  #   RAPPORTS EXCEL.
  my $cds = compileDailyStats({
    AGENCY  => $agency,
    SUBTASK => $tmpTask.'-'.$agency,
    MARKET  => $params->{GlobalParams}->{market},
#   CAL_ID  => 710036,      # Lorsque le Job n'a pas pu s'ex�cuter
#   DATE    => '02/12/2009' # Lorsque le Job n'a pas pu s'ex�cuter - Garder format date ! DD/MM/YYYY
  });
  notice('Problem detected during compileDailyStats insertion !') unless $cds;
  # ________________________________________________________________
  
  return 1;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Profile Synchronization Processor / Users & Companies
sub synProcessor {
  my $self = shift;

	my $params = {};
	   $params->{TaskName} = $self->{_TASK};

  # ----------------------------------------------------------------
  # V�rification qu'un process similaire n'est pas d�j� en cours de traitement
  my $pm = Expedia::Workflow::ProcessManager->new($self->{_TASK});
  return 1 if ($pm->isRunning() == 1);
  # ----------------------------------------------------------------

  # R�cup�ration des param�tres globaux du contexte li�s � cette t�che
  foreach my $key (keys %{$self->{_H_TASK}}) {
    $params->{GlobalParams}->{$key} = $self->{_H_TASK}->{$key}
      unless ($key =~ /modules|logFile|amadeus|source/);
  }

  # ----------------------------------------------------------------
  # Ex�cution du/des modules de r�cup�ration des items � traiter
  my @items      = ();
  my @modulesSrc = @{$self->{_H_SOURCES}->{modules}};
  foreach my $h_mod (@modulesSrc) {
    foreach my $module (keys %$h_mod) {
      $params->{ModuleParams} = {};
      notice("# PROCESSING module $module");
      foreach my $param (keys %{$h_mod->{$module}}) {
        $params->{ModuleParams}->{$param} = $h_mod->{$module}->{$param};
      }
      eval {
        my $modSrc = Expedia::Workflow::ModuleLoader->new($module);
			  push (@items, $modSrc->run($params));
      };
      error("Error during run of module $module : ".$@) if ($@);
    }
  }
  # ----------------------------------------------------------------
  
  # ----------------------------------------------------------------
  # Ex�cution du/des modules de traitement sur chaque item
  my $count   = 0;
  my $lock    = 0;
  my $unlock  = 0;
  my @modules = @{$self->{_H_TASK}->{modules}};
  my $changes = { add => [], del => [], mod => [] };
  my $GDS     = $cnxMgr->getConnectionByName($self->{_AMADEUS});
  
  my $dbh = $cnxMgr->getConnectionByName('mid');
  
  my $query = "EXECUTE MIDADMIN.INHOUSE_LST";
  my $results = $dbh->sproc_array($query);
  my %inhouse_lst=();
  
  foreach my $row(@$results) {
     $inhouse_lst{ $row->[1] } { $row->[0] } = $row->[2];
  }
  $params->{INHOUSE_LST} = \%inhouse_lst;
  
  ITEM: foreach my $item (@items) {
    
    $count++;
    
    # Afin de pr�venir des d�connections de l'API !
    if ($count % 100 == 0) { $GDS->disconnect; return 1 unless ($GDS->connect); }
    
    # debug('ITEM = '.Dumper($item));
    
    # ---------------------------------------------------------------------
    # Vidage des actions � effectuer
    $changes = { add => [], del => [], mod => [] };
    $params->{Changes} = $changes;
    $params->{Item}    = $item;
    $params->{Params}  = undef;
    $params->{GDS}     = $GDS;
    # ---------------------------------------------------------------------

	#our use to transfert the variable to the others package
    our $log_id= '';

    if($item->{MSG_TYPE} eq 'USER'){$log_id='p'.$item->{MSG_CODE};}
    else{$log_id='c'.$item->{MSG_CODE};}

    notice('---------------------------------------------------------------');
    notice(' Working on item MSG_ID = '.$item->{MSG_ID}." MSG_TYPE = '".
                                        $item->{MSG_TYPE}."' ACTION = '".
                                        $item->{ACTION}."'");
    notice('---------------------------------------------------------------');
    
    # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
    # Verrouillage de l'ITEM
    $lock = &synLockItem($item);
    next ITEM unless $lock;
    # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
    
    my $status = 0;
    foreach my $h_mod (@modules) {
      MODULE: foreach my $module (keys %$h_mod) {
        $params->{ModuleParams} = {};
        notice("# PROCESSING module $module against MSG_ID = '".$item->{MSG_ID}."'");
        foreach my $param (keys %{$h_mod->{$module}}) {
  			  $params->{ModuleParams}->{$param} = $h_mod->{$module}->{$param};
        }
        eval {      
          my $mod = Expedia::Workflow::ModuleLoader->new($module);
          $status = $mod->run($params);
        };
        if (($status == 0) || ($@)) {
          notice("Error during run of module $module : ".$@) if ($@);
          &synUnlockItem({ITEM => $item, STATUS => 'ERROR'});
          next ITEM;
        }
      } # Fin MODULE: foreach my $module (keys %$h_mod)  
    } # Fin foreach my $h_mod (@modules)
    
    # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
    # D�verrouillage de l'ITEM
	if ($params->{flag_no_comcode} == 1) {
		$unlock = &synUnlockItem({ITEM => $item, STATUS => 'NEW'});
	} else{
		$unlock = &synUnlockItem({ITEM => $item, STATUS => 'DELETE'});
	}
    # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
    
  } # Fin ITEM: foreach my $item (@items)
  # ----------------------------------------------------------------
  
  # $pm->xmlProcessed($count); # Pour NAGIOS

  return 1;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Workflow Processor
sub flwProcessor {
  my $self = shift;
  
  my $params = {};
     $params->{TaskName} = $self->{_TASK};
  
  # ----------------------------------------------------------------
  # V�rification qu'un process similaire n'est pas d�j� en cours de traitement
  my $pm = Expedia::Workflow::ProcessManager->new($self->{_TASK});
  return 1 if ($pm->isRunning() == 1);
  # ----------------------------------------------------------------
  
  $params->{GlobalParams}->{_START_VERSION} = $self->{_START_VERSION} ;  # PARAM SUPPLEMENTAIRE POUR WORKFLOW DEBUG
  $params->{GlobalParams}->{_STOP_VERSION} = $self->{_STOP_VERSION} ;  # PARAM SUPPLEMENTAIRE POUR WORKFLOW DEBUG

  # R�cup�ration des param�tres globaux du contexte li�s � cette t�che
  foreach my $key (keys %{$self->{_H_TASK}}) {
    $params->{GlobalParams}->{$key} = $self->{_H_TASK}->{$key}
      unless ($key =~ /modules|logFile|amadeus|source/);
  }
  
  # ----------------------------------------------------------------
  # Ex�cution du/des modules de r�cup�ration des items � traiter
  my @items      = ();
  my @modulesSrc = @{$self->{_H_SOURCES}->{modules}};
      notice("MODULES:".Dumper(@modulesSrc)); 
  foreach my $h_mod (@modulesSrc) {
    foreach my $module (keys %$h_mod) {
      $params->{ModuleParams} = {};
      notice("# PROCESSING module $module");
      foreach my $param (keys %{$h_mod->{$module}}) {
        $params->{ModuleParams}->{$param} = $h_mod->{$module}->{$param};
      }
      eval {
        my $modSrc   = Expedia::Workflow::ModuleLoader->new($module);
        my $modItems = $modSrc->run($params);
			  push (@items, $_) foreach (@$modItems);
      };
      error("Error during run of module $module : ".$@) if ($@);
    }
  }
  # debug('ITEMS = '.Dumper(\@items));
  # ----------------------------------------------------------------

  # ----------------------------------------------------------------
  # Ex�cution du/des modules de traitement sur chaque item
  my @modules = @{$self->{_H_TASK}->{modules}};
  my $count   = 0;
  
  my $h_ttComCodes = &getTravellerTrackingImplicatedComCodesForMarket_new($params->{TaskName});
  #debug("Liste comcodes tracking:".Dumper($h_ttComCodes));
  $params->{TTComCodes} = $h_ttComCodes;
	
  ITEM: foreach my $item (@items) {
    
    #our use to transfert the variable to the others package
    our $log_id= '';

    if($item->{EVT_NAME} =~ /USER/){$log_id='p'.$item->{MSG_CODE};}
    elsif($item->{EVT_NAME} =~ /COMPANY/){$log_id='c'.$item->{MSG_CODE};}
    else{$log_id=$item->{MSG_CODE};}
    
    $count += 1;
    
    # ----------------------------------------------------------------
    # On passe les infos de l'ITEM aux modules de Workflow
    $params->{Item} = $item;
    # ----------------------------------------------------------------
    
    foreach my $h_mod (@modules) {
      MODULE: foreach my $module (keys %$h_mod) {
        notice('---------------------------------------------------------------');
        $params->{ModuleParams} = {};
        foreach my $param (keys %{$h_mod->{$module}}) {
  			  $params->{ModuleParams}->{$param} = $h_mod->{$module}->{$param};
        }
        eval {
          my $mod = Expedia::Workflow::ModuleLoader->new($module);
          $mod->run($params);
        };
        error("Error during run of module $module : ".$@) if ($@);
      } # Fin MODULE: foreach my $h_mod (@modules)
    } # Fin foreach my $h_mod (@modules)
    
  } # Fin ITEM: foreach my $item (@items)
  # ----------------------------------------------------------------
  
  # $pm->xmlProcessed($count); # Pour NAGIOS

  return 1;  
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# TRACKING Processor
sub trkProcessor {
  my $self = shift;

	my $params = {};
	   $params->{TaskName} = $self->{_TASK};
	
  # ----------------------------------------------------------------
  # V�rification qu'un process similaire n'est pas d�j� en cours de traitement
  my $pm = Expedia::Workflow::ProcessManager->new($self->{_TASK});
  return 1 if ($pm->isRunning() == 1);
  # ----------------------------------------------------------------
  
  $params->{GlobalParams}->{market}   = $self->{_MARKET};
	
  # ----------------------------------------------------------------
  # Ex�cution du/des modules de r�cup�ration des items � traiter
  my @items      = ();
  my @modulesSrc = @{$self->{_H_SOURCES}->{modules}};
  foreach my $h_mod (@modulesSrc) {
    foreach my $module (keys %$h_mod) {
      $params->{ModuleParams} = {};
      notice("# PROCESSING module $module");
      foreach my $param (keys %{$h_mod->{$module}}) {
        $params->{ModuleParams}->{$param} = $h_mod->{$module}->{$param};
      }
      eval {
        my $modSrc = Expedia::Workflow::ModuleLoader->new($module);
			  push (@items, $modSrc->run($params));
      };
      error("Error during run of module $module : ".$@) if ($@);
    }
  }
  # ----------------------------------------------------------------

  # ----------------------------------------------------------------
  # Ex�cution du/des modules de traitement sur chaque item
  my $PNR      = undef;
  my $GDS      = $cnxMgr->getConnectionByName($self->{_AMADEUS});
  my $lock     = 0;
  my $unlock   = 0;
  my $count    = 0;
  my @modules  = @{$self->{_H_TASK}->{modules}};
  my $changes  = { add => [], del => [], mod => [] };
  my %h_pnr = (); 
  
	#Get the connexion information by country
	my $nav_conn = &getNavisionConnForAllCountry();

	#Get the complete name of the market
	my $country = &getNavCountrybycountry($self->{_MARKET});

	#Set the nav connexion 
	&setNavisionConnection($country,$nav_conn,$self->{_TASK});
	
  ITEM: foreach my $item (@items) {
    
    $count++;
    
    #our use to transfert the variable to the others package
    our $log_id= '';

    $log_id=$item->{MSG_CODE};
        
    # ---------------------------------------------------------------------
    # Vidage des actions � effectuer
    $changes = { add => [], del => [], mod => [] };
    $params->{Changes} = $changes;
    # ---------------------------------------------------------------------

	
	$params->{ParsedXML} = Expedia::XML::Booking->new($item->{XML});
    debug('XML = '.$params->{ParsedXML}->doc->toString(1)); # On log dans la TRACE
	
    notice('---------------------------------------------------------------');
    notice(" Working on item REF = '".$item->{ID}."' PNR = '".$item->{PNR}."'") if ($item->{ID} &&  $item->{PNR});
    notice(" Working on item REF = '".$item->{ID}."'")                          if ($item->{ID} && !$item->{PNR});
    notice('---------------------------------------------------------------');
    notice('MSG_TYPE:'.$item->{MSG_TYPE});
    notice('PNR:'.$item->{PNR});

	my $PNRId=undef;

	
	if ( $item->{MSG_TYPE} eq 'TRAIN' ) { 
		my $mdCode = $params->{ParsedXML}->getMdCode ;
	    my $dv= $item->{PNR}; ### Dans le tracking train le pnr est celui de socrate
  		$PNRId = getPnrIdFromDv2Pnr({MDCODE => $mdCode, DVID => $dv});    ### on fait le mapping pnr socrate vers pnr amadeus
		
		if (defined($PNRId)){
			notice('PNR AMADEUS :'.$PNRId);	
			$item->{PNR} = $PNRId;
		}
									    
    }
  	
	
		
    # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
    # On passe � l'�l�ment suivant si on est dans un cas de booking TRAIN ou si le PNR Amadeus n'existe pas encore
    if(($item->{MSG_TYPE} eq 'TRAIN' ) && (!defined($PNRId) || $PNRId == 0)) 
    {
     &synUnlockItem({ITEM => $item, STATUS => 'NEW'});
     notice("No tracking for TRAIN at this time");
     next ITEM; 
    }
	
	
    # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
    # Verrouillage de l'ITEM
    $lock = &synLockItem($item);
    next ITEM unless $lock;
    # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
	


        
    # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
    # V�rification que le PNR existe encore dans AMADEUS.
 
    my $b = undef;
        # $b = $params->{ParsedXML}->getTravelDossierStruct()   if ($item->{MSG_TYPE} eq 'AIR');
       $b = $params->{ParsedXML}->getTrainTravelDossierStruct() 		 if ($item->{MSG_TYPE} eq 'TRAIN');
       $b = $params->{ParsedXML}->getAirCancelledTravelDossierStruct()   if ($item->{MSG_TYPE} eq 'AIR_CANCELLED');
       $b = $params->{ParsedXML}->getTrainCancelledTravelDossierStruct() if ($item->{MSG_TYPE} eq 'TRAIN_CANCELLED');
	   $b = $params->{ParsedXML}->getTravelDossierStruct_LC 			 if ($item->{MSG_TYPE} eq 'LOWCOST');

	  ###EGE-8821 :Modification for OWP
	if ($item->{MSG_TYPE} eq 'AIR' || $item->{MSG_TYPE} eq 'LOWCOST') 
	{ 
		my $x=0;
		my $mktype = undef;
		my $Listdossier = undef;
		my $tmp = undef;
        my $nbDossier = undef;
		
		if($item->{MSG_TYPE} eq 'LOWCOST')
		{
			#CALCUL DU NOMBRE DE TRAVELDOSSIER
			$nbDossier      = $params->{ParsedXML}->getNbOfTravelDossiers_LC;
			notice($nbDossier." TravelDossiers LC");
			$Listdossier = $params->{ParsedXML}->getTravelDossierStruct_LC;
		}
		else
		{
			#CALCUL DU NOMBRE DE TRAVELDOSSIER
			$nbDossier      = $params->{ParsedXML}->getNbOfTravelDossiers;
			notice($nbDossier." TravelDossiers ");
			$Listdossier = $params->{ParsedXML}->getTravelDossierStruct ;
		}
		
		if($nbDossier == 1)
		{
			notice("UN SEUL TRAVELDOSSIER");
			$mktype = $Listdossier->[0]->{lwdType};
			if(!exists($h_pnr{$Listdossier->[0]->{lwdPnr}}))
			{
			  $h_pnr{$Listdossier->[0]->{lwdPnr}}=$Listdossier->[0]->{lwdPos};
			}
			notice($Listdossier->[0]->{lwdPnr}." est en position:".$h_pnr{$Listdossier->[0]->{lwdPnr}});
		}
		else
		{
			#ON BOUCLE SUR CHAQUE TRAVELDOSSIER
			for ($x=0; $x < $nbDossier; $x++)
			{
			  if($Listdossier->[$x]->{lwdPnr} eq  $item->{PNR})
			  {
				notice("PNR:".$Listdossier->[$x]->{lwdPnr}." TROUVE EN POSITION:".$x);
				$mktype = $Listdossier->[$x]->{lwdType};
				if(!exists($h_pnr{$Listdossier->[$x]->{lwdPnr}}))
				{
				  $h_pnr{$Listdossier->[$x]->{lwdPnr}}=$x;
				}
				last;
			  }
			  else
			  {notice("PNR:".$Listdossier->[$x]->{lwdPnr}." ne corresponds pas en position pas ".$x);}
			}
			notice($Listdossier->[$x]->{lwdPnr}." est en position:".$h_pnr{$Listdossier->[$x]->{lwdPnr}});
		  }


            $item->{PNR} = $Listdossier->[$x]->{lwdPnr} ;
        }
		elsif ($item->{MSG_TYPE} eq 'TRAIN' || $item->{MSG_TYPE} eq 'AIR_CANCELLED' || $item->{MSG_TYPE} eq 'TRAIN_CANCELLED')
		{

            $item->{PNR} = $b->[0]->{lwdPnr} unless defined($PNRId);
        }
		
        $PNR = Expedia::GDS::PNR->new(PNR => $item->{PNR}, GDS => $GDS);
        if (!defined $PNR) {
            &synUnlockItem({ITEM => $item, STATUS => 'ERROR'});
            error("Could not read PNR '".$item->{PNR}."' from GDS.");
            next ITEM;
        }
        $params->{PNR}  = $PNR;  # Sous-entendu l'objet PNR
        $params->{Item} = $item;
        # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

        my $status = 0;
        foreach my $h_mod (@modules) {
            MODULE: foreach my $module (keys %$h_mod) {
                $params->{ModuleParams} = {};
                notice("# PROCESSING PNR = '".$item->{PNR}."' with module $module");
                foreach my $param (keys %{$h_mod->{$module}}) {
                    $params->{ModuleParams}->{$param} = $h_mod->{$module}->{$param};
                }
                eval {
                    my $mod = Expedia::Workflow::ModuleLoader->new($module);
                    $status = $mod->run($params);
                    debug('status = '.$status);
                };
                if (($status == 0) || ($@)) {
                    notice("Error during run of module $module : ".$@) if ($@);
                    &synUnlockItem({ITEM => $item, STATUS => 'ERROR'});
                    next ITEM;
                }
            } # Fin MODULE: foreach my $module (keys %$h_mod)
        } # Fin foreach my $h_mod (@modules)

        debug('Changes = '.Dumper($params->{Changes}));

        # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
        # On aplique les modifications sur l'ITEM [Fin des Modules "NON INTERACIFS"]
        my $update = 0;
        notice('Applying changes on PNR [...]') if (scalar(@{$changes->{add}}) > 0);
        $update = $PNR->update(
            add   => $params->{Changes}->{add},
            del   => $params->{Changes}->{del},
            mod   => $params->{Changes}->{mod},
            NoGet => 1
        );
        if ($update == 0) {
            notice('Problem during call of PNR update function !');
            &synUnlockItem({ITEM => $item, STATUS => 'ERROR'});
            next ITEM;
        }
        # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

        # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
        # D�rrouillage de l'ITEM
        $unlock = &synUnlockItem({ITEM => $item, STATUS => 'DELETE'});
        # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
    } # Fin ITEM: foreach my $item (@items)
    # ----------------------------------------------------------------

    # $pm->xmlProcessed($count); # Pour NAGIOS

  return 1;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# QUEUE-PNR Processor
sub queProcessor {
  my $self = shift;

	my $params = {};
	   $params->{TaskName} = $self->{_TASK};
	
  # ----------------------------------------------------------------
  # V�rification qu'un process similaire n'est pas d�j� en cours de traitement
  my $pm = Expedia::Workflow::ProcessManager->new($self->{_TASK});
  return 1 if ($pm->isRunning() == 1);
  # ----------------------------------------------------------------

  # R�cup�ration des param�tres globaux du contexte li�s � cette t�che
  foreach my $key (keys %{$self->{_H_TASK}}) {
    $params->{GlobalParams}->{$key} = $self->{_H_TASK}->{$key}
      unless ($key =~ /modules|logFile|amadeus|source/);
  }

  # ----------------------------------------------------------------
  # R�cup�ration de notre connection � Amadeus
  my $GDS = $cnxMgr->getConnectionByName($self->{_AMADEUS});
  $params->{GDS} = $GDS;
  $params->{MARKET}   = $self->{_MARKET};
  # ----------------------------------------------------------------
  
  # ----------------------------------------------------------------
  my @modules = @{$self->{_H_TASK}->{modules}};
  foreach my $h_mod (@modules) {
    MODULE: foreach my $module (keys %$h_mod) {
      $params->{ModuleParams} = {};
      foreach my $param (keys %{$h_mod->{$module}}) {
  		  $params->{ModuleParams}->{$param} = $h_mod->{$module}->{$param};
      }
      eval {
        my $mod = Expedia::Workflow::ModuleLoader->new($module);
           $mod->run($params);
      };
	   error("Error during run of module $module : ".$@) if ($@);
    } # Fin MODULE: foreach my $module (keys %$h_mod)
  } # Fin foreach my $h_mod (@modules)
  # ----------------------------------------------------------------
  
  return 1;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# LAUNCHER Processor
sub lchProcessor {
  my $self = shift;

	my $params = {};
	my $test_queue = ''; 
	   $params->{TaskName} = $self->{_TASK};

  # ----------------------------------------------------------------
  # V�rification qu'un process similaire n'est pas d�j� en cours de traitement
  my $pm = Expedia::Workflow::ProcessManager->new($self->{_TASK});
  return 1 if ($pm->isRunning() == 1);
  # ----------------------------------------------------------------

  $params->{GlobalParams}->{_SERVER}   = $self->{_SERVER};

  # R�cup�ration des param�tres globaux du contexte li�s � cette t�che
  foreach my $key (keys %{$self->{_H_TASK}}) {
    $params->{GlobalParams}->{$key} = $self->{_H_TASK}->{$key}
      unless ($key =~ /modules|logFile|amadeus|source/);
  }
    
  # ----------------------------------------------------------------
  # Ex�cution du/des modules de r�cup�ration des items � traiter
  my @items      = ();
  my @modulesSrc = @{$self->{_H_SOURCES}->{modules}};
  foreach my $h_mod (@modulesSrc) {
    foreach my $module (keys %$h_mod) {
      $params->{ModuleParams} = {};
      notice("# PROCESSING module $module");
      foreach my $param (keys %{$h_mod->{$module}}) {
        $params->{ModuleParams}->{$param} = $h_mod->{$module}->{$param};
      }
      eval {
        my $modSrc = Expedia::Workflow::ModuleLoader->new($module);
			  push (@items, $modSrc->run($params));
      };
      error("Error during run of module $module : ".$@) if ($@);
    }
  }
  
  #ON DOIT BOUCLER SUR LA LISTE DES QUEUES TROUVES PAR OFFICE_ID
  foreach my $item (@items) 
  {
      notice ("##############################################################################");
      notice ("#                     TRAITEMENT DU JOBS: ".$item->{SHORT_DESC}."'           #");
      notice ("##############################################################################");

	
	    #AFFECTATION DES PARAMETRES DE LA TABLE POUR PASSAGE EN PARAMETRE
	    $params->{Item} = $item;	  
	       	     
      my @modules  = @{$self->{_H_TASK}->{modules}};  # Modules "NON INTERACTIFS"
  	     	     	     
  	  # MODULES [NON INTERACTIFS]
      my $status = 0;
      foreach my $h_mod (@modules) {
        MODULE: foreach my $module (keys %$h_mod) {
          $params->{ModuleParams} = {};
          #notice("################ PROCESSING QUEUE = '".$item->{QUEUE}."' with module $module");
          foreach my $param (keys %{$h_mod->{$module}}) {
    			  $params->{ModuleParams}->{$param} = $h_mod->{$module}->{$param};
          }
          eval {
            my $mod = Expedia::Workflow::ModuleLoader->new($module);
            $status = $mod->run($params);
            debug('status = '.$status);
          };
          if (($status == 0) || ($@)) {
            notice("Error during run of module $module : ".$@) if ($@);
            #$params->{WBMI}->status('FAILURE');
            #$params->{WBMI}->sendXmlReport();
            next ITEM;
          }
        } # Fin MODULE: foreach my $module (keys %$h_mod)
      } # Fin foreach my $h_mod (@modules)
    
    #  debug('params = '.Dumper($params->{Changes}));
    
  }
  
  return 1;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# TJQocessor
sub tjqProcessor {
  my $self = shift;

	my $params = {};
	   $params->{TaskName} = $self->{_TASK};
	
  # ----------------------------------------------------------------
  # V�rification qu'un process similaire n'est pas d�j� en cours de traitement
  my $pm = Expedia::Workflow::ProcessManager->new($self->{_TASK});
  return 1 if ($pm->isRunning() == 1);
  # ----------------------------------------------------------------

  # ----------------------------------------------------------------
  # R�cup�ration de notre connection � Amadeus
  my $GDS = $cnxMgr->getConnectionByName($self->{_AMADEUS});
  $params->{GDS} = $GDS;
  # ----------------------------------------------------------------

  $params->{GlobalParams}->{market}   = $self->{_MARKET};
  $params->{GlobalParams}->{name}     = $self->{_NAME};
  $params->{GlobalParams}->{gds}     = $GDS;
   
   notice("TEST:".Dumper($self->{_H_TASK})); 
  
  # ----------------------------------------------------------------
  my @modules = @{$self->{_H_TASK}->{modules}};
  my $status='';
  foreach my $h_mod (@modules) {
    MODULE: foreach my $module (keys %$h_mod) {
      $params->{ModuleParams} = {};
      foreach my $param (keys %{$h_mod->{$module}}) {
  		  $params->{ModuleParams}->{$param} = $h_mod->{$module}->{$param};
      }
      eval {
        my $mod = Expedia::Workflow::ModuleLoader->new($module);
           $mod->run($params);
      };
	     if (($status == 0) || ($@)) {
         notice("Error during run of module $module : ".$@) if ($@);
         }
    } # Fin MODULE: foreach my $module (keys %$h_mod)
  } # Fin foreach my $h_mod (@modules)
  # ----------------------------------------------------------------
  
  
  return 1;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Processor Generique avec un get et un module
sub comProcessor {
  my $self = shift;
        my $params = {};
           $params->{TaskName} = $self->{_TASK};

  # ----------------------------------------------------------------
  # Vérification qu'un process similaire n'est pas déjà en cours de traitement
  my $pm = Expedia::Workflow::ProcessManager->new($self->{_TASK});
  return 1 if ($pm->isRunning() == 1);
  # ----------------------------------------------------------------

  # ----------------------------------------------------------------
  # Récupération de notre connection à Amadeus
  my $GDS = $cnxMgr->getConnectionByName($self->{_AMADEUS});
  $params->{GDS} = $GDS;
  # ----------------------------------------------------------------

  $params->{GlobalParams}->{market}   = $self->{_MARKET};
  $params->{GlobalParams}->{name}     = $self->{_NAME};
  $params->{GlobalParams}->{gds}     = $GDS;

  # ----------------------------------------------------------------
  # Exécution du/des modules de récupération des items à traiter
  my @items      = ();
  my @modulesSrc = @{$self->{_H_SOURCES}->{modules}};
  foreach my $h_mod (@modulesSrc) {
    foreach my $module (keys %$h_mod) {
      $params->{ModuleParams} = {};
      notice("# PROCESSING module $module");
      foreach my $param (keys %{$h_mod->{$module}}) {
        $params->{ModuleParams}->{$param} = $h_mod->{$module}->{$param};
      }
      eval {
        my $modSrc = Expedia::Workflow::ModuleLoader->new($module);
                          push (@items, $modSrc->run($params));
      };
      error("Error during run of module $module : ".$@) if ($@);
    }
  }

  # ----------------------------------------------------------------
  my @modules = @{$self->{_H_TASK}->{modules}};
  my $status='';
  foreach my $h_mod (@modules) {
    MODULE: foreach my $module (keys %$h_mod) {
      $params->{ModuleParams} = {};
      notice("# PROCESSING module $module");
      foreach my $param (keys %{$h_mod->{$module}}) {
                  $params->{ModuleParams}->{$param} = $h_mod->{$module}->{$param};
      }
      eval {
        my $mod = Expedia::Workflow::ModuleLoader->new($module);
           $mod->run($params);
      };
        if (($status == 0) || ($@)) {
          notice("Error during run of module $module : ".$@) if ($@);
        }
    } # Fin MODULE: foreach my $module (keys %$h_mod)
  } # Fin foreach my $h_mod (@modules)
  # ----------------------------------------------------------------


  return 1;

}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# BTC-CAR Processor
sub carProcessor {
  
  my $self = shift;

        my $params = {};
           $params->{TaskName} = $self->{_TASK};

  my %h_pnr=();

  # ----------------------------------------------------------------
  # V�rification qu'un process similaire n'est pas d�j� en cours de traitement
  my $pm = Expedia::Workflow::ProcessManager->new($self->{_TASK});
  return 1 if ($pm->isRunning() == 1);
  # ----------------------------------------------------------------

  # R�cup�ration des param�tres globaux du contexte li�s � cette t�che
  foreach my $key (keys %{$self->{_H_TASK}}) {
    $params->{GlobalParams}->{$key} = $self->{_H_TASK}->{$key}
      unless ($key =~ /modules|logFile|amadeus|source/);
  }

  # ----------------------------------------------------------------
  # Ex�cution du/des modules de r�cup�ration des items � traiter
  my @items      = ();
  my @modulesSrc = @{$self->{_H_SOURCES}->{modules}};
  foreach my $h_mod (@modulesSrc) {
    foreach my $module (keys %$h_mod) {
      $params->{ModuleParams} = {};
      notice("# PROCESSING module $module");
      foreach my $param (keys %{$h_mod->{$module}}) {
        $params->{ModuleParams}->{$param} = $h_mod->{$module}->{$param};
      }
      eval {
        my $modSrc = Expedia::Workflow::ModuleLoader->new($module);
                          push (@items, $modSrc->run($params));
      };
      error("Error during run of module $module : ".$@) if ($@);
    }
  }
  # Record items into IN_PROGRESS table
  foreach (@items) {
    my $b   = Expedia::XML::Booking->new($_->{XML});
    my $x=0;
    my $mktype = undef;
    my $Listdossier = undef;
    my $tmp = undef;

    #CALCUL DU NOMBRE DE TRAVELDOSSIER
    my $nbDossier      = $b->getNbOfTravelDossiers;
    notice($nbDossier." TravelDossiers ");

    if($nbDossier == 1)
    {
        notice("UN SEUL TRAVELDOSSIER");
        $Listdossier = $b->getTravelDossierStruct;
        $mktype = $Listdossier->[0]->{lwdType};
        if(!exists($h_pnr{$Listdossier->[0]->{lwdPnr}}))
        {
          $h_pnr{$Listdossier->[0]->{lwdPnr}}=$Listdossier->[0]->{lwdPos};
        }
        notice($Listdossier->[0]->{lwdPnr}." est en position:".$h_pnr{$Listdossier->[0]->{lwdPnr}});
    }
    else
    {
        #RECUPERATION DE LA STRUCTURE DES DIFFERENTS TRAVELDDOSIERS
        $Listdossier = $b->getTravelDossierStruct;

        #debug("LISTDOSSIER:".Dumper($Listdossier));

        #ON BOUCLE SUR CHAQUE TRAVELDOSSIER
        for ($x=0; $x < $nbDossier; $x++)
        {
          if($Listdossier->[$x]->{lwdPnr} eq  $_->{PNR})
          {
            notice("PNR:".$Listdossier->[$x]->{lwdPnr}." TROUVE EN POSITION:".$x);
            $mktype = $Listdossier->[$x]->{lwdType};
            if(!exists($h_pnr{$Listdossier->[$x]->{lwdPnr}}))
            {
              $h_pnr{$Listdossier->[$x]->{lwdPnr}}=$x;
            }
            last;
          }
          else
          {notice("PNR:".$Listdossier->[$x]->{lwdPnr}." ne corresponds pas en position pas ".$x);}
        }
        notice($Listdossier->[$x]->{lwdPnr}." est en position:".$h_pnr{$Listdossier->[$x]->{lwdPnr}});
    }
  #my $GDS      = $cnxMgr->getConnectionByName($self->{_AMADEUS});
   # my $PNR = Expedia::GDS::PNR->new(PNR => '4K8N27', GDS => $GDS);

        my $res = &btcInsertItem({ REF  => $_->{ID},
                                   TASK => $self->{_TASK},
                                   TYPE => $mktype,
                                   PNR  => $_->{PNR} }); # Sous-entendu identifiant de PNR
        notice('Problem during call of btcInsertItem method.')
          if (!$res || $res != 1);
  }

  # R�cup�ration finale des items � traiter
  @items = &btcGetItems($self->{_TASK});
  my $nbItems = scalar @items;
  # ----------------------------------------------------------------

#debug("H_PNR:".Dumper(%h_pnr));


  # ----------------------------------------------------------------
  # Ex�cution du/des modules de traitement sur chaque item
  my $PNR      = undef;
  my $GDS      = $cnxMgr->getConnectionByName($self->{_AMADEUS});
  my $lock     = 0;
  my $unlock   = 0;
  my $count    = 0;
  my @modules  = @{$self->{_H_TASK}->{modules}};  # Modules "NON INTERACTIFS"
  my @imodules = @{$self->{_H_TASK}->{imodules}}; # Modules "INTERACTIFS"
  my $changes  = { add => [], del => [], mod => [] };

  ITEM: foreach my $item (@items) {

    $count += 1;

    #our use to transfert the variable to the others package
    our $log_id= '';

    $log_id=$item->{MSG_CODE};

    # ---------------------------------------------------------------------
    # Vidage des actions � effectuer
    $changes = { add => [], del => [], mod => [] };
    $params->{Changes} = $changes;
    # ---------------------------------------------------------------------

    notice('---------------------------------------------------------------');
    notice(' Working on item REF = '.$item->{REF}." PNR = '".$item->{PNR}."' ($count/$nbItems)") if ($item->{REF} && $item->{PNR});
    notice('---------------------------------------------------------------');

    my $tmpXML =  $item->{XML};
    $tmpXML =~ s/'/''''/ig;
    $tmpXML = '<?xml version="1.0" encoding="ISO-8859-1" standalone="yes"?>'.$tmpXML;

    my $tmp  = ' xmlns="http://www.expediacorporate.fr/newsimages/xsds/v1"';
    $tmpXML =~ s/$tmp//ig;

    $params->{ParsedXML} = Expedia::XML::Booking->new($tmpXML);
    #$params->{WBMI}      = Expedia::Workflow::WbmiManager->new({batchName => 'BTC_CAR', mdCode => $params->{ParsedXML}->getMdCode});

    notice('MdCode  = '.$params->{ParsedXML}->getMdCode);
    notice('Version = '.$item->{MSG_VERSION});

    # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
    # Verrouillage de l'ITEM
    $lock = &btcLockItem({REF => $item->{REF}, TASK => $self->{_TASK}, PNR => $item->{PNR} });
    # Si nous en sommes � notre dernier essai [...]
    #    [...] notification dans WBMI (Probl�me du 18 Juillet 2008) !
    if ($item->{TRY} == 5) {
      $params->{WBMI}->status('FAILURE');
      $params->{WBMI}->addReport({ Code => 29, PnrId => $item->{PNR} });
      $params->{WBMI}->sendXmlReport();
    }
    next ITEM unless $lock;
    # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

    # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
    # V�rification que le PNR existe encore dans AMADEUS.

    $PNR = Expedia::GDS::PNR->new(PNR => $item->{PNR}, GDS => $GDS);
    if (!defined $PNR) {
      $unlock = &btcUnlockItem({REF => $item->{REF}, TASK => $self->{_TASK}, PNR => $item->{PNR}});
      error("Could not read PNR '".$item->{PNR}."' from GDS.");
      next ITEM;
    }
    $params->{PNR}  = $PNR;  # Sous-entendu l'objet PNR
    $params->{Item} = $item;
    $params->{GDS}      = $GDS;

    #ON PASSE LA REFERENCE DU TABLEAU DE HASHAGE
    $params->{Position} = \%h_pnr;
    $params->{RefPNR}   = $item->{PNR};
    debug('XML = '.$params->{ParsedXML}->doc->toString(1)); # On log dans la TRACE
    # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
    my $status = 0;
    foreach my $h_mod (@modules) {
      MODULE: foreach my $module (keys %$h_mod) {
        $params->{ModuleParams} = {};
        notice("# PROCESSING PNR = '".$item->{PNR}."' with module $module");
        foreach my $param (keys %{$h_mod->{$module}}) {
                          $params->{ModuleParams}->{$param} = $h_mod->{$module}->{$param};
        }
        eval {
          my $mod = Expedia::Workflow::ModuleLoader->new($module);
          $status = $mod->run($params);
          debug('status = '.$status);
        };
        if (($status == 0) || ($@)) {
          notice("Error during run of module $module : ".$@) if ($@);
          &btcUpdateItem({REF => $item->{REF}, TASK => $self->{_TASK}, STATUS => 'error', PNR => $item->{PNR}});
          #$params->{WBMI}->status('FAILURE');
          #$params->{WBMI}->sendXmlReport();
          next ITEM;
        }
      } # Fin MODULE: foreach my $module (keys %$h_mod)
    } # Fin foreach my $h_mod (@modules)

    debug('params = '.Dumper($params->{Changes}));

    # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
    # D�verrouillage de l'ITEM + "WBMI"
    $unlock = &btcUnlockItem({REF => $item->{REF}, TASK => $self->{_TASK}, PNR => $item->{PNR}});
    #$params->{WBMI}->sendXmlReport();
    # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

    &btcUpdateItem({REF => $item->{REF}, TASK => $self->{_TASK}, STATUS => 'finished', PNR => $item->{PNR}});
  } # Fin ITEM: foreach my $item (@items)
  # ----------------------------------------------------------------

  # $pm->xmlProcessed($count); # Pour NAGIOS

  return 1;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@


1;
