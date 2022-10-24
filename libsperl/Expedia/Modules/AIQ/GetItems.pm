package Expedia::Modules::AIQ::GetItems;
#-----------------------------------------------------------------
# Package Expedia::Modules::AIQ::GetItems
#
# $Id: GetItems.pm 686 2011-04-21 12:33:02Z pbressan $
#
# (c) 2002-2007 Expedia.                   www.expediacorporate.fr
#-----------------------------------------------------------------

use Data::Dumper;

use Expedia::Tools::Logger qw(&debug &notice &warning &error);
use Expedia::Tools::GlobalVars qw($cnxMgr);
use Expedia::Databases::MidSchemaFuncs qw(&getHighWaterMark &setHighWaterMark);

sub run {
  my $self   = shift;
  my $params = shift;
  
  my $taskName     = $params->{TaskName};
  my $globalParams = $params->{GlobalParams};
  my $moduleParams = $params->{ModuleParams};
  my $changes      = $params->{Changes};
  my $market       = $globalParams->{market};
  my $oid          = substr($taskName,10,length($taskName)-10);
  
  my $dbh = $cnxMgr->getConnectionByName('navision');

  # -------------------------------------------------------------------
  # Récupération des queues à traiter et ACTIVE (1) 
  my $query = "
    SELECT QUEUE, TYPE, WBMI_RULES, AO.POS 
      FROM AQH_QUEUE AQ, AQH_OFFICE_ID AO
      WHERE AO.POS= AQ.POS
      AND   AQ.POS=? 
      AND   AO.OFFICE_ID=?
      AND   AQ.ACTIF=1
      AND   AO.ACTIF=1
      ORDER BY QUEUE ASC";
  my $results = $dbh->saarBind($query, [$market, $oid]);

  # -------------------------------------------------------------------
  
  return () unless ((defined $results) && (scalar @$results > 0));
  
  my @finalRes = ();
  
  RES: foreach my $res (@$results) {
    
    push @finalRes, {
      QUEUE          => $res->[0],
      TYPE           => $res->[1],
      WBMI_RULES     => $res->[2],
      POS            => $res->[3],
    };

  }

  return @finalRes; 
}

1;
