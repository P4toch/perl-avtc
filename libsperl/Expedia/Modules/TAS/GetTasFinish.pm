package Expedia::Modules::TAS::GetTasFinish;
#-----------------------------------------------------------------
# Package Expedia::Modules::TAS::GetTasFinish
#
# $Id: GetTasFinish.pm 669 2011-04-19 13:27:29Z pbressan $
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
  my $changes      = $params->{Changes};
    
  my $dbh = $cnxMgr->getConnectionByName('mid');
  
  # --------------------------------------------------------------------------------------------------
  # Vérification de la présence de <task></task> dans la source-finish-*
  my $task = 'tas-'.$params->{GlobalParams}->{agency};
  if (!defined($task) || $task =~ /^\s*$/) {
    error("A 'task' element has to be defined in the <Source></Source> section.");
    return ();
  }
  # --------------------------------------------------------------------------------------------------

 # --------------------------------------------------------------------------------------------------
  # Sélection des Dossiers à traiter triés du plus ancien au plus récent.
  # Dossiers en TAS_ERROR = 13 également sélectionnés !
  my $query = "
    SELECT REF, PNR, DELIVERY_ID,
           (SELECT NAME FROM APPLICATIONS A WHERE A.ID = APP_ID)    AS TASK,
           (SELECT NAME FROM APPLICATIONS A WHERE A.ID = SUBAPP_ID) AS SUBTASK,
           --CAST(XML as varchar(max)) as XML
            CONVERT(VARCHAR(MAX), CONVERT(NVARCHAR(MAX), XML)) as XML
      FROM IN_PROGRESS WHERE PNR IN (

      SELECT PNR
        FROM IN_PROGRESS
       WHERE STATUS='TAS_TICKETED'

      UNION

      SELECT PNR
        FROM IN_PROGRESS
       WHERE STATUS='TAS_ERROR'
         AND TAS_ERROR = 13

    ) AND SUBAPP_ID = (SELECT ID FROM APPLICATIONS WHERE NAME = ?)
    ORDER BY TIME ASC ";
  #  AND TO_CHAR(TIME, 'DDMMYYYY') = TO_CHAR(sysdate, 'DDMMYYYY') MODIF TAS AU 
  # --------------------------------------------------------------------------------------------------

  my @res = ();
	my $res = $dbh->saarBind($query, [$task]);

	# debug('res = '.Dumper($res)) if (defined $res);
	return @res unless (defined $res);
  
  foreach (@$res) {
    my $tmp    = undef;
    my $tmpXML =  $_->[5];
       $tmpXML =~ s/'/''''/ig;
       $tmpXML = '<?xml version="1.0" encoding="ISO-8859-1" standalone="yes"?>'.$tmpXML;
       $tmp  = ' xmlns="http://www.expediacorporate.fr/newsimages/xsds/v1"';
       $tmpXML =~ s/$tmp//ig;
       
		push @res, { REF         => $_->[0],
		             PNR         => $_->[1],
		             DELIVERY_ID => $_->[2],
		             TASK        => $_->[3],
		             SUBTASK     => $_->[4],
		             XML         => $tmpXML, };
	}
	# debug('res = '.Dumper(\@res));

  return @res;
}

1;
