package Expedia::Modules::TAS::GetTasStats;
#-----------------------------------------------------------------
# Package Expedia::Modules::TAS::GetTasStats
#
# $Id: GetTasStats.pm 657 2011-04-05 13:40:22Z pbressan $
#
# (c) 2002-2008 Expedia.                   www.expediacorporate.fr
#-----------------------------------------------------------------

use Data::Dumper;

use Expedia::Tools::Logger qw(&debug &notice &warning &error);
use Expedia::Tools::GlobalVars qw($cnxMgr);
use Expedia::Databases::Calendar qw(&getCalIdwithtz);
use Expedia::Databases::MidSchemaFuncs qw(&getAppId &getTZbycountry);

sub run {
  my $self   = shift;  
  my $params = shift;
  
  my $globalParams = $params->{GlobalParams};
  my $moduleParams = $params->{ModuleParams};
  my $changes      = $params->{Changes};
  
  my $dbh = $cnxMgr->getConnectionByName('mid');

  # --------------------------------------------------------------------------------------------------
  # Vérification de la présence de <task></task> dans la source-report-*
  my $task = 'tas-'.$params->{GlobalParams}->{agency};
  if (!defined($task) || $task =~ /^\s*$/) {
    error("A 'task' element has to be defined in the <Source></Source> section.");
    return ();
  }
  # --------------------------------------------------------------------------------------------------
  
  # __________________________________________________________________________________________________
  # Récupération du CALENDAR.ID de la date du jour et des infos nécessaires à la requète
  #  TASK Attention ici avec la gestion des billets "PAPER" !
  my $market   = $globalParams->{market};
  my $tz       = &getTZbycountry($market);
  my $calId    = getCalIdwithtz($tz);
  my $appId    = getAppId('tas-'.$globalParams->{product}.'-etkt');
  my $subappId = getAppId('tas-'.$params->{GlobalParams}->{agency});
  # __________________________________________________________________________________________________

  # --------------------------------------------------------------------------------------------------
  # Sélection des items pour la sauvegarde des éléments TAS.
  my $query = "
    SELECT ID, CAL_ID, APP_ID, SUBAPP_ID, MARKET, ISNULL(TAS_STATS,'') + ISNULL(TAS_STATS2,'') + ISNULL(TAS_STATS3,'') + ISNULL(TAS_STATS4,'') + ISNULL(TAS_STATS5,''), TIME
      FROM TAS_STATS_DAILY
     WHERE CAL_ID    = ?
       AND APP_ID    = ?
       AND SUBAPP_ID = ?
       AND MARKET    = ? ";
  # --------------------------------------------------------------------------------------------------

  my @res = ();
	my $res = $dbh->saarBind($query, [$calId, $appId, $subappId, $market]);
	debug('res = '.Dumper($res));
  
  foreach (@$res) {
		push @res, { ID        => $_->[0],
		             CAL_ID    => $_->[1],
		             APP_ID    => $_->[2],
		             SUBAPP_ID => $_->[3],
		             MARKET    => $_->[4],
		             TAS_STATS => $_->[5],
		             TIME      => $_->[6], };
	}
	debug('res = '.Dumper(\@res));

  return @res;
}

1;
