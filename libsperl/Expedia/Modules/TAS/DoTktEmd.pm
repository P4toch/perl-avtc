package Expedia::Modules::TAS::DoTktEmd;
#-----------------------------------------------------------------
#
# 2015-06-23 sdubuc 
#
#-----------------------------------------------------------------

use strict;

use File::Slurp;
use Data::Dumper;
use Expedia::Tools::Logger qw(&debug &notice &warning &error &monitore);
use Expedia::Tools::GlobalVars qw($cnxMgr);
#use Expedia::XML::Booking;
#use Expedia::XML::Config;
use Expedia::WS::Front                 qw(&addBookingComment);
use Expedia::Databases::MidSchemaFuncs  qw(&getFpec);
use Expedia::Tools::GlobalVars qw($cnxMgr $h_context);
use Expedia::Tools::EmdFuncs qw (&tkt_emd);

use Expedia::XML::MsgGenerator;
use POSIX qw(strftime);

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
  my $GDS          = $params->{GDS};
  my $RTU_markup =   $globalParams->{RTU_markup};
  my $market       = $globalParams->{market};
  my $mdCode       = $params->{mdCode};  
  my $countryCode  = $ab->getCountryCode({trvPos => $ab->getWhoIsMain});
  my $tpid         = $ab->getTpid ({trvPos => $ab->getWhoIsMain});
  my $gpid         = $ab->getGpid ({trvPos => $ab->getWhoIsMain});
  my $fpec         = &getFpec($countryCode);

  my $h_pnr        = $params->{Position};
  my $refpnr       = $params->{RefPNR};
  my $position     = $h_pnr->{$refpnr};
  
  
  notice("Position du pnr:".$refpnr." dans le traveldossier:".$position);

#	my $OID    = $GDS->{_OFFICEID};
#	my $market = $params->{GlobalParams}->{market};
	#our use to transfert the variable to the others package
	our $log_id= '';
	
	my $dbh  = $cnxMgr->getConnectionByName('mid');

	my $PNRId = undef;
	my $line  = undef;
	my $command_RH = undef;
	my $lines_percode = undef;
	my $line_percode = undef;
	my $percode= undef;
	my $comcode = undef;
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
	
	my $type="TAS";
	my $command = 'RT'.$refpnr;
	
	my $lines        = $GDS->command(Command => $command, NoIG => 1, NoMD => 0);
	
	my $lines_tqm    = $GDS->command(Command => 'TQM', NoIG => 1, NoMD => 0);

	if($lines_tqm->[0] =~/AUCUN ENREGISTREMENT TSM/ || $lines_tqm->[0] =~/NO TSM RECORD EXISTS/ || $lines_tqm->[0] =~/NO EXISTE NINGUN REGISTRO TSM/ )
	{
		notice("NO EMD");
	}
	else
	{
		&monitore("TAS_TICKETING", "EMD_ISSUE","INFO",$market,"AIR",$refpnr,'',"START"); #  AIR only for the moment
		my $res = '';
		my $error_msg = '';
		if(! defined $tpid){
			$res = 69;
			$error_msg = "The value of TPID does not exist in XML";
		}else{
			notice("TPID : ".$tpid);
			notice("GPID : ".$gpid);
			($res, $error_msg)  = &tkt_emd($command,$type,$GDS,$market,$RTU_markup,$tpid,$gpid);
		}
		if($res == 69)
		{
			notice('1 ### TAS MSG TREATMENT 69 ###');
			$pnr->{TAS_ERROR} = 69;
			my $soapOut = undef;
			$soapOut = &addBookingComment('DeliveryWS', {
				language     => 'FR',
				mdCode       => $mdCode,
				eventType    => 9,
				eventDesc    => "PNR $refpnr TAS message : $error_msg " });
			#EGE-87369	 
			#notice('### TAS MSG TREATMENT 69 ###');
			#$pnr->{TAS_ERROR} = 69;
			#$pnr->{EMD_ERROR} = $error_msg;
			&monitore("TAS_TICKETING", "EMD_ISSUE","ERROR",$market,"AIR",$refpnr,'',"END"); #  AIR only for the moment
		}
		else 
		{
			&monitore("TAS_TICKETING", "EMD_ISSUE","INFO",$market,"AIR",$refpnr,'',"END"); #  AIR only for the moment
		}
	}
	
return 1;

}

1;


