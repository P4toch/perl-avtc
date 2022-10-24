package Expedia::Modules::FLW::synchroWorkflow;
#-----------------------------------------------------------------
# Package Expedia::Modules::FLW::synchroWorkflow
#
# $Id: synchroWorkflow.pm 686 2011-04-21 12:33:02Z pbressan $
#
# (c) 2002-2008 Expedia.                   www.expediacorporate.fr
#-----------------------------------------------------------------

use Data::Dumper;

use Expedia::Tools::Logger              qw(&debug &notice &warning &error);
use Expedia::Tools::GlobalVars          qw($cnxMgr);
use Expedia::Databases::MidSchemaFuncs  qw(&isInMsgKnowledge &insertIntoMsgKnowledge &updateMsgKnowledge &deleteMsgKnowledge
                                           &isIntoWorkTable  &insertIntoWorkTable
                                           &isInAmadeusSynchro
                                           &getAppId
                                           &getCountrybyUpComCode);
use Expedia::XML::UserProfile;
use Expedia::XML::CompanyProfile;

sub run {
  my $self   = shift;
  my $params = shift;

  my $globalParams = $params->{GlobalParams};
  my $moduleParams = $params->{ModuleParams};
  my $changes      = $params->{Changes};
  my $item         = $params->{Item};

  # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
  # Cet item est utilisé pour la synchronisation des Profils 
  if ($item->{USED_FOR} eq 'SYNCHRO') {

    notice("# PROCESSING module FLW::synchroWorkflow against MSG_ID = '".$item->{MSG_ID}."'");
    
    # debug('ITEM = '.Dumper($item));
    
    # ----------------------------------------------------------
#    if ($item->{MSG_VERSION} =~ /^(5178)$/) {
#      use XML::LibXML;
#      use File::Slurp;
#      my $parser = XML::LibXML->new();
#      my $doc    = $parser->parse_string($item->{MESSAGE});
#         $doc->indexElements();
#         $doc    = $doc->toString(1);
#      write_file('/home/pbressan/synchro'.$item->{MSG_VERSION}.'.xml', $doc);
#    }
    # ----------------------------------------------------------

    # -----------------------------------------------------------------
    # Pour chaque item nous vérifions ce qui doit être fait côté MID
    my $msgId      = $item->{MSG_ID};
    my $msgCode    = $item->{MSG_CODE};
    my $message    = $item->{MESSAGE};
    my $msgVersion = $item->{MSG_VERSION};
    my $evtName    = $item->{EVT_NAME};

    debug('MSG_VERSION = '.$item->{MSG_VERSION});
    debug('MSG_CODE    = '.$item->{MSG_CODE});
    debug('TYPE = SYNCHRO - EVENT = '.$evtName);

    # -----------------------------------------------------------------
    # TODO Vérifier que le message peut être valider avec son XSL
    # -----------------------------------------------------------------
    
    # -----------------------------------------------------------------
    my $tmp  = ' xmlns="http://www.expediacorporate.fr/newsimages/xsds/v1"';
    #$message =~ s/UTF-8/ISO-8859-1/ig;
    $message =~ s/&euro;/&#8364;/ig;
    $message =~ s/$tmp//ig;
    # -----------------------------------------------------------------

    # -----------------------------------------------------------------
    # Conversion des typages entre les noms d'évènements et les TYPE "MSG_KNOWLEDGE"
    debug('evtName = '.$evtName);
    my $mkType   = undef;
    my $xmlDatas = undef;
    
    if      ($evtName =~ /(USER_NEW|USER_UPDATED|USER_DELETED)/) {
      $mkType   = 'USER';
      $xmlDatas = Expedia::XML::UserProfile->new($message);
    } elsif ($evtName =~ /(COMPANY_NEW|COMPANY_UPDATED|COMPANY_DATA_FIELD_VALUES_UPDATED|COMPANY_CLOSED)/) {    
      $mkType   = 'COMPANY';
			$xmlDatas = Expedia::XML::CompanyProfile->new($message);
    } else {
    	notice('EVT_NAME does not match something known !');
      return 0;
    }
    # -----------------------------------------------------------------
    
    # _________________________________________________________________
    # S'agit-il d'un évènement MEETING ?
    my $isMeeting = $xmlDatas->isMeetingCompany();
    debug('isMeeting = '.$isMeeting);
    if ($isMeeting) {
      notice('This a MEETING [ '.$mkType.' ] XML message.');
      return 1;
    } # Si tel est le cas, ne rien faire !
    # _________________________________________________________________

    my $market = &getCountrybyUpComCode($xmlDatas->getPOSCompanyComCode()); 
    my $appId  = &getAppId('synchro-'.$market);

    # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
    # Est-ce que nous connaissons cet objet message dans MSG_KNOWLEDGE ?
    my $mkItem = &isInMsgKnowledge({CODE => $msgCode, TYPE => $mkType});
    
    # $$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$
    # CAS 1 = Ce message est inconnu de la base de connaissance des messages
    # $$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$
    if ((!defined $mkItem) || (scalar(@$mkItem) == 0)) {
      debug('CASE 1');

      # ------------------------------------------------------------------
      # Insertion du message dans la base de connaissance
      my $row = &insertIntoMsgKnowledge({CODE => $msgCode, TYPE => $mkType, VERSION => $msgVersion, MARKET => $market});
      return 0 unless $row; # Quest-ce qu'on fait si $rows == 0 ?

      # ------------------------------------------------------------------
      # Est ce que ce couple (CODE, TYPE) est connu dans AMADEUS_SYNCHRO ?
      my $asItem = &isInAmadeusSynchro({CODE => $msgCode, TYPE => $mkType});
       
      # ££££££££££££££££££££££££££££££££££££££££££££££££££££££££££££££££££
      # CAS 1.1 = Aucune information dans la table AMADEUS_SYNCHRO
      # ££££££££££££££££££££££££££££££££££££££££££££££££££££££££££££££££££      
      if ((!defined $asItem) || (scalar @$asItem == 0)) {
        debug('CASE 1.1');
        
        my $action = 'CREATE';

        # ------------------------------------------------------------------
        # Si l'action demandée est USER_DELETED ou COMPANY_CLOSED
        if ($evtName =~ /(USER_DELETED|COMPANY_CLOSED)/) {
          $action = 'DELETE';
          # Le message est inconnu de MSG_KNOWLEDGE et AMADEUS_SYNCHRO, 
          #   nous devons vérifier s'il est dans la WORK_TABLE.
          my $wtItem = &isIntoWorkTable({MESSAGE_CODE => $msgCode, MESSAGE_TYPE => $mkType});
          # S'il est dans la WORK_TABLE et qu'une action de CREATE ou UPDATE
          #  est déja en cours, alors nous devons bien faire un DELETE.
          # Sinon, il n'y a rien à faire [...]
          return 1 unless ((defined $wtItem)                               &&
                           (scalar @$wtItem > 0)                           &&
                           ($wsItem->[0]->{ACTION} =~ /^(CREATE|UPDATE)$/) &&
                           ($wsItem->[0]->{STATUS} =~ /^(NEW|LOCKED)$/));
        }
        # ------------------------------------------------------------------
        
        # L'action à faire est un CREATE 
        $row = &insertIntoWorkTable(
          { MESSAGE_ID      => $msgId,
            MESSAGE_CODE    => $msgCode,
            MESSAGE_VERSION => $msgVersion,
            MESSAGE_TYPE    => $mkType,
            EVENT_VERSION   => '',
            TEMPLATE_ID     => '',
            MARKET          => $market, 
            APP_ID          => $appId,  
            ACTION          => $action,
            STATUS          => 'NEW',
            XML             => $message,
            PNR             => '',
          }
        );
        return 0 unless $row; # Quest-ce qu'on fait si $rows == 0 ?
      }
      # ££££££££££££££££££££££££££££££££££££££££££££££££££££££££££££££££££
      # CAS 1.2 = Une information associée dans la table AMADEUS_SYNCHRO
      # ££££££££££££££££££££££££££££££££££££££££££££££££££££££££££££££££££      
      elsif ((scalar @$asItem == 1) && (defined $asItem->[0][2])) {
        debug('CASE 1.2');
        
        my $action = 'UPDATE';
        
        # ------------------------------------------------------------------
        # Si l'action demandée est USER_DELETED ou COMPANY_CLOSED
        $action = 'DELETE' if ($evtName =~ /(USER_DELETED|COMPANY_CLOSED)/);
        # ------------------------------------------------------------------
                
        # L'action à faire est un UPDATE
        $row = &insertIntoWorkTable(
          { MESSAGE_ID      => $msgId,
            MESSAGE_CODE    => $msgCode,
            MESSAGE_VERSION => $msgVersion,
            MESSAGE_TYPE    => $mkType,
            EVENT_VERSION   => '',
            TEMPLATE_ID     => '',
            MARKET          => $market,
            APP_ID          => $appId, 
            ACTION          => $action,
            STATUS          => 'NEW',
            XML             => $message,
            PNR             => '',
          }
        );
        return 0 unless $row; # Quest-ce qu'on fait si $rows == 0 ?
      }
      # ££££££££££££££££££££££££££££££££££££££££££££££££££££££££££££££££££      
      # CAS 1.3 = Plusieurs résultats trouvés dans la table AMADEUS_SYNCHRO
      # ££££££££££££££££££££££££££££££££££££££££££££££££££££££££££££££££££      
      else { # Cas normalement impossible car contrainte unique sur la table.
        notice('CASE 1.3 - asItem = '.Dumper($asItem));
        notice('Multiple results returned but only one is expected.');
        return 0;
      }
      # ------------------------------------------------------------------
    }



    # $$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$
    # CAS 2 = Ce message est connu de la base de connaissance des messages
    # $$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$
    elsif (scalar(@$mkItem) == 1) {
      debug('CASE 2');

      # ------------------------------------------------------------------
      # Mise à jour du message dans la base de connaissance
      my $row = &updateMsgKnowledge({CODE => $msgCode, TYPE => $mkType, VERSION => $msgVersion});
      return 0 unless $row; # Quest-ce qu'on fait si $rows == 0 ?
      
      # ------------------------------------------------------------------
      # Est ce que ce message figure déja dans la table WORK_TABLE ?
      my $wtItem = &isIntoWorkTable({MESSAGE_CODE => $msgCode, MESSAGE_TYPE => $mkType});
      
      # ££££££££££££££££££££££££££££££££££££££££££££££££££££££££££££££££££
      # CAS 2.1 = Aucune information dans la table WORK_TABLE
      # ££££££££££££££££££££££££££££££££££££££££££££££££££££££££££££££££££      
      if ((!defined $wtItem) || (scalar @$wtItem == 0)) {
        debug('CASE 2.1');

        # ------------------------------------------------------------------
        # Est ce que ce couple (CODE, TYPE) est connu dans AMADEUS_SYNCHRO ?
        my $asItem = &isInAmadeusSynchro({CODE => $msgCode, TYPE => $mkType});
        
        # µµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµ
        # CAS 2.1.1 = Aucune information dans la table AMADEUS_SYNCHRO
        # µµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµ        
        if ((!defined $asItem) || (scalar @$asItem == 0)) {
          debug('CASE 2.1.1');
          
          # ------------------------------------------------------------------
          # Si l'action demandée est USER_DELETED ou COMPANY_CLOSED
          if ($evtName =~ /(USER_DELETED|COMPANY_CLOSED)/) {
            # Le message est connu de MSG_KNOWLEDGE et inconnu de AMADEUS_SYNCHRO & WORK_TABLE
            &deleteMsgKnowledge({CODE => $msgCode, TYPE => $mkType});
            return 1;
          }
          # ------------------------------------------------------------------
        
          # L'action à faire est bien un CREATE 
          $row = &insertIntoWorkTable(
            { MESSAGE_ID      => $msgId,
              MESSAGE_CODE    => $msgCode,
              MESSAGE_VERSION => $msgVersion,
              MESSAGE_TYPE    => $mkType,
              EVENT_VERSION   => '',
              TEMPLATE_ID     => '',
              MARKET          => $market,
              APP_ID          => $appId,
              ACTION          => 'CREATE',
              STATUS          => 'NEW',
              XML             => $message,
              PNR             => '',
            }
          );
          return 0 unless $row; # Quest-ce qu'on fait si $rows == 0 ?
        }
        # µµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµ
        # CAS 2.1.2 = Une information associée dans la table AMADEUS_SYNCHRO
        # µµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµ
        elsif ((scalar @$asItem == 1) && (defined $asItem->[0][2])) {
          debug('CASE 2.1.2');
          
          my $action = 'UPDATE';
          
          # ------------------------------------------------------------------
          # Si l'action demandée est USER_DELETED ou COMPANY_CLOSED
          if ($evtName =~ /(USER_DELETED|COMPANY_CLOSED)/) {
            # Le message est connu de MSG_KNOWLEDGE & AMADEUS_SYNCHRO et inconnu de WORK_TABLE
            $action = 'DELETE';
          }
          # ------------------------------------------------------------------

          # L'action à faire est un UPDATE
          $row = &insertIntoWorkTable(
            { MESSAGE_ID      => $msgId,
              MESSAGE_CODE    => $msgCode,
              MESSAGE_VERSION => $msgVersion,
              MESSAGE_TYPE    => $mkType,
              EVENT_VERSION   => '',
              TEMPLATE_ID     => '',
              MARKET          => $market, 
              APP_ID          => $appId,  
              ACTION          => $action,
              STATUS          => 'NEW',
              XML             => $message,
              PNR             => '',
            }
          );
          return 0 unless $row; # Quest-ce qu'on fait si $rows == 0 ?
        }
        # µµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµ
        # CAS 2.1.3 = Plusieurs résultats trouvés dans la table AMADEUS_SYNCHRO
        # µµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµ
        else { # Cas normalement impossible car contrainte unique sur la table.
          notice('CASE 2.1.3 - asItem = '.Dumper($asItem));
          notice('Multiple results returned but only one is expected.');
          return 0;
        }

      }
      # ££££££££££££££££££££££££££££££££££££££££££££££££££££££££££££££££££      
      # CAS 2.2 = Une ou plusieurs informations sont associées dans la table WORK_TABLE
      # ££££££££££££££££££££££££££££££££££££££££££££££££££££££££££££££££££      
      elsif (scalar @$wtItem >= 1) {
        debug('CASE 2.2');

        # ------------------------------------------------------------------
        # Est ce que ce couple (CODE, TYPE) est connu dans AMADEUS_SYNCHRO ?
        my $asItem = &isInAmadeusSynchro({CODE => $msgCode, TYPE => $mkType});

        # µµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµ
        # CAS 2.2.1 = Aucune information dans la table AMADEUS_SYNCHRO
        # µµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµ        
        if ((!defined $asItem) || (scalar @$asItem == 0)) {
          debug('CASE 2.2.1');
          
          my $action = 'UPDATE';

          # ------------------------------------------------------------------
          # Si l'action demandée est USER_DELETED ou COMPANY_CLOSED
          if ($evtName =~ /(USER_DELETED|COMPANY_CLOSED)/) {
            # Le message est connu de MSG_KNOWLEDGE & WORK_TABLE et inconnu de AMADEUS_SYNCHRO
            if (($wtItem->[0]->{ACTION} =~ /^(CREATE|UPDATE)$/) &&
                ($wtItem->[0]->{STATUS} =~ /^(NEW|LOCKED)$/)) {
              $action = 'DELETE';
            } else {
              &deleteMsgKnowledge({CODE => $msgCode, TYPE => $mkType});
              return 0;
            }
          }
          # ------------------------------------------------------------------

          # L'action à faire est un UPDATE
          $row = &insertIntoWorkTable(
            { MESSAGE_ID      => $msgId,
              MESSAGE_CODE    => $msgCode,
              MESSAGE_VERSION => $msgVersion,
              MESSAGE_TYPE    => $mkType,
              EVENT_VERSION   => '',
              TEMPLATE_ID     => '',
              MARKET          => $market,
              APP_ID          => $appId,
              ACTION          => $action,
              STATUS          => 'NEW',
              XML             => $message,
              PNR             => '',
            }
          );
          return 0 unless $row; # Quest-ce qu'on fait si $rows == 0 ?
        }
        # µµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµ
        # CAS 2.2.2 = Une information associée dans la table AMADEUS_SYNCHRO
        # µµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµ
        elsif ((scalar @$asItem == 1) && (defined $asItem->[0][2])) {
          debug('CASE 2.2.2');

          my $action = 'UPDATE';

          # ------------------------------------------------------------------
          # Si l'action demandée est USER_DELETED ou COMPANY_CLOSED
          if ($evtName =~ /(USER_DELETED|COMPANY_CLOSED)/) {
            # Le message est connu de MSG_KNOWLEDGE & WORK_TABLE & AMADEUS_SYNCHRO
            my $size = scalar @$wtItem;
            if (($wtItem->[$size-1]->{ACTION} ne 'DELETE') &&
                ($wtItem->[$size-1]->{STATUS} =~ /^(NEW|LOCKED)$/)) {
              $action = 'DELETE';
            } else { return 0; }
          }
          # ------------------------------------------------------------------

          # L'action à faire est un UPDATE
          $row = &insertIntoWorkTable(
            { MESSAGE_ID      => $msgId,
              MESSAGE_CODE    => $msgCode,
              MESSAGE_VERSION => $msgVersion,
              MESSAGE_TYPE    => $mkType,
              EVENT_VERSION   => '',
              TEMPLATE_ID     => '',
              MARKET          => $market,
              APP_ID          => $appId,
              ACTION          => $action,
              STATUS          => 'NEW',
              XML             => $message,
              PNR             => '',
            }
          );
          return 0 unless $row; # Quest-ce qu'on fait si $rows == 0 ?
        }
        # µµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµ
        # CAS 2.2.3 = Plusieurs résultats trouvés dans la table AMADEUS_SYNCHRO
        # µµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµ
        else { # Cas normalement impossible car contrainte unique sur la table.
          notice('CASE 2.2.3 - asItem = '.Dumper($asItem));
          notice('Multiple results returned but only one is expected.');
          return 0;
        }

      }

    }

    # $$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$
    # CAS 3 = Ce message est connu de la base de connaissance des messages
    # $$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$
    # La requète de récupération a fourni plusieurs résultats alors
    #  que un seul est attendu !
    else { # Cas normalement impossible car contrainte unique sur la table.
      debug('CASE 3 - mkItem = '.Dumper($mkItem));
      notice('Multiple results returned but only one is expected.');
      return 0;
    }
    # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

  } # Fin : if ($item->{USED_FOR} eq 'SYNCHRO')
  # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

  return 1;
}

1;
