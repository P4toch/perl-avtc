package Expedia::Modules::GLD::InsertRM;
#-----------------------------------------------------------------
# Package Expedia::Modules::GLD::InsertRM
#
# $Id: InsertRM.pm 713 2011-07-04 15:45:26Z pbressan $
#
# (c) 2002-2010 Expedia.                            www.egencia.eu
#-----------------------------------------------------------------

use Data::Dumper;

use Expedia::Tools::Logger             qw(&debug &notice &warning &error);
use Expedia::Tools::GlobalVars         qw($cnxMgr);
                                          
# PHASE 1

sub run {
  my $self   = shift;
  my $params = shift;

  my $globalParams = $params->{GlobalParams};
  my $moduleParams = $params->{ModuleParams};
  my $changes      = $params->{Changes};
  my $item         = $params->{Item};
  my $tb           = $params->{ParsedXML};
  my $DVs          = $params->{DVs};
  my $WBMI         = $params->{WBMI};
  my $pnr		   = $item->{PNR};


  # Pas besoin d'exécuter ce module si nous l'avons déja effectué ;)
  return 1 if ($item->{STATUS} eq 'retrieve');
  return 1 if ($item->{STATUS} eq 'process');
  
  my $isMeeting    = $tb->isMeetingCompany();
  my $comCode      = $tb->getPerComCode({trvPos => $tb->getWhoIsMain}); debug('comCode = '.$comCode);
  my $nbOfTrv      = $tb->getNbOfTravellers;
  my $nbDVs        = scalar @$DVs;
  
  my $gdsName      = 'amadeus-FR';
     $gdsName      = 'amadeus-meetings-FR' if ($isMeeting);
  my $GDS          = $cnxMgr->getConnectionByName($gdsName);
    
  # ---------------------------------------------------------------
  # Pour chacune des DVs, On insère une remarque afin de synchro avec Amadeus !
  foreach my $dv (@$DVs) {
       next unless ($dv->{_DV} eq $pnr);
    RETRY: {{
      my $resLines = $dv->RT; # Réouverture de la DV ;)
      last RETRY unless (defined $resLines);
        
      # -------------------------------------------------------------------
      # Ferme la DV et valide les modifications.
      $GDS->command(Command=>'R/RM BTC TRAIN AMADEUS PNR CREATION', NoIG=>1, NoMD=>1, PostIG=>0);
  	  $GDS->command(Command=>'R/RFAG/'.$GDS->modifsig,              NoIG=>1, NoMD=>1, PostIG=>0);
  	  my $lines = $GDS->command(Command=>'R/ER',                    NoIG=>1, NoMD=>1, PostIG=>0);

  	  if ( (grep (/UTILISATION SIMULTANEE DU PNR/, @$lines)) ||
	       (grep (/VERIFIER LE PNR ET REESSAYER/ ,   @$lines)) ||
		   (grep (/VERIFIER LE CONTENU DU PNR/ ,   @$lines)) ) {
  		  notice("Cannot save DV '".$dv->{DVId}."' because of simultaneous modifs. Retrying [...]");
  		  goto RETRY;
  	  }
      # -------------------------------------------------------------------
    }} # Fin RETRY

  }
  # ---------------------------------------------------------------
  
  # ____________________________________________________________________
  # Vérification du nom des voyageurs.
  foreach my $dv (@$DVs) {
	next unless ($dv->{_DV} eq $pnr);
    foreach my $pax (@{$dv->{PAX}}) {
      my $paxName = $pax->{Pax};
      my $paxRank = substr($pax->{rank}, 0, 1).'.'.substr($pax->{rank}, 1, 1);
      if (($paxName =~ /^(OCCASIONNEL|RAVEL|NOM\/PRENOM|XX)/) ||
          ($paxName =~ /PRENOM|NEW USER/)) {
        $WBMI->addReport({
          Code      => 34,
          DvId      => $dv->{_DV},
          PaxNumber => $paxRank });
      }
    }
  }
  # ____________________________________________________________________
  
  debug('isMeeting    = '.$isMeeting);
  debug('nbOfTrv      = '.$nbOfTrv);
  
  # S'il s'agit d'un dossier Meetings ou TravellerTracking ou nombre de DV est > 1 ou
  #  que le nombre de voyageurs est > 1, alors nous devons poursuivre le traitement.
  if (($isMeeting) || ($nbOfTrv > 1) || ($nbDVs > 1)) {
    # Attention 0 est important ici !
    #   Cela signifie que nous devons poursuivre le traitement.
    return 0;
  }

#  # Si nous sommes ici c'est que nous n'avons plus besoin de poursuivre.
#  return -3;

  return 0; # Bug 13384
}

1;
