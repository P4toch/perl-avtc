package Expedia::Modules::TAS::DoTkt;
#-----------------------------------------------------------------
# Package Expedia::Modules::TAS::DoTkt
#
# $Id: DoTkt.pm 663 2011-04-12 13:33:45Z pbressan $
#
# (c) 2002-2008 Expedia.                   www.expediacorporate.fr
#-----------------------------------------------------------------

use strict;
use Data::Dumper;
use Clone qw(clone);

use Expedia::WS::Commun         qw(&isAuthorize &ticketingIssue &quality_control_service &isAuthorize_repricing);
use Expedia::WS::Back           qw(&BO_GetBookingFormOfPayment);
use Expedia::Tools::Logger      qw(&debug &notice &warning &error &monitore);
use Expedia::XML::MsgGenerator;

use Expedia::Tools::GlobalVars  qw($h_context $h_tstNumFstAcCode $h_fvMapping $h_tarifExpedia $N1111 $quality_control_serviceURL);
use Expedia::Tools::GlobalFuncs qw(&stringGdsPaxName &getRTUMarkup &check_TQN_markup);
use Expedia::Tools::TasFuncs         qw(&getCurrencyForTas);
use Expedia::Databases::Payment qw(&getCreditCardData);
use Expedia::Databases::MidSchemaFuncs  qw(&getFpec);


# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Variables globales pour tout ce module
my $currency  = undef;
my $ttp_code  = '';
my $maxTstNum = 0;
our %h_refTST  = ();
our %h_YR      = ();
our %h_FOP     = ();
our %h_pax = ();
our %h_segment = ();
our %h_OBFEES = ();
our %h_original_amount = ();
our %h_new_amount = ();
our %h_variation_amount = ();	
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
sub run {
  my $self   = shift;
  my $params = shift;

  my $globalParams 	= $params->{GlobalParams};
  my $moduleParams 	= $params->{ModuleParams};
  my $changes      	= $params->{Changes};
  my $item         	= $params->{Item};
  my $pnr          	= $params->{PNR};
  my $GDS          	= $params->{GDS};
  my $ab           	= $params->{ParsedXML};

  my $h_pnr        	= $params->{Position};
  my $refpnr       	= $params->{RefPNR};
  my $position     	= $h_pnr->{$refpnr};
  
  my $market    	= $globalParams->{market};
  notice("market:".$market);
  my $list_yr      	= $globalParams->{TASYR};
  my $list_fpec    	= $globalParams->{FPEC};
       
  my $atds 			= $ab->getTravelDossierStruct;    
  my $comCode 		= $ab->getPerComCode ({trvPos => $ab->getWhoIsMain});
  my $tpid 			= $ab->getTpid ({trvPos => $ab->getWhoIsMain});
  my $gpid 			= $ab->getGpid({trvPos => $ab->getWhoIsMain});

  my $reprice       = 0;
  
   	if ((!exists $item->{TASK}) || ($item->{TASK} !~ /^tas-air-etkt|tas-air-paper$/)) {
   	  warning('run: no Valid Task param provided = '.$item->{TASK});
   	  return 0;
   	}
   	
   	my $task = $item->{TASK};
   	debug('Task = '.$task);

  	$GDS->RT(PNR => $pnr->{PNRId});
  	
    my $tstdoc  = $pnr->{_XMLTST};
          
  	# -----------------------------------------------------------------------
  	my $printer = ''; # Nouvelles imprimantes ATB - 02 Avril 2007
  	my $special = ''; # Spécifique TTP pour la Belgique
  	# -----------------------------------------------------------------------
  	
  	# -----------------------------------------------------------------------
  	# CURRENCY qui va être utilisée EUR ou GBP et spécificité GB KA4439
    $currency = &getCurrencyForTas($market); #$moduleParams->{currency};
    #$ttp_code = $moduleParams->{ttp_code} if (exists($moduleParams->{ttp_code}));
    $ttp_code =""; #TODO TOREMOVE JE TEST POUR VOIR SI CETTE VARIABLE A ENCORE UN SENS
    #notice("RES:".Dumper(@finalRes));
    $ttp_code = '' if ($GDS->saipem);
    $ttp_code = '' if ($GDS->psa1);
    
    #$ttp_code='EG3978';
    
    debug('CURRENCY = '.$currency);
    debug('TTP_CODE = '.$ttp_code);
    # -----------------------------------------------------------------------

  	my $tstNumber = 0;
  	my @TTPNums   = ();

	#only for QCS logs 
  	my @tst_node_list = $tstdoc->getElementsByTagName('fareList');
  	debug('nbOfTsts  = '.scalar(@tst_node_list));
  	foreach (@tst_node_list) {
  	  $tstNumber = $_->find('fareReference/uniqueReference')->to_literal->value();
  	  debug('TSTNum = '.$tstNumber);
  	  push(@TTPNums, $tstNumber);
	  
		#for logs in repricing 
		my $lines = $GDS->command(Command=>"TQT/T$tstNumber", NoIG=>1, NoMD=>1);
		my $tmp_fp = '';
		foreach (@$lines)
		{
			if ($_ =~ /^FX\w{1}(\/\s*R,U[^\/]*)?($|(\/S(\d{2})(-|,)?(\d{2})?)?(\/.*)?)$/ || $_ =~ /^FXP/ || $_ =~ /^FXA/ ) 
			{ 
				if($2 ne '')
				{
					my @tmp_split = split(/\//, $2);
					notice("tst:".$tstNumber." segment:".$tmp_split[0]." pass:".$tmp_split[1]);
					$h_segment{$tstNumber}=$tmp_split[0];
					$h_pax{$tstNumber}=$tmp_split[1];
				}
				else
				{
					$h_segment{$tstNumber}=1;
					$h_pax{$tstNumber}=1;
				}
			}
		
			if($_ =~/FP (.*)/) { $tmp_fp = "FP".$1; $tmp_fp =~ s/\s+//g; $h_FOP{$tstNumber}=$1;   }

		}
		
		$h_refTST{$tstNumber}				=$tstNumber;
		$h_YR{$tstNumber}					='false';
		$h_OBFEES{$tstNumber}				='false';
		$maxTstNum = $tstNumber if ($tstNumber > $maxTstNum);
  	}	
  	debug('maxTstNum = '.$maxTstNum);

  	my $command; my $lines_tkt = '';

  	my $countryCode = $ab->getCountryCode({trvPos => $ab->getWhoIsMain});
  	debug('countryCode = '.$countryCode);
  	$pnr->{market} = $countryCode;

  
	#QUALITY-CONTROL-SERVICE   
	my $isAuth   = isAuthorize_repricing('quality-control-service.activation', $tpid, $comCode) ;
	my $response = '';
	my $account_code = &getPnrOnlinePricing($pnr);
	debug("account_code before split:".$account_code);
	my @tmp_account_code = split(/\//,$account_code);
	$account_code=$tmp_account_code[1];
	notice("account_code:".$account_code);
	debug("auth to qcs:".$isAuth);
	if($isAuth && $isAuth ne '')
	{
		$response = quality_control_service($pnr->{PNRId}, $tpid, $comCode, $account_code);
		notice("RESPONSE QCS:".Dumper($response));
		
		#ON RECHARGE LE DOSSIER POUR REFAIRE UNE PASSE SUR LES TTS
		$GDS->RT(PNR => $pnr->{PNRId});
	  
		$pnr->getXML($tpid);
		  
		$tstdoc  = $pnr->{_XMLTST};
		
		@tst_node_list = ();
		$tstNumber = 0;
		@TTPNums   = ();
		
		#ON RECUPERE LA FARELIST
		@tst_node_list = $tstdoc->getElementsByTagName('fareList');
		debug('do TTP : number of fare list : '.scalar(@tst_node_list));

		#ON REPARCOURS LA LISTE DES TST (@TTPNums)
		foreach (@tst_node_list) {
		  $tstNumber = $_->find('fareReference/uniqueReference')->to_literal->value();
		  debug('TSTNum = '.$tstNumber);
		  push(@TTPNums, $tstNumber);
		}
  
	}
	else
	{
		notice("NO CALL TO QCS");
	}
		

  
	#------------------------------------------------------------------------
	# Check if the customer is ON ACCOUNT (on a defined list in TASYR table) , if yes, then reprice and add a ",ET-YR" command
	if(scalar(@$list_yr) ne 0)
	{
		my $tmp_fp = '';
		my $tmp_fv = '';
		my $do_fp_reprice = 0;
		my $do_fv_reprice = 0;

		foreach (sort triCroissant (@TTPNums)) 
		{
			my $lines = $GDS->command(Command=>"TQT/T$_", NoIG=>1, NoMD=>1);
			foreach (@$lines)
			{
				if($_ =~/FP (.*)/) { $tmp_fp = "FP".$1; $tmp_fp =~ s/\s+//g; }
				if($_ =~/FV (.*)/) { $tmp_fv = $1; $tmp_fv =~ s/\s+//g; }
			}

			foreach (@$list_yr)
			{
				if($_->[0] eq $tmp_fv) { $do_fv_reprice=1; last;}
				else{ $do_fv_reprice = 0; }
			}
			
			foreach (@$list_fpec)
			{
				if($_->[0] eq $tmp_fp) { $do_fp_reprice=1; last;}
				else{ $do_fp_reprice = 0; }
			}

			if($do_fp_reprice == 1 && $do_fv_reprice == 1 ) 
			{
				my  $add_yr=",ET-YR";
				notice("DOReprIce");
				$reprice=1;
				$h_YR{$_}=1; 
				my $ttp_res = $self->_reprice($pnr, $_, $printer, $task, $GDS, $ab, $position,$currency,$add_yr);
				notice("TTP RES:".$ttp_res);
			}
		}

		$GDS->RT(PNR => $pnr->{PNRId});
		$pnr->getXML($tpid);
		$tstdoc  = $pnr->{_XMLTST};
		@tst_node_list = ();
		$tstNumber = 0;
		@TTPNums   = ();

		#ON RECUPERE LA FARELIST
		@tst_node_list = $tstdoc->getElementsByTagName('fareList');
		debug('do TTP : number of fare list : '.scalar(@tst_node_list));

		#ON REPARCOURS LA LISTE DES TST (@TTPNums)
		foreach (@tst_node_list) {
		  $tstNumber = $_->find('fareReference/uniqueReference')->to_literal->value();
		  debug('TSTNum = '.$tstNumber);
		  push(@TTPNums, $tstNumber);
		}
		
	}
	
  	# -----------------------------------------------------------------------
    #BUG 16312 FOR NL TICKETING -- CHANGE THE FV LINE IF AF TO KL
    if($countryCode eq 'NL')
    {
    foreach (@{$pnr->{'PNRData'}}) {

  		my $lineData = uc $_->{'Data'};
  		my $lineNumb = $_->{'LineNo'};

  		if ($lineData =~ /^FV\s+(?:(?:PAX|INF)\s+)?(?:\*\w\*)?(AF)/) {  			
  				debug('LIGNE '.$lineNumb.' = '.$lineData);
  				$command=$lineNumb."/KL";
  				$GDS->command(Command => $command, NoIG => 1, NoMD => 1);
  				$GDS->command(Command => 'RFBTCTAS', NoIG => 1, NoMD => 1);
  				$GDS->command(Command => 'ER', NoIG => 1, NoMD => 1);
  		}  	
    }}
  	# -----------------------------------------------------------------------
  	
  	$pnr =$self->simplification_iep(\@TTPNums,$GDS,$pnr,$task,$countryCode,$command,$ttp_code,$comCode,$globalParams->{product},0,$tpid,$gpid);
    
    # _____________________________________________________________________________
    # Bizarre, comment le TQT/T1 pouvait marcher lorsque le TTP/T(1+N) = OK ETICKET
    #  et le TTP/T1 est en TST EXPIRED.
    $GDS->RT(PNR => $pnr->{PNRId});
    # _____________________________________________________________________________
    my $ttp_res = [];
    
  	foreach my $uniqueRef (sort triCroissant (keys %{$pnr->{TTP}})) {

  	  $ttp_res = $pnr->{TTP}->{$uniqueRef};

  	  $ttp_res = $self->_chgFop($pnr, $uniqueRef, $printer, $task, $GDS, $ab)
  	    if ( (grep(/FP NOT ALLOWED FOR NEGOTIATED FARE/,@$ttp_res)) ||
  	         (grep(/CREDIT CARD NOT ACCEPTED BY TICKETING AIRLINE/,@$ttp_res)) );
  	  
  	    if ( (grep(/TST PERIME/,         @$ttp_res)) 						||
  	         (grep(/TST EXPIRED/,        @$ttp_res)) 						||
  	         (grep(/TST VENCIDO/,        @$ttp_res)) 						||
  	         (grep(/PLEASE REPRICE/,     @$ttp_res)) 						||
  	         (grep(/VUELVA A TARIFICAR/, @$ttp_res)) 						||
  	         (grep(/VEUILLEZ RETARIFER/, @$ttp_res)) 						||
  	         (grep(/TST PRICING CONTEXT MODIFIED/, @$ttp_res)) 				||
  	         (grep(/CONTEXTE TARIF TST MODIFIE/, @$ttp_res)) 				||
  	         (grep(/CONTEXTO TARIF. TST MODIFICADO/, @$ttp_res)) 			||
  	         (grep(/CONTEXTO DE TARIFICACION DE TST MODIFICADO/, @$ttp_res))||
			 (grep(/LAST TIME TO TICKET IS PAST/, @$ttp_res )) 				||
			 (grep(/CHANGEMENT D.*ITINERAIRE/,@$ttp_res))					||
			 (grep(/ITINERARY\/NAME CHANGE-VERIFY TST/,@$ttp_res))			||
			 (grep(/CAMBIO DE ITINERARIO/,@$ttp_res))   	        		)
		{
			$ttp_res = $self->_reprice($pnr, $uniqueRef, $printer, $task, $GDS, $ab, $position,$currency);
			$reprice=1;
		}

      ######################################################################################
      #DEBUT DU NOUVEAU CODE 
  	}
  	
	#the repricing have been made ( or not) , we will not store the logs 
	if($reprice == 1 )
	{
	
	  # Check the number of pax
		my $nb_pax = scalar(@{$pnr->{'PAX'}}); 
		my $nb_tst = scalar(@tst_node_list);  		
		my $ligne_tst = '';
		my $x=0;
		
		for($x=$tst_node_list[0];$x<=$maxTstNum;$x++)
		{
		    if(exists($h_refTST{$x}))
			{
				$ligne_tst .=  "{    'tst_reference' : ".$x.",    'nb_pax' : ".$h_pax{$x}.",    'nb_segment' : ".$h_segment{$x}.",     'form_of_payment' : '".$h_FOP{$x}."',    'yr_mode' : ".$h_YR{$x}.",    'ob_fees' : ".$h_OBFEES{$x}.",    'fare_basis_list' : [ ],    'original_tstamount' : ".$h_original_amount{$x}.",    'new_tstamount' : ".$h_new_amount{$x}.",    'amount_variation' : ".$h_variation_amount{$x}."  } ";
				$ligne_tst .= " , ";
			}
		}
		
		my $success='SUCCESS';
		if (exists($pnr->{TAS_ERROR}) && (defined $pnr->{TAS_ERROR})) 
		{
			$success='ERROR';
		}
		
		my $logs=" {  'status' : '".$success."',  'nb_tst' : ".$nb_tst.",  'nb_pax' : ".$nb_pax.",  'tst_logs' : [ ".$ligne_tst." ]}";
		notice("logs to kibana:".$logs); 
		
		&monitore("TAS_TICKETING", 'REPRICING', $success, $countryCode, "AIR" , $pnr->{PNRId}, "" , $logs);

						
	}
	
  	return 1 if (exists($pnr->{TAS_ERROR}) && (defined $pnr->{TAS_ERROR}));
  	 
	  #ON RECHARGE LE DOSSIER POUR REFAIRE UNE PASSE SUR LES TTS
	  $GDS->RT(PNR => $pnr->{PNRId});
	  
	  $pnr->getXML($tpid);
	  
    $tstdoc  = $pnr->{_XMLTST};
    
    @tst_node_list = ();
    $tstNumber = 0;
  	@TTPNums   = ();
  	
  	#ON RECUPERE LA FARELIST
  	@tst_node_list = $tstdoc->getElementsByTagName('fareList');
  	debug('do TTP : number of fare list : '.scalar(@tst_node_list));

    #ON REPARCOURS LA LISTE DES TST (@TTPNums)
  	foreach (@tst_node_list) {
  	  $tstNumber = $_->find('fareReference/uniqueReference')->to_literal->value();
  	  debug('TSTNum = '.$tstNumber);
  	  push(@TTPNums, $tstNumber);
  	}
  
    # POUR CHAQUE TST ON EMETS LE BILLET (si ce n'est pas déjà fait) 
	$pnr =$self->simplification_iep(\@TTPNums,$GDS,$pnr,$task,$countryCode,$command,$ttp_code,$comCode,$globalParams->{product},1,$tpid,$gpid); # UNLESS CONDITION
    
    my $do_fop = 0; my $do_srfoid = 0; my $do_fv = 0;
          
    $ttp_res = [];
    
  	foreach my $uniqueRef (sort triCroissant (keys %{$pnr->{TTP}})) {

  	  $ttp_res   = $pnr->{TTP}->{$uniqueRef};

      # TODO Déplacer plus bas. C'est deja presents plus bas.
  	  $ttp_res   = $self->_chgFop($pnr, $uniqueRef, $printer, $task, $GDS, $ab)
  	    if ( (grep(/FP NOT ALLOWED FOR NEGOTIATED FARE/,@$ttp_res)) ||
  	         (grep(/CREDIT CARD NOT ACCEPTED BY TICKETING AIRLINE/,@$ttp_res)) );
  
    
     ######################################################################################
     ######FIN DU NOUVEAU CODE  
              
  		$do_fop    = 1 if (grep(/MODE DE PAIEMENT NECESSAIRE/,@$ttp_res));
  		$do_fop    = 1 if (grep(/NEED FORM OF PAYMENT/,@$ttp_res));
  	  $do_fop    = 1 if (grep(/SE REQUIERE FORMA DE PAGO/,@$ttp_res));
  		
  		$do_srfoid = 1 if (grep(/ID ENREGISTREMENT AEROPORT MANQUANT OU INC/,@$ttp_res));
  		$do_srfoid = 1 if (grep(/SSRFOID OBLIGATOIRE/,@$ttp_res));
  		$do_srfoid = 1 if (grep(/SSRFOID MISSING/,@$ttp_res));
  		$do_srfoid = 1 if (grep(/SSRFOID OBLIGATORIO/,@$ttp_res));
  		$do_srfoid = 1 if (grep(/ID VENDEUR INCORRECT/,@$ttp_res));
  		$do_srfoid = 1 if (grep(/MANDATORY SSRFOID MISSING FOR CARRIER/,@$ttp_res));
  		$do_srfoid = 1 if (grep(/MISSING OR INVALID AIRPORT CHECK-IN ID/,@$ttp_res));
  		
  		$do_fv     = 1 if (grep(/COMPAGNIE EMETTRICE ERRONEE- RESSAISIR ELEMENT FV/,@$ttp_res));
  		$do_fv     = 1 if (grep(/INVALID TICKETING CARRIER/,@$ttp_res));
  		$do_fv     = 1 if (grep(/PROHIBITED TICKETING CARRIER/,@$ttp_res));
  		$do_fv     = 1 if (grep(/INVALID AIRLINE DESIGNATOR\/VENDOR SUPPLIER/,@$ttp_res));
  		$do_fv     = 1 if (grep(/SE REQUIERE LA COMPANA AEREA EMISORA/,@$ttp_res));

  	  $ttp_res   = $self->_chgFop($pnr, $uniqueRef, $printer, $task, $GDS, $ab)
  	    if ( (grep(/FP NOT ALLOWED FOR NEGOTIATED FARE/,@$ttp_res)) ||
  	         (grep(/CREDIT CARD NOT ACCEPTED BY TICKETING AIRLINE/,@$ttp_res)) );

  	}	
  	
  	return 1 if (exists($pnr->{TAS_ERROR}) && (defined $pnr->{TAS_ERROR}));
  
    # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
    # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
    # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
    
    # =====================================================================================
    # FOP (lorsqu'elle est manquante)
    if ($do_fop == 1) {
    	debug('# DO FOP');
    	
    	$GDS->RT(PNR => $pnr->{PNRId}, NoPostIG => 1, NoMD => 1);
    
    	$do_fop    = 0;
    	my $addFop = $self->_addFop($pnr, $ab, $GDS, $position,$globalParams);
    	debug('addFop = '.$addFop);
    
    	if ($addFop == 1) {
    	
      	$GDS->command(Command => 'RF'.$GDS->modifsig, NoIG => 1, NoMD => 1);
      	$GDS->command(Command => 'ER', NoIG => 1, NoMD => 1);
      	$GDS->command(Command => 'ER', NoIG => 1, NoMD => 1);
      	
		
		$pnr =$self->simplification_iep(undef,$GDS,$pnr,$task,$countryCode,$command,$ttp_code,$comCode,$globalParams->{product},1,$tpid,$gpid); # UNLESS CONDITION # Without giving @TTPNums because looping on keys %$pnr->{TTP}
		
      	 
      	foreach my $ttp_res (values %{$pnr->{TTP}}) {
      		$do_srfoid = 1 if (grep(/ID ENREGISTREMENT AEROPORT MANQUANT OU INC/,@$ttp_res));
      		$do_srfoid = 1 if (grep(/SSRFOID OBLIGATOIRE/,@$ttp_res));
      		$do_srfoid = 1 if (grep(/ID VENDEUR INCORRECT/,@$ttp_res));	
      		$do_srfoid = 1 if (grep(/SSRFOID MISSING/,@$ttp_res));
      		$do_srfoid = 1 if (grep(/SSRFOID OBLIGATORIO/,@$ttp_res));
      		$do_srfoid = 1 if (grep(/MISSING OR INVALID AIRPORT CHECK-IN ID/,@$ttp_res));
      		
  		    $do_fv     = 1 if (grep(/COMPAGNIE EMETTRICE ERRONEE- RESSAISIR ELEMENT FV/,@$ttp_res));
  		    $do_fv     = 1 if (grep(/INVALID TICKETING CARRIER/,@$ttp_res));
  		    $do_fv     = 1 if (grep(/PROHIBITED TICKETING CARRIER/,@$ttp_res));
  		    $do_fv     = 1 if (grep(/INVALID AIRLINE DESIGNATOR\/VENDOR SUPPLIER/,@$ttp_res));
  		    $do_fv     = 1 if (grep(/SE REQUIERE LA COMPANA AEREA EMISORA/,@$ttp_res));
      	}
    	
    	} # Fin if ($addFop == 1)
    	
    } # Fin if ($do_fop == 1)
    # =====================================================================================
    
    # =====================================================================================
    # SRFOID
    if ($do_srfoid == 1) {
    	debug('# DO SRFOID');
    
      $do_srfoid = 0;
    
    	$GDS->RT(PNR => $pnr->{PNRId}, NoPostIG => 1, NoMD => 1);
    
    	$self->_srfoid($pnr, $ab, $GDS, $position);
    	
      $GDS->command(Command => 'RF'.$GDS->modifsig, NoIG => 1, NoMD => 1);
    	$GDS->command(Command => 'ER', NoIG => 1, NoMD => 1);
    	$GDS->command(Command => 'ER', NoIG => 1, NoMD => 1);
    
		$pnr =$self->simplification_iep(undef,$GDS,$pnr,$task,$countryCode,$command,$ttp_code,$comCode,$globalParams->{product},1,$tpid,$gpid); # UNLESS CONDITION # Without giving @TTPNums because looping on keys %$pnr->{TTP}
    	
    	foreach my $ttp_res (values %{$pnr->{TTP}}) {
  		  $do_fv   = 1 if (grep(/COMPAGNIE EMETTRICE ERRONEE- RESSAISIR ELEMENT FV/,@$ttp_res));
  		  $do_fv   = 1 if (grep(/INVALID TICKETING CARRIER/,@$ttp_res));
  		  $do_fv   = 1 if (grep(/PROHIBITED TICKETING CARRIER/,@$ttp_res));
  		  $do_fv   = 1 if (grep(/INVALID AIRLINE DESIGNATOR\/VENDOR SUPPLIER/,@$ttp_res));
  		  $do_fv   = 1 if (grep(/SE REQUIERE LA COMPANA AEREA EMISORA/,@$ttp_res));
    	}
    }
    # =====================================================================================
    
    # =====================================================================================
    # FV (lorsqu'elle est erronée suite à un repricing) - Le repricing supprime la bonne
    #  information qui avait été mis en AutomaticFV
    if ($do_fv == 1) {
      debug('# DO FV');
    
      $do_fv = 0;
  
      $pnr->reload;
      # $GDS->RT(PNR=>$pnr->{PNRId}, NoIG=>1);
      
      my $commands = {};
            
      foreach (@{$pnr->{'PNRData'}}) {
  
    		my $lineData = uc $_->{'Data'};
    		my $lineNumb = $_->{'LineNo'};
  
    		if ($lineData =~ /^FV\s+(.*)$/) {
    			if (($lineData =~ /^FV\s+(\w{2})$/) ||
    			    ($lineData =~ /^FV\s+(?:(?:PAX|INF)\s+)?(?:\*\w\*)?(\w{2})\/S(?:\d+(?:,|-|\/|$))+/)) {
    				debug('LIGNE '.$lineNumb.' = '.$lineData);
    				my $airCompanyCode = $1;
    				debug('AirCompanyCode = '.$airCompanyCode);
    				$commands->{$lineNumb} = $h_fvMapping->{$countryCode}->{$airCompanyCode}
    				 if (exists $h_fvMapping->{$countryCode}->{$airCompanyCode});
    			}
          else {
            notice('WARNING: FV line does not match regexp [...]');
            notice($lineData);
          }
    		} else { next; }
    	
      } # Fin foreach (@{$pnr->{'PNRData'}})

    	if (scalar(keys %{$commands}) > 0) {
    
    		foreach (sort triDecroissant (keys %{$commands})) {
    			$command = $_.'/'.$commands->{$_};
    			$GDS->command(Command => $command, NoIG => 1, NoMD => 1);
    		}
    		$GDS->command(Command => 'RF'.$GDS->modifsig, NoIG => 1, NoMD => 1);
    		$GDS->command(Command => 'ER', NoIG => 1, NoMD => 1);
    		$GDS->command(Command => 'ER', NoIG => 1, NoMD => 1);
    
			$pnr =$self->simplification_iep(undef,$GDS,$pnr,$task,$countryCode,$command,$ttp_code,$comCode,$globalParams->{product},1,$tpid,$gpid); # UNLESS CONDITION # Without giving @TTPNums because looping on keys %$pnr->{TTP}
  
      } # Fin if (scalar(keys %{$commands}) > 0)
    
    }
    # =====================================================================================
    
    # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
    # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
    # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

  return 1;  
} # END OF THE RUN PROCESS
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# GLOBAL REPRICING PROCESS
sub _reprice {
  my $self      = shift;
  my $pnr       = shift;
  my $uniqueRef = shift;
  my $printer   = shift;
  my $task      = shift;
  my $GDS       = shift;
  my $ab        = shift;
  my $position  = shift;
  my $currency  = shift;
  my $YR		= shift;
	
  if (!$pnr || !$uniqueRef || !$task) {    
    warning('run_reprice: Missing parameter.');
	  $pnr->{TAS_ERROR} = 8;
		debug('### TAS MSG TREATMENT 8 ###');
    return [];
  }
  
  $printer = ''; # Nouvelles imprimantes ATB - 02 Avril 2007

  notice('TST not valid. TAS will try to reprice !');

  my $market   = $ab->getCountryCode({trvPos => $ab->getWhoIsMain});
  
  my $retryNeeded = 0;
  my $retryNumberMax = 1;
  
  RETRY: for (my $retryNumber = 0;
              $retryNumber == 0 ||
              ($retryNeeded && $retryNumber <= $retryNumberMax);
              $retryNumber++) {
    
    if ($retryNeeded) {
      $retryNeeded = 0;
      notice('Reprice retry '.$retryNumber);
      sleep(5);
      $GDS->RT(PNR => $pnr->{PNRId});
    }
    
    my $fareList = &getFareList($pnr, $uniqueRef, $market);

    my $lines = $GDS->command(Command=>"TQT/T$uniqueRef", NoIG=>1, NoMD=>1);
    debug('AFFICHAGE DE LA TROISIEME LIGNE : '.$lines->[2]) if (defined $lines->[2]);
    debug('AFFICHAGE DE LA PREMIRE LIGNE : '.$lines->[0]) if (defined $lines->[0]);
    
    # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
    # Refonte de la gestion des Retarifications (TAS MANCHESTER)
    # ----------------------------------------------------------------------------------
    my $fareType    = $self->getFareType($ab, $position);
    my $corporateId = $self->getCorporateId($ab, $position);

    &setNewPrice($pnr, $fareList, $uniqueRef, $lines->[2], $corporateId, $fareType, $GDS, $ab, $position,$lines->[0],$currency,$YR);
    return ['TST PERIME - IGNORER, SUPPRIMER OU RETARIFER']
      if (exists($pnr->{TAS_ERROR}) && (defined $pnr->{TAS_ERROR}));
    # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
    
    # ------------------------------------------------------------------
    # Si le process a correctement repricé, on valide les modifications.
    # Sinon on annule et on sort la TAS_ERROR.
    if (&checkFareList($pnr, $fareList)) {
      notice('TAS will confirm reprice modifications.');
      
      # ------------------------------------------------------------
      # $GDS->command(Command=>'IR', NoIG=>1, NoMD=>1);
      # return ['TST PERIME - IGNORER, SUPPRIMER OU RETARIFER'];
      # ------------------------------------------------------------    
      
      $GDS->command(Command=>'RF'.$GDS->modifsig, NoIG=>1, NoMD=>1);
      my $ER = $GDS->command(Command=>'ER', NoIG=>1, NoMD=>1);
      foreach my $ERline (@$ER) {
        if (($ERline =~ /AVERTISSEMENT : VERIF\. CONTINUITE SEGMENT/)         ||
            ($ERline =~ /WARNING: CHECK SEGMENT CONTINUITY/)                  || # Language english
            ($ERline =~ /AVERTISSEMENT : VERIFIER LE CODE D'ETAT OSI\/SSR/)   ||
            ($ERline =~ /WARNING: CHECK OSI\/SSR STATUS CODE/)                || # Language english
            ($ERline =~ /AVERTISSEMENT: VERIFIER LE STATUT DE L\'ITINERAIRE/) ||
            ($ERline =~ /REQUIRES TICKET ON OR BEFORE/)                       ||
            ($ERline =~ /AVERTISSEMENT : VERIF\. SEGMENT - ARRIVEE\/DEPART/)  ||
            ($ERline =~ /AVISO\s*:\s*VERIFIQUE EL CODIGO DE ESTADO OSI\/SSR/) ||
            ($ERline =~ /AVISO\s*:\s*VERIFIQUE EL SEGMENTO DE CONTINUIDAD/)) {
          $GDS->command(Command=>'ER', NoIG=>1, NoMD=>1);
        } elsif (($ERline =~ /VERIFIER HEURE MINI DE CORRESPONDANCE/) ||
                 ($ERline =~ /CHECK MINIMUM CONNECTION TIME/)         ||
                 ($ERline =~ /VERIFIQUE EL TIEMPO DE CONEXION MINIMA/)) {
          $pnr->{TAS_ERROR} = 10;
          return ['VERIFIER HEURE MINI DE CORRESPONDANCE'];
        } elsif (($ERline =~ /CHANGEMENTS SIMULTANES PNR/)  ||
                 ($ERline =~ /SIMULTANEOUS CHANGES TO PNR/) ||
                 ($ERline =~ /CAMBIOS SIMULTANEOS A PNR/)) {
          notice('Simultaneous changes detected');
          $retryNeeded = 1;
          next RETRY;
        } elsif ($ERline =~ /^--- TST/) {
          last;
        } else {
          notice('_reprice: Réponse commande ER = '.$ERline);
          last;
        }
      }
    }
    
  }
  
  sleep(1);
    
  return [];
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# _simulChange : Effectue un RT et relance l'ordre de TTP lorsque les
#                message suivants sont rencontres apres un TTP
#   'CHANGEMENTS SIMULTANES PNR'
#   'SIMULTANEOUS CHANGES TO PNR'
sub _simulChange {
  my $self      = shift;
  my $pnr       = shift;
  my $GDS       = shift;
	my $TTP       = shift;

	my $lines_tkt = ['SIMULTANEOUS CHANGES TO PNR'];

	while ((grep(/CHANGEMENTS SIMULTANES PNR/,  @$lines_tkt)) ||
				 (grep(/SIMULTANEOUS CHANGES TO PNR/, @$lines_tkt)) ||
				 (grep(/CAMBIOS SIMULTANEOS A PNR/,   @$lines_tkt)) ) {
		notice('Simultaneous changes detected. Retry [...]');
	  sleep 5;
	  $GDS->RT(PNR => $pnr->{PNRId}, NoPostIG => 1, NoMD => 1);
		$lines_tkt = $GDS->command(Command => $TTP, NoIG => 1, NoMD => 1);
	}

	return $lines_tkt;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# _chgFop : Change le moyen de paiement dans le dossier par FP EC
#           lorsque les messages ci dessous sont rencontrés :
#  " FP NOT ALLOWED FOR NEGOTIATED FARE "
#  " CREDIT CARD NOT ACCEPTED BY TICKETING AIRLINE "
sub _chgFop {
  my $self      = shift;
  my $pnr       = shift;
  my $uniqueRef = shift;
  my $printer   = shift;
  my $task      = shift;
  my $GDS       = shift;
  my $ab        = shift;
  
  $printer    = ''; # Nouvelles imprimantes ATB - 02 Avril 2007
  my $comCode = $ab->getPerComCode ({trvPos => $ab->getWhoIsMain});
  
  notice('TAS will change FPCC to FPEC !');
  
  $pnr->reload;
  # $GDS->RT(PNR=>$pnr->{PNRId}, NoIG=>1);
  
  # Check the number of pax
  my $nb_pax = scalar(@{$pnr->{'PAX'}});

  # ---------------------------------------------------------------------
  # Suppression des lignes 'FP '   
  my @linesToDelete = ();
  DATA: foreach (@{$pnr->{'PNRData'}}) {
    if (($_->{'Data'} =~ /^FP /)) {
      push(@linesToDelete, $_->{'LineNo'});
    }
  }
  foreach (sort triDecroissant (@linesToDelete)) {
    $GDS->command(Command=>'XE '.$_, NoIG=>1, NoMD=>1);
  }
  # ---------------------------------------------------------------------
  
  # ---------------------------------------------------------------------
  # Ajout des nouvelles FP pour chacun des PAX
  my $i    = 1;
  my $fpec         = &getFpec($pnr->{market});
  foreach (@{$pnr->{PAX}}) {
    $GDS->command(Command=>$fpec.'/P'.$i, NoIG=>1, NoMD=>1);
    $i++;
  }
  # ---------------------------------------------------------------------

  # ---------------------------------------------------------------------  
  # Validation des modifications
  $GDS->command(Command=>'RF'.$GDS->modifsig, NoIG=>1, NoMD=>1);
  my $ER = $GDS->command(Command=>'ER', NoIG=>1, NoMD=>1);
  foreach my $ERline (@$ER) {
    if (($ERline =~ /AVERTISSEMENT : VERIF\. CONTINUITE SEGMENT/)         ||
        ($ERline =~ /WARNING: CHECK SEGMENT CONTINUITY/)                  || # Language english
        ($ERline =~ /AVERTISSEMENT : VERIFIER LE CODE D'ETAT OSI\/SSR/)   ||
        ($ERline =~ /WARNING: CHECK OSI\/SSR STATUS CODE/)                || # Language english
        ($ERline =~ /AVERTISSEMENT: VERIFIER LE STATUT DE L\'ITINERAIRE/) ||
        ($ERline =~ /REQUIRES TICKET ON OR BEFORE/)                       ||
        ($ERline =~ /AVERTISSEMENT : VERIF\. SEGMENT - ARRIVEE\/DEPART/)  ||
        ($ERline =~ /AVISO\s*:\s*VERIFIQUE EL CODIGO DE ESTADO OSI\/SSR/) ||
        ($ERline =~ /AVISO\s*:\s*VERIFIQUE EL SEGMENTO DE CONTINUIDAD/)) {
      $GDS->command(Command=>'ER', NoIG=>1, NoMD=>1);
    } else {
      return ['VERIFIER HEURE MINI DE CORRESPONDANCE']
        if (($ERline =~ /VERIFIER HEURE MINI DE CORRESPONDANCE/) ||
            ($ERline =~ /CHECK MINIMUM CONNECTION TIME/)         ||
            ($ERline =~ /VERIFIQUE EL TIEMPO DE CONEXION MINIMA/));
      last if ($ERline =~ /^--- TST/);
      notice('_chgFop: Réponse commande ER = '.$ERline);
      last;
    }
  }
  sleep(1);
  
    # Réouverture du dossier Amadeus
    $GDS->RT(PNR => $pnr->{PNRId});
    my $special = '';
	$special = '/V*SK' if (($pnr->{market} eq 'BE') && ($h_tstNumFstAcCode->{$_} eq 'JK'));
	$special = '/V*IB' if (($pnr->{market} eq 'BE') && ($h_tstNumFstAcCode->{$_} eq 'UX'));
	my $command = 'TTP'.$ttp_code."/T$uniqueRef".$printer.$special.'/ET' if  ($task eq 'tas-air-etkt');
	#EGE-89055 remove this line for AU pos and do IEP (DoCheck)  
	#$command = 'TTP'.$ttp_code."/T$_".$printer.$special.'/ITR-EML-eticket_archive@egencia.au'      if (($task eq 'tas-air-etkt') && ($countryCode eq 'AU'));
  	$command = "TTP/PT/T$uniqueRef".$printer                                   if  ($task eq 'tas-air-paper');
  my $lines_tkt = $GDS->command(Command => $command, NoIG => 1, NoMD => 1);
  # -------------------------------------------------------------------------------------
  $lines_tkt = $self->_simulChange($pnr, $GDS, $command)
		if ( (grep(/CHANGEMENTS SIMULTANES PNR/,  @$lines_tkt)) ||
         (grep(/SIMULTANEOUS CHANGES TO PNR/, @$lines_tkt)) ||
				 (grep(/CAMBIOS SIMULTANEOS A PNR/,   @$lines_tkt)) );
  # -------------------------------------------------------------------------------------
  $pnr->{TTP}->{$uniqueRef} = $lines_tkt;
	$GDS->RT(PNR => $pnr->{PNRId});
	
	
  return $lines_tkt;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# FORM OF PAYEMENT
sub _addFop {
  my $self   = shift;
  my $pnr    = shift;
  my $ab     = shift;
  my $GDS    = shift;
  my $position = shift;
  my $globalParams = shift;
  
  notice("_addFop DoTkt");
  my $atds = $ab->getTravelDossierStruct;   
  #my $atds         = $ab->getAirTravelDossierStruct;
  my $lwdPos       = $atds->[$position]->{lwdPos};
  my $lwdCode      = $atds->[$position]->{lwdCode};
  my $lwdHasMarkup = $atds->[$position]->{lwdHasMarkup};
  my $travellers   = $pnr->{Travellers};
  my $nbPax        = scalar @$travellers;
   
  notice('No Pax founded in XML booking !') if ($nbPax == 0);
  return 0                                  if ($nbPax == 0);
   
  my $countryCode  = $pnr->{market};
  my $fpec         = &getFpec($countryCode);
   
  my $fstSegComp   = $pnr->{'Segments'}->[0]->{'Data'};
     $fstSegComp   = '' unless (defined $fstSegComp);
     $fstSegComp   = substr($fstSegComp, 0, 2) if ($fstSegComp ne '');
  # -----------------------------------------------------------

  
    if (getRTUMarkup($countryCode)) {  
		
		my $GDS    = $pnr->{_GDS};	
		my $lines        = $GDS->command(Command => 'RT'.$pnr->{_PNR}, NoIG => 1, NoMD => 0);	
		my $lines_tqn    = $GDS->command(Command => 'TQN', NoIG => 1, NoMD => 0);
	
		$lwdHasMarkup= check_TQN_markup($lines_tqn, $pnr, $countryCode);
		notice('RTU MARKUP :'.$lwdHasMarkup);
		if ($lwdHasMarkup eq 'true'){
			$globalParams->{RTU_markup} = 'EC';
		}else {
			$globalParams->{RTU_markup}='';
		}

	}	
  
  
     
    # ----------------------------------------------------------------------------
    # Pour chacun des voyageurs du dossier, nous allons récupérer les moyens de paiement [...]
    PAX: foreach my $traveller (@$travellers) {
        
     
     my $ComCode  = $ab->getPerComCode({trvPos => $traveller->{Position}});
	 my $ccId= $ab->getCcUsedCode({trvPos => $traveller->{Position}});
     my $paymentMean = $ab->getPaymentMean({trvPos => $traveller->{Position}, lwdCode => $lwdCode});
	 my $percode= $traveller->{PerCode};
	 my $tmp_lc      = '';
 	 
	 my $cc;
	  
	 $cc=undef                                             if (!exists $paymentMean->{PaymentType});
	 if ($lwdHasMarkup eq 'true'){   
		$cc=$fpec;
		debug('THIS IS A MARKUP FILE: '.$lwdHasMarkup);
		
	 }

	my $type= $paymentMean->{PaymentType};
	
		
	
	
	my $cToken = undef;
	  
	if ($type =~  /^(CC|OOCC|ICCR)$/) {
		my $service = $paymentMean->{Service};
		my $token   = $paymentMean->{CcCode};
		my $CC1           = undef;
		$CC1           = $ccId->{CC1} if ((exists $ccId->{CC1}) && ($ccId->{CC1} ne ''));
		my $res = BO_GetBookingFormOfPayment('BackWebService', $countryCode,$ComCode, $token,$percode,$service,$fstSegComp,$CC1,$pnr->{_PNR});
		$cc=undef unless defined($res);
		$cc=$res->{FormOfPayment} if defined($res->{FormOfPayment});
		if($res->{PaymentType} eq 'EC'){
			$cc=$fpec;
		}
		if (defined $res->{Financial}){
			if($res->{Financial} eq 'FIRSTCARD'){ 
				$tmp_lc = '/'.$N1111; 
				$cc=$cc.$tmp_lc if(defined $cc);
			}
		}
		
		$cToken=$token;
	}
	  # -----------------------------------------------------------------------
	  # Type EC = En Compte
	elsif ($type eq 'EC' || $globalParams->{RTU_markup} eq 'EC') {
		$cc=$fpec;
	}
                
     if (defined $cc) {
       $GDS->command(Command=>$cc.'/'.$traveller->{PaxNum}, NoIG=>1, NoMD=>1);
     } else {
       notice('No Payment Mean found / '.$traveller->{PaxNum});
       return 0;
     }
     
      if(defined($cToken))
      {  
        my $tokenFlag="N";
		foreach ( @{$pnr->{PNRData}} ) {
			my $lineData = $_->{Data};
			if ( $lineData =~ /RM \*TOKEN\s.*/) {
				if( $lineData !~/RM \*TOKEN\s$cToken\/$traveller->{PaxNum}/ )
				{
						$GDS->command(Command=>'XE'.$_->{'LineNo'}, NoIG=>1, NoMD=>1);
						last;
				} 
				else 
				{
						$tokenFlag="Y";
						last;
				}
			}
		}

		if ( $tokenFlag eq "N" ) {
			$GDS->command(Command=>'RM *TOKEN '.$cToken.'/'.$traveller->{PaxNum}, NoIG=>1, NoMD=>1);
		}
       }

   }
   # ----------------------------------------------------------------------------

  
  # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

  return 1;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# SRFOID
sub _srfoid {
  my $self   = shift;
  my $pnr    = shift;
  my $ab     = shift;
  my $GDS    = shift;
  my $position = shift;
  
  my $atds = $ab->getTravelDossierStruct;   
  #my $atds       = $ab->getAirTravelDossierStruct;
  my $lwdPos     = $atds->[$position]->{lwdPos};
  my $travellers = $pnr->{Travellers};
  my $nbPax      = scalar @$travellers;
    
  notice('No Pax founded in XML booking !') if ($nbPax == 0);
  return 0                                  if ($nbPax == 0);

  my $sfroids = $ab->getSrfoids({lwdPos => $lwdPos});
  debug('srfoids = '.Dumper($sfroids));

  # ---------------------------------------------------------------------------
  # MONO PAX
  if ($nbPax == 1) {
    foreach my $srfoid (@$sfroids) {
      my $command  =  'SRFOID-';
         $command .=  $srfoid->{DocType}.$srfoid->{DocNumber}           if ($srfoid->{DocType} ne 'FF');
         $command .=  'FF'.$srfoid->{SupplierCode}.$srfoid->{DocNumber} if ($srfoid->{DocType} eq 'FF');
         $command  =~ s/&//ig;
       $GDS->command(Command => $command, NoIG => 1, NoMD => 1);
    }
  }
  # ---------------------------------------------------------------------------
  # MULTI PAX    
  elsif ($nbPax > 1) {
    PAX: foreach my $traveller (@$travellers) {
      my $tPerCode = $traveller->{PerCode};
      SRFOID: foreach my $srfoid (@$sfroids) {
        my $sPerCode = $srfoid->{PerCode};
        next SRFOID unless ($tPerCode eq $sPerCode);
        my $command  =  'SRFOID-';
           $command .=  $srfoid->{DocType}.$srfoid->{DocNumber}.'/'.$traveller->{PaxNum}           if ($srfoid->{DocType} ne 'FF');
           $command .=  'FF'.$srfoid->{SupplierCode}.$srfoid->{DocNumber}.'/'.$traveller->{PaxNum} if ($srfoid->{DocType} eq 'FF');
           $command  =~ s/&//ig;
        $GDS->command(Command => $command, NoIG => 1, NoMD => 1);
      }
    }
  }
  # ---------------------------------------------------------------------------

  return 1;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@



# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# This function will prepare and return a Hash for the do_reprice process.
#   It will get infos from the two xmlPNR and xmlTST !
sub getFareList {
  my $pnr       = shift;
  my $uniqueRef = shift;
  my $market    = shift;
  
  # Récupération des anciens tarifs & infos dans le XML
  my $tstdoc   = $pnr->{_XMLTST};
  my $pnrdoc   = $pnr->{_XMLPNR};
  
  # ---------------- Bug du 31 Janvier 2007 ----------------
  # Il faut absolument associer les bons numéros de passager
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
  # -------------------------------------------------------------------------
  
  my $fareList = {};
  my $uniqueReference = 0;
  
  my @fareList = $tstdoc->getElementsByTagName('fareList');
  
  foreach my $fare (@fareList) {
    
    $uniqueReference = $fare->find('fareReference/uniqueReference')->to_literal->value();
    warning(' Fare skipped because of bad uniqueReference.') unless ($uniqueReference);
    next unless ($uniqueReference);
    
    debug(' Fare uniqueRef = '.$uniqueReference.' skipped because we are looking for uniqueRef = '.$uniqueRef)
      if ($uniqueReference != $uniqueRef);
    next if ($uniqueReference != $uniqueRef);
    
    debug(' TST uniqueRef = '.$uniqueReference);
    
    my @supInformation     = $fare->findnodes('fareDataInformation/fareDataSupInformation');
    my @statusInformation  = $fare->findnodes('statusInformation');
    my @segmentInformation = $fare->findnodes('segmentInformation');
    
    foreach my $supNode (@supInformation) {
      next if ($supNode->find('fareDataQualifier')->to_literal->value() ne '712');
      my $oldPrice = $supNode->find('fareAmount')->to_literal->value();
      debug('   Ancien Prix = '.$oldPrice);
      $fareList->{$uniqueReference}->{oldPrice} = $oldPrice if ($oldPrice);
      last;
    }

    my @refDetailsNode = $fare->findnodes('paxSegReference/refDetails');
    my $paxRefNums = [];
    foreach (@refDetailsNode) {
      # ---------------------------------------------- Bug du 31 Janvier 2007 ---      
      # push (@$paxRefNums, $_->find('refNumber')->to_literal->value()); # Commenté
      # TODO ALLER CHERCHER LE VRAI PAX NUM
      my $refNumber = $_->find('refNumber')->to_literal->value();
      push (@$paxRefNums, $travellersPnrXml->{$refNumber}->{PaxNum});
      # -------------------------------------------------------------------------      
    }
    $fareList->{$uniqueReference}->{paxReference} = $paxRefNums;

    # foreach my $statusNode (@statusInformation) {   
    #   debug("Status = ".$statusNode->find('otherStatusDetails/tstFlag')->to_literal->value());
    # }
    
    foreach my $segInfoNode (@segmentInformation) {
      my $refNumber = $segInfoNode->find('segmentReference/refDetails/refNumber')->to_literal->value();
      # On saute les segmentInformation Fantômes ;-?
      next if ((!$refNumber) || ($refNumber =~ /^\s*$/));
      debug('     RefNumber = '.$refNumber);
      my $primaryCode     = $segInfoNode->find('fareQualifier/fareBasisDetails/primaryCode')->to_literal->value();
      my $fareBasisCode   = $segInfoNode->find('fareQualifier/fareBasisDetails/fareBasisCode')->to_literal->value();
      my $ticketDesignator= $segInfoNode->find('fareQualifier/fareBasisDetails/ticketDesignator')->to_literal->value();#BUG 15543
      my $ticketingStatus = $segInfoNode->find('segDetails/ticketingStatus')->to_literal->value();
      next if ((!$ticketingStatus) || ($ticketingStatus ne 'OK'));        
      debug('     PrimaryCode = '.$primaryCode);
      debug('   FareBasisCode = '.$fareBasisCode);
      debug('   TicketDesignator = '.$ticketDesignator);#BUG 15543
      debug(' TicketingStatus = '.$ticketingStatus);
      $fareList->{$uniqueReference}->{segmentReference}->{$refNumber}->{primaryCode}     = $primaryCode;
      $fareList->{$uniqueReference}->{segmentReference}->{$refNumber}->{fareBasisCode}   = $fareBasisCode;
      $fareList->{$uniqueReference}->{segmentReference}->{$refNumber}->{ticketDesignator}= $ticketDesignator;#BUG 15543
      $fareList->{$uniqueReference}->{segmentReference}->{$refNumber}->{ticketingStatus} = $ticketingStatus;
    }
  }
  
  # On rattache les lignes de segment (lignes du PNR cryptique)
  my @itineraryInfo = $pnrdoc->getElementsByTagName('itineraryInfo');
  
  foreach my $node (@itineraryInfo) {
    my $refNumber  = $node->find('elementManagementItinerary/reference/number')->to_literal->value();
    debug('     RefNumber = '.$refNumber);
    my $lineNumber = $node->find('elementManagementItinerary/lineNumber')->to_literal->value();
    debug('    LineNumber = '.$lineNumber);
    
FARE: foreach my $uniqueRef (keys %{$fareList}) {
      foreach my $segRef (keys %{$fareList->{$uniqueRef}->{segmentReference}}) {
        if ($segRef == $refNumber) {
          $fareList->{$uniqueRef}->{segmentReference}->{$segRef}->{segmentLine} = $lineNumber;
          last FARE;
        }
      }
    } 
  }
  
  debug('fareList = '.Dumper($fareList));
  
  return $fareList;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# This function will search for NewPrice regarding
# to a FXP command line provided
sub setNewPrice 
 {
  my $pnr            = shift;
  my $fareList       = shift;
  my $uniqueRef      = shift;
  my $cmdFXP         = shift; # ma 3eme ligne de TST
  my $corporateId    = shift; # my $airContract    = shift;
  my $fareType       = shift; # my $isTarifSociete = shift;
  my $GDS            = shift;
  my $ab             = shift;
  my $position       = shift;
  my $firstline      = shift;
  my $currency       = shift;
  my $YR			 = shift;
  
  my $country        = $ab->getCountryCode({trvPos => $ab->getWhoIsMain});
  my $fareBasis      = undef;
  my $h_FareBas      = {};
  my $new_process	 = undef;
  $uniqueRef         = 0 unless (defined $uniqueRef);
  $cmdFXP            =~ s/\s*$//;
  my $FV             = '';
     $FV             = $h_tstNumFstAcCode->{$uniqueRef} if (exists $h_tstNumFstAcCode->{$uniqueRef}); debug('FV = '.$FV);
  
  # EGE-59776 Update repricing logic to comply with Amadeus webservice bookings
  
  if($cmdFXP eq'FXA')
  {
  	$new_process = 0;
  }
  else
  {
  	if($firstline =~  /\w{3}EC38DD/)
  	{
  		$new_process = 1;
  	}
  	else
  	{
  		$new_process = 0;
  	}
  }
  
  #check if the RM is available, if not doing the GAP process 
  my $checkToNP = &getPnrOnlinePricing($pnr);
  if( $checkToNP eq ''){ $new_process = 0; } 
  
  my $jumpRUphase = 0; # Faire le traitement normal de base
  
  if($new_process == 0)
  {
	  # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
	  # Rajout de la bidouille suite à GAP snif :(
	  # + Refonte de la gestion des Retarifications (TAS MANCHESTER)
	  if    (($cmdFXP eq 'FXA') && ($fareType =~ /TARIF_(EXPEDIA|SOCIETE|EGENCIA)/)) {
	    $jumpRUphase = 1;
	    $cmdFXP      = 'FXP/R,U'.$corporateId;
	  }
	  elsif (($cmdFXP eq 'FXA') && ($fareType eq '')) { # Autre bidouille -_-'
	    $jumpRUphase = 1;
	    $cmdFXP      = 'FXP/R,U'              if ($corporateId eq '12345');
	    $cmdFXP      = 'FXP/R,U'.$corporateId if ($corporateId ne '12345');
	  }
	  elsif (($cmdFXP eq 'FXA') && ($fareType =~ /TARIF_PUBLIC/)) {
	    my $airFare  = getPnrAirFare($pnr);
	    my $codReduc = '';
	       $codReduc = $h_tarifExpedia->{$country}->{$FV} if (exists $h_tarifExpedia->{$country}->{$FV});
	    notice('airFare = '.$airFare);
	    if    ($airFare eq 'PUBLIC')       {  }
	    elsif ($airFare eq 'EXPEDIA')      { $cmdFXP = 'FXP/R,U'.$codReduc;                  $jumpRUphase = 1; }
	    elsif ($airFare eq 'EGENCIA')      { $cmdFXP = 'FXP/R,U'.$codReduc;                  $jumpRUphase = 1; }
	    elsif ($airFare eq 'CORPORATE')    { $cmdFXP = 'FXP/R,U'.getCorpoContract($ab, $FV, $position); $jumpRUphase = 1; }  #TODO ERREUR TST? 
	    elsif ($airFare eq 'SENIOR')       {  }
	    elsif ($airFare eq 'YOUNG')        {  }
	    elsif ($airFare eq 'SUBSCRIPTION') {  }
	  }
	  # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@  
  }
  else
  {
    #new process
    $cmdFXP = &getPnrOnlinePricing($pnr);
    notice("OnlinePricing:".$cmdFXP);
    #EGE-102585
    manageFareFamily($pnr, $FV, \$cmdFXP);
    if (defined($pnr->{TAS_ERROR})) {
      return 0;
    }
    $jumpRUphase = 1;
  }
    
  if ($cmdFXP =~ /^FX\w{1}(\/\s*R,U[^\/]*)?($|(\/S(\d{2})(-|,)?(\d{2})?)?(\/.*)?)$/) {
    unless ($jumpRUphase) { # @@@ Ajout Bidouille GAP
      $cmdFXP    = 'FXP';
      $cmdFXP   .= $1 if ($1);
      
      # Si le R,U est situé dans $7 càd à la fin de la ligne FXP
      if (!$1 && $7) {
        if ($7 =~ /^.*(\/\s*R,U[^\/]*).*?$/) {
          $cmdFXP .= $1 if ($1);
        }
      }
    } # @@@ Ajout Bidouille GAP

	if($YR ne '')
	{
	if($cmdFXP =~/^FXP$/){$cmdFXP .='/R';  }
    $cmdFXP .= $YR;
	}
	
    my $i = 0;
    my $sizeSegRef = scalar(keys %{$fareList->{$uniqueRef}->{segmentReference}});
    debug('sizeSegRef = '.$sizeSegRef);
    if ($sizeSegRef > 0) {
      $cmdFXP .= '/S';
      foreach my $segRef (keys %{$fareList->{$uniqueRef}->{segmentReference}}) {
        my $segLine = $fareList->{$uniqueRef}->{segmentReference}->{$segRef}->{segmentLine};
        $i++;
        $cmdFXP .= $segLine.',' if ($sizeSegRef != $i);
        $cmdFXP .= $segLine     if ($sizeSegRef == $i);
      }
    }
    
    $i = 0;
    my $sizePaxRef = scalar(@{$fareList->{$uniqueRef}->{paxReference}});
    debug(' sizePaxRef = '.$sizePaxRef);
    if ($sizePaxRef > 0) {
      $cmdFXP .= '/P';
      foreach my $paxRef (@{$fareList->{$uniqueRef}->{paxReference}}) {
        $i++;
        $cmdFXP .= $paxRef.',' if ($sizePaxRef != $i);
        $cmdFXP .= $paxRef     if ($sizePaxRef == $i);
      }
    }
    
    foreach my $segRef (keys %{$fareList->{$uniqueRef}->{segmentReference}}) {
      my $fareBasis = $fareList->{$uniqueRef}->{segmentReference}->{$segRef}->{primaryCode}.
                      $fareList->{$uniqueRef}->{segmentReference}->{$segRef}->{fareBasisCode};
      #BUG 15543
      if(defined($fareList->{$uniqueRef}->{segmentReference}->{$segRef}->{ticketDesignator}) && $fareList->{$uniqueRef}->{segmentReference}->{$segRef}->{ticketDesignator} ne '')
      {    
              $fareBasis .= "/".$fareList->{$uniqueRef}->{segmentReference}->{$segRef}->{ticketDesignator};
      }    
      debug(' fareBasis = '.$fareBasis);
      $h_FareBas->{$fareBasis}->{fareList}++;
    }
    
    debug(' h_FareBas = '.Dumper($h_FareBas));
    
  } else {
    warning(' The FXP command does not match regexp ;(');
		$pnr->{TAS_ERROR} = 8;
	  debug('### TAS MSG TREATMENT 8 ###');
		return 0;
  }
    		
  debug(' FXP command = '.$cmdFXP);

  my $lines = $GDS->command(Command=>$cmdFXP, NoIG=>1, NoMD=>1);
  
  # __________________________________________________________________________
  # Patrick Sébastien : 22 Février 2011. Suite à modification dans la gestion
  #  des TST par Amadeus. L'envoi d'une commande FXP créé systématiquement
  #  un nouveau numéro de TST. L'ancien passe en statut DELETED.
  delete $pnr->{TTP}->{$uniqueRef};
  $maxTstNum += 1;
  # __________________________________________________________________________
  
  # Dans le cas de plusieurs pages, nous devons nous assurer de tout récupérer
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
    debug("setNewPrice:\n".Dumper($lines));
  }

  my $monoFare     = 0;
  my $multiFare    = 0;
  # my $multiPax     = 0;
  # my $monoPax      = 0;
  my $fbFound      = 0; # fareBasis trouvé ?!?
  my $jmpFareCheck = 0;
  my $priceLine    = '';
  my $AIRFEES      = '';
   
L:foreach my $line (@$lines) {
    if ($line =~ /AL FLGT  BK T DATE  TIME  FARE BASIS      NVB  NVA   BG/) {
      debug('setNewPrice: SIMPLE FARE PROPOSAL !');
      $monoFare = 1;
      next;
    }
    if ($line =~ /FARE BASIS \*  DISC    \*  PSGR      \* FARE&lt;$currency&gt;  \* MSG  \*T/) {
      debug('setNewPrice: MULTI FARE PROPOSAL !');
      $multiFare = 1;
      next;
    }
    if ($line =~ /NO FARES\/RBD\/CARRIER\/PASSENGER TYPE/) {
      debug('setNewPrice: NO FARES !');
			$pnr->{TAS_ERROR} = 35;
			debug('### TAS MSG TREATMENT 35 ###');
			return 0;
    }
    if (($line =~ /PASSENGER         PTC    NP  ATAF&lt;$currency&gt; TAX\/FEE   PER PSGR/) ||
        ($line =~ /PASSENGER         PTC    NP  FARE&lt;$currency&gt; TAX\/FEE   PER PSGR/)) {
      debug('setNewPrice: MULTI PAX PROPOSAL !');
      # $monoPax = 1;      # Bidouille
      $jmpFareCheck = 1; # Bidouille
      my $linesTQT = $GDS->command(Command=>'TQT/T'.$maxTstNum, NoIG=>1, NoMD=>1);
      # --------------------------------------------
      # On scroll 3 fois pour être sûr de tout récupérer
      my $lastLine = $linesTQT->[$#$linesTQT];
      for (my $i = 1; $i <= 3; $i++) {
        my $MD = $GDS->command(Command=>'MD', NoIG=>1, NoMD=>1);
           $MD = [''] if (scalar @$MD == 0);
        my $MDlastLine = $MD->[$#$MD];
        if ($lastLine eq $MDlastLine) {
          $i = 3;
        } else {
          push (@$linesTQT, @$MD);
          $lastLine = $MDlastLine;
        }
      }
      # --------------------------------------------
      my $total;
      my $grandTotal;
      foreach my $tqtLine (@$linesTQT) {
        if ($tqtLine =~ /^\s{1}(\d+)\s*.*\s*OK\s*(\w*[^\s]*).*$/) {
          my $tqtFareBasis = $2;
          foreach my $FB (keys %$h_FareBas) {
            next if ((exists $h_FareBas->{$FB}->{fareList}) &&
                     (exists $h_FareBas->{$FB}->{fareFX})   &&
                     ($h_FareBas->{$FB}->{fareList} == $h_FareBas->{$FB}->{fareFX}));
            if ($tqtFareBasis =~ /$FB/) {
              debug(" fareBasis $FB found.");
              debug(' line = '.$tqtLine);
              $h_FareBas->{$FB}->{fareFX}++;
            }
          }
        }
        if ($tqtLine =~ /^TOTAL\s*$currency\s*(\d+(\.)?(\d+)?)\s*/) {
          $total = $1;
          next;
        }
        if ($tqtLine =~ /^GRAND TOTAL\s*$currency\s*(\d+(\.)?(\d+)?)\s*$/) {
          $grandTotal = $1;
          $priceLine = $tqtLine;
          $priceLine =~ s/^GRAND TOTAL\s*($currency.*)$/$1/;
          debug('PRICELINE = '.$priceLine);
          last;
        }
      }
      $AIRFEES = $grandTotal - $total;
      last L;
    }
    if ($monoFare == 1) {
      # $monoPax = 1;
      if ($line =~ /^$currency\s*(\d+(\.)?(\d+)?)\s*AIRLINE\s*FEES$/) {
        $AIRFEES = $1;
      }
      $priceLine = $line if ($line =~ /^$currency.*/);
      foreach my $fb (keys %$h_FareBas) {
        next if ((exists $h_FareBas->{$fb}->{fareList}) &&
                 (exists $h_FareBas->{$fb}->{fareFX})   &&
                 ($h_FareBas->{$fb}->{fareList} == $h_FareBas->{$fb}->{fareFX}));
      # if ($line =~ /[A-Z]{3}\s+\d{4}\s+$fb\s+/) { # Bug 11467
        if ($line =~ /[A-Z]{3}\s+\d{4}\s+$fb(?:\/?\S+)?\s+/) {
          debug(" fareBasis $fb found.");
          debug(' line = '.$line);
          $h_FareBas->{$fb}->{fareFX}++;
        }
      }
    }
    if ($multiFare == 1) {
      my $fareLineNumber = undef;
      
      # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
      # Développement de FQQ
      my $linesMultiFare = $lines;
      my $checkIt = 0;
      my $h_fb    = {};
      foreach my $lmf (@$linesMultiFare) {
        last if ($lmf =~ /FARE VALID/);
        if ($lmf =~ /FARE BASIS \*  DISC    \*  PSGR      \* FARE&lt;$currency&gt;  \* MSG  \*T/) {
          $checkIt = 1;
          next;
        }
        if ($checkIt == 1) {
          # if ($lmf =~ /^(\d{2})\s+([^\*\s]*\*?)\s+\*.*$/) {
          if ($lmf =~ /^(\d{2})\s+([^\*\s]*\*?).*\s+([^\W]+\.?\d*).*$/) {
            $h_fb->{$2}->{fbnumber} += 1;
            push (@{$h_fb->{$2}->{fblines}},  $1);
            push (@{$h_fb->{$2}->{fbprices}}, $3); # On stocke également le prix
          }
        }
      }
      debug(' h_fb = '.Dumper($h_fb));
            
      # A t-on besoin ou pas de faire une FQQ ?
      my $doFQQ = 1;
      if (scalar(keys %$h_FareBas) == 1) {
        my @keys    = keys %$h_FareBas;
        my $fareBas = $keys[0];   # C'est la fareBasis que l'on cherche
FBCHK:  foreach my $_fb (keys %{$h_fb}) {
          if ($_fb eq $fareBas) { # Strictement équivalent
            last if ($doFQQ == 0);
            # Si elle n'est proposée qu'une fois
            if (scalar(@{$h_fb->{$_fb}->{fblines}}) == 1) {
              debug(' Je suis dans ce cas (1).');
              $doFQQ = 0;
              $fareLineNumber = sprintf("%d", $h_fb->{$_fb}->{fblines}->[0]);
              last FBCHK;
            }
            # Si elle est proposée plusieurs fois,
            # il faut prendre celle avec le prix le plus proche
            # Modif : Finalement, on doit faire la FQQ !
            elsif (scalar(@{$h_fb->{$_fb}->{fblines}}) > 1) {
              debug(' Je suis dans ce cas (2).');
              last FBCHK;
            }
          }
        }
      }
      debug("setNewPrice: doFQQ = ".$doFQQ);
      
      # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
      # Si on doit faire une FQQ !
      if ($doFQQ == 1) {
        my $FQQPriceDiffMin;
        my $oldPrice = $fareList->{$uniqueRef}->{oldPrice};
        debug(' (FQQ) oldPrice = '.$oldPrice.' '.$currency);
FQQ:    foreach my $fbasis (keys %{$h_fb}) {
FBLINE:   foreach my $fbline (sort triCroissant (@{$h_fb->{$fbasis}->{fblines}})) {
            my $FQQAirFees = 0;
            my $FQQNewPrice;
            my $h_FareBas_clone = clone($h_FareBas);
            my $linesFQQ = $GDS->command(Command=>'FQQ'.sprintf("%d", $fbline), NoIG=>1, NoMD=>1);
            # Dans le cas de plusieurs pages, nous devons nous assurer de tout récupérer
            my $lastLineFQQ = $linesFQQ->[$#$linesFQQ];
            if ($lastLineFQQ =~ /PAGE\s*(\d)\/\s*(\d)$/) {
              my $currentPage = $1;
              my $totalPage   = $2;
              my $nbMD2do     = $totalPage - $currentPage;
              debug("CURRENT_PAGE = ".$currentPage);
              debug("TOTAL_PAGE   = ".$totalPage);
              debug("NBMD2DO      = ".$nbMD2do);
              for (my $i = 1; $i <= $nbMD2do; $i++) {
                my $MD = $GDS->command(Command=>'MD', NoIG=>1, NoMD=>1);
                push(@$linesFQQ, @$MD);
              }
            }
            debug(' (FQQ) linesFQQ = '.Dumper($linesFQQ));
            $checkIt = 0;
            foreach my $lineFQQ (@$linesFQQ) {
              if ($lineFQQ =~ /^$currency\s*(\d+(\.)?(\d+)?)\s*AIRLINE\s*FEES$/) {
                $FQQAirFees = $1;
              }
              if ($lineFQQ =~ /^$currency\s*(\d+(\.)?(\d+)?)\s*.*$/) {
                $FQQNewPrice = $1;
              }
              if ($lineFQQ =~ /AL FLGT  BK T DATE  TIME  FARE BASIS      NVB  NVA   BG/) {
                $checkIt = 1;
                next;
              }
              if ($checkIt == 1) {
                foreach my $fbc (keys %$h_FareBas_clone) {
                  next if ((exists $h_FareBas_clone->{$fbc}->{fareList}) &&
                           (exists $h_FareBas_clone->{$fbc}->{fareFX})   &&
                           ($h_FareBas_clone->{$fbc}->{fareList} == $h_FareBas_clone->{$fbc}->{fareFX}));
                # if ($lineFQQ =~ /[A-Z]{3}\s+\d{4}\s+$fbc\s+/) { # Bug 11467
                  if ($lineFQQ =~ /[A-Z]{3}\s+\d{4}\s+$fbc(?:\/?\S+)?\s+/) {
                    debug(" (FQQ) fareBasis $fbc found.");
                    debug(' (FQQ) line = '.$lineFQQ);
                    $h_FareBas_clone->{$fbc}->{fareFX}++;
                  }
                }
              }
            } # Fin foreach my $lineFQQ (@$linesFQQ)

            # ---------------------------------------------------------------------
            # Vérification du Hash h_FareBas_clone
            debug(' (FQQ) h_FareBas_clone = '.Dumper($h_FareBas_clone));
            my $FQQfound = 1;
            foreach my $fbc (keys %$h_FareBas_clone) {
              if ((!exists $h_FareBas_clone->{$fbc}->{fareFX}) ||
                  ($h_FareBas_clone->{$fbc}->{fareFX} < $h_FareBas_clone->{$fbc}->{fareList})) {
                debug(" (h_FareBas_clone) The number of fareBasis $fbc doesn't match.");
                $FQQfound = 0;
                last;
              }
            }
            debug(' (FQQ) FQQfound = '.$FQQfound);
            
            if ($FQQfound == 1) {
              debug(' (FQQ) FQQNewPrice = '.$FQQNewPrice.' '.$currency);
              debug(' (FQQ) FQQAirFees = '.$FQQAirFees.' '.$currency);
              my $FQQPriceDiff = abs($FQQNewPrice - $FQQAirFees - $oldPrice);
              debug(' (FQQ) FQQPriceDiff = '.$FQQPriceDiff.' '.$currency);
              if (!defined($FQQPriceDiffMin) ||
                  $FQQPriceDiff < $FQQPriceDiffMin) {
                $fareLineNumber = sprintf("%d", $fbline);
                debug(' (FQQ) fareLineNumber = '.$fareLineNumber);
                $FQQPriceDiffMin = $FQQPriceDiff;
                if ($FQQPriceDiffMin == 0) {
                  last FQQ;
                }
              }
            }
          } # Fin foreach my $fbline (sort triCroissant (@{$h_fb->{$fbasis}->{fblines}}))
        } # Fin foreach my $fbasis (keys %{$h_fb})
      } # Fin if ($doFQQ == 1)
      
      # Si $fareLineNumber est toujours 'undef' alors il faut sortir !
      if (!$fareLineNumber) {
        notice(" (h_FareBas) The number of fareBasis doesn't match.");
			  $pnr->{TAS_ERROR} = 35;
			  debug('### TAS MSG TREATMENT 35 ###');
			  return 0;
      } else {
        debug(" fareLineNumber = $fareLineNumber");
      }
      # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

          my $cmdFXT = 'FXT'.$fareLineNumber;
          # Gestion Multi-PAX
          my $sizePaxReference = scalar (@{$fareList->{$uniqueRef}->{paxReference}});
          if ($sizePaxReference <= 0) {
            warning(' Problem with the pax numbers for this TST');
#           return 0;
          } elsif ($sizePaxReference > 1) {
#           $multiPax = 1;
            my $i = 0;
            $cmdFXT .= '/P';
            foreach (sort triCroissant (@{$fareList->{$uniqueRef}->{paxReference}})) {
              $i++;
              $cmdFXT .= $_.',' if ($sizePaxReference != $i);
              $cmdFXT .= $_     if ($sizePaxReference == $i);
            }
          } else {
            $cmdFXT .= '/P'.$fareList->{$uniqueRef}->{paxReference}->[0];
          }
          debug(" Commande = $cmdFXT");
          my $linesFXT = $GDS->command(Command=>$cmdFXT, NoIG=>1, NoMD=>1);
          
          # Dans le cas de plusieurs pages, nous devons nous assurer de tout récupérer
          my $lastLine = $linesFXT->[$#$linesFXT];
          if ($lastLine =~ /PAGE\s*(\d)\/\s*(\d)$/) {
            my $currentPage = $1;
            my $totalPage   = $2;
            my $nbMD2do     = 0;
            $nbMD2do = $totalPage - $currentPage;
            debug("CURRENT_PAGE = ".$currentPage);
            debug("TOTAL_PAGE   = ".$totalPage);
            debug("NBMD2DO      = ".$nbMD2do);
            for (my $i = 1; $i <= $nbMD2do; $i++) {
              my $MD = $GDS->command(Command=>'MD', NoIG=>1, NoMD=>1);
              push(@$linesFXT, @$MD);
            }
          }
          debug("setNewPrice: ".Dumper($linesFXT));
          
#         # Gestion Multi-PAX
#         if ($multiPax == 1) {
#           # Cette bidouille est faite car nous n'avons pas l'info sur le retour Amadeus
#           $h_FareBas->{$fb}->{fareFX} = $h_FareBas->{$fb}->{fareList};
#           my $found = 0;
#           foreach my $lineFXT (@$linesFXT) {
#             if ($lineFXT =~ /PASSENGER         PTC    NP  ATAF&lt;EUR&gt;     TAX   PER PSGR/) {
#               $found = 1;
#               next;
#             }
#             next if ($found == 0);
#             if ($found == 1) {
#               $priceLine = $lineFXT;
#               last;
#             }
#           }
#         # Gestion Mono-PAX
#         } else {
            my $search = 0;
            # $monoPax   = 1;
   LINEFXT: foreach my $lineFXT (@$linesFXT) {
              if ($lineFXT =~ /^$currency\s*(\d+(\.)?(\d+)?)\s*AIRLINE\s*FEES$/) {
                $AIRFEES = $1;
              }
              $priceLine = $lineFXT if ($lineFXT =~ /^$currency.*/);
              $search    = 1 if ($lineFXT =~ /AL FLGT  BK T DATE  TIME  FARE BASIS      NVB  NVA   BG/);
              next LINEFXT if ($search != 1);
          FB: foreach my $FB (keys %$h_FareBas) {
                next FB if (
                  (exists $h_FareBas->{$FB}->{fareList}) &&
                  ($h_FareBas->{$FB}->{fareFX})          &&
                  ($h_FareBas->{$FB}->{fareList} == $h_FareBas->{$FB}->{fareFX}));
              # if ($lineFXT =~ /[A-Z]{3}\s+\d{4}\s+$FB\s+/) { # Bug 11467
                if ($lineFXT =~ /[A-Z]{3}\s+\d{4}\s+$FB(?:\/?\S+)?\s+/) {
                  debug("setNewPrice: fareBasis $FB found.");
                  debug('setNewPrice: line = '.$lineFXT);
                  $h_FareBas->{$FB}->{fareFX}++;
                  # last LINEFXT if $h_FareBas->{$FB}->{fareList} == $h_FareBas->{$FB}->{fareFX};
                }
              }
            }
            last L; # Dernière ligne de MULTI FARE
#         }
          # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
          
#       } # Fin if ($line =~ /^\d{2}\s+$fb\s+.*/)
#     } # Fin foreach my $fb (keys %$h_FareBas)
    } # Fin if ($multiFare == 1)
  } # Fin foreach my $line (@$lines)
  
  # ---------------------------------------------------------------------
  # Vérification du Hash h_FareBas
  debug(' h_FareBas = '.Dumper($h_FareBas));
  foreach my $fb (keys %$h_FareBas) {
    if ((!exists $h_FareBas->{$fb}->{fareFX}) ||
        ($h_FareBas->{$fb}->{fareFX} < $h_FareBas->{$fb}->{fareList})) {
      notice(" (h_FareBas) The number of fareBasis $fb doesn't match.");
			$pnr->{TAS_ERROR} = 35;
			debug('### TAS MSG TREATMENT 35 ###');
			return 0;
    }
  }
  # ---------------------------------------------------------------------
  
  unless ($jmpFareCheck == 1) {
    if ((($monoFare == 0) && ($multiFare == 0)) ||
        (($monoFare == 1) && ($multiFare == 1))) {
      notice(' Problem during detect of FXP case !');
	    $pnr->{TAS_ERROR} = 8;
		  debug('### TAS MSG TREATMENT 8 ###');
		  return 0;
    }
  }
      
  my $newPrice = 987654321; # EUROS =)
  
  debug(' PRICE LINE = '.$priceLine);

  # if ($monoPax == 1) {
    $newPrice = $priceLine;
    $newPrice =~ s/^$currency\s*(\d+(\.)?(\d+)?)\s*.*$/$1/;
    # debug(' NEW PRICE = '.$newPrice);
  # } elsif ($multiPax == 1) {
    # $newPrice = $priceLine;
    # $newPrice = $1 if ($newPrice =~ s/\s+(\d+\.?\d*)$/$1/);
  # }

  debug(' NEW PRICE = '.$newPrice);    

  $fareList->{$uniqueRef}->{newPrice} = $newPrice;
  $fareList->{$uniqueRef}->{airfees}  = $AIRFEES;
  
  return 1;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# This function will check the validity of the
#   repricing process (inside $fareList) at the END.
sub checkFareList {
  my $pnr      = shift;
  my $fareList = shift;
  # my $simul    = shift; # Simulation needed for FQQ
  
  my $KO = 0;
  # $simul = defined($simul) ? 1 : 0;

  # On vérifie que toutes les TST ont été repricées
  # et qu'elles vérifient les conditions de retarification
  foreach my $uniqueRef (keys %{$fareList}) {
    if (exists($fareList->{$uniqueRef}->{newPrice})) {
      debug(' uniqueReference = '.$uniqueRef);
      debug(' oldPrice = '.$fareList->{$uniqueRef}->{oldPrice});
      debug(' newPrice = '.$fareList->{$uniqueRef}->{newPrice});
	  debug(' airfees  = '.$fareList->{$uniqueRef}->{airfees});
	  
	  $h_new_amount{$uniqueRef} 		= $fareList->{$uniqueRef}->{newPrice};
	  $h_original_amount{$uniqueRef} 	= $fareList->{$uniqueRef}->{oldPrice};
	  $h_variation_amount{$uniqueRef}	= $h_new_amount{$uniqueRef} - $h_original_amount{$uniqueRef};
	  
	  if($fareList->{$uniqueRef}->{airfees} ne '')
	  {
	    $h_OBFEES{$uniqueRef}='true';
	  }
	  else
	  {
		$h_OBFEES{$uniqueRef}='false';
	  }
	  
      if (&repriceCheck($fareList->{$uniqueRef}->{oldPrice}, $fareList->{$uniqueRef}->{newPrice}, $fareList->{$uniqueRef}->{airfees})) {
        $fareList->{$uniqueRef}->{repriced} = 'OK';
        debug(' reprice OK');
      } else {
        $fareList->{$uniqueRef}->{repriced} = 'KO';
        debug(' reprice KO');
        debug(' TST uniqueReference = '.$uniqueRef." doesn't match repricing rules");
        $KO = 1;
      }
      next;
    }
    notice(' The TST uniqueReference = '.$uniqueRef.' has not been repriced');
	  $pnr->{TAS_ERROR} = 8;
		debug('### TAS MSG TREATMENT 8 ###');
    return 0;
  }

  debug(" FARELIST = ".Dumper($fareList));
  
  if ($KO == 1) {
	  $pnr->{TAS_ERROR} = 36;
		debug('### TAS MSG TREATMENT 36 ###');
    return 0;
  }

  return 1;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Check the difference between oldPrice and NewPrice
#   diff <= 25 euros or < 2% of oldPrice 
sub repriceCheck {
  my $oldPrice = shift;
  my $newPrice = shift;
  my $airfees  = shift; 
  
  error(' Missing parameter !!!') if (!$oldPrice || !$newPrice);
  return 0 if (!$oldPrice || !$newPrice);
  
  notice('oldPrice = '.$oldPrice.' '.$currency);
  notice('newPrice = '.$newPrice.' '.$currency);
  notice('airfees  = '.$airfees.' '.$currency);
  
  # Si au moins un des paramètres n'est pas du bon format.
  if (($oldPrice !~ /^\d+(\.)?(\d+)?$/) ||
      ($newPrice !~ /^\d+(\.)?(\d+)?$/)) {
    error(' Given parameters are not floating typed.');
    return 0;
  }
  
  #EGE-85875
  my $newPrice_minus_airfees =  $newPrice - $airfees ;
  
  # Si le nouveau tarif est inférieur ou égal, c'est bon !
  return 1 if ($newPrice_minus_airfees <= $oldPrice);
  
  # Si le nouveau tarif ne dépasse pas 25 euros.
  return 1 if ($newPrice_minus_airfees - $oldPrice <= 25);
  
  # Par rapport à 2%. Dernière chance ;-)
  my $euros = ($oldPrice * 2) / 100;
  return 1 if (($newPrice_minus_airfees - $oldPrice) <= $euros);
  
  # Sinon c'est pas bon !
  notice(' New price is 2% more expensive than old one.');

  return 0;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Récupère le CORPORATE_ID dans le cas d'1 TARIF_SOCIETE ou d'1 TARIF_EXPEDIA
sub getCorporateId {
  my $self = shift;
  my $ab   = shift;
  my $position = shift;
  
  my $atds = $ab->getTravelDossierStruct;    
  my $pp   = $ab->getAirProductPricing({lwdPos => $atds->[$position]->{lwdPos}});
  
  return '' unless (exists $pp->{CorporateCode});
  debug('getCorporateId = '.$pp->{CorporateCode});
  return $pp->{CorporateCode};
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Récupère le champ FARE_TYPE utilisé lors du Booking.
sub getFareType {
  my $self = shift;
  my $ab   = shift;
  my $position = shift;
  
  my $atds = $ab->getTravelDossierStruct;    
  my $pp   = $ab->getAirProductPricing({lwdPos => $atds->[$position]->{lwdPos}});
  
  return '' unless (exists $pp->{FareType});
  debug('getFareType = '.$pp->{FareType});
  return $pp->{FareType};
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Récupérer le Corporate Contract qui va bien
sub getCorpoContract {
  my $ab        = shift;
  my $FV        = shift;
  my $position = shift;
    
  my @res       = ();
  my $atds = $ab->getTravelDossierStruct;  
  my $lwdPos    = $atds->[$position]->{lwdPos};
  my $contracts = $ab->getTravelDossierContracts({lwdPos => $lwdPos});

  foreach my $contract (@$contracts) {
    next if ($contract->{ContractType}    ne 'DISCOUNT');
    next if ($contract->{SupplierService} ne 'AIR');
    next if ($contract->{CorporateNumber} =~ /^\s*$/);
    push (@res, $contract);
  }
  
  return $res[0]->{CorporateNumber}             if scalar (@res == 1);
  foreach (@res) { return $_->{CorporateNumber} if ($_->{SupplierCode} eq $FV); }
  return '';
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Récupérer le AirFare dans un PNR
sub getPnrAirFare {
  my $pnr = shift;
  
  my $airFare = '';
  
  foreach (@{$pnr->{PNRData}}) {
    if ($_->{Data} =~ /^RM \*AIRFARE (PUBLIC|EXPEDIA|EGENCIA|CORPORATE|SUBSCRIPTION|YOUNG|SENIOR) /) {
      $airFare = $1;
      last;
    }
  }
  
  return $airFare;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Récupérer l'online pricing dans un PNR
sub getPnrOnlinePricing {
  my $pnr = shift;
  
  my $onlinepricing = '';
  
  foreach (@{$pnr->{PNRData}}) {
    if ($_->{Data} =~ /^RM \*ONLINE PRICING LINE FOR TAS: (.*)/) {
      $onlinepricing = $1;
      last;
    }
  }
  
  return $onlinepricing;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# This sub manages the fare family
sub manageFareFamily {
  my $pnr    = shift;
  my $FV     = shift;
  my $cmdFXP = shift;
  
  if ($FV eq 'LH' || $FV eq 'OS' || $FV eq 'LX' ||
      $FV eq 'AB' ||
      $FV eq 'NZ' || $FV eq 'VA') {
    
    my $fareBasis;
    foreach (@{$pnr->{PNRData}}) {
      if ($_->{Data} =~ /^RM \*AIRFARE (?:PUBLIC|EXPEDIA|EGENCIA|CORPORATE|SUBSCRIPTION|YOUNG|SENIOR) .(.*)/) {
        $fareBasis = $1;
        last;
      }
    }
    unless (defined($fareBasis)) {
      return 1;
    }
    
    if ($FV eq 'LH' || $FV eq 'OS' || $FV eq 'LX' ||
        $FV eq 'AB') {
      
      my $fareFamily = '';
      
      if ($FV eq 'LH' || $FV eq 'OS' || $FV eq 'LX') {
        
        if    ($fareBasis =~ /CLS/) {$fareFamily = 'FF-CLASSIC';}
        elsif ($fareBasis =~ /FLX/) {$fareFamily = 'FF-FLEX';}
        elsif ($fareBasis =~ /LGT/) {$fareFamily = 'FF-LIGHT';}
        
      } elsif ($FV eq 'AB') {
        
        if    ($fareBasis =~ /NY/) {$fareFamily = 'FF-ECOLIGHT'; $$cmdFXP =~ s/\/R,U513058$//;}
        elsif ($fareBasis =~ /FF/) {$fareFamily = 'FF-ECOFLEX';}
        elsif ($fareBasis =~ /NC/) {$fareFamily = 'FF-ECOCLASSIC';}
        
      }
      
      notice('fareFamily:'.$fareFamily);
      
      if ($fareFamily ne '') {
        $$cmdFXP =~ s/FXP/FXP\/$fareFamily/g;
        notice('NEW FXP:'.$$cmdFXP);
      }
      
    } elsif ($FV eq 'NZ' || $FV eq 'VA') {
      
      my $newCmdFXP;
      
      if    ($FV eq 'NZ' && fareBasisContainsOnly($fareBasis, 'SAT')) {$newCmdFXP = 'FXP/RSPT';}
      elsif ($FV eq 'NZ' && fareBasisContainsOnly($fareBasis, 'FXT')) {$newCmdFXP = 'FXP/RTIM,*PTC';}
      elsif ($FV eq 'NZ' && fareBasisContainsOnly($fareBasis, 'FXP')) {$newCmdFXP = 'FXP/RCTZ,*PTC';}
      
      if (defined($newCmdFXP)) {
        $$cmdFXP = $newCmdFXP;
        notice('NEW FXP:'.$$cmdFXP);
      } elsif (($FV eq 'NZ' && fareBasisContains($fareBasis, 'DLX')) ||
               ($FV eq 'NZ' && fareBasisContains($fareBasis, 'SAT')) ||
               ($FV eq 'NZ' && fareBasisContains($fareBasis, 'FXT')) ||
               ($FV eq 'NZ' && fareBasisContains($fareBasis, 'FXP')) ||
               ($FV eq 'VA' && fareBasisContains($fareBasis, 'GO')) ||
               ($FV eq 'VA' && fareBasisContains($fareBasis, 'GP'))) {
        debug('### TAS MSG TREATMENT 71 ###');
        $pnr->{TAS_ERROR} = 71;
        return 1;
      }
      
    }
    
  }
  
  return 1;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Checks if the fare basis contains only the pattern
sub fareBasisContainsOnly {
  my $fareBasis = shift;
  my $pattern   = shift;
  
  my $sep = '\/';
  if ($fareBasis =~ /^[^$sep]*$pattern[^$sep]*(?:$sep[^$sep]+$pattern[^$sep]*)*$/) {
    return 1;
  } else {
    return 0;
  }
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Checks if the fare basis contains the pattern
sub fareBasisContains {
  my $fareBasis = shift;
  my $pattern   = shift;
  
  my $sep = '\/';
  if ($fareBasis =~ /(?:^|$sep[^$sep])[^$sep]*$pattern/) {
    return 1;
  } else {
    return 0;
  }
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

###########  TTP / IEP Command + Log for Monitoring ######
sub simplification_iep 
{

    my $self          = shift;
    my $TTPNums_ref   = shift || undef;
    my $GDS           = shift;
    my $pnr           = shift;
    my $task          = shift;
    my $countryCode   = shift;
    my $command       = shift;
    my $ttp_code      = shift;
    my $comCode       = shift;
    my $service       = shift;
    my $already_issue = shift;  # 0 or 1 => 0 for bypassing unless condition
    my $tpid          = shift;
    my $gpid          = shift;
    my $printer = '';
    my $special = '';
    my $lines_tkt = '';
    my @TTPNums;
    @TTPNums =(keys %{$pnr->{TTP}})   unless(defined($TTPNums_ref));
    @TTPNums= @$TTPNums_ref           if (defined($TTPNums_ref));

    # Réécriture en utilisant la uniqueReference du XML suite
    # au problème détecté avec Céline. Il n'y a pas forcément
    # de chronologie dans les TTP...
    foreach (sort triCroissant (@TTPNums)) {

        unless ($already_issue && grep(/OK ETICKET|OK TRAITE(E)/, @{$pnr->{TTP}->{$_}})) 
		{
            eval 
			{
                notice('ComCode : '.$comCode);
                notice('Market : '.$countryCode);
				my $isAuth = isAuthorize('air.authorization-call-fbs-ticketing-for-issue-ticket', $countryCode, $comCode) ; 
                if ( $isAuth == 1) {
                    notice("Use FBS web service");
                    notice("TST : ".$_);
                    notice("PNR : ".$pnr->{PNRId});
                    if (! defined $tpid) 
					{
                        notice("Error : The value of tpid does not exist in XML");
                        $pnr->{TTP}->{$_} = ["Error during issue TICKET"];
                    } 
					else 
					{
                        notice("TPID : ".$tpid);
                        notice("GPID : ".$gpid);
                        my $err_level = "INFO";
                        my $rejetMessage = '';
                        my $response = ticketingIssue($pnr->{PNRId}, $tpid, $gpid, 'TICKET', $_, 'true');
                        if ($response->{'code'} eq 'OK') 
						{
                            my $ticket = $response->{'tickets'}->[0];
                            my $message = $ticket->{'message'};
                            if ($ticket->{'code'} eq 'OK') 
							{
                                notice('Result of the issuance of TICKET : '.$message);
                            } else 
							{
                                $err_level = "ERROR";
                                $rejetMessage = $message;
                                notice('Error when issue TICKET : '.$rejetMessage);
                            }
                            $pnr->{TTP}->{$_} = [$message];
                        } else 
						{
                            $err_level = "ERROR";
                            $rejetMessage = $response->{'message'};
                            notice('Error when issue TICKET : '.$rejetMessage);
                            $pnr->{TTP}->{$_} = ["Error during issue TICKET"];
                        }
                        &monitore("TAS_TICKETING", 'TST_ISSUE_USING_SUPPLY_LAYER', $err_level, $countryCode, $service, $pnr->{PNRId}, $rejetMessage, 'WEBSERVICE CALL');
                    }
                } 
				else
				{
                    notice('Use cryptic command');
                    #suprission de certainne instruction
                    $GDS->RT(PNR => $pnr->{PNRId});
                    $command = 'TTP'.$ttp_code."/T$_".$printer.$special.'/ET'            if  ($task eq 'tas-air-etkt');
                    $command = "TTP/PT/T$_".$printer                                     if  ($task eq 'tas-air-paper');
                    # -------------------------------------------------------------------------------------
                    $lines_tkt = $GDS->command(Command => $command, NoIG => 1, NoMD => 1);
                    # -------------------------------------------------------------------------------------
                    $lines_tkt = $self->_simulChange($pnr, $GDS, $command)
                    if ((grep(/CHANGEMENTS SIMULTANES PNR/,@$lines_tkt))  ||
                            (grep(/SIMULTANEOUS CHANGES TO PNR/,@$lines_tkt)) ||
                            (grep(/CAMBIOS SIMULTANEOS A PNR/,@$lines_tkt)) ||
                            (grep (/PLEASE VERIFY PNR AND RETRY/ ,   @$lines_tkt)) ||
                            (grep (/VERIFIER LE PNR ET REESSAYER/ ,   @$lines_tkt)) ||
                            (grep (/VERIFIQUE PNR Y REINTENTE/ ,   @$lines_tkt)) ||
                            (grep (/PLEASE VERIFY PNR CONTENT/ ,   @$lines_tkt)) ||
                            (grep (/VERIFIER LE CONTENU DU PNR/ ,   @$lines_tkt)) ||
                             (grep (/VERIFIQUE EL CONTENIDO DEL PNR/ ,   @$lines_tkt))
                    );
                    $pnr->{TTP}->{$_} = $lines_tkt;
                }
            };
            if (@_) 
			{
                notice("TST $_ : Error during issue TICKET.");
                $pnr->{TTP}->{$_} = ["Error during issue TICKET"];
            }

        }
    }

    return $pnr;

}


# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Routine de Tri Des Numériques
sub triDecroissant { $b <=> $a } 
sub triCroissant   { $a <=> $b }
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

1;
