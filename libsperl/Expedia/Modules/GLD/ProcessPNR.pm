package Expedia::Modules::GLD::ProcessPNR;
#-----------------------------------------------------------------
# Package Expedia::Modules::GLD::ProcessPNR
#
# $Id: ProcessPNR.pm 713 2011-07-04 15:45:26Z pbressan $
#
# (c) 2002-2010 Egencia.                            www.egencia.eu
#-----------------------------------------------------------------

use strict;
use Data::Dumper;
use Expedia::GDS::PNR;
use Expedia::Tools::Logger             qw(&debug &notice &warning &error);
use Expedia::Tools::GlobalVars         qw($cnxMgr $h_context);
use Expedia::Tools::GlobalFuncs        qw(&stringGdsOthers &stringGdsPaxName);
use Expedia::XML::MsgGenerator;
use Expedia::Databases::Payment        qw(&getCreditCardData);
use Expedia::Databases::MidSchemaFuncs qw(&getPnrIdFromDv2Pnr &deleteFromDv2Pnr
                                          &getQInfosForComCode &getFpec);

# PHASE 4

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

  my $ttds         = $tb->getTrainTravelDossierStruct;
  my $mdCode       = $tb->getMdCode;
  my $travellers   = $tb->getTravellerStruct;
  my $lwdPos       = $ttds->[0]->{lwdPos};
  my $lwdType      = $ttds->[0]->{lwdType};
  my $lwdCode      = $ttds->[0]->{lwdCode};
  my $lwdHasMarkup = $ttds->[0]->{lwdHasMarkup};
  my $pnr		   = $item->{PNR};
  # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
  # Préparation de la remarque des PNR liés dans le cas des MULTI-DVs
  if (scalar @$DVs > 1) {
    my $remark  = '';
    my $PNRId   = '';
    foreach my $dv (@$DVs) {
	  next unless ($dv->{DVId} eq $pnr);
      $remark   = 'RM @@ PNR LIES ';
      $PNRId    = $dv->{PNRId};
      foreach (@$DVs) { $remark .= $_->{PNRId}.' ' unless ($_->{PNRId} eq $PNRId); }
      $remark  .= '@@';
      push @{$dv->{add}}, $remark; # Ajout de la remarque
    }
  }
  # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

  # ---------------------------------------------------------------
  # Pour chacune des DVs
  foreach my $dv (@$DVs) {
      
    next if (exists $dv->{ItineraryEmpty}); # Si l'itinéraire est vide, on fait rien !
    next unless ($dv->{DVId} eq $pnr);
    # Réouverture des dossiers en AMADEUS
    my $PNRId = $dv->{PNRId};
    my $PNR   = Expedia::GDS::PNR->new(PNR => $PNRId, GDS => $GDS);
    my @add   = (); # Liste des choses a insérer dans le dossier AMADEUS.

      push (@add, { Data => 'RM *BOOKSOURCE WEB' }); # Bug 13384
            
    # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
    # ~ Remarques RM *PERCODE ~
    # --------------------------------------------------------------
    #  Dans Amadeus, ils seront classés par ordre alphabétique [...]
    my @paxNames = ();
    my $paxInfos = _getPaxPnrInformations($tb, $lwdPos, $dv->{DVId});
    PERCODE: foreach my $paxInfo (@$paxInfos) {
      # Position du voyageur dans le dossier XML
      my $paxName   = stringGdsPaxName($paxInfo->{LastName}).'/'.stringGdsPaxName($paxInfo->{FirstName});
      #BUG 15822
      $paxName =~ s/\s+//g;
      debug('paxName = '.$paxName);
      push @paxNames, { perCode => $paxInfo->{PerCode}, paxName => $paxName};
    }
    @paxNames = sort { $a->{paxName} cmp $b->{paxName} } @paxNames;
    debug('paxNames = '.Dumper(\@paxNames));
    # --------------------------------------------------------------
    # Maintenant qu'ils sont par ordre alphabétique, on va associer les perCodes
    my $rmPerCode = 'RM *PERCODE '; my $gdsPaxNum = 1;
    foreach (@paxNames) {
      push (@add, { Data => $rmPerCode.$_->{perCode}.'/P'.$gdsPaxNum } );
      $gdsPaxNum += 1;
    }
    # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
     
   
    # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

    # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
    #ADD THE METADDOSIER IF NOT EXISTS   
    unless ( grep { $_->{Data} =~ /RM \*METADOSSIER/ } @{$PNR->{PNRData}} ) {
               push (@add, { Data => 'RM *METADOSSIER '.$params->{ParsedXML}->getMdCode });
    }
    # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
    
    # ______________________________________________________________
    # On récupère les éléments précalculés auparavant [[ PNR LIéS ]]
    push (@add, { Data => $_ }) foreach (@{$dv->{add}});
    # ______________________________________________________________
      
    # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
    # On applique les modifications dans AMADEUS
    debug('+ Eléments à ajouter en Amadeus +') if (scalar @add > 0);
    my $update = $PNR->update(add => \@add, del => [], mod => [], NoGet => 1);
    if ($update == 0) { # Simultaneous change
      $WBMI->status('FAILURE');
      $WBMI->addReport({ Code => 17, DvId => $dv->{DVId}, PnrId => $dv->{PNRId} });
      $WBMI->sendXmlReport();
      return 0;
    }
    # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
      
    # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
    # Nettoyage dans la table DV2PNR sauf si le transporteur est Thalys
    my $suppliers = _getSuppliers($dv);
    deleteFromDv2Pnr({MDCODE => $mdCode, DVID => $dv->{DVId}}) unless (grep(/(TH)/, @{$suppliers}));
    # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

  } # Fin foreach my $dv (@$DVs)
  # ----------------------------------------------------------------

  return 1;
}

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Récupère le h_traveller par rapport à son perCode
sub _getTraveller {
  my $travellers = shift;
  my $perCode    = shift;
  
  foreach my $traveller (@$travellers) {
    return $traveller if ($traveller->{PerCode} eq $perCode);
  }
  
  return undef;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
sub _getPaxPnrInformations {
  my $tb       = shift;
  my $lwdPos   = shift;
  my $DVId     = shift;
  
  my $retour   = [];
  my $paxInfos = $tb->getPaxPnrInformations({lwdPos => $lwdPos});
  
  foreach my $paxInfo (@$paxInfos) {
    push (@$retour, $paxInfo) if ($paxInfo->{DV} eq $DVId);
  }
  
  return $retour;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@



# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Renvoi tous les Suppliers d'une DV dans un ref de tableau
sub _getSuppliers {
  my $dv = shift;
  
  my @suppliers = ();
  
  push (@suppliers, $_->{Supplier}) foreach (@{$dv->{ITINERAIRE}});
  
  debug('bookingClass = '.Dumper(\@suppliers));
  
  return \@suppliers;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

1;
