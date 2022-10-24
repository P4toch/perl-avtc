package Expedia::Modules::GLD::AnalyseDV;
#-----------------------------------------------------------------
# Package Expedia::Modules::GLD::AnalyseDV
#
# $Id: AnalyseDV.pm 586 2010-04-07 09:26:34Z pbressan $
#
# (c) 2002-2010 Expedia.                            www.egencia.eu
#-----------------------------------------------------------------

use strict;
use Data::Dumper;

use Expedia::GDS::DV;
use Expedia::Tools::Logger qw(&debug &notice &warning &error);
use Expedia::Tools::GlobalVars qw($cnxMgr);

# PHASE 0

sub run {
  my $self   = shift;
  my $params = shift;

  my $globalParams = $params->{GlobalParams};
  my $moduleParams = $params->{ModuleParams};
  my $changes      = $params->{Changes};
  my $item         = $params->{Item};
  my $tb           = $params->{ParsedXML};
  my $WBMI         = $params->{WBMI};
  
  my $ttds         = $tb->getTravelDossierStruct;
    
  # ______________________________________________________________________
  # ANALYSE DE LA STRUCTURE DES DVS
  # ~~~ On récupère les identifiants des DVs ~~~
  my @DVs           = ();
  my $isMeeting     = $tb->isMeetingCompany();
  my $gdsName       = 'amadeus-FR';
     $gdsName       = 'amadeus-meetings-FR' if ($isMeeting);
  my $GDS           = $cnxMgr->getConnectionByName($gdsName);
  my $itinerayEmpty = 0;
  my $alreadyIssued = 0;
  
  my $dvId = $item->{PNR};
    
    debug('dvId = '.$dvId);
    
    my $dv = Expedia::GDS::DV->new(DV => $dvId, GDS => $GDS, doWP9 => 0);
    
    if (($dv->{SECUREDPNR} == 1) || ($dv->{NOTEXISTS} == 1)) {
      $WBMI->addReport({ Code => 30, DvId => $dv->{_DV}, AmadeusMesg => 'ACCES INTERDIT A CE PNR' })           if ($dv->{SECUREDPNR} == 1);
      $WBMI->addReport({ Code => 35, DvId => $dv->{_DV}, AmadeusMesg => 'ERREUR SUR ADRESSE DOSSIER VOYAGE' }) if ($dv->{NOTEXISTS}  == 1);
      return -2; # CAS SPECIAL DU SECURED PNR
    }
    
    if ((scalar(@{$dv->{_SCREEN}}) == 0) ||
        ($dv->{_DV} ne $dv->{DVId})      ||
        ($dv->{BROKENLINK} == 1)) {
      return -1; # CAS D'UNE MAUVAISE LECTURE DE LA DV ... Merci RAVEL :(
    }
    
    if (scalar(@{$dv->{ITINERAIRE}}) == 0) {
      notice("ITINERARY EMPTY FOR '".$dv->{_DV}."'. Aborting ...");
      $WBMI->addReport({ Code => 15, DvId => $dv->{_DV} });
      $dv->{ItineraryEmpty} = 1;
      $itinerayEmpty       += 1;
    }
      
    if (scalar(@{$dv->{EMISSION}}) > 0) {
      notice("ALREADY ISSUED DV '".$dv->{_DV}."' DETECTED. Aborting ...");
      $WBMI->addReport({ Code => 11, DvId => $dv->{_DV} });         
      $dv->{AlreadyIssued}  = 1;
      $alreadyIssued       += 1;
    }

    push (@DVs, $dv);

  
  # On passe en "params" l'analyse des DVs 
  $params->{DVs} = \@DVs;
  debug('DVs = '.Dumper(\@DVs));
  # _______________________________________________________________________
  
  # -----------------------------------------------------------------------
  # Si au moins une des dossiers ne contient contient pas d'itinéraire
  return -2 if ($itinerayEmpty > 0); # CAS SPECIAL DU ITINERARY EMPTY
  # -----------------------------------------------------------------------
    
  # -----------------------------------------------------------------------
  # Si au moins un des dossiers a déjà été émis ou est en cours d'émission
  return -2 if ($alreadyIssued > 0); # CAS SPECIAL DU ALREADY ISSUED
  # -----------------------------------------------------------------------  
  
  return 1;
}

1;
