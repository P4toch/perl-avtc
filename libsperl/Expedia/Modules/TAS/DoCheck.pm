package Expedia::Modules::TAS::DoCheck;
#-----------------------------------------------------------------
# Package Expedia::Modules::TAS::DoCheck
#
# $Id: DoCheck.pm 430 2008-03-12 16:09:40Z pbressan $
#
# (c) 2002-2007 Expedia.                   www.expediacorporate.fr
#-----------------------------------------------------------------

use Data::Dumper;

use Expedia::Tools::Logger qw(&debug &notice &warning &error &monitore);
use Expedia::Tools::GlobalVars  qw($cnxMgr);

sub run {
  my $self   = shift;
  my $params = shift;

  my $globalParams = $params->{GlobalParams};
  my $moduleParams = $params->{ModuleParams};
  my $changes      = $params->{Changes};
  my $item         = $params->{Item};
  my $pnr          = $params->{PNR};
  my $ab           = $params->{ParsedXML};
  my $GDS          = $params->{GDS};
  my $task = $item->{TASK};
  my $countryCode = $ab->getCountryCode({trvPos => $ab->getWhoIsMain});
  notice("COUNTRYCODE:".$countryCode);
  my $dbh = $cnxMgr->getConnectionByName('mid');
  
  #IEP RECUPERATION DES PAYS QUI SONT ACTIFS POUR IEP
  my $query="SELECT POS FROM IEP";
  my $h_pos = $dbh->sahr($query, 'POS');  
      
    my $os_cies = [
     'AF','LH','BA','AZ','TP','IB','IG','LX','LG','SN','KL','SK','AY','LO','OK','OS',
     'OU','TU','AT','BD','EI','UX','LK','AP','EN','A5','T7','V7','GN','FV','PS','ME',
     'EK','QR','HM','MK','UU','DL','CO','UA','NW','US','AC','AM','SB','TN','BM'
    ];
    
    $GDS->RT(PNR => $pnr->{'PNRId'}, NoPostIG => 1, NoMD => 1);
    
    my $doc    = $pnr->{'_XMLPNR'};
    my $tstdoc = $pnr->{'_XMLTST'};

    my @tst_node_list = $tstdoc->getElementsByTagName('fareList');

    my $tst_number = scalar (@tst_node_list);
    debug("TST number <1> = $tst_number");
    
    # ----------------------------------------------------------------
    my @fa_lines;
    my $command;

    # CHANGEMENT ITR/IEP BUG 15711
    $command='WM/ELN';
    $GDS->command(Command => $command, NoIG => 1, NoMD => 1);

	my $lines_ret;
	
    # Traitement des lignes FA
    foreach (@{$pnr->{'PNRData'}}) {
		next unless ($_->{'Data'} =~ /^FA\s+PAX\s+(\d+\-\d+).*?\/((S(\d{1})((-|,)?(\d{1})?)*)(\/)?.*)/o);     
		push @fa_lines, $1;
		# CHANGEMENT ITR/IEP BUG 15711
		if ($task eq 'tas-air-etkt') {
			my $typeMail;
			my $option;
			if ($h_pos->{$countryCode}) {
				$typeMail = 'IEP';
				$option = $2;
			} else {
				$typeMail = 'ITR';
				$option = 'L'.$_->{'LineNo'};
			}
			my $err_level = "INFO";
			notice('Sending '.$typeMail.' mail');
			$command = $typeMail.'-EMLA/'.$option;
			$lines_ret = $GDS->command(Command => $command, NoIG => 1, NoMD => 1);
			unless (grep(/EMAIL D'ITINERAIRE ENVOYE/, @$lines_ret) ||
				grep(/ITINERARY EMAIL SENT/, @$lines_ret)      ||
				grep(/ITINERARIO CORREO ELECT. ENVIADO/, @$lines_ret) ||
				grep(/ITINERARY RECEIPT EMAIL SENT/, @$lines_ret))
				{
					$err_level = "ERROR";
					notice($typeMail.' ERROR'.Dumper($lines_ret));
				}
				
			&monitore("TAS_FINISH",$typeMail."_ITINERARY",$err_level,$countryCode,$globalParams->{product},$pnr->{'PNRId'},'',"AMADEUS COMMAND");
			#checker valeur $globalParams->{product} + PNR +voir si valeur = AIR ou RAIL
		}
		$tst_number--;
    }
    # ----------------------------------------------------------------
    
    debug("TST number <2> = $tst_number");
  
    if ($tst_number > 0) {
      debug('### TAS MSG TREATMENT 13 ###');
  	  $pnr->{TAS_ERROR} = 13;
  		return 1;
  	}
  
    if ($tst_number <= 0) {
      
      notice('More FA Lines than Active TST detected in PNR...') if ($tst_number < 0);
      
      my $comp = '';
      my $itinerary_holds_only_airlines_listed = 1;
      
      foreach (@{$pnr->{'Segments'}}) {
        $comp = substr($_->{'Data'}, 0, 2);
        $itinerary_holds_only_airlines_listed = 0 unless (grep(/$comp/, @$os_cies));
      }
      
      unless ($itinerary_holds_only_airlines_listed) {
        $GDS->command(Command => 'OSYYTKNO'.$_, NoIG => 1, NoMD => 1) foreach (@fa_lines);
        $GDS->command(Command => 'RF'.$GDS->modifsig, NoIG => 1, NoMD => 1);
      }

      $GDS->command(Command => 'ER', NoIG => 1, NoMD => 1);

      $GDS->command(Command => 'RF'.$GDS->modifsig, NoIG => 1, NoMD => 1);
      $GDS->command(Command => 'ET', NoIG => 1, NoMD => 1);
		  $GDS->command(Command => 'ET', NoIG => 1, NoMD => 1);
    }

  return 1;  
}

1;
