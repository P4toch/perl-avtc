package Expedia::Modules::GAP::Finalize;
#-----------------------------------------------------------------
# Package Expedia::Modules::GAP::Finalize
#
# $Id: Finalize.pm 608 2010-12-14 13:27:03Z pbressan $
#
# (c) 2002-2008 Expedia.                   www.expediacorporate.fr
#-----------------------------------------------------------------

use Data::Dumper;

use Expedia::Tools::Logger qw(&debug &notice &warning &error);
use Expedia::Tools::GlobalFuncs qw(&stringGdsOthers);

sub run {
  my $self   = shift;
  my $params = shift;

  my $globalParams = $params->{GlobalParams};
  my $moduleParams = $params->{ModuleParams};
  my $changes      = $params->{Changes};
  my $item         = $params->{Item};
  my $pnr          = $params->{PNR};
  my $ab           = $params->{ParsedXML};

  # ______________________________________________________________
  # Spécificité Espagne & Holland
  my $countryCode = $ab->getCountryCode({trvPos => $ab->getWhoIsMain });
  debug('countryCode = '.$countryCode);
  push (@{$changes->{add}}, { Data => 'RM *CN22236' })          			if ($countryCode eq 'ES');
  push (@{$changes->{add}}, { Data => 'RM *ACECLN-103377' })    			if ($countryCode eq 'NL');
  push (@{$changes->{add}}, { Data => 'RM *ACEBRO-AMSEC3100' }) 			if ($countryCode eq 'NL');
  push (@{$changes->{add}}, { Data => 'RM *ACEPNO-ECSU' })      			if ($countryCode eq 'NL');
  push (@{$changes->{add}}, { Data => 'RM *CID:E03000' })         			if ($countryCode eq 'SE');
  push (@{$changes->{add}}, { Data => 'RM*TLID:ECCOR,SOU: ECCOR,CHA:ON,' }) if ($countryCode eq 'SE');
  # ______________________________________________________________
  
  # ______________________________________________________________
  # Spécificité Meeting
  my $isMeeting = $ab->isMeetingCompany();
  debug('isMeeting = '.$isMeeting);
  if ($isMeeting) {
    my $meetingOrderNumber = stringGdsOthers($ab->getMeetingOrderNumber());
    debug('MeetingOrderNumber = '.$meetingOrderNumber);
    push (@{$changes->{add}}, { Data => 'RM *GROUP '.$meetingOrderNumber })
      if ($meetingOrderNumber ne '');
  }
  # ______________________________________________________________
  
  # ______________________________________________________________
  # Demande Stéphane BALON 25 Février 2009 # TARKETT SWEDEN (BEL)
  # Désactivé par Patrick Bressan le 19 Août 2010. Ce ComCode n'est plus référencé.
  # my $comCode = $ab->getPerComCode({trvPos => $ab->getWhoIsMain});
  # push (@{$changes->{add}}, { Data => 'RM *K:769' }) if ($comCode eq '754576');
  # ______________________________________________________________

  # ______________________________________________________________
  # Suppression des anciennes lignes RM @@ BTC-AIR PROCEED @@
  # Suppression de APE VOTRE VALIDEUR NOTILUS @ DIMO GESTION # 02 Août 2010
  DATA: foreach (@{$pnr->{PNRData}}) {
    if ($_->{'Data'} =~ /BTC-AIR PROCEED/) {
      push (@{$changes->{del}}, $_->{'LineNo'});
    }
    if ($_->{'Data'} =~ /VOTRE VALIDEUR/) {
      push (@{$changes->{del}}, $_->{'LineNo'});
    }
  }
  # ______________________________________________________________

  push (@{$changes->{add}}, { Data => 'RM @@ BTC-AIR PROCEED @@' });

  return 1;  
}

1;
