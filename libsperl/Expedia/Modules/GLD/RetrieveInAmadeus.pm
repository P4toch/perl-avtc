package Expedia::Modules::GLD::RetrieveInAmadeus;
#-----------------------------------------------------------------
# Package Expedia::Modules::GLD::RetrieveInAmadeus
#
# $Id: RetrieveInAmadeus.pm 586 2010-04-07 09:26:34Z pbressan $
#
# (c) 2002-2010 Expedia.                            www.egencia.eu
#-----------------------------------------------------------------

use Data::Dumper;

use Expedia::Tools::Logger qw(&debug &notice &warning &error);
use Expedia::Tools::GlobalVars qw($cnxMgr);
use Expedia::Tools::GlobalFuncs qw(&xmldatetosearchdate);
use Expedia::Databases::MidSchemaFuncs qw(&insertIntoDv2Pnr);

# PHASE 2

sub run {
  my $self   = shift;
  my $params = shift;

  my $globalParams = $params->{GlobalParams};
  my $moduleParams = $params->{ModuleParams};
  my $changes      = $params->{Changes};
  my $item         = $params->{Item};
  my $tb           = $params->{ParsedXML};
  my $DVs          = $params->{DVs};
  my $GDS          = $params->{GDS};
  my $WBMI         = $params->{WBMI};
  
  my $mdCode       = $tb->getMdCode;
  my $depDate      = xmldatetosearchdate($tb->getDepartureDate);
  my $ttds         = $tb->getTrainTravelDossierStruct; # A voir si on supprime
  my $lwdPos       = $ttds->[0]->{lwdPos}; # A voir si on supprime
  my $paxInfos     = $tb->getPaxPnrInformations({lwdPos => $lwdPos}); # A voir si on supprime
  my $pnr		   = $item->{PNR}; 	
  my $change_GDS   = 0;
  # Pas besoin d'exécuter ce module si nous l'avons déja effectué ;)
  return 1 if ($item->{STATUS} eq 'process');

  # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
  # Cette phase essaye de RT les PNR via une recherche par NOM/PRENOM et DEPARTUREDATE
  foreach my $dv (@$DVs) 
  {
	 next unless ($dv->{_DV} eq $pnr);
    my $PNRId    = 'UVWXYZ';   
    my $r		 = '';
	my $q	     = '';
	my $a        = ''; 
	my $tries 	 = 0; 
	my $success  = 0; 
    my $command  = "RTOA/2C-".$dv->{_DV};	
	my $lines    = '';
	

    TRIES: while ($tries < 5) {
			$lines    = '';
			$lines    = $GDS->command(Command => $command, NoIG => 1, NoMD => 0); 
      
			foreach my $line (@$lines) 
			{	
				if ($line =~ /^ RP\/(\w+)(\/(\w+)).*\s+(\w+)\s* $/x)
				{
					my ($r, $q, $a) = ($1, $3, $4);
					$PNRId = $a;
					notice("PNRID:".$PNRId);
					last;
				}
			}
			
			
      # Si on arrive pas à retrouver le PNRId alors on attend 10 secondes
      if ($PNRId eq '') {
        $tries++;
        sleep 10;
      }
      else {
        $success = 1;
        last TRIES;
      }
    }

    if ($success == 0) {
      notice("Could not retrieve ResaRail booking '".$dv->{_DV}."' into Amadeus.");
      debug('numberOfTries = '.$item->{TRY});
      if ($item->{TRY} == 4) {
        $WBMI->status('FAILURE');
        $WBMI->addReport({ Code => 10, DvId => $dv->{_DV} });
        $WBMI->sendXmlReport();
      }
      return 0; # On sort, on réessayera plus tard !
    } else {
      notice("~ Dossier Ravel '".$dv->{DVId}."' is mapped with Amadeus PNR '".$PNRId."'.");      
    }

    # On associe le PNRId à la DV ;)
    $dv->{PNRId} = $PNRId;


  } # Fin foreach my $dv (@$DVs)
  # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

  # Vérification finale
  foreach my $dv (@$DVs) {
    if (!exists $dv->{PNRId}) {
      if ($item->{TRY} == 4) {
        $WBMI->status('FAILURE');
        $WBMI->addReport({ Code => 10, DvId => $dv->{_DV} });
        $WBMI->sendXmlReport();
      }
      return 0;
    }
  }

  # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
  # Insertion dans la table DV2PNR pour une utilisation utlérieure
  foreach my $dv (@$DVs) {
    my $dvId  = $dv->{DVId};
    my $pnrId = $dv->{PNRId};
    my $rows  = &insertIntoDv2Pnr({MDCODE => $mdCode, DVID => $dvId, PNRID => $pnrId});
  }
  # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
  
  $params->{WBMI}->status('SUCCESS');
  $params->{WBMI}->sendXmlReport();   # Nous envoyons le rapport 2/3 à WBMI.
  $params->{WBMI}->currentPhase(3);   # On set à 3 pour le rapport 3/3.
  $params->{WBMI}->reportSended(0);   # On remet à 0.

   if ($change_GDS == 1) 
        {
          notice("CONNEXION OID amadeus-FR");
          $GDS->disconnect;
          $GDS = $cnxMgr->getConnectionByName('amadeus-FR');
          $GDS->MRSEC3100(0);
          return 1 unless $GDS->connect;
        }

  return 1;
}

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Récupère le TravellerName à partir du nouveau bloc noeud
sub _getTrvName {
  my $paxInfos = shift;
  my $DV       = shift;
  
  foreach my $paxInfo (@$paxInfos) {
    if (($paxInfo->{ResarailId} eq '1.1') && ($paxInfo->{DV} eq $DV)) {
      return $paxInfo->{LastName}.'/'.$paxInfo->{FirstName};
    }
  }
  
  return 'ABCDEF/GHIJKLM';
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

1;
