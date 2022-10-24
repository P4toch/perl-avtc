package Expedia::Modules::LCH::GetItems;
#-----------------------------------------------------------------
# Package Expedia::Modules::LCH::GetItems
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

  my $server       = $globalParams->{_SERVER};
  my $dbh = $cnxMgr->getConnectionByName('mid');
  
  # -------------------------------------------------------------------
  # Récupération des jobs à traiter

    my $query = "Use FrEgen_B; SELECT P.ID, P.SHORT_DESC, P.COMMAND, L.HEURE_DEB, L.HEURE_FIN, L.RECURENCE, CONVERT(CHAR(30),L.DATE_DERNIERE_EXEC,120)
		FROM MO_LAUNCHER L, MO_PROCESS P 
		WHERE L.ID = P.ID 
		AND L.ACTIF=1
		AND NOM_SERVER ='$server'";
    my $results = $dbh->saar($query);

    #notice("Dumper:".Dumper($results));
  # -------------------------------------------------------------------
  
  return () unless ((defined $results) && (scalar @$results > 0));
  
  
  my @finalRes = ();
  
  RES: foreach my $res (@$results) {

    push @finalRes, {
      ID                 => $res->[0],
      SHORT_DESC         => $res->[1],
      COMMAND            => $res->[2],
      HEURE_DEB          => $res->[3],
      HEURE_FIN          => $res->[4],
      REC                => $res->[5],
      DATE_DERNIERE_EXEC => $res->[6],
    };

  }

    notice("Dumper:".Dumper(@finalRes));

  return @finalRes; 
}

1;
