package Expedia::Tools::EmdFuncs;

use Data::Dumper;
use Exporter 'import';
use MIME::Lite;
use POSIX qw(strftime);
use Spreadsheet::WriteExcel;

use Expedia::Tools::GlobalVars  qw($sendmailProtocol $sendmailIP $sendmailTimeout);
use Expedia::Tools::GlobalVars qw($cnxMgr);
#use Expedia::Tools::GlobalFuncs qw(&_getcompanynamefromcomcode);
use Expedia::Databases::MidSchemaFuncs  qw(&getUserComCode &getFpec);
use Expedia::Tools::Logger qw(&monitore &debug &notice &warning &error);
use Expedia::WS::Back           qw(&BO_GetBookingFormOfPayment);
use Expedia::WS::Commun           qw(&isAuthorize &ticketingIssue);

@EXPORT_OK = qw(&emd_reporting &tkt_emd);

sub tkt_emd
{
	my $command 	= shift; 
	my $type    	= shift; 
	my $GDS     	= shift;
	my $market  	= shift;
	my $RTU_markup 	= shift;
	my $tpid 		= shift;
	my $gpid 		= shift;
	my $res     	= "";
    my $command_sauv = $command;
	
	my $lines    	= $GDS->command(Command => $command, NoIG => 1, NoMD => 0);
	my $error_msg;
	
	$PNRId	= undef;
	$percode	= undef;
	$comcode  = undef;
	%h_percode = ();
	%h_token = ();
	%h_tsmpax  = ();
	$sp       = 0;
	@liste_tsm = ();
	$no_tsm    = 0;
	$fp       = 0; 
	$status = '';
	$pax = '';
	$err = 0;
	$tsm_mono = 0;
	$t_token = 0;
	$t_percode = 0;

	#COMMAND could be "RT" (TAS) or result of "QS" (BTC)
	foreach my $line (@$lines)
	{
		  if ($line =~ /^ RP\/(\w+)(\/(\w+)).*\s+(\w+)\s* $/x)
		  {
					my ($r, $q, $a) = ($1, $3, $4);
					$PNRId = $a;
					$log_id=$PNRId;
					notice("PNRID:".$PNRId);
							  notice ("##############################################################################");
							  notice ("#                        DEBUT DE TRAITEMENT DU PNR:".$PNRId);
							  notice ("##############################################################################");
					#last;
		  }
		  
		  if($line =~ /(.*)RM \*TOKEN\s(.*)(.*)/)
		  {
					$token = $2;
					if($token =~/P(.*)/)
									{ 
						$pax=substr($token,length($token)-1,1); 
						$token=substr($token,0,length($token)-3); 
					}
					else{
						$pax = "1"; 
					}
					
					if($token =~/___/)
					{
						$token=substr($token,0,8).substr($token,11,8);
					}
					notice("PAX:".$pax);
					notice("TOKEN:".$token);
					$h_token{$pax}=$token;
					$t_token = 1;
		  }
	}

	#notice("LINES:".Dumper($lines));
	#Check for the PERcODE
	$command_RH  = 'RTR/PERCODE';
	$lines_percode    = $GDS->command(Command => $command_RH, NoIG => 1, NoMD => 0);
	foreach $line_percode (@$lines_percode)
	{
		if($line_percode =~ /(.*)RM \*PERCODE\s*(\d*)(.*)/ )
		{
			debug("percode:".$2);
			if(length($3) == 0)
			{ $pax = "1"; }
			else{$pax=substr($3,2,1);}
			debug("pax:".$pax);
		  $percode= $2;
		  $h_percode{$pax}=$2;
		  $t_percode =1;
		}
	}

	if(defined($percode) && $percode ne '')
	{
		$comcode=&getUserComCode($percode);
		if(defined($comcode)){debug("Comcode:".$comcode);}
	}

	##### NO TOKEn NO PErcOdE we leave 
	if($t_token ne 1 && $t_percode ne 1)
	{
		if($type eq "BTC")
		{
			&NoPerTok($GDS,'RM* PLEASE ADD PERCODE RE-QUEUE PNR');
		}
		$err = 1;
		$error_msg="Token and Percode missing";
	}

	if($err == 0)
	{
		############## Check the EMD ###############
		my $lines_tqm    = $GDS->command(Command => 'TQM', NoIG => 1, NoMD => 0);
		notice("TQM:".Dumper($lines_tqm));

		foreach my $lines_tqm (@$lines_tqm)
		{
			#Do know if it's a mono pax
			if ($lines_tqm =~ /^TSM\s*(\d+)\s*TYPE/x)
			{
				notice("=====>>> ONE PAX");
				$tsm_mono=$1;	
				debug("NUM TSM:".$tsm_mono);
				$sp = 1;
			}

			#to get the pax and the tsm number in multi pax
			if($lines_tqm =~ /^(\d+)\s*.(\d+)(.*)/ && $sp != 1)
			{
				if($sp != 2){notice("=====>>> MULTI PAX");}
				debug("NUM TSM:".$1);
				debug("PAX:".$2);
				push @liste_tsm, $1;
				$h_tsmpax{$1}=$2;
				$sp = 2;
			}

			#to get the pax number in mono pax
			if($sp == 1 && $lines_tqm =~ /^\s*(\d+)..*\/.*/)
			{
				$pax=$1;
				$h_tsmpax{$tsm_mono}=$pax; #only one TSM
				notice("PAX:".$1);
				#last;
			}
		 
			#in mono pax, get the FP 	
			if($sp == 1 && $lines_tqm =~ /^FP(.*)/ )
			{
			    if($type eq "BTC")
				{
				notice("=====>>> FP is available, we will do nothing - ".$lines_tqm);
				&add_report($market, "KO" , $PNRId, $pax, $h_tsmpax{$tsm_mono}, $comcode, $h_percode{$pax}, $h_token{$pax}, "FP is available, we will do nothing - ".$lines_tqm);
				last;  # TODO NE PAS SORTIR POUR L'EMISSION DES OFFLINES 
				}
				$fp=  1; 
			}

			if($lines_tqm =~/AUCUN ENREGISTREMENT TSM/ || $lines_tqm =~/NO TSM RECORD EXISTS/ || $lines_tqm =~/NO EXISTE NINGUN REGISTRO TSM/ )
			{
				$sp = 0;
			}
		}

		#ADD A FP TO THE EMD 
		if($fp == 0)
		{

			# SP = 0 PAS DE TSM 
			if($sp == 0)
			{
				#cannot happen for TAS (already check before if we have EMD)
				if($type eq 'BTC')
				{
					$command="RM* NO EXISTING TSM";
					&NoPerTok($GDS,$command);
					&add_report($market, "KO" , $PNRId, $pax, 0, $comcode, $h_percode{$pax}, $h_token{$pax}, $command);
				}
			}	
			# SP MULTI PAX 
			elsif($sp == 2)
			{
			#IF mutli pax, we need to check every TQM for each PAX 
				foreach(@liste_tsm)
				{
					$fp = 0;
					$command='TQM/M'.$_;
					my $lines_tqm    = $GDS->command(Command => $command, NoIG => 1, NoMD => 0);
					notice("TQM/M:".Dumper($lines_tqm));
					foreach my $lines_tqm (@$lines_tqm)
					{
						if($lines_tqm =~ /^FP/ )
						{	
							notice("=====>>> FP trouve:".$lines_tqm." for PAX:".$pax);						
							#ADD ERROR MESSAGE ONLY IN OFFLINE 
							if($type eq 'BTC')
							{
								my $tmp= "ALREADY EXIST ".$lines_tqm;
								&add_report($market, 'OK', $PNRId, $pax, $_, $comcode, $h_percode{$pax}, '', $tmp);
								last; # TODO DO NOT LEAVE FOR TICKETING 
							}
							$fp = 1;
						}
					}
						
					# NO FP ADD IT
					if($fp == 0)
					{
						$pax = $h_tsmpax{$_};
						##### NO TOKEn NO PErcOdE we leave 
						if(!exists($h_percode{$pax}) && !exists($h_token{$pax})){
							if($type eq 'BTC')
							{
								&NoPerTok($GDS,'RM* PLEASE ADD PERCODE RE-QUEUE PNR');
							}
							$err = 1;
							$error_msg="TSM $_ :Token and Percode missing";
						}
						else
						{
							$command = &add_fp($h_percode{$pax},$comcode,$h_token{$pax},$market,$pax,$_,$GDS,$PNRId,$RTU_markup);
							#REPORTING
							#my $date = strftime("%Y%m%d%H%M%S", localtime());
							if($command =~/ERROR/){ $status="KO";} else { $status="OK"; $command=substr($command,10,2); }
							&add_report($market, $status , $PNRId, $pax, $_, $comcode, $h_percode{$pax}, $h_token{$pax}, $command);
						}
					}					
				}
			}
			# MONO PAX 
			else
			{
				##### NO TOKEn NO PErcOdE we leave 
				if(!exists($h_percode{$pax}) && !exists($h_token{$pax}))
				{
					&NoPerTok($GDS,'RM* PLEASE ADD PERCODE RE-QUEUE PNR');
					$err = 1;
					$error_msg="TSM 1 :Token and Percode missing\n";
				}
				else
				{
					$command = &add_fp($h_percode{$pax},$comcode,$h_token{$pax},$market,$pax,$tsm_mono,$GDS,$PNRId,$RTU_markup); 
					if($type eq 'BTC')
					{
						if($command =~/ERROR/){ $status="KO";} else { $status="OK";  $command=substr($command,10,2);}
						&add_report($market, $status, $PNRId, $pax, $tsm_mono, $comcode, $h_percode{$pax}, $h_token{$pax}, $command);
					}
					else
					{
						if($command =~/ERROR/)
						{
							$err=1; # log an error in dispatch 
							$error_msg= "TSM 1:".$command;
						}
					}
				}
			}	
			# ---------------------------------------------------------------------
		} # fin fp == 0 
		
		############EMD TICKETING 
		
		#IF NO ERROR WHEn adding the FOP 
		if($err == 0 )
		{
			#TRick to add the mono pax in the loop
			if($sp eq 1){ @liste_tsm=(1);}
			
			foreach(@liste_tsm)
			{
				eval{
					$command='TQM/M'.$_;
                    my $lines_tqm = $GDS->command(Command => $command, NoIG => 1, NoMD => 0);
                    if(getEmdPrice($lines_tqm) == 1){
						notice('ComCode : '.$comcode);
						notice('Pos : '.$market);
						if (isAuthorize('air.authorization-call-fbs-ticketing-for-issue-emd', $market, $comcode)){
							notice("Use FBS web service");
							notice("TSM : ".$_);
							notice("PNR : ".$PNRId);
							notice("TPID : ".$tpid);
							if(! defined $tpid){
								$err = 1;
								$error_msg = "The value of TPID doesn't exist in XML.";
								&monitore("TAS_TICKETING", "EMD_ISSUE_USING_SUPPLY_LAYER", "ERROR", $market, "air", $PNRId, $error_msg, "WEBSERVICE CALL");					
								last;
							}else{
								my $response = ticketingIssue($PNRId, $tpid, $gpid, 'EMD', $_);
								if($response->{'code'} eq 'OK'){
									if($response->{'tickets'}->[0]->{'code'} eq 'OK'){
										notice('Result of the issuance of EMD : '.$response->{'tickets'}->[0]->{'message'});
										&monitore("TAS_TICKETING", "EMD_ISSUE_USING_SUPPLY_LAYER", "INFO", $market, "air", $PNRId, '', "WEBSERVICE CALL");
									}else{
										&monitore("TAS_TICKETING", "EMD_ISSUE_USING_SUPPLY_LAYER", "ERROR", $market, "air", $PNRId, $response->{'tickets'}->[0]->{'message'}, "WEBSERVICE CALL");
										notice('Error when issue EMD : '.$response->{'tickets'}->[0]->{'message'});
										$err = 1;
										$error_msg="TSM $_:".$lines_tqm->[0];
										last;
									}
								}else{
									monitore("TAS_TICKETING", "EMD_ISSUE_USING_SUPPLY_LAYER", "INFO", $market, "air", $PNRId, "Error occurred when connexion with FBS", "WEBSERVICE CALL");
									notice('Error when issue EMD : '.$response->{'message'});
									$err = 1;
									$error_msg="TSM $_:".$lines_tqm->[0];
									last;
								}
							}
						}else{
							notice("Use cryptic commandes");
							$command='TTM/M'.$_.'/EPR-EMLA';
							my $lines_tqm    = $GDS->command(Command => $command, NoIG => 1, NoMD => 1);
							notice("RES:".Dumper($lines_tqm));
							if($lines_tqm->[0] !~ "OK EMD"){
								$err = 1;
								$error_msg="TSM $_:".$lines_tqm->[0];
								last; # stop loop on the EMD if any errors
							}
						}
						$GDS->command(Command=>$command_sauv, NoIG=>1, NoMD=>1);
					}else{
                        notice('Price of EMD is free => we don\'t need to issue it');
                    }
				};
				if (@_){
				    notice("TSM $_ : Error during issue EMD.");
					$err = 1;
					$error_msg="TSM $_ : Error during issue EMD.";
					last;
				}
			}
			
			# Validation des modifications.
			$GDS->command(Command=>'RF'.$GDS->modifsig, NoIG=>1, NoMD=>1);
			my $ER1 = $GDS->command(Command=>'ER',                NoIG=>1, NoMD=>1);
			my $ER2 = $GDS->command(Command=>'ER',                NoIG=>1, NoMD=>1);
		} # FIN err == 0 
		
	} # FIN err == 0 
	
	#EGE-90741 we need to add the ETK remark if an EMD have been succesfully ticketed. 
	my $emd_abag_found = 0;
	my $ssr_found = 0 ;
	my $oid_online_found = 0 ;
	my $ret_rt = $GDS->command(Command => 'RT'.$refpnr , NoIG => 1, NoMD => 0);
	my $ret_rh  = $GDS->command(Command => 'RH/ALL'  , NoIG => 1, NoMD => 0);
	my $sauv_etk = '';

	foreach $line_rh (@$ret_rh)
	{
			#search for one ABAG EMD
			if($line_rh =~/SA\/\*SSR ABAG/)
			{
				notice("ABAG FOUND:".$line_rh);
				$emd_abag_found = 1;
			}

			if($line_rh =~/.*RF-.*CR-\w{3}EC38\w{2}\s.*/ && $emd_abag_found == 1)
			{
				notice("RF LINE:".$line_rh);
				$oid_online_found = 1;
				last;
			}

			#if no line found at the end, we will do nothing more
	}

	if($oid_online_found == 1 )
	{
		foreach $line_rt(@$ret_rt)
		{
			if($line_rt =~/\s(.*)\s\/SSR ABAG/ && $ssr_found == 0)
			{
				notice("SSR LINE:".$line_rt);
				notice("NUMBER:".$1."|");
				$ssr_found = $1;
			}

			#we found directly the FA LINE with the /EXX
			if($line_rt =~/.*FA PAX (\d{3}-\d{10})\/DT.*\/E(\d{2}).*/ && $ssr_found != 0 )
			{
				if($1 == $ssr_found)
				{
					notice("FA:".$line_rt);
					notice("ETK:".$1);
					$sauv_etk=$1;
					last;
				}
			}

			#we found a FA line but without /EXX , we need to check the line after
			if($line_rt =~/.*FA PAX (\d{3}-\d{10})\/DT.*/ && $ssr_found != 0 )
			{
				notice("FA NOT FUll:".$1);
				$sauv_etk=$1;
			}

			if($sauv_etk ne '')
			{
				if($line_rt=~/.*\/E(\d{2})/ || $line_rt=~/.*\/E(\d{1})/)
				{
					#the ssr line and the fa match
					if($1 == $ssr_found)
					{
							notice("COMPLETEMENT LINE FA:".$line_rt);
							notice("ETK:".$1);
							last;
					}

				}
			}
		}

		notice("ETK FOUND:".$sauv_etk);
		if($sauv_etk ne '')
		{
			$GDS->command(Command => 'RM*EMD ONLINE '.$sauv_etk, NoIG => 1, NoMD => 0);
			$GDS->command(Command => 'RFBTCTAS', NoIG => 1, NoMD => 1);
			$GDS->command(Command => 'ER', NoIG => 1, NoMD => 1);
		}
	}
	#END EGE-90741			
		
	# IF AN ERROR , REJECT IN DISPATCH 
	if($err eq 1)
	{
		#reject the EMD
		notice('### TAS MSG TREATMENT 69 ###');
		return (69, $error_msg );
	}
	
	notice ("##############################################################################");
	notice ("#                        FIN DE TRAITEMENT DU PNR:".$PNRId."                 #");
	notice ("##############################################################################");


	  $GDS->disconnect;
	  notice("DECONNECTION");
	  my $tmp_amadeus="amadeus-".$market;
	  $GDS      = $cnxMgr->getConnectionByName($tmp_amadeus);
	  $GDS->connect;
	  
	  return 1;
}

sub add_fp
{
	my $perCode = shift;
	my $comCode = shift;
	my $token   = shift;
	my $market  = shift;
	my $pax     = shift;
    my $tsm     = shift;
	my $GDS		= shift;
	my $pnr		= shift;
	my $RTU_markup = shift;
	
	my $myfop   ='';
	my $command='';
	notice("=====>>> FP NOT IN TSM WILL ADD IT");
	
	my $service='AIR';
	my $commonString  = undef;
	my $datasToReturn = [];
	my $amadeusMsg;
	my $hDatas = BO_GetBookingFormOfPayment('BackWebService',$market,$comCode,$token,$perCode,$service,undef,undef,$pnr);

	if ((defined $hDatas)  && (defined $hDatas->{PaymentType}) && ($hDatas->{PaymentType} =~ /^(ICCR|OOCC|CC|EC)$/))
	{

		if ($hDatas->{PaymentType} =~ /^EC$/ || $RTU_markup eq 'EC') {
			$myfop=&getFpec($market);
			$myfop=substr($myfop,2,length($myfop)-2);
			$myfop="FP-".$myfop;
			
		}
		elsif ($hDatas->{PaymentType} =~ /^(ICCR|OOCC)$/) {
		  
			  push (@$datasToReturn,'RM PLEASE ASK FOR CREDIT CARD');
			  
		}
		elsif ($hDatas->{PaymentType} =~ /^CC$/){
		  
			 #Une erreur quelconque dans le WS, on renvoit le message d'erreur, ERROR
			  if(defined $hDatas->{ErrorMsg})
			  {
				 push (@$datasToReturn, 'Error Message = '.$hDatas->{ErrorMsg});
				 notice("Error Message:".$hDatas->{ErrorMsg});
			  }
			  $commonString = $hDatas->{CardType}.$hDatas->{CardNumber}.'/'.$hDatas->{CardExpiry}
			  if (exists $hDatas->{CardType} && exists $hDatas->{CardNumber} && exists $hDatas->{CardExpiry});
			  
			  if (defined $commonString) {
				  my $fop=&getFpec($market);
				  push (@$datasToReturn, 'FP-CC'.$commonString);
				  push (@$datasToReturn, 'FPO/'.substr($fop, 2).'+/CC'.$commonString);
			  }
			  else {
				  push (@$datasToReturn,'RM PLEASE ASK FOR CREDIT CARD');
				  
			  }			
		  
	   }
		 
	   if (defined (@$datasToReturn[0])){
		if (@$datasToReturn[0] !~ /^Error Message/) {
			$myfop=@$datasToReturn[0];
			notice("DAZADADADADAZDA:".@$datasToReturn[0]);
		}	
		else
		{
			$myfop="";
		}
	  }
	  
	  
	 } # end ICCR|OOCC|CC|EC
		
		
	#CAS Ou ws EN ErreUR 
	if($myfop=~/^FP/)
	{
	            $command="TMI/M".$tsm."/".$myfop;
				my $ret = $GDS->command(Command=>$command, NoIG=>1, NoMD=>1);
					if($ret->[0] !~ /^TSM/)
					{
						$command="RM* ERROR FOP NOT INSERTED BY BTC EMD, PLEASE INSERT MANUALLY";
					}
					else
					{
						$command="RM* FOP INSERTED BY BTC EMD";
					}
	}
	else
	{
			$command="RM* TECHNICAL ERROR";
	}
	my $ret2 = $GDS->command(Command=>$command, NoIG=>1, NoMD=>1);
	# ---------------------------------------------------------------------  
	# Validation des modifications.
	$GDS->command(Command=>'RF'.$GDS->modifsig, NoIG=>1, NoMD=>1);
	my $ER1 = $GDS->command(Command=>'ER',                NoIG=>1, NoMD=>1);
	my $ER2 = $GDS->command(Command=>'ER',                NoIG=>1, NoMD=>1);
    return $command;
}

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Répétion des Infos depuis une info de "PerCode"
sub _getInfosOnPerCode {
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
sub _getBillingEntityLabel {
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

sub emd_reporting
{

my $pos = shift; 
my $mytime_gen= strftime("%Y-%m-%dT00:00:00",localtime());
  
# ===================================================================
# Génération du fichier EXCEL
# ===================================================================
my $xlsFile = "/var/tmp/EMD_REPORTING_".$pos.".xls";

my $workbook  = Spreadsheet::WriteExcel->new($xlsFile);
die "Problème à la création du fichier excel: $!" unless defined $workbook;

my $worksheet = $workbook->addworksheet();

my $row = 0;

my $format1 = $workbook->addformat();
my $format2 = $workbook->addformat();
my $format3 = $workbook->addformat();

    $format1->set_border(1);
    $format1->set_bottom; 
    $format1->set_top;
    $format1->set_align('center');
    $format1->set_size(8);
    $format1->set_text_wrap();
        
    $format2->set_border(1);
    $format2->set_bottom; 
    $format2->set_top;
    $format2->set_bold;
    $format2->set_align('center');
    $format2->set_size(12);
    $format2->set_fg_color('silver'); 

    #CAS EN ERREUR - ROUGE ET GRAS
    $format3->set_border(1);
    $format3->set_bottom; 
    $format3->set_top;
    $format3->set_bold;
    $format3->set_align('vjustify');
    $format3->set_size(8);
    $format3->set_text_wrap();
    $format3->set_fg_color('red'); 
    
      
		$worksheet->set_column('A:A', 5);
		$worksheet->set_column('B:B', 5);
		$worksheet->set_column('C:C', 10);
		$worksheet->set_column('D:D', 10);
		$worksheet->set_column('E:E', 15);
		$worksheet->set_column('F:F', 25);
		$worksheet->set_column('G:G', 25);
		$worksheet->set_column('H:H', 15);
		$worksheet->set_column('I:I', 80);
		$worksheet->set_column('J:J', 80);

$worksheet->set_column(1, 1, 30); # Column B width set to 30

    #create table EMD_REPORT 
#(country varchar(2) not null, status varchar(2) not null, pnr varchar(6) not null, pax number not null, tsm number not null, comcode number , percode number , token varchar(16), textfree varchar(100), creation_date datetime not null)

$worksheet->write(0, 0, 'POS', $format2);
$worksheet->write(0, 1, 'STATUS', $format2);
$worksheet->write(0, 2, 'PNR', $format2);
$worksheet->write(0, 3, 'PAX', $format2);
$worksheet->write(0, 4, 'TSM', $format2);
$worksheet->write(0, 5, 'COMPANY NAME', $format2);
$worksheet->write(0, 6, 'COMCODE', $format2);
$worksheet->write(0, 7, 'PERCODE', $format2);
$worksheet->write(0, 8, 'TOKEN', $format2);
$worksheet->write(0, 9, 'DESC', $format2);
$worksheet->write(0, 10, 'DATE', $format2);

  my $dbh = $cnxMgr->getConnectionByName('mid');
  $request="SELECT * FROM EMD_REPORT WHERE COUNTRY_CODE='".$pos."' ORDER BY CREATION_DATE DESC";
  my $results = $dbh->saar($request);
  
  if(scalar(@$results) == 0) { return 1; } 
  
$row++;
foreach $res_report (@$results)
{
   my @myreport = ();
   my $libelle_error = "";
   my $compteur_report = 1;
   $format = $format1;
   
   my $company_name = &_getcompanynamefromcomcode($res_report->[5]);
  
   $worksheet->write($row, 0, $res_report->[0], $format);
   $worksheet->write($row, 1, $res_report->[1], $format);
   $worksheet->write($row, 2, $res_report->[2], $format);
   $worksheet->write($row, 3, $res_report->[3], $format);
   $worksheet->write($row, 4, $res_report->[4], $format);
   $worksheet->write($row, 5, $company_name   , $format);
   $worksheet->write($row, 6, $res_report->[5], $format);
   $worksheet->write($row, 7, $res_report->[6], $format);
   $worksheet->write($row, 8, $res_report->[7], $format);
   $worksheet->write($row, 9, $res_report->[8], $format);
   $worksheet->write($row, 10, $res_report->[9], $format);
   $row++;
}
$workbook->close();

# ===================================================================
# Envoi email
# ===================================================================
eval
{
$subject = 'EMD reporting: '.$pos;

my $var_mail="EMD_TO";
my $my_from = 'noreply@egencia.eu';
my $my_to   = &getMailForEmd($pos,$var_mail);

my $my_cc   = '';

my $msg = MIME::Lite->new(
        From     => $my_from,
        To       => $my_to,
        Cc       => $my_cc,
        Subject  => $subject,
  Type     => 'application/vnd.ms-excel',
  Encoding => 'base64',
        Path     => $xlsFile); 


MIME::Lite->send($sendmailProtocol, $sendmailIP, Timeout => $sendmailTimeout);
$msg->send;
};
  if ($@) {
    error('Problem during email send process. '.$@);
  }
  
unlink($xlsFile);

  my $midDB = $cnxMgr->getConnectionByName('mid');
  my $query = "DELETE FROM EMD_REPORT WHERE COUNTRY_CODE=?";
  my $finalRes = $midDB->saarBind($query, [$pos]);


}



# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Get the company name with the comcode
sub _getcompanynamefromcomcode {
  my $code = shift;

  my $midDB = $cnxMgr->getConnectionByName('mid');

  my $query = "
    SELECT AMADEUS_NAME
      FROM AMADEUS_SYNCHRO
     WHERE CODE = ?
       AND TYPE = 'COMPANY' ";

  return $midDB->saarBind($query, [$code])->[0][0];
}

sub NoPerTok
{
	my $GDS	    = shift;
    my $command = shift;
	my $res = $GDS->command(Command => $command, NoIG => 1, NoMD => 0);
    # ---------------------------------------------------------------------
    # Validation des modifications.
       $GDS->command(Command=>'RF'.$GDS->modifsig, NoIG=>1, NoMD=>1);
    my $ER1 = $GDS->command(Command=>'ER',                NoIG=>1, NoMD=>1);
    my $ER2 = $GDS->command(Command=>'ER',                NoIG=>1, NoMD=>1);
    # ---------------------------------------------------------------------
}

sub add_report
{
	my $market 		= shift;
	my $status 		= shift;
	my $pnr			= shift;
	my $pax			= shift;
	my $tsm			= shift;
	my $comcode 	= shift;
	my $percode 	= shift;
	my $token		= shift;
	my $freetext	= shift;
	
  my $dbh = $cnxMgr->getConnectionByName('mid');
  my $query="INSERT INTO EMD_REPORT VALUES (?,?,?,?,?,?,?,?,?,getdate())";
  $dbh->doBind($query, [$market, $status, $pnr, $pax, $tsm, $comcode, $percode, $token, $freetext]);  
}

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Get mail for EMD
sub getMailForEmd {
  my $market    = shift;
  my $champ     = shift || undef;
  
  my $midDB = $cnxMgr->getConnectionByName('mid');
  my $query = "
    SELECT EMD_TO
        FROM MO_CFG_MAIL
     WHERE COUNTRY= ?  ";
  my $finalRes = $midDB->saarBind($query, [$market])->[0][0];
  return $finalRes;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

sub getEmdPrice {
  my $tqm_lignes = shift;
  my $authorizeIssueEmd = 1;
  foreach my $ligne (@$tqm_lignes) {
     if($ligne =~/TOTAL/){
        $ligne =~ m/([0-9]{1,2}.[0-9]{2})/;
        if($1 eq '0.00'){
            $authorizeIssueEmd = 0;
        }
     }
  }
  return $authorizeIssueEmd;
}

1;
