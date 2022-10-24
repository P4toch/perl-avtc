package Expedia::Modules::GAP::SeatPref;
#-----------------------------------------------------------------
# Package Expedia::Modules::GAP::SeatPref
#
# $Id: SeatPref.pm 607 2010-12-14 10:39:31Z pbressan $
#
# (c) 2002-2008 Expedia.                   www.expediacorporate.fr
#-----------------------------------------------------------------

use strict;
use Data::Dumper;

use Expedia::Tools::Logger qw(&debug &notice &warning &error);

sub run {
  my $self   = shift;
  my $params = shift;

  my $globalParams = $params->{GlobalParams};
  my $moduleParams = $params->{ModuleParams};
  my $changes      = $params->{Changes};
  my $item         = $params->{Item};
  my $pnr          = $params->{PNR};
  my $ab           = $params->{ParsedXML};
  my $WBMI         = $params->{WBMI};
    
  my $travellers   = $pnr->{Travellers};
  my $nbPax        = scalar @$travellers;
  
  my $h_pnr        = $params->{Position};
  my $refpnr       = $params->{RefPNR};
  
  my $position        = $h_pnr->{$refpnr};

  my $atds = $ab->getTravelDossierStruct;  

  my $lwdPos       = $atds->[$position]->{lwdPos};
  my $segments     = $ab->getAirSegments({lwdPos => $lwdPos});
  my $vendors      = _formatSegments($segments, 0);
  my $segCountries = _concatSegCountries($segments);
  
  # On ne fait rien si les segment contiennent de l'EUROSTAR
  #  ~ Demande Vinh Giang 25 Février 2009
  return 1 if ($vendors =~ /9F/);
  # On ne fait rien s'il s'agit d'un vol domestic sur un trajet "France"
  #  ~ Demande Catherine Dubost 17 Septembre 2009 
  return 1 if (($atds->[$position]->{lwdTripType} eq 'DOMESTIC') && ($segCountries =~ /^(FRA)+$/));
  # 09 Novembre 2010 - SeatMap Project. Attribution des sièges géré par le site.
  return 1 if ($nbPax <= 1);
  
  # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
  # On commence par recharger le PNR
  $pnr->reload;
  # $pnr->{_GDS}->RT(PNR=>$pnr->{PNRId}, NoIG=>1);
  # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
  
  # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
  # MONO PAX
  if ($nbPax == 1) {
    
    my $seatPref = $ab->getSeatPref({trvPos => $ab->getWhoIsMain});
    my $seatComd = '';
    
    # *************************************************************************
    # Passenger has a seat preference defined
    if ($seatPref =~ /^(AISLE|WINDOW|UNDEFINED)$/) {
      debug('Pax has seat preference defined in his profile ('.$seatPref.').');
      $seatComd = 'ST/A' if ($seatPref =~ /^(AISLE|UNDEFINED)$/);
      $seatComd = 'ST/W' if ($seatPref eq 'WINDOW');
    
      # -----------------------------------------------------------------------
      # On regarde si on trouve dans le dossier des lignes NSS
      my $NSS = _getNssDatas($pnr);
      my @linesToDelete = ();
      # -----------------------------------------------------------------------
      
      # -----------------------------------------------------------------------
      # Si j'ai trouvé des lignes NSS dans le dossier, je vérifie si elles
      #   sont toutes en HK or KK or HN.
      if (scalar @$NSS > 0) {
        debug('NSS lines found.');
        @linesToDelete = _getNssLinesWhichDoNotMatch($NSS);
        if (scalar @linesToDelete == 0) { $pnr->{_GDS}->IG; return 1; }
      }
      
      # One of them is not HK or KK or HN then delete this particular line
      
      # Launch a seat request corresponding to his preference
      debug('Launch a seat request corresponding to his preference.');
      _applyChanges($pnr, \@linesToDelete, [$seatComd]);
      $NSS = _getNssDatas($pnr);
      @linesToDelete = _getNssLinesWhichDoNotMatch($NSS);
      if ((scalar @$NSS > 0) && (scalar @linesToDelete == 0)) { $pnr->{_GDS}->IG; return 1; }
      
      # Launch a seat request opposite to preference
      debug('Launch a seat request opposite to preference.');
      $seatComd = 'ST/W' if ($seatPref =~ /^(AISLE|UNDEFINED)$/);
      $seatComd = 'ST/A' if ($seatPref eq 'WINDOW');
      _applyChanges($pnr, \@linesToDelete, [$seatComd]);
      $NSS = _getNssDatas($pnr);
      @linesToDelete = _getNssLinesWhichDoNotMatch($NSS);
      if ((scalar @$NSS > 0) && (scalar @linesToDelete == 0)) { $pnr->{_GDS}->IG; return 1; }
      
      # Launch a basic seat request "ST"
      debug('Launch a basic seat request.');
      _applyChanges($pnr, \@linesToDelete, ['ST'], 'NORELOAD');
      # -----------------------------------------------------------------------
    
    } # Fin if ($seatPref =~ /^(AISLE|WINDOW|UNDEFINED)$/)
    # *************************************************************************
    
  }
  # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
  # MULTI PAX    
  elsif ($nbPax > 1) {
    
    my @add           = ();
    my @linesToDelete = ();
    my $addRemark     = 0;
    my $message       = 'RM @@ CHECK SEATS PREFERENCES @@';
    
    # -----------------------------------------------------------------------
    # On regarde si on trouve dans le dossier des lignes NSS et on les
    #   supprimes toutes. On envoi également ST et on regarde
    #     si on a des lignes SSR NSS.
    my $NSS = _getNssDatas($pnr);
    push (@linesToDelete, $_->{LineNo}) foreach (@$NSS);
    _applyChanges($pnr, \@linesToDelete, ['ST']);
       $NSS = _getNssDatas($pnr);
    if (scalar @$NSS == 0) {
      $pnr->{_GDS}->IG;
      debug('Cannot define seat assignement for this trip.');
      return 1;
    }
    # -----------------------------------------------------------------------
    
    foreach my $traveller (@$travellers) {
      my $seatPref = $ab->getSeatPref({trvPos => $traveller->{Position}});
      my $paxNum   = $traveller->{PaxNum};
      $addRemark   = 1                                    if ($seatPref ne 'UNDEFINED');
      push (@add, "RM @@ SEAT PREF $paxNum $seatPref @@") if ($seatPref =~ /^(AISLE|WINDOW)$/);
    }

    if ($addRemark == 1) {
      push (@add, $message);
      _applyChanges($pnr, [], \@add, 'NORELOAD');
      $WBMI->addReport({ Code        => 3,
                         PnrId       => $pnr->{_PNR},
                         AmadeusMesg => $message });
    }
    
  }
  # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

  return 1;  
}



# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Effectue des suppressions dans Amadeus + Envoi éventuellement d'une
#  ou plusieurs commandes + Rechargement du PNR.
sub _applyChanges {
  my $pnr           = shift;
  my $linesToDelete = shift;
  my $amadCommands  = shift;
  my $noReload      = shift;
     $noReload      = 1 if (defined $noReload); 
  
  @$linesToDelete = sort {$b <=> $a} (@$linesToDelete);
  my $ER1 = []; my $ER2 = [];
  my $GDS = $pnr->{_GDS};
  
  RETRY: {{
    $GDS->command(Command=>'XE'.$_, NoIG=>1, NoMD=>1) foreach (@$linesToDelete);
    $GDS->command(Command=>$_,      NoIG=>1, NoMD=>1) foreach (@$amadCommands);
    # ---------------------------------------------------------------------  
    # Validation des modifications
           $GDS->command(Command=>'RF'.$GDS->modifsig, NoIG=>1, NoMD=>1);
    $ER1 = $GDS->command(Command=>'ER',                NoIG=>1, NoMD=>1);
    $ER2 = $GDS->command(Command=>'ER',                NoIG=>1, NoMD=>1);
    # ---------------------------------------------------------------------
  
   if (   (grep(/CHANGTS SIMULT DANS PNR/, @$ER1)) ||
		 (grep(/CHANGTS SIMULT DANS PNR/, @$ER2)) ||
		 (grep (/VERIFIER LE PNR ET REESSAYER/ ,   @$ER1)) ||
		 (grep (/VERIFIER LE CONTENU DU PNR/ ,   @$ER1))  ||
		 (grep (/VERIFIER LE PNR ET REESSAYER/ ,   @$ER2)) ||
		 (grep (/VERIFIER LE CONTENU DU PNR/ ,   @$ER2))  
	 ) {
      $pnr->reload;
      # $GDS->RT(PNR=>$pnr->{PNRId}, NoIG=>1);
      my $NSS              = _getNssDatas($pnr);
      my @newlinesToDelete = _getNssLinesWhichDoNotMatch($NSS);
       $linesToDelete      = \@newlinesToDelete;
      @$linesToDelete      = sort {$b <=> $a} (@$linesToDelete);
      goto RETRY;
    }
  }};
  
  # ---------------------------------------------------------------------
  # Puis reloadage de PNR
  $pnr->reload unless ($noReload);
  # $GDS->RT(PNR=>$pnr->{PNRId}, NoIG=>1);
  # ---------------------------------------------------------------------
  
  return 1;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Retourne une référence de tableau avec un détail des lignes NSS
sub _getNssDatas {
  my $pnr = shift;
  
  my $NSS = [];
  
  LINE: foreach (@{$pnr->{'PNRData'}}) {
    next LINE unless ($_->{'Data'} =~ /SSR (?:NSS\D|SEAT) \w{2} (\w{2})/);
    debug('This Line match NSS : '.$_->{'Data'});
    push @$NSS, { LineNo => $_->{'LineNo'}, Data => $_->{'Data'}, Code => $1};
  }
  
  return $NSS;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Retourne un tableau avec les lignes NSS qui ne sont pas en HK or KK or HN
sub _getNssLinesWhichDoNotMatch {
  my $NSS = shift;
  
  my @linesToDelete = ();
  
  foreach (@$NSS) {
    push @linesToDelete, $_->{LineNo} if ($_->{Code} !~ /^(HK|KK|HN)$/);
  }
  
  return @linesToDelete;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Fonction visant à applanir les segments
sub _formatSegments {
  my $h_segments = shift;
  my $substitute = shift;
  
  $substitute = 1 if (!defined $substitute);

  my @vendors = ();

  foreach (@$h_segments) { push (@vendors, $_->{VendorCode}); }
  
  my $vendors = join(' ', @vendors);
     $vendors =~ s/(KL|NW|KQ)/AF/ig if ($substitute == 1);

  debug('Vendors = '.$vendors);

  return $vendors;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Fonction visant à applanir les pays de départ et destination de tous les segments
sub _concatSegCountries {
  my $h_segments = shift;

  my $countries  = '';

  foreach (@$h_segments) {
    $countries .= $_->{DepCountryCode}.$_->{ArrCountryCode};
  }

  return $countries;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

1;
