package Expedia::Databases::WbmiQueries;
#-----------------------------------------------------------------
# Package Expedia::Databases::WbmiQueries
#
# $Id: WbmiQueries.pm 586 2010-04-07 09:26:34Z pbressan $
#
# (c) 2002-2008 Expedia.                   www.expediacorporate.fr
#-----------------------------------------------------------------

use Data::Dumper;
use Exporter 'import';

use Expedia::Tools::Logger qw(&debug &notice &warning &error);
use Expedia::Tools::GlobalVars qw($cnxMgr $h_wbmiMessages);

@EXPORT_OK = qw(&getWbmiMessage);

use strict;

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
sub getWbmiMessage {
  my $wbmiId = shift;

  if (defined $h_wbmiMessages->{0}) {
		return $h_wbmiMessages->{$wbmiId} || undef;
	}
	else {
		my $dbh   = $cnxMgr->getConnectionByName('mid');
  
	  my $query = 'SELECT ID, DESCRIPTION FROM WBMI_MESSAGES';
    my $res   = $dbh->saarBind($query, []);

		foreach (@$res) {
			$h_wbmiMessages->{$_->[0]} = $_->[1];
		}
	}
  
  return $h_wbmiMessages->{$wbmiId} || undef;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

1;
