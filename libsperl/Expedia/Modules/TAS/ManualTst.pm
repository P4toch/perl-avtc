package Expedia::Modules::TAS::ManualTst;
#-----------------------------------------------------------------
# Package Expedia::Modules::TAS::ManualTst
#
# $Id: ManualTst.pm 628 2011-03-03 11:22:53Z pbressan $
#
# (c) 2002-2007 Expedia.                   www.expediacorporate.fr
#-----------------------------------------------------------------

use strict;
use Data::Dumper;

use Expedia::Tools::Logger qw(&debug &notice &warning &error);

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
 
  debug('Market = '.$market);
  
    my $tstdoc = $pnr->{_XMLTST};

  	my $checkRU = 0; # = 1 si au moins une ligne du PNR contient FP CC 

  	my @tst_node_list = $tstdoc->getElementsByTagName('fareList');
  	foreach my $node (@tst_node_list) {
  		if($market eq 'GB') {
  			if ($node->find('pricingInformation/fcmi')->to_literal->value() !~ /^(0|5|N|F)$/) {
  				$pnr->{TAS_ERROR} = 29;
  				debug('### TAS MSG TREATMENT 29 ###');
  				return 1;
  			}
  		}
  	}

  return 1;  
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

1;
