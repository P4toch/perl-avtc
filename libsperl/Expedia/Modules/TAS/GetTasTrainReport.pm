package Expedia::Modules::TAS::GetTasTrainReport;
#-----------------------------------------------------------------
# Package Expedia::Modules::TAS::GetTasTrainReport
#
# $Id: GetTasTrainReport.pm 682 2011-04-19 14:07:57Z pbressan $
#
# (c) 2002-2009 Expedia.                   www.expediacorporate.fr
#-----------------------------------------------------------------

use Data::Dumper;

use Expedia::Tools::Logger qw(&debug &notice &warning &error);
use Expedia::Tools::GlobalVars qw($cnxMgr);

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
   
  # --------------------------------------------------------------------------------------------------
  # Sélection des dossiers pour l'envoi de l'email de rapport TAS.
  my $query = "
    SELECT REF, PNR, TAS_ERROR, TIME, DELIVERY_ID,
          (SELECT NAME FROM APPLICATIONS WHERE ID = APP_ID),
          (SELECT NAME FROM APPLICATIONS WHERE ID = SUBAPP_ID),
					--CAST(XML as varchar(max)) as XML
					 CONVERT(VARCHAR(MAX), CONVERT(NVARCHAR(MAX), XML)) as XML
      FROM IN_PROGRESS WHERE REF IN (

      SELECT REF
        FROM IN_PROGRESS
       WHERE STATUS = 'TAS_CHECKED'
         AND TYPE IN ('SNCF_TC', 'RG_TC')

       UNION

      SELECT REF
        FROM IN_PROGRESS
       WHERE STATUS = 'TAS_ERROR'

    ) AND SUBAPP_ID = (SELECT ID FROM APPLICATIONS WHERE NAME = ?)
      AND TYPE IN ('SNCF_TC', 'RG_TC')
    ORDER BY TAS_ERROR ASC, REF DESC ";
  # AND TO_CHAR(TIME, 'DDMMYYYY') = TO_CHAR(sysdate, 'DDMMYYYY') CHANGEMENT TAS AU
  # --------------------------------------------------------------------------------------------------

  my @res = ();
	my $res = $dbh->saarBind($query, [$task]);
  # debug('res = '.Dumper($res));
  
  foreach (@$res) {
    
        my $tmp    = undef;
    my $tmpXML =  $_->[7];
       $tmpXML =~ s/'/''''/ig;
       $tmpXML = '<?xml version="1.0" encoding="ISO-8859-1" standalone="yes"?>'.$tmpXML;
       $tmp  = ' xmlns="http://www.expediacorporate.fr/newsimages/xsds/v1"';
       $tmpXML =~ s/$tmp//ig;
       
		push @res, { REF         => $_->[0],
		             PNR         => $_->[1],
		             TAS_ERROR   => $_->[2],
		             TIME        => $_->[3],
		             DELIVERY_ID => $_->[4],
		             TASK        => $_->[5],
		             SUBTASK     => $_->[6],
		             XML         => $tmpXML, };
	}
  # debug('res = '.Dumper(\@res));

  return @res;
}

1;
