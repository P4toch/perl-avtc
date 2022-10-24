package Expedia::Modules::TAS::DoRtfVerif;
#-----------------------------------------------------------------
# Package Expedia::Modules::TAS::DoRtfVerif
#
# $Id: DoRtfVerif.pm 462 2008-05-22 15:45:13Z pbressan $
#
# (c) 2002-2007 Expedia.                   www.expediacorporate.fr
#-----------------------------------------------------------------

use strict;
use Data::Dumper;

use Expedia::Tools::Logger qw(&debug &notice &warning &error);
use Expedia::Databases::MidSchemaFuncs qw(&btcTasProceed &isInMsgKnowledge);

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
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
 
  $GDS->RT(PNR => $pnr->{'PNRId'}, NoPostIG => 1, NoMD => 1);
   	
  my $countryCode = $ab->getCountryCode({trvPos => $ab->getWhoIsMain});

  	# -----------------------------------------------------------------------
    #BUG 16312 FOR NL TICKETING -- CHANGE THE FV LINE IF AF TO KL
    if($countryCode eq 'NL')
    {
    foreach (@{$pnr->{'PNRData'}}) {

  		my $lineData = uc $_->{'Data'};
  		my $lineNumb = $_->{'LineNo'};

  		if ($lineData =~ /^FV\s+(?:(?:PAX|INF)\s+)?(?:\*\w\*)?(AF)/) {  			
  				debug('CHANGE AIRLINE AF TO KL '.$lineNumb.' = '.$lineData);
  				my $command=$lineNumb."/KL";
  				$GDS->command(Command => $command, NoIG => 1, NoMD => 1);
  				$GDS->command(Command => 'RFBTCTAS', NoIG => 1, NoMD => 1);
  				$GDS->command(Command => 'ER', NoIG => 1, NoMD => 1);
  		}  	
    }}
  	# -----------------------------------------------------------------------
  	  
  	  
    # RTF lines
    
  	my $lines = $GDS->command(Command => 'RTF', NoIG => 1, NoMD => 1); 
  	            $GDS->command(Command => 'IG',  NoIG => 1, NoMD => 1); 


  	debug('RTF : '.Dumper($lines));
  	{
  		last if (grep(/^\s+(\d{1,2})\s+FA.*$/,  @$lines));
  		last if (grep(/^\s+(\d{1,2})\s+FB.*$/,  @$lines));
  		last if (grep(/^\s+(\d{1,2})\s+FHE.*$/, @$lines));
  		last if (grep(/^\s+(\d{1,2})\s+FHA.*$/, @$lines) or grep(/^\s+(\d{1,2})\s+FHM.*$/, @$lines));
  		return 1;
  	}
  	
  	# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
  	# Si je suis là, c'est que le billet est déja émis [...]
  	notice("PNR = '".$pnr->{'PNRId'}."' is already issued.");
  	# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

    # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
    # On vérifie que ce META_DOSSIER_ID (= mdCode)
    #   n'est pas déjà "BTC-TAS PROCEED"
    my $mdCode = $item->{REF};
    my $mkItem = &isInMsgKnowledge({ PNR => $pnr->{'PNRId'} });
    if ($mkItem->[0][5] == 1) {
      debug('### TAS MSG TREATMENT 38 ###');
  	  $pnr->{TAS_ERROR} = 38;
    } else {
      debug('### TAS MSG TREATMENT 4 ###');
  	  &btcTasProceed({ PNR => $pnr->{'PNRId'}, TYPE => 'AIR' });
  	  $pnr->{TAS_ERROR} = 4;
    }
    # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

  # ----------------------------------------------------------------

  return 1;  
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

1;
