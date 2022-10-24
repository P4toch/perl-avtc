package Expedia::Modules::CAR::GetItems;
#-----------------------------------------------------------------
# Package Expedia::Modules::GAP::GetItems
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
  my $midDB        = $cnxMgr->getConnectionByName('mid');
  
  # -----------------------------------------------------------------
  # Requète pour connaitre à quelle "version" nous nous étions arretés.
  my $version = &getHighWaterMark($taskName);
  if (!defined $version) {
    warning('Problem detected during get of last treated version');
    return [];
  }
  # -----------------------------------------------------------------

  # -------------------------------------------------------------------
  # Récupération des dossiers à traiter pour BTC-AIR
  my $query = "
    SELECT ID,
           MESSAGE_ID, MESSAGE_CODE, MESSAGE_VERSION, MESSAGE_TYPE,
           EVENT_VERSION, TEMPLATE_ID,
           MARKET, APP_ID, ACTION, STATUS, ERROR_ID, 
           --CAST(XML as varchar(max)) as XML,
           CONVERT(VARCHAR(MAX), CONVERT(NVARCHAR(MAX), XML)) as XML,
           CONVERT(VARCHAR(10), TIME, 103) + ' ' + CONVERT(VARCHAR(8), TIME, 8),
           PNR
      FROM WORK_TABLE
     WHERE APP_ID = (SELECT ID FROM APPLICATIONS WHERE NAME = ?)
       AND MARKET = ?
       AND STATUS IN ('NEW')
       AND MESSAGE_VERSION > ?
  ORDER BY MESSAGE_VERSION ASC";
  
  my $results = $midDB->saarBind($query, [$taskName, $market, $version]);
  # debug('results = '.Dumper($results));
  # -------------------------------------------------------------------
  
  return () unless ((defined $results) && (scalar @$results > 0));
  
  my @finalRes = ();
  
  RES: foreach my $res (@$results) {
    
    my $tmp    = undef;
    my $tmpXML =  $res->[12];
       $tmpXML =~ s/'/''''/ig;
       $tmpXML = '<?xml version="1.0" encoding="ISO-8859-1" standalone="yes"?>'.$tmpXML;
       $tmp  = ' xmlns="http://www.expediacorporate.fr/newsimages/xsds/v1"';
       $tmpXML =~ s/$tmp//ig;
       
    push @finalRes, {
      ID          => $res->[0],
      MSG_ID      => $res->[1],
      MSG_CODE    => $res->[2],
      MSG_VERSION => $res->[3],
      MSG_TYPE    => $res->[4],
      EVT_VERSION => $res->[5],
      TEMPLATE_ID => $res->[6],
      MARKET      => $res->[7],
      APP_ID      => $res->[8],
      ACTION      => $res->[9],
      STATUS      => $res->[10],
      ERROR_ID    => $res->[11],
      XML         => $tmpXML,
      TIME        => $res->[13],
      PNR         => $res->[14],
    };
    $version = $res->[3];
  }
    
  &setHighWaterMark($taskName, $version);

  return @finalRes; 
}

1;

