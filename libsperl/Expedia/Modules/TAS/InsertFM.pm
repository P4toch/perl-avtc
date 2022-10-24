package Expedia::Modules::TAS::InsertFM;
#-----------------------------------------------------------------
# Package Expedia::Modules::TAS::InsertFM
#
# $Id: InsertFM.pm 706 2011-07-01 09:21:10Z pbressan $
#
# (c) 2002-2008 Expedia.                   www.expediacorporate.fr
#-----------------------------------------------------------------

use strict;
use Data::Dumper;

use Expedia::Tools::Logger      qw(&debug &notice &warning &error);
use Expedia::Tools::GlobalVars  qw($h_tstNumFstAcCode $h_fvMapping $h_pcc $h_context);
use Expedia::Tools::GlobalFuncs qw(&stringGdsPaxName);
use Expedia::WS::Australia      qw(&ECTEAddCommission);

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
  my $ab           = $params->{ParsedXML};
  
  my $market       = $globalParams->{market};
        
    my $pnrdoc = $pnr->{_XMLPNR};
    my $tstdoc = $pnr->{_XMLTST};
   
   #debug("PNRDOC:".Dumper($pnrdoc));
   #debug("TSTDOC:".Dumper($tstdoc));

    my $i               = 0;
    my @FV              = ();
    my $SG              = '';
    my $PX              = '';
    my $FXX             = '';
    my $FP              = '';
    my $NBP             = '';
    my $doFXX           = 0;
    my $frstAirlineCode = ''; # First
    my $prevAirlineCode = ''; # Previous
    my $currAirlineCode = ''; # Current
    my $ValidatingCarrierCode    = '';
    my $FareType                 = '';
    my $PCC                      = $h_pcc->{$market};
    my $BookingReference         = $item->{PNR};
    my $PaxType                  = '';    
    my $FormOfPayment            = '';
       
   my @pnr_node_list2 = $tstdoc->find('//passengerData/travellerInformation/passenger/type');
  	debug('pnr_node_list2 '.Dumper(\@pnr_node_list2));
  	if (scalar(@pnr_node_list2)) {
  		foreach my $node (@pnr_node_list2) {
  			my $content = $node->to_literal->value();
  			debug("CONTENT $content");
  		}
  	}
  	
    my @fareListNodes                 = $tstdoc->getElementsByTagName('fareList');
    my @originDestinationDetailsNodes = $pnrdoc->getElementsByTagName('originDestinationDetails');
    my @dataElementsIndivNodes        = $pnrdoc->getElementsByTagName('dataElementsIndiv');
    my @segmentInformation            = $tstdoc->getElementsByTagName('segmentInformation');
    
    my @tmpNodes                = ();
    my @itineraryInfoNodes      = ();
    my @segmentInformationNodes = ();
    my @segmentReferenceNodes   = ();
    my @refDetailsNodes         = (); 
    my @city                    = ();
    my $h_FV                    = {};
    my $h_FP                    = {};
    

    my @StartCityCode;
    my @EndCityCode;
    my @MarketingAirlineCode;
    my @FareBasisCode;
    
 	  # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@   
    #RECUPERATION DE LA FORME DE PAYMENT PAR REFERENCE 

    foreach my $dNode (@dataElementsIndivNodes)
    {
        my $tmpFP = $dNode->find('elementManagementData/segmentName')->to_literal->value();
        if($tmpFP eq 'FP') #FP
        {
          $FP  = $dNode->find('otherDataFreetext/longFreetext')->to_literal->value();
          $NBP = $dNode->find('referenceForDataElement/reference/number')->to_literal->value();
          if($FP =~ /^CC/)        													{          $FP=substr($FP,2,2);        }
          if($FP =~ /NONREF/ || $FP =~ /CASH/ || $FP =~ /INV/ || $FP =~ /EC/ )      {          $FP="INV";                  }
          $h_FP->{$NBP}=$FP;
        } #FIN NODE FP 
      } #FIN NODE DATAELEMENTSINDIV
    
     debug('$h_FP = '.Dumper($h_FP));
    
    foreach my $iNode (@itineraryInfoNodes) {
      my $segName    = $iNode->find('elementManagementItinerary/segmentName')->to_literal->value();
      next unless ($segName eq 'AIR');
      my $StartCityCode         = $iNode->find('travelProduct/boardpointDetail/cityCode')->to_literal->value();
      my $EndCityCode           = $iNode->find('travelProduct/offpointDetail/cityCode')->to_literal->value();
      my $MarketingAirlineCode  = $iNode->find('travelProduct/companyDetail/identification')->to_literal->value();
      push @StartCityCode, $StartCityCode;
      push @EndCityCode, $EndCityCode;
      push @MarketingAirlineCode, $MarketingAirlineCode;
    }
         
 	  # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@   
    #RECUPERATION ET CREATION DES SEGMENTS (ATTENTION AU CHANGEMENT PAR TST ) 

    foreach my $oNode (@originDestinationDetailsNodes) {
      @tmpNodes = $oNode->getElementsByTagName('itineraryInfo');
      push @itineraryInfoNodes, $_ foreach (@tmpNodes);
    }
    
    foreach my $iNode (@itineraryInfoNodes) {
      my $segName    = $iNode->find('elementManagementItinerary/segmentName')->to_literal->value();
      next unless ($segName eq 'AIR');
      my $StartCityCode         = $iNode->find('travelProduct/boardpointDetail/cityCode')->to_literal->value();
      my $EndCityCode           = $iNode->find('travelProduct/offpointDetail/cityCode')->to_literal->value();
      my $MarketingAirlineCode  = $iNode->find('travelProduct/companyDetail/identification')->to_literal->value();
      push @StartCityCode, $StartCityCode;
      push @EndCityCode, $EndCityCode;
      push @MarketingAirlineCode, $MarketingAirlineCode;
    }

	
	  # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
	  # RECUPERATION DES INFORMATIONS PAR TST 
    # Association des numéros de passager entre le XML et le PNR
    my $travellersPnrXml = {};
    
    my @travellerInfoNodes = $pnrdoc->getElementsByTagName('travellerInfo');
    foreach my $travellerInfoNode (@travellerInfoNodes) {
      my $lastName  = $travellerInfoNode->find('passengerData/travellerInformation/traveller/surname')->to_literal->value();
      my $firstName = $travellerInfoNode->find('passengerData/travellerInformation/passenger/firstName')->to_literal->value();
      my $type      = $travellerInfoNode->find('passengerData/travellerInformation/passenger/type')->to_literal->value();
      my $number    = $travellerInfoNode->find('elementManagementPassenger/reference/number')->to_literal->value();
      $_ = stringGdsPaxName($_, $market) foreach ($firstName, $lastName);
      if(!$type){$type="ADT";}
      $travellersPnrXml->{$number}->{FIRST_NAME} = $firstName;
      $travellersPnrXml->{$number}->{LAST_NAME}  = $lastName;
      $travellersPnrXml->{$number}->{TYPE}       = $type;
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
    notice(' Association des passagers CRYPTIC et XML / travellersPnrXml = '.Dumper($travellersPnrXml));
    # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
    
    $h_tstNumFstAcCode = {};
    
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

    notice('$h_FV = '.Dumper($h_FV));

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
          my $PaxType         = $h_FV->{$refNumber}->{type};
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
        $frstAirlineCode = $self->_doFXX($FXX, $pnr);
        $h_tstNumFstAcCode->{$tstNumber} = $frstAirlineCode if ($frstAirlineCode ne '');
        $frstAirlineCode = $h_fvMapping->{$market}->{$frstAirlineCode}
          if (($frstAirlineCode ne '') && (exists $h_fvMapping->{$market}->{$frstAirlineCode}));
      }
      # ==================================================================
      
      if ($frstAirlineCode eq '') {
        debug('### TAS MSG TREATMENT 44 ###');
        $pnr->{TAS_ERROR} = 44;
        return 1;
      }

      # VALIDATING CARRIER CODE (Companie qui recoit l'argent du booking) 
  	  my $ValidatingCarrierCode=$frstAirlineCode; 
  	  debug('ValidatingCarrierCode = '.$ValidatingCarrierCode);
  	  
  	  # FARE TYPE 
  	  # I or A -> 2 (published)
  	  # F      -> 4 (private)
  	  my $tstIndicator         = $fNode->findnodes('pricingInformation/tstInformation/tstIndicator')->to_literal->value();
  	  if( ( $tstIndicator eq 'I' ) || ( $tstIndicator eq 'A') ) { $FareType=2;}
  	  if  ( $tstIndicator eq 'F' ) { $FareType=4;}
 	    debug("FareType:".$FareType);
  	  
  	  #FAREBASISCODE
  	  foreach my $sNode (@segmentInformation)
      {
         my $FareBasisCode  = $sNode->findnodes('fareQualifier/fareBasisDetails/primaryCode')->to_literal->value().$sNode->findnodes('fareQualifier/fareBasisDetails/fareBasisCode')->to_literal->value();
  	     push @FareBasisCode, $FareBasisCode;
      }
      debug('FB = '.Dumper(\@FareBasisCode));	 
      	  	  
  	  my $refNumber="";
  	  #FORM DE PAIEMENT
  	  foreach my $rNode (@refDetailsNodes) {
           $refNumber = $rNode->find('refNumber')->to_literal->value();
           debug("RefNumber:".$refNumber);
        }
  	  if(exists($h_FP->{$refNumber})) {                                           #PLUSIEURS PASSAGERS
  	    $FormOfPayment = $h_FP->{$refNumber}; 
  	    debug("FormOfPayment Multiple Passenger:".$FormOfPayment);
	  } elsif (!$NBP){$FormOfPayment = $FP;                                         #UN SEUL PASSAGER -> PAS DE LIGNE REFNUMBER DANS LE PNR XML
  	    debug("FormOfPayment Unique Passenger:".$FormOfPayment);
  	  }
  	  else
  	  { debug("Attention pas de FOP"); } 

  	  
  	  #PAXTYPE
  	  my $PaxType         = $travellersPnrXml->{$refNumber}->{TYPE};
  	  debug("PaxType:".$PaxType);
  	  
#$PaxType="";
my $tries = 0;
my $succes = 0;
my $commission = '';
my $FP_status = '';

    TRIES: while ($tries < 2) {
       $commission = ECTEAddCommission(1,'http://www.travelforce.com.au/ws/commission',  $ValidatingCarrierCode , $FareType, $PCC, $BookingReference, $FormOfPayment, $PaxType, \@StartCityCode, \@EndCityCode, \@MarketingAirlineCode, \@FareBasisCode);

        if($commission=~/^KOFONC/)
        {
                notice($commission);
                $pnr->{TAS_ERROR} = 67;
                return 1;
        }
        elsif($commission=~/^KOTECH/)
        {
                notice($commission);
                $succes = 0;
        }
        else
        {
                notice("Commission:".$commission);
                $succes = 1;

        }

      if ($succes == 0) {
        $tries++;
        sleep 10;
      }
      else {
        $succes = 1;
        last TRIES;
      }
    }

if($succes == 0)
{
        notice("WS AU doesn't response");
        $pnr->{TAS_ERROR} = 67;
        return 1;
}

$tries= 0;
$succes = 0;

#$FareType='';
#$FormOfPayment='';
    TRIES2: while ($tries < 2) {
       $FP_status = ECTEAddCommission(2,'http://www.travelforce.com.au/ws/commission',  $ValidatingCarrierCode , $FareType, $PCC, $BookingReference, $FormOfPayment, $PaxType, \@StartCityCode, \@EndCityCode, \@MarketingAirlineCode, \@FareBasisCode);

#$FP_status="OK;false";

        if($FP_status=~/^KOFONC/)
        {
                notice($FP_status);
                $pnr->{TAS_ERROR} = 68;
                return 1;
        }
        elsif($FP_status=~/^KOTECH/)
        {
                notice($FP_status);
                $succes = 0;
        }
        else
        {
                notice("VALID FOP:".$FP_status);
                $succes = 1;

        }

      if ($succes == 0) {
        $tries++;
        sleep 10;
      }
      else {
        $succes = 1;
        last TRIES2;
      }
    }

if($succes == 0)
{
        notice("WS AU doesn't response");
        $pnr->{TAS_ERROR} = 68;
        return 1;
}

        my @FP_status = ();
        my @commission = ();

       @FP_status  = split(';',$FP_status);
       @commission = split(';',$commission);

        $FP_status = @FP_status->[1];
        $commission = @commission->[1];

      #SI LE WS RENVOI FALSE ALORS PAS D'AJOUT DE FM
      if($FP_status eq "true")
      {       push @FV, 'FM'.$commission.$SG.$PX;      }
      else{
       # push @FV, 'FM0'.$SG.$PX;
        notice("FOP Invalide -- Pas de COMMISSION pour:".$SG.$PX);}

  } #FIN TST

  notice('FM = '.Dumper(\@FV));

  $self->_chgFv($pnr, \@FV) if (scalar @FV > 0);

  return 1;  
} #FIN RUN
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
    $GDS->command(Command=>$_, NoIG=>1, NoMD=>1);
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
