package Expedia::Modules::EMD::PnrGetInfos;
#-----------------------------------------------------------------
#
# 2014-06-17 sdubuc 
#
#-----------------------------------------------------------------

use Exporter 'import';
use strict;
use Net::FTP;
use File::Slurp;
use Data::Dumper;
use POSIX qw(strftime);
use Expedia::Tools::Logger qw(&debug &notice &warning &error);
use Expedia::Tools::GlobalVars qw($cnxMgr);
use Expedia::XML::Booking;
use Expedia::XML::Config;
use Expedia::Databases::MidSchemaFuncs  qw(&getUserComCode &getFpec);
use Expedia::Tools::GlobalVars qw($cnxMgr $h_context $GetBookingFormOfPayment_errors);
use Expedia::Tools::GlobalFuncs qw(&stringGdsOthers &getRTUMarkup &check_TQN_markup);
use Expedia::WS::Back qw(&BO_GetBookingFormOfPayment);
use Expedia::XML::MsgGenerator;
use POSIX qw(strftime);
#use Expedia::Tools::SendMail qw(&BackWSSendError);


sub run {

	my $self   = shift;
	my $params = shift;
	

	my $globalParams = $params->{GlobalParams};
	my $moduleParams = $params->{ModuleParams};

	my $GDS    = $params->{GlobalParams}->{gds};
	my $OID    = $GDS->{_OFFICEID};
	my $market = $params->{GlobalParams}->{market};
	#our use to transfert the variable to the others package
	our $log_id= '';
	
	my $dbh  = $cnxMgr->getConnectionByName('mid');

	my $x = 1;
    my $limite = 2;

    for ($x=1;$x<$limite;$x++)
    {

	my $PNRId = undef;
	my $line  = undef;
	my $command_RH = undef;
	my $lines_percode = undef;
	my $line_percode = undef;
	my $percode= undef;
	my $comcode = undef;
	my $countryCode = undef;
	my $nb_pnr_in_queue = undef;
	my $count = 1;
    my $fp		= 0;
	my $token	= '';
	my $tsm_mono   = 0;
	my $status    = '';
	my %h_percode = ();
	my %h_tsmpax  = ();
	my %h_token  = ();
	my $sp = undef;
	my @liste_tsm = undef;
    my $no_tsm = 0;	
	my $pax = '';
	my $err ='';
	my $t_token= '';
	my $t_percode ='';
	my $my_queue="19C0"; 
	my $command  = 'QS/'.$OID.'/'.$my_queue;
	my $sauv_QS  = $command; 
	
	my $lines    = $GDS->command(Command => $command, NoIG => 1, NoMD => 0);
	notice("LINES:".Dumper($lines));

    # CAS OU LE RETOUR EST "50 PNR SANS OPC/OPW TROUVES - RECOMMENCER LA SAISIE
    if($lines->[0] =~ /PURGES TROUVES/ || $lines->[0] =~ /OPW TROUVES/ || $lines->[0] =~ /SORTI DE LA FILE/ || $lines->[0] =~ /OPW FOUND/ || $lines->[0] =~ /OPW EXISTED/)
    {
        $lines    = $GDS->command(Command => $command, NoIG => 1, NoMD => 0); 
        notice ("QS FOR OPW:".$lines->[0]);
    }
      
    if($lines->[0] =~ /IGNORE AND RE-ENTER/ || $lines->[0] =~ /IGNORER\/ENTER DE NOUVEAU/ || $lines->[0] =~ /IGNORE Y VUELVA A INTRODUCIR/  || $lines->[0] =~ /TERMINER OU IGNORER/)
    {
      $GDS->disconnect;
      notice("DECONNECTION");
      $GDS      = $cnxMgr->getConnectionByName('amadeus-FR');
      $GDS->connect;
      notice("CONNECTE A NOUVEAU");
      $lines       = $GDS->command(Command => $command, NoIG => 1, NoMD => 0); 
    }
    
    #COMMANDE POUR DETERMINER SI L'APPEL A LA QUEUE RENVOIE UN DOSSIER OU UN MESSAGE
    #POUR DIRE QUE LA QUEUE EST VIDE
    #SI C'EST VIDE, ALORS ON SORT DE LA QUEUE, ET ON PASSE A LA SUIVANTE
    while($lines->[0] !~ /VIDE/ && $lines->[0] !~ /QUEUE.*EMPTY/ && $lines->[0] !~ /NOT ASSIGNED/ && $lines->[0] !~ /NON ATTRIBUEE/
    && $lines->[0] !~ /PERIODO EN BLANCO/ && $lines->[0] !~ /COLA VACIA/)
    {
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

		  #LA QUEUE N'EST PAS VIDE
		  #PREMIERE ETAPE TROUVER LE PNR  POUR  RECUPERER LE PERCODE
		  foreach my $line (@$lines)
		  {
				  if ($line =~ /^ RP\/(\w+)(\/(\w+)).*\s+(\w+)\s* $/x)
				  {
							my ($r, $q, $a) = ($1, $3, $4);
							$PNRId = $a;
							$log_id=$PNRId;
							notice("PNRID:".$PNRId);
									  notice ("##############################################################################");
									  notice ("#                        DEBUT DE TRAITEMENT DU PNR:".$PNRId." AVEC OID:".$OID."               #");
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

		notice("LINES:".Dumper($lines));
		#ON RECHERCHE LE PERCODE
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
		if($t_token ne 1 && $t_percode ne 1){
			&NoPerTok($GDS,'RM* PLEASE ADD PERCODE RE-QUEUE PNR');
			$err = 1;
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
				if($sp == 1 && $lines_tqm =~ /^\s*(\d+).(\w{1}).*\/.*/)
				{
					$pax=$1;
					$h_tsmpax{$tsm_mono}=$pax; #only one TSM
					notice("PAX:".$1);
					#last;
				}
			 
				#in mono pax, get the FP 	
				if($sp == 1 && $lines_tqm =~ /^FP(.*)/ )
				{
					notice("=====>>> FP is available, we will do nothing - ".$lines_tqm);
					&add_report($market, "KO" , $PNRId, $pax, $h_tsmpax{$tsm_mono}, $comcode, $h_percode{$pax}, $h_token{$pax}, "FP is available, we will do nothing - ".$lines_tqm);
					$fp = 1;
					last;
				}

				if($lines_tqm =~/AUCUN ENREGISTREMENT TSM/ || $lines_tqm =~/NO TSM RECORD EXISTS/ || $lines_tqm =~/NO EXISTE NINGUN REGISTRO TSM/ )
				{
					$sp = 0;
				}
			}
 
			if($fp == 0)
			{

				# SP = 0 PAS DE TSM 
				if($sp == 0)
				{
					$command="RM* NO EXISTING TSM";
					&NoPerTok($GDS,$command);
					&add_report($market, "KO" , $PNRId, $pax, 0, $comcode, $h_percode{$pax}, $h_token{$pax}, $command);
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
								$fp = 1;
								my $tmp= "ALREADY EXIST ".$lines_tqm;
								&add_report($market, 'OK', $PNRId, $pax, $_, $comcode, $h_percode{$pax}, '', $tmp);
								last;
							}
						}
							
						# NO FP ADD IT
						if($fp == 0)
						{
							$pax = $h_tsmpax{$_};
							##### NO TOKEn NO PErcOdE we leave 
							if(!exists($h_percode{$pax}) && !exists($h_token{$pax})){
								&NoPerTok($GDS,'RM* PLEASE ADD PERCODE RE-QUEUE PNR');
								$err = 1;
							}
							else
							{
								$command = &add_fp($h_percode{$pax},$comcode,$h_token{$pax},$market,$pax,$_,$GDS,$PNRId);
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
					}
					else
					{
						$command = &add_fp($h_percode{$pax},$comcode,$h_token{$pax},$market,$pax,$tsm_mono,$GDS,$PNRId);
						#REPORTING
						if($command =~/ERROR/){ $status="KO";} else { $status="OK";  $command=substr($command,10,2);}
						&add_report($market, $status, $PNRId, $pax, $tsm_mono, $comcode, $h_percode{$pax}, $h_token{$pax}, $command);
					}
				}	
				# ---------------------------------------------------------------------
			} # fin fp == 0 
		} # FIN err == 0 
		notice ("##############################################################################");
		notice ("#                        FIN DE TRAITEMENT DU PNR:".$PNRId."                 #");
		notice ("##############################################################################");
		$log_id='';
		#QN - SUPPRIME
		#QD - POUR TEST
		###########POUR TEST#############
		#$command  = 'QD';
		#$lines    = $GDS->command(Command => $command, NoIG => 1, NoMD => 0);
		#debug("QD:".Dumper($lines));
		###########POUR TEST#############

		###########EN PROD#############     
		$command  = 'QN';
		$lines    = $GDS->command(Command => $command, NoIG => 1, NoMD => 0); 
		notice ("QN:".$lines->[0]);
		#########EN PROD#############
		
		# CAS OU LE RETOUR EST "50 PNR SANS OPC/OPW TROUVES - RECOMMENCER LA SAISIE
		if($lines->[0] =~ /OPW TROUVES/ || $lines->[0] =~ /SORTI DE LA FILE/ || $lines->[0] =~ /OPW FOUND/ || $lines->[0] =~ /OPW EXISTED/)
		{
			my $command  = 'QS/'.$OID.'/'.$my_queue;
			$lines    = $GDS->command(Command => $command, NoIG => 1, NoMD => 0); 
			notice ("QS FOR OPW:".$lines->[0]);
		}

		#when this error occurs, disconnect and reconnect to Amadeus --- Don't do a QN because, we can't be sure that we will be on the same before that before the deconnection 
		if($lines->[0] =~ /IGNORE AND RE-ENTER/ || $lines->[0] =~ /IGNORER\/ENTER DE NOUVEAU/ || $lines->[0] =~ /IGNORE Y VUELVA A INTRODUCIR/  || $lines->[0] =~ /TERMINER OU IGNORER/)
		{
		  $GDS->disconnect;
		  notice("DECONNECTION");
		  my $tmp_amadeus="amadeus-".$market;
		  $GDS      = $cnxMgr->getConnectionByName($tmp_amadeus);
		  $GDS->connect;
		  notice("CONNECTE A NOUVEAU");
		  $lines    = $GDS->command(Command => $sauv_QS, NoIG => 1, NoMD => 0);
		}
		###########POUR TEST#############
		#if($count == 1)
		#{
		#   notice("FIN:".$count);
		#   $command  = 'QI';
		#   $lines    = $GDS->command(Command => $command, NoIG => 1, NoMD => 0);
		#   notice ("QI:".$lines->[0]);
		#   last;
		#}
		#$count++;
		#notice("COuNT:".$count);
		###########POUR TEST#############
	}
	
sleep(20);

		  $GDS->disconnect;
		  notice("DECONNECTION");
		  my $tmp_amadeus="amadeus-".$market;
		  $GDS      = $cnxMgr->getConnectionByName($tmp_amadeus);
		  $GDS->connect;
		  
} # fin for
	
	
#if ((defined(@$GetBookingFormOfPayment_errors)) && (scalar(@$GetBookingFormOfPayment_errors) > 0))  
#{			
# 	BackWSSendError($market);	  
#}	
	
$GDS->disconnect;
	
#my $cmd=" /var/egencia/btc-emd/btc-emd.sh    --pos=".$market." &";
#system($cmd);



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
	
	
	
	my $myfop   ='';
	my $command='';
	notice("=====>>> FP NOT IN TSM WILL ADD IT");
	
	if (getRTUMarkup($market))  
	{
		#$GDS    = $pnr->{_GDS};	
		my $lines        = $GDS->command(Command => 'RT'.$pnr, NoIG => 1, NoMD => 0);	
		my $lines_tqn    = $GDS->command(Command => 'TQN', NoIG => 1, NoMD => 0);	
		my $lwdHasMarkup= check_TQN_markup($lines_tqn, $pnr, $market);
		notice('EMD MARKUP for RTU after TQN:'.$lwdHasMarkup);
		if ($lwdHasMarkup eq 'true'){
					
			$myfop=&getFpec($market);
			$myfop=substr($myfop,2,length($myfop)-2);
			$myfop="FP-".$myfop;
	
		}
	 					
	}	
	
	if ( $myfop eq '' ){
	
		# RÃ©pÃ©tion des moyens de paiement mis Ã our
		
		my $service='AIR';
    	my $commonString  = undef;
	    my $datasToReturn = [];
		my $amadeusMsg;
		my $hDatas = BO_GetBookingFormOfPayment('BackWebService',$market,$comCode,$token,$perCode,$service,undef,undef,$pnr);

		if ((defined $hDatas)  && (defined $hDatas->{PaymentType}) && ($hDatas->{PaymentType} =~ /^(ICCR|OOCC|CC|EC)$/))
		{
	
			if ($hDatas->{PaymentType} =~ /^EC$/ ) {
			
				$myfop=&getFpec($market);
				$myfop=substr($myfop,2,length($myfop)-2);
				$myfop="FP-".$myfop;
				
			}
			elsif ($hDatas->{PaymentType} =~ /^(ICCR|OOCC)$/) {
			  
				  push (@$datasToReturn,'RM PLEASE ASK FOR CREDIT CARD');
				  
			}
			elsif ($hDatas->{PaymentType} =~ /^CC$/){
				 
				
				
				  
				 #Une erreur quelconque dans le WS, on renvoit le message d'erreur, prÃ©dÃ©e ERROR
				  if(defined $hDatas->{ErrorMsg})
				  {
					 push (@$datasToReturn, 'Error Message = '.$hDatas->{ErrorMsg});
					 notice("Error Message:".$hDatas->{ErrorMsg});
				  }
				  $commonString = $hDatas->{CardType}.$hDatas->{CardNumber}.'/'.$hDatas->{CardExpiry}
							if ($hDatas->{CardType} && $hDatas->{CardNumber} && $hDatas->{CardExpiry});
				  
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
	
	}
	
	
	
	
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

1;


