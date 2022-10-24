package Expedia::Modules::TAS::AutomaticFV;
#-----------------------------------------------------------------
# Package Expedia::Modules::TAS::AutomaticFV
#
# $Id: AutomaticFV.pm 713 2011-07-04 15:45:26Z pbressan $
#
# (c) 2002-2008 Expedia.                   www.expediacorporate.fr
#-----------------------------------------------------------------

use strict;
use Data::Dumper;

use Expedia::Tools::Logger      qw(&debug &notice &warning &error);
use Expedia::Tools::GlobalVars  qw($h_tstNumFstAcCode $h_fvMapping);
use Expedia::Tools::GlobalFuncs qw(&stringGdsPaxName);
use Expedia::Tools::TasFuncs         qw(&getCurrencyForTas);

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Variable globale
my $currency = undef;
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
sub run {
  my $self   = shift;
  my $params = shift;

  my $globalParams = $params->{GlobalParams};
  my $moduleParams = $params->{ModuleParams};
  my $changes      = $params->{Changes};
  my $item         = $params->{Item};
  my $pnr          = $params->{PNR};
  my $GDS          = $params->{GDS};
  my $market       = $globalParams->{market};
    
    my $pnrdoc = $pnr->{_XMLPNR};
    my $tstdoc = $pnr->{_XMLTST};
       
    $currency = &getCurrencyForTas($market); #$moduleParams->{currency};
    
    # $self->_delFv($pnr); # _delFV : Supprime les FV existantes. 07 Août 2009 - A la demande de Céline Perdriau
    # Commenté le 12 Janvier 2010 à la demande de Céline Perdriau
    
    # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
    # Association des numéros de passager entre le XML et le PNR
    my $travellersPnrXml = {};
    
    my @travellerInfoNodes = $pnrdoc->getElementsByTagName('travellerInfo');
    foreach my $travellerInfoNode (@travellerInfoNodes) {
      my $lastName  = $travellerInfoNode->find('passengerData/travellerInformation/traveller/surname')->to_literal->value();
      my $firstName = $travellerInfoNode->find('passengerData/travellerInformation/passenger/firstName')->to_literal->value();
      my $number    = $travellerInfoNode->find('elementManagementPassenger/reference/number')->to_literal->value();
      $_ = stringGdsPaxName($_, $market) foreach ($firstName, $lastName);
      $travellersPnrXml->{$number}->{FIRST_NAME} = $firstName;
      $travellersPnrXml->{$number}->{LAST_NAME}  = $lastName;
    }
    foreach my $uRef (keys %$travellersPnrXml) {
      my $xmlName = $travellersPnrXml->{$uRef}->{LAST_NAME}.' '.$travellersPnrXml->{$uRef}->{FIRST_NAME};
  
      foreach my $pax (@{$pnr->{Travellers}}) {
        my $lastName    =  $pax->{LASTNAME};
        my $firstName   =  $pax->{FIRSTNAME};
        my $crypticName =  $lastName.' '.$firstName;
        debug('xmlName     = '.$xmlName);
        debug('crypticName = '.$crypticName);
        $travellersPnrXml->{$uRef}->{PaxNum} = substr($pax->{PaxNum}, 1, 1)
          if ($xmlName =~ $crypticName);
      }
  
    }
    debug(' Association des passagers CRYPTIC et XML / travellersPnrXml = '.Dumper($travellersPnrXml));
    # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
    
    $h_tstNumFstAcCode = {};
    
    my @fareListNodes                 = $tstdoc->getElementsByTagName('fareList');
    my @originDestinationDetailsNodes = $pnrdoc->getElementsByTagName('originDestinationDetails');
    
    my @tmpNodes                = ();
    my @itineraryInfoNodes      = ();
    my @segmentInformationNodes = ();
    my @segmentReferenceNodes   = ();
    my @refDetailsNodes         = (); 
    my $h_FV                    = {};
    
    foreach my $oNode (@originDestinationDetailsNodes) {
      @tmpNodes = $oNode->getElementsByTagName('itineraryInfo');
      push @itineraryInfoNodes, $_ foreach (@tmpNodes);
    }
    
    foreach my $iNode (@itineraryInfoNodes) {
      my $refNumber  = $iNode->find('elementManagementItinerary/reference/number')->to_literal->value();
      my $lineNumber = $iNode->find('elementManagementItinerary/lineNumber')->to_literal->value();
      my $segName    = $iNode->find('elementManagementItinerary/segmentName')->to_literal->value();
      my $comDetail  = $iNode->find('travelProduct/companyDetail/identification')->to_literal->value(); 
    	next unless ($segName eq 'AIR');
    	next unless ($iNode->find('travelProduct/offpointDetail/cityCode')->to_literal->value());
  	  next unless ($iNode->find('relatedProduct/status')->to_literal->value() eq 'HK');
  	  $h_FV->{$refNumber} = { segLine => $lineNumber, acCode  => $comDetail };
    }

    debug('$h_FV = '.Dumper($h_FV));

    my $i               = 0;
    my @FV              = ();
    my $SG              = '';
    my $PX              = '';
    my $FXX             = '';
    my $doFXX           = 0;
    my $frstAirlineCode = ''; # First
    my $prevAirlineCode = ''; # Previous
    my $currAirlineCode = ''; # Current

    foreach my $fNode (@fareListNodes) {
      $i   = 0;
      $SG  = '/S';
      $PX  = '/P';
      $FXX = 'FXX';
      @refDetailsNodes         = $fNode->findnodes('paxSegReference/refDetails');
      @segmentInformationNodes = $fNode->findnodes('segmentInformation');
      my $tstNumber            = $fNode->find('fareReference/uniqueReference')->to_literal->value();
      foreach my $rNode (@refDetailsNodes) {
        my $refNumber = $rNode->find('refNumber')->to_literal->value();
        $PX .= $travellersPnrXml->{$refNumber}->{PaxNum}.',';
      }
      foreach my $siNode (@segmentInformationNodes) {
        @segmentReferenceNodes = $siNode->findnodes('segmentReference');
        foreach my $srNode (@segmentReferenceNodes) {
          $i++;
          my $refNumber       = $srNode->find('refDetails/refNumber')->to_literal->value();
          my $currAirlineCode = $h_FV->{$refNumber}->{acCode};
          if ($i == 1) {
            $frstAirlineCode = $h_FV->{$refNumber}->{acCode};
            $h_tstNumFstAcCode->{$tstNumber} = $frstAirlineCode;
            $frstAirlineCode = $h_fvMapping->{$market}->{$frstAirlineCode} if (exists $h_fvMapping->{$market}->{$frstAirlineCode});
          } else {
            $doFXX = 1 if ($currAirlineCode ne $prevAirlineCode);
          }
          $prevAirlineCode = $currAirlineCode;
          $SG .= $h_FV->{$refNumber}->{segLine}.',';
        }
      }
      chop $SG;
      chop $PX;
      
      # ==================================================================
      # Nous devons savoir quelle est la compagnie aérienne à utiliser
      #  dans les FV s'il s'agit d'un vol transatlantique pour éviter les
      #  pénalités monétaires (ADM).
      if ($doFXX == 1) {
        $FXX .= $SG.$PX;
        debug('FXX = '.$FXX);
        $frstAirlineCode = $self->_doFXX($FXX, $pnr,$currency);
        $h_tstNumFstAcCode->{$tstNumber} = $frstAirlineCode if ($frstAirlineCode ne '');
        $frstAirlineCode = $h_fvMapping->{$market}->{$frstAirlineCode}
          if (($frstAirlineCode ne '') && (exists $h_fvMapping->{$market}->{$frstAirlineCode}));
      }
      # ==================================================================

      if ($frstAirlineCode eq '') {
        # debug('### TAS MSG TREATMENT 44 ###');
        # $pnr->{TAS_ERROR} = 44;
        # return 1;
      }
      
      # push @FV, 'FV'.$frstAirlineCode.$SG.$PX; # Commenté le 12 Janvier 2010 à la demande de Céline Perdriau
      push @FV, 'TTI/A20K'      if (($market eq 'DE') && ($frstAirlineCode eq 'AP'));
      push @FV, 'FM4'.$SG.$PX   if (($market eq 'DE') && ($frstAirlineCode eq 'AP'));
      
      #EGE-41150 RULES TAS POS PL
      push @FV, 'FM0.01'.$SG.$PX   if (($market eq 'PL') && ($frstAirlineCode eq 'SK'));
	  
	  #EGE-83047 RULES FOR TAS ES 
	  push @FV, 'FM0'.$SG.$PX   if (($market eq 'ES') && ($frstAirlineCode eq 'DY'));
	  
	  #EGE-85121 RULES FOR TAS DE 
	  push @FV, 'FM0'.$SG.$PX   if (($market eq 'DE') && ($frstAirlineCode eq 'EY'));
	  
	  #EGE-68035 RULES FOR TAS CZ 
	  push @FV, 'FM0'.$SG.$PX   if (($market eq 'CZ') && ($frstAirlineCode eq 'QS'));

	
    }

    debug('FV = '.Dumper(\@FV));
    debug('frstAirlineCode = '.$frstAirlineCode);
	
    $params->{GlobalParams}->{AirlineCode} = $frstAirlineCode;
	
    $self->_chgFv($pnr, \@FV) if (scalar @FV > 0);

  # -----------------------------------------------------------------------

  return 1;  
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# _delFV : Supprime les FV existantes.
#   07 Août 2009 - A la demande de Céline Perdriau
#     Il semble que procéder à la suppression des FV avant d'effectuer
#     les commandes FXX produit des résultats différents.
sub _delFv {
  my $self   = shift;
  my $pnr    = shift;
  my $fv     = shift;

	my $GDS    = $pnr->{_GDS};
	
	$pnr->reload;
	# $GDS->RT(PNR=>$pnr->{PNRId}, NoIG=>1);
	
  # ---------------------------------------------------------------------
  # Suppression des lignes 'FV '   
  my @linesToDelete = ();
  DATA: foreach (@{$pnr->{'PNRData'}}) {
    if (($_->{'Data'} =~ /^FV\s+(.*)$/)) {
      push(@linesToDelete, $_->{'LineNo'});
    }
  }
  foreach (sort triDecroissant (@linesToDelete)) {
    $GDS->command(Command=>'XE '.$_, NoIG=>1, NoMD=>1);
  }
  # ---------------------------------------------------------------------
  
  # ---------------------------------------------------------------------  
  # Validation des modifications
  $GDS->command(Command=>'RF'.$GDS->modifsig, NoIG=>1, NoMD=>1);
  $GDS->command(Command=>'ER',                NoIG=>1, NoMD=>1);
  $GDS->command(Command=>'ER',                NoIG=>1, NoMD=>1);
  # ---------------------------------------------------------------------  

  return 1;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# _chgFV : Applique les bons FV sur un PNR
sub _chgFv {
  my $self   = shift;
  my $pnr    = shift;
  my $fv     = shift;

	my $GDS    = $pnr->{_GDS};

  $GDS->RT(PNR=>$pnr->{PNRId}, NoIG=>1);

  # ---------------------------------------------------------------------
  # Ajout des nouvelles lignes de FV
  foreach (@$fv) {
    my $lines = $GDS->command(Command=>$_, NoIG=>1, NoMD=>1);
    if ($_ eq 'TTI/A20K') {
      if (grep(/NEED TST\/PASSENGER NUMBER/, @$lines)) {
        debug('### TAS MSG TREATMENT 39 ###');
        $pnr->{TAS_ERROR} = 39;
        return 1;
      } 
    }
  }
  # ---------------------------------------------------------------------

  # ---------------------------------------------------------------------  
  # Validation des modifications
  $GDS->command(Command=>'RF'.$GDS->modifsig, NoIG=>1, NoMD=>1);
  $GDS->command(Command=>'ER',                NoIG=>1, NoMD=>1);
  $GDS->command(Command=>'ER',                NoIG=>1, NoMD=>1);
  # ---------------------------------------------------------------------  

  return 1;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# _doFXX : Va chercher le airline code à utiliser dans la FV
sub _doFXX {
  my $self = shift;
  my $FXX  = shift;
  my $pnr  = shift;
  my $currency = shift;
  
  my $GDS  = $pnr->{_GDS};
  
  my $fxxAirlineCode = '';
  
  $GDS->RT(PNR=>$pnr->{PNRId});
  
  # ==========================================================================
  # Dans le cas de plusieurs pages, nous devons nous assurer de tout récupérer
  my $lines    = $GDS->command(Command=>$FXX, NoIG=>1, NoMD=>1);
  my $lastLine = $lines->[$#$lines];
  if ($lastLine =~ /PAGE\s*(\d)\/\s*(\d)$/) {
    my $currentPage = $1;
    my $totalPage   = $2;
    my $nbMD2do     = 0;
    $nbMD2do = $totalPage - $currentPage;
    debug('CURRENT_PAGE = '.$currentPage);
    debug('TOTAL_PAGE   = '.$totalPage);
    debug('NBMD2DO      = '.$nbMD2do);
    for (my $i = 1; $i <= $nbMD2do; $i++) {
      my $MD = $GDS->command(Command=>'MD', NoIG=>1, NoMD=>1);
      push(@$lines, @$MD);
    }
    debug('FXX = '.Dumper($lines));
  }
  # ==========================================================================
  
  my $monoFare  = 0;
  my $multiFare = 0;
  
  LINE: foreach my $line (@$lines) {

    # $$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$
    if ($line =~ /AL FLGT  BK T DATE  TIME  FARE BASIS      NVB  NVA   BG/) {
      debug('_doFXX: SIMPLE FARE PROPOSAL !');
      $monoFare = 1;
      next LINE;
    }
    if ($line =~ /FARE BASIS \*  DISC    \*  PSGR      \* FARE&lt;$currency&gt;  \* MSG  \*T/) {
      debug('_doFXX: MULTI FARE PROPOSAL !');
      $multiFare = 1;
      next LINE;
    }
    if (($line =~ /PASSENGER         PTC    NP  ATAF&lt;$currency&gt; TAX\/FEE   PER PSGR/) ||
        ($line =~ /PASSENGER         PTC    NP  FARE&lt;$currency&gt; TAX\/FEE   PER PSGR/)) {
      debug('_doFXX: MULTI PAX PROPOSAL !');
      $multiFare = 1;
      next LINE;
    }
    # $$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$
    
    debug('monoFare  = '.$monoFare);
    debug('multiFare = '.$multiFare);
    
    # $$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$
    # CAS SIMPLE DU MONOFARE
    if ($monoFare == 1) {
      if ($line =~ /^PRICED WITH VALIDATING CARRIER (\w{2})/) {
        $fxxAirlineCode = $1;
        last LINE;
      }
      last LINE if ($fxxAirlineCode ne '');
    } # Fin if ($monoFare == 1)
    # $$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$
    
    # $$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$
    # CAS PLUS DIFFICILE DU MULTIFARE ou NOFARE - FQQ
    if ($multiFare == 1) {
      # ======================================================================
      my $linesFQQ = $GDS->command(Command=>'FQQ1', NoIG=>1, NoMD=>1);
      $lastLine = $linesFQQ->[$#$linesFQQ];
      if ($lastLine =~ /PAGE\s*(\d)\/\s*(\d)$/) {
        my $currentPage = $1;
        my $totalPage   = $2;
        my $nbMD2do     = 0;
        $nbMD2do = $totalPage - $currentPage;
        debug('CURRENT_PAGE = '.$currentPage);
        debug('TOTAL_PAGE   = '.$totalPage);
        debug('NBMD2DO      = '.$nbMD2do);
        for (my $i = 1; $i <= $nbMD2do; $i++) {
          my $MD = $GDS->command(Command=>'MD', NoIG=>1, NoMD=>1);
          push(@$linesFQQ, @$MD);
        }
        debug('FQQ1 = '.Dumper($linesFQQ));
      }
      # ======================================================================
      LINEFQQ: foreach my $fqqLine (@$linesFQQ) {
        if ($fqqLine =~ /^PRICED WITH VALIDATING CARRIER (\w{2})/) {
          $fxxAirlineCode = $1;
          last LINEFQQ;
        }
        last LINEFQQ if ($fxxAirlineCode ne '');
      } # Fin LINEFQQ: foreach my $fqqLine (@$linesFQQ)
      last LINE;
    } # Fin if ($multiFare == 1)
    # $$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$

  } # Fin LINE: foreach my $line (@$lines)
  
  return $fxxAirlineCode;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Routine de Tri Des Numériques
sub triDecroissant { $b <=> $a } 
sub triCroissant   { $a <=> $b }
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

1;
