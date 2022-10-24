package Expedia::Modules::TAS::TrainPreTicketing;
#-----------------------------------------------------------------
# Package Expedia::Modules::TAS::TrainPreTicketing
#
# $Id: TrainPreTicketing.pm 603 2010-08-10 13:29:02Z pbressan $
#
# (c) 2002-2008 Expedia.                   www.expediacorporate.fr
#-----------------------------------------------------------------

use strict;
use DateTime;
use Data::Dumper;
use POSIX qw(strftime);
use DateTime::Duration;

use Expedia::Tools::Logger qw(&debug &notice &warning &error);
use Expedia::Tools::GlobalFuncs qw(&dateTimeXML);
use Expedia::Databases::MidSchemaFuncs qw(&btcTasProceed &isInMsgKnowledge);

sub run {
  my $self   = shift;
  my $params = shift;

  my $globalParams = $params->{GlobalParams};
  my $moduleParams = $params->{ModuleParams};
  my $changes      = $params->{Changes};
  my $item         = $params->{Item};
  my $DVs          = $params->{DVs};
  my $tb           = $params->{ParsedXML};
  my $btcProceed   = $params->{BtcProceed};

  my $ttds         = $tb->getTrainTravelDossierStruct;
  my $travellers   = $tb->getTravellerStruct();
  my $lwdPos       = $ttds->[0]->{lwdPos};
  my $FCE          = _contractFilter($tb->getTravelDossierContracts({lwdPos => $lwdPos}));
  
  foreach my $dv (@{$DVs}) {
    
    # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
    # Vérification de la présence d'un ITINERAIRE dans la DV
    if (scalar(@{$dv->{ITINERAIRE}}) == 0) {
      notice("ITINERARY EMPTY FOR '".$dv->{_DV}."'. Aborting ...");
      debug('### TAS MSG TREATMENT 33 ###');
      $dv->{TAS_ERROR} = 33;
      return 1;
    }
    # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

    # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
    # Check element "TITRE PRE ENREGISTRE"
    if ($dv->{TPE} == 0) {
      if (scalar (@{$dv->{EMISSION}}) > 0) {
        # ------------------------------------------------------------
        # On vérifie que ce META_DOSSIER_ID (= mdCode)
        #   n'est pas déjà "BTC-TAS PROCEED"
        my $mdCode = $item->{REF};
        my $mkItem = &isInMsgKnowledge({ PNR => $item->{PNR} });
        if ($mkItem->[0][5] == 1) {
          debug('### TAS MSG TREATMENT 38 ###');
      	  $dv->{TAS_ERROR} = 38;
        } else {
          debug('### TAS MSG TREATMENT 4 ###');
      	  &btcTasProceed({ PNR => $item->{PNR}, TYPE => 'TRAIN' });
      	  $dv->{TAS_ERROR} = 4;
        }
        # ------------------------------------------------------------
      } else {
        debug('### TAS MSG TREATMENT 21 ###');
        $dv->{TAS_ERROR} = 21;
      }
      return 1;
    }
    # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
    
    # $$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$ #
    # $$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$ #
    #   TRAIN CHECK PRICING - TRAIN CHECK PRICING - TRAIN CHECK PRICING   #
    # $$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$ #
    # $$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$ #

    # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
    # Vérification qu'une des TST n'est pas périmée
    foreach (@{$dv->{_WP9}}) {
      if ($_ =~ /^IMAGE-TITRE PERIMEE/) {
        debug('### TAS MSG TREATMENT 8 ###');
        $dv->{TAS_ERROR} = 8;
        return 1;        
      }
    }
    # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# _____________________________________________________________________
# SECTION COMMENTÉE LE 22 AOÛT 2008
#  REMPLACÉE PAR LA VÉRIFICATION COMPLETE CHECKED DE WBMI
#    DANS TASKPROCESSOR.PM (isTcChecked FONCTION dans TASFUNCS.PM)
# _____________________________________________________________________
#    # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
#    # Pour les online Bookings, on doit faire des vérifications
#    #  supplémentaires (Moulinette BTC-TRAIN ok).
#    
#    my $isOnlineBooking = 1;
#    my $events          = $tb->getMdEvents;
#    EVENT: foreach my $event (@$events) {
#      if ((exists $event->{EventAction}) &&
#          ($event->{EventAction} =~ /^TRAININSERTION$/)) {
#        notice('Offline booking detected [...]');
#        $isOnlineBooking = 0;
#        last EVENT;
#      }
#    }
#    
#    # ================================================================
#    # Sauf si la bookDate est supérieure à 3 H 00 !
#    #   On considère que les conseillers voyage ont eu le temps
#    #     de s'occuper des remarques RM @@ (sauf si c'est un W-E !!!)
#    if ($isOnlineBooking == 1) {
#      notice('Online booking detected [...]');
#      
#      my $bookDate = &dateTimeXML($tb->getMdBookDate);
#      my $currDate = strftime("%Y/%m/%d %H:%M:%S",localtime());
#      debug('bookDate = '.$bookDate) if ($bookDate);
#      debug('currDate = '.$currDate);
#      
#      if ($bookDate ne '') { # Bizarrement, il peut ne pas y avoir de BookDate
#
#        my $dtBookDate = DateTime->new(
#          year   => substr($bookDate,  0, 4),
#          month  => substr($bookDate,  5, 2),
#          day    => substr($bookDate,  8, 2),
#          hour   => substr($bookDate, 11, 2),
#          minute => substr($bookDate, 14, 2),
#        );
#        
#        my $dtCurrDate = DateTime->new(
#          year   => substr($currDate,  0, 4),
#          month  => substr($currDate,  5, 2),
#          day    => substr($currDate,  8, 2),
#          hour   => substr($currDate, 11, 2),
#          minute => substr($currDate, 14, 2),
#        );
#        
#        my $duration = $dtCurrDate - $dtBookDate; debug('DURATION = '.Dumper($duration));
#  
#        $isOnlineBooking = 0
#          if ( ((abs($duration->{minutes}) > 180) && (abs($duration->{days})) == 0) ||
#                (abs($duration->{days}) > 0) );
#        
#        # Sauf les bookings "Online" faits les Samedis & Dimanches
#        my $dayOfWeek = $dtBookDate->day_of_week(); debug('DAYOFWEEK = '.$dayOfWeek);
#        $isOnlineBooking = 1 if ($dayOfWeek =~ /^(6|7)$/);
#
#      } # Fin if ($bookDate ne '')
#
#    }
#    # ================================================================
#    
#    if ($isOnlineBooking == 1) {
#      my $doNotAutomaticProcess = 0;
#      my $btcTrainProceed       = 0;
#      my $PNRId                 = $dv->getAmadeusRef;
#      if (defined $PNRId) {
#        notice("Corresponding PNR = '$PNRId'");
#        my $PNR = Expedia::GDS::PNR->new(PNR => $PNRId, GDS => $dv->{_GDS});
#        if (defined $PNR) {
#          DATA: foreach (@{$PNR->{PNRData}}) {
#            $btcTrainProceed = 1 if ($_->{'Data'} =~ /TRAIN PROCEED/);
#            if (($_->{'Data'} =~ /^RM @@ VERIFIER ATTRIBUTION REDUCTIONS/) ||
#                ($_->{'Data'} =~ /^RM @@ VERIFIER ID ETICKET/)             ||
#                ($_->{'Data'} =~ /^RM @@ AUCUNE CC TROUVEE/)               ||
#                ($_->{'Data'} =~ /^RM @@ ECHEC RETARIFICATION/)            ||
#                ($_->{'Data'} =~ /^RM @@ REPRICE FUNCTION FAILURE/)        ||
#                ($_->{'Data'} =~ /^RM @@ TRAVELLERCOMMENTS/)               ||
#                ($_->{'Data'} =~ /^RM @@ PASS ENTREPRISE FARE/)            ||
#                ($_->{'Data'} =~ /^RM @@ FID DE/)) {
#              $doNotAutomaticProcess = 1;
#            }
#          } # Fin DATA: foreach my $line (@{$self->{PNRData}})
#        } # Fin if (defined $PNR)
#        else {
#          notice("Problem detected during 'Expedia::GDS::PNR->new()'");
#          return 0;
#        }
#        # ============================================================
#        # Dernières vérifications
#        if ($btcTrainProceed == 0) {
#          notice('This booking has not been Btc-Train proceed.');
#          return 0;
#        }
#        # Nous ne sortons plus en TAS_ERROR dans ce cas.
#        # if ($doNotAutomaticProcess == 1) {
#        #   debug('### TAS MSG TREATMENT 45 ###');
#        #   $dv->{TAS_ERROR} = 45;
#        #   return 1;        
#        # }
#        # ============================================================
#      } # Fin if (defined $PNRId)
#      else {
#        notice('Cannot retrieve reference in Amadeus.');
#        return 0;
#      }
#    }
#    else {
#      # C'est du Offline ou bien on le traite comme du Offline
#      # notice('Offline booking detected [...]');
#    }
#    # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
    
    # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
    # Tous les segments du dossier sont tarifés
    my @itineraire = @{$dv->{ITINERAIRE}};
    my @fareInfos  = @{$dv->{FAREINFO}};
    foreach my $iti (@itineraire) {
      my $segNumber = $iti->{Line};
      foreach my $finfo (@fareInfos) {
        my @advanced = @{$finfo->{advanced}};
        foreach my $adv (@advanced) {
          my @segList  = @{$adv->{SegList}};
          foreach (@segList) {
            $iti->{Priced} = 1 if ($segNumber eq $_);
          }
        }
      }
    }
    # Si on n'a pas trouvé de tarification pour un segment,
    #  c'est peut-être qu'il s'agit d'un segment en "Additional Option"
    #    si l'itinéraire est le même qu'un itinéraire tarifé.
    foreach my $iti1 (@itineraire) {
      if (!exists $iti1->{Priced}) {
        my $FromTo1 = $iti1->{From}.$iti1->{To};
        foreach my $iti2 (@itineraire) {
          next unless (exists $iti2->{Priced});
          my $FromTo2 = $iti2->{From}.$iti2->{To};
          $iti1->{AddOption} = 1 if ($FromTo1 eq $FromTo2);
        }
      }
    }
    # Vérification finale - Soit il est Priced, soit il est Option.
    my $h_itineraire = {}; # Pour utilisation ultérieure
    foreach my $iti (@itineraire) {
      if (!exists $iti->{Priced}) {
        if (!exists $iti->{AddOption}) {
          debug('### TAS MSG TREATMENT 3 ###');
          $dv->{TAS_ERROR} = 3;
          return 1;
        }
      } else {
        # ===================================================
        # Pour utilisation ultérieure
        $h_itineraire->{$iti->{Line}}->{From} = $iti->{From};
        $h_itineraire->{$iti->{Line}}->{To}   = $iti->{To};
        # ===================================================
      }
    }
    # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
    
    # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
    # Tous les passagers apparaissant dans le dossier doivent effectuer
    #   l'intégralité du voyage !!!
    # ================================================================
    # Initialisation du hashage passagers et segments
    my $h_pax = {};
    foreach my $pax (@{$dv->{PAX}}) {
      my $paxNum = substr($pax->{rank}, 0, 1);
      $h_pax->{$paxNum} = [];
    }
    my @segNums = ();
    foreach my $seg (@{$dv->{ITINERAIRE}}) {
      next if (exists $seg->{AddOption});
      my $segNum = $seg->{Line};
      push @segNums, $segNum;
    }
    # ================================================================
    # Démarrage de la vérification
    foreach my $ita (@{$dv->{FAREINFO}}) {
      my $paxList = $ita->{paxList};
      my $advFare = $ita->{advanced};
      # **************************************************************
      # Récupération de la liste des segments de cette image titre.
      my @itaSegs = (); my $h_iSegs = {};
      foreach my $advItem (@$advFare) {
        my @tmpList = @{$advItem->{SegList}};
        foreach (@tmpList) {
          next if exists $h_iSegs->{$_};
          push (@itaSegs, $_);
          $h_iSegs->{$_} = 1;
        }
      }
      # **************************************************************
      debug('paxList = '.$paxList);
      debug('itaSegs = '.Dumper(\@itaSegs));
      if ($paxList =~ /^(\d)\.1$/) {
        my $paxNum = $1;
        debug('Cas1> PaxList est renseigné = '.$paxNum);
        push (@{$h_pax->{$paxNum}}, $_) foreach (@itaSegs);
      }
      else {
        debug('Cas2> Analyse du nbPaxIndicator.');
        debug('$ita->{nbPaxIndicator} = '.$ita->{nbPaxIndicator});
        if ($ita->{nbPaxIndicator} == $dv->{PAXNUM}) {
          foreach my $key (keys %$h_pax) {
            push (@{$h_pax->{$key}}, $_) foreach (@itaSegs);
          }
        }
        else {
          debug("'nbPaxIndicator' différent de '$dv->{PAXNUM}'");
          debug('### TAS MSG TREATMENT 23 ###');
          $dv->{TAS_ERROR} = 23;
          return 1;
        }
      }
    } # Fin foreach my $ita (@{$dv->{FAREINFO}})
    # ================================================================
    # Vérification finale - Tous les passagers doivent effectuer
    #    l'intégralité du voyage.
    # ================================================================
    foreach my $key (keys %$h_pax) {
      debug('paxNum = '.$key);
      my $res = _compare(\@segNums, $h_pax->{$key});
      if ($res == 0) {
        debug('### TAS MSG TREATMENT 23 ###');
        $dv->{TAS_ERROR} = 23;
        return 1;
      }
    }
    # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
    
    # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
    # Pour un passager donné, on ne peut pas avoir deux fois le même
    #  itinéraire tarifé.
    debug('Pas de doublons dans les itineraires "tarifés".');
    foreach my $key (keys %$h_pax) {
      debug('paxNumber = '.$key);
      my $h_FromTo = {}; 
      my $segs     = $h_pax->{$key};
      foreach my $segNum (@$segs) {
        debug('segNumber = '.$segNum);
        my $FromTo = $h_itineraire->{$segNum}->{From}.$h_itineraire->{$segNum}->{To};
        debug('FromTo = '.$FromTo);
        if (exists $h_FromTo->{$FromTo}) {
          debug('### TAS MSG TREATMENT 6 ###');
          $dv->{TAS_ERROR} = 6;
          return 1;
        }
        $h_FromTo->{$FromTo} = 1;
      }
    }
    # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
    
    $dv->{H_PAXSEGS_TOTICKET} = $h_pax; # Est utilisé ensuite dans TrainTicketingCheck.pm
    
    # $$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$ #
    # $$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$ #
    #   TRAIN CHECK PRICING - TRAIN CHECK PRICING - TRAIN CHECK PRICING   #
    # $$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$ #
    # $$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$ #

    # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
    # Vérification que les noms dans Socrate ne commencent pas par
    #    ZZZZZ, OCCASIONNEL, ENTREPRISE
    foreach my $pax (@{$dv->{PAX}}) {
      my $paxName = $pax->{Pax};
      if (($paxName =~ /^(ZZZZZ|OCCASIONNEL|ENTREPRISE|RAVEL|NOM\/PRENOM|XX)/) ||
          ($paxName =~ /PRENOM|NEW USER/)) {
        notice('Invalid PaxName detected : '.$paxName);
        debug('### TAS MSG TREATMENT 22 ###');
        $dv->{TAS_ERROR} = 22;
        return 1;
      }
    }
    # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
    
    # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
    # Vérification de la présence d'un identifiant e-ticket
    #   uniquement si le nombre de passagers est > à 1
    if (scalar(@{$dv->{PAX}}) > 1) {
      foreach my $pax (@{$dv->{PAX}}) {
        my $paxName = $pax->{Pax}.$pax->{id};
        if ($item->{TICKET_TYPE} eq 'etkt')    {
          if ($paxName !~ /\?29090109/) {
            my $idFound = 0;
            while ($paxName =~ /-C(.*)/) {
              $paxName = $1;
              if (defined $1) {
                my $nextLetter = substr($1, 0, 1);
                $idFound = 1 if $nextLetter ne 'V';
              }
            }
            if (!$idFound) {
              notice('No eticket identifier found for : '.$pax->{Pax});
              debug('### TAS MSG TREATMENT 16 ###');
              $dv->{TAS_ERROR} = 16;
              return 1;
            }
          }
        }
        if ($item->{TICKET_TYPE} eq 'ebillet') {
          my $idNotFound = 0;
          if (($paxName !~ /-MM/) && ($paxName !~ /-CV/)) {
            $idNotFound  = 1;
          } else {
            $dv->_scanRTN unless defined $dv->{RTNINFO};
            my $paxRank = $pax->{rank};
            foreach my $rtnInfo (@{$dv->{RTNINFO}}) {
              if ($rtnInfo->{rank} eq $paxRank) {
                if ((!defined $rtnInfo->{birthdate}) || ($rtnInfo->{birthdate} !~ /^\d{2}\D{3}\d{4}$/)) {
                  $idNotFound = 1;
                  last;
                }
                else { $idNotFound = 0; last; }
              }
              $idNotFound = 1;
            } # FIN foreach my $rtnInfo (@{$dv->{RTNINFO}})
          }
          if ($idNotFound) {
            notice('No ebillet identifier found for : '.$pax->{Pax});
            debug('### TAS MSG TREATMENT 16 ###');
            $dv->{TAS_ERROR} = 16;
            return 1;
          }
        }
        if ($item->{TICKET_TYPE} eq 'ttless')  {
          if ($paxName !~ /\?30840601/) {
            notice('No ttless identifier found for : '.$pax->{Pax});
            debug('### TAS MSG TREATMENT 16 ###');
            $dv->{TAS_ERROR} = 16;
            return 1;
          }
        }
      }
    }
    # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
    
    # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
    # Vérification de la présence d'un e-mail @ booking level / Pax
    #   Projet Ebillet / Thalys Ticketless ~ 01 Décembre 2009
    if ($item->{TICKET_TYPE} eq 'ebillet') {
      if ((!defined $dv->{BOOKINGEMAIL}) || ($dv->{BOOKINGEMAIL} =~ /^\s*$/)) {
        notice('Email missing at booking level.');
        $dv->_scanRTN unless defined $dv->{RTNINFO};
        foreach my $rtnInfo (@{$dv->{RTNINFO}}) {
          if ((!defined $rtnInfo->{email}) || ($rtnInfo->{email} =~ /^\s*$/)) {
            notice('Email missing for one of the travellers.');
            debug('### TAS MSG TREATMENT 14 ###');
            $dv->{TAS_ERROR} = 14;
            return 1;
          }
        }
      }
      else { debug('BOOKINGEMAIL = '.$dv->{BOOKINGEMAIL}); }
    }
    # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
    
    # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
    # Présence du FCE Tracking Number
    if (scalar (@$FCE) > 0) { # Si contrat FCE disponible
      my $fceHasBeenapplied = 1;
      my $fce = $FCE->[0]->{CorporateNumber}; # On prend le premier contrat FCE
      my $GDS = $dv->{_GDS};
      $GDS->command(
        Command     => 'R//IG',
        NoIG        => 1,
        NoMD        => 1,
        PostIG      => 0,
        ProfileMode => 0);
      $GDS->command(
        Command     => 'R/RT'.$dv->{_DV},
        NoIG        => 1,
        NoMD        => 1,
        PostIG      => 0,
        ProfileMode => 0);
      $GDS->command(Command=>"R/NMALL\@\$".$fce,       NoIG=>1, NoMD=>1, PostIG=>0);
      $GDS->command(Command=>'R/RFAG/'.$GDS->modifsig, NoIG=>1, NoMD=>1, PostIG=>0);
      $GDS->command(Command=>'R/ET',                   NoIG=>1, NoMD=>1, PostIG=>0);
    }
    # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
    
  }
  
  return 1;
}

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Fonction d'extraction d'un contrat FCE parmi tous les contrats
sub _contractFilter {
  my $tdContracts = shift; 

  my @res = ();

  foreach my $contract (@$tdContracts) {
    next if ($contract->{SupplierService} ne 'RAIL');
    next if ($contract->{SupplierCode}    ne '2C');    # Ou SupplierName = 'SNCF'
    next if ($contract->{CorporateNumber} =~ /^\s*$/);
  # next if ($contract->{ContractType}    =~ /^(DISCOUNT|TRACKING)$/); # L'un ou l'autre, pas les 2 [...]
    push (@res, $contract);
  }
  
  return \@res;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Compare la liste "Base" avec celle "Pax". Vérifie que tous les 
# éléments de "Base" sont présents dans "Pax" en un unique exemplaire.
sub _compare {
  my $h_segBase = shift;
  my $h_segPax  = shift;
  
  my $h_Res = {};
   
  foreach my $sBase (@$h_segBase) {
    $h_Res->{$sBase} = 0;
    foreach my $sPax (@$h_segPax) {
      $h_Res->{$sBase} += 1 if ($sBase eq $sPax);
    }
  }
  
  debug('$h_Res = '.Dumper($h_Res));
  
  foreach my $key (keys %$h_Res) {
    if ($h_Res->{$key} == 0) {
      notice("Segment number '$key' is not priced.");
      return 0;
    }
    elsif ($h_Res->{$key}  > 1) {
      notice("Segment number '$key' is priced more than one time.");
      return 0;
    }
  }
  
  return 1;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Va chercher la date de naissance dans le profil
#   La difficulté est que nous ne faisons pas de reconnaissance des
#     voyageurs dans TAS au niveau du RAIL.
sub _getBirthDate {
  my $paxName   = shift;
  my $trvStruct = shift;
  my $etkIds    = shift;
  
  return 1;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

1;
