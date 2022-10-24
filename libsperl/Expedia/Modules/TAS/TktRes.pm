package Expedia::Modules::TAS::TktRes;
#-----------------------------------------------------------------
# Package Expedia::Modules::TAS::TktRes
#
# $Id: TktRes.pm 629 2011-03-03 12:08:05Z pbressan $
#
# (c) 2002-2007 Expedia.                   www.expediacorporate.fr
#-----------------------------------------------------------------

use strict;
use Data::Dumper;

use Expedia::Tools::Logger qw(&debug &notice &warning &error);
use Expedia::Tools::SendMail qw(&tasSendError12);

sub run {
  my $self   = shift;
  my $params = shift;

  my $globalParams = $params->{GlobalParams};
  my $moduleParams = $params->{ModuleParams};
  my $changes      = $params->{Changes};
  my $item         = $params->{Item};
  my $pnr          = $params->{PNR};
  my $GDS          = $params->{GDS};
    
    debug("DUMP DE TTP RES : ".Dumper($pnr->{TTP}));
    
    no warnings;
    
    foreach my $ttp_res (values %{$pnr->{TTP}}) {
  		next if (grep(/OK\s+TRAITE\(E\)/,@$ttp_res) or grep(/OK\s+ETICKET\s*/,@$ttp_res));	
  	  # Traitement des erreurs ...
  		debug(Dumper($ttp_res));
  		($pnr->{TAS_ERROR} =  5) && last if (grep(/VALIDATING CARRIERS DO NOT MATCH/,@$ttp_res));
  		($pnr->{TAS_ERROR} =  5) && last if (grep(/TRANSPORTEUR EMETTEUR DU BILLET NECESSAIRE/,@$ttp_res));
  		($pnr->{TAS_ERROR} =  5) && last if (grep(/NEED TICKETING CARRIER/,@$ttp_res));
  		($pnr->{TAS_ERROR} =  5) && last if (grep(/COMPAGNIE EMETTRICE ERRONEE- RESSAISIR ELEMENT FV/,@$ttp_res));
  		($pnr->{TAS_ERROR} =  5) && last if (grep(/INVALID TICKETING CARRIER/,@$ttp_res));
  		($pnr->{TAS_ERROR} =  5) && last if (grep(/INVALID AIRLINE DESIGNATOR\/VENDOR SUPPLIER/,@$ttp_res));
  		($pnr->{TAS_ERROR} =  5) && last if (grep(/PROHIBITED TICKETING CARRIER/,@$ttp_res));
  		($pnr->{TAS_ERROR} =  5) && last if (grep(/SE REQUIERE LA COMPANA AEREA EMISORA/,@$ttp_res));
  		($pnr->{TAS_ERROR} =  8) && last if (grep(/TST PERIME/,@$ttp_res));
  		($pnr->{TAS_ERROR} =  8) && last if (grep(/TST EXPIRED/,@$ttp_res));
  		($pnr->{TAS_ERROR} =  8) && last if (grep(/TST VENCIDO/,@$ttp_res));
  		($pnr->{TAS_ERROR} =  8) && last if (grep(/VEUILLEZ RETARIFER/,@$ttp_res));
  		($pnr->{TAS_ERROR} =  8) && last if (grep(/PLEASE REPRICE/,@$ttp_res));
  		($pnr->{TAS_ERROR} =  9) && last if (grep(/UN TST EXISTE DEJA/,@$ttp_res));
  		($pnr->{TAS_ERROR} =  9) && last if (grep(/CHANGEMENT D.*ITINERAIRE/,@$ttp_res));
  		($pnr->{TAS_ERROR} =  9) && last if (grep(/ITINERARY\/NAME CHANGE-VERIFY TST/,@$ttp_res));
  		($pnr->{TAS_ERROR} =  9) && last if (grep(/CAMBIO DE ITINERARIO/,@$ttp_res));
  		($pnr->{TAS_ERROR} = 10) && last if (grep(/VERIFIER HEURE MINI DE CORRESPONDANCE/,@$ttp_res));
  		($pnr->{TAS_ERROR} = 10) && last if (grep(/CHECK MINIMUM CONNECTION TIME/,@$ttp_res));
  		($pnr->{TAS_ERROR} = 10) && last if (grep(/VERIFIQUE EL TIEMPO DE CONEXION MINIMA/,@$ttp_res));
  		($pnr->{TAS_ERROR} = 16) && last if (grep(/SSRFOID OBLIGATOIRE/,@$ttp_res));
  		($pnr->{TAS_ERROR} = 16) && last if (grep(/ID VENDEUR INCORRECT/,@$ttp_res));
  		($pnr->{TAS_ERROR} = 16) && last if (grep(/SSRFOID MISSING/,@$ttp_res));
  		($pnr->{TAS_ERROR} = 16) && last if (grep(/ID ENREGISTREMENT AEROPORT MANQUANT OU INC/,@$ttp_res));
  		($pnr->{TAS_ERROR} = 16) && last if (grep(/MANDATORY SSRFOID MISSING FOR CARRIER/,@$ttp_res));
  		($pnr->{TAS_ERROR} = 16) && last if (grep(/MISSING OR INVALID AIRPORT CHECK-IN ID/,@$ttp_res));
  		($pnr->{TAS_ERROR} = 16) && last if (grep(/TYPE DE FOID ENTRE INCORRECT/,@$ttp_res));
  		($pnr->{TAS_ERROR} = 16) && last if (grep(/SSRFOID OBLIGATORIO/,@$ttp_res));
  		($pnr->{TAS_ERROR} = 17) && last if (grep(/CETTE CIE INTERDIT LES ETKT/,@$ttp_res));
  		($pnr->{TAS_ERROR} = 17) && last if (grep(/AIRLINE PROHIBITS ETKT/,@$ttp_res));
  		($pnr->{TAS_ERROR} = 17) && last if (grep(/ETKT NON AUTORISE/,@$ttp_res));
  		($pnr->{TAS_ERROR} = 17) && last if (grep(/ETKT:NON AUTORISE/,@$ttp_res));
  		($pnr->{TAS_ERROR} = 17) && last if (grep(/ETKT:NOT AUTHORISED/,@$ttp_res));
  		($pnr->{TAS_ERROR} = 17) && last if (grep(/ETKT DISALLOWED/,@$ttp_res));
  		($pnr->{TAS_ERROR} = 17) && last if (grep(/ET NON AUTORISE POUR CE TRANSPORTEUR/,@$ttp_res));
  		($pnr->{TAS_ERROR} = 17) && last if (grep(/ETKT TRANSPORTEUR NON VALIDE/,@$ttp_res));
  		($pnr->{TAS_ERROR} = 17) && last if (grep(/ETKT INTERDIT/,@$ttp_res));
  		($pnr->{TAS_ERROR} = 17) && last if (grep(/ETKT RJT - PAS D.*INTERLIGNE ENTRE/,@$ttp_res));
  		($pnr->{TAS_ERROR} = 17) && last if (grep(/NO INTERLINE BETWEEN CARRIERS/,@$ttp_res));
  		($pnr->{TAS_ERROR} = 17) && last if (grep(/SEGMENT NOT VALID FOR ELECTRONIC TICKETING/,@$ttp_res));
  		($pnr->{TAS_ERROR} = 17) && last if (grep(/ETKT THIS CARRIER NOT VALID THIS MARKET/,@$ttp_res));
  		($pnr->{TAS_ERROR} = 19) && last if ( (grep(/CHANGEMENTS SIMULTANES PNR/,@$ttp_res)) || (grep(/VERIFIER LE PNR ET REESSAYER/,@$ttp_res)) || (grep(/VERIFIER LE CONTENU DU PNR/,@$ttp_res)) ) ;
  		($pnr->{TAS_ERROR} = 19) && last if ( (grep(/SIMULTANEOUS CHANGES TO PNR/,@$ttp_res)) ||  (grep(/PLEASE VERIFY PNR AND RETRY/,@$ttp_res)) || (grep(/PLEASE VERIFY PNR CONTENT/,@$ttp_res)) );
  		($pnr->{TAS_ERROR} = 19) && last if ( (grep(/CAMBIOS SIMULTANEOS A PNR/,@$ttp_res)) || (grep(/VERIFIQUE PNR Y REINTENTE/,@$ttp_res)) || (grep(/VERIFIQUE EL CONTENIDO DEL PNR/,@$ttp_res)) ) ;
  		($pnr->{TAS_ERROR} = 31) && last if (grep(/ERREUR CARTE DE CREDIT/,@$ttp_res));
  		($pnr->{TAS_ERROR} = 31) && last if (grep(/ERREUR CARTE CREDIT/,@$ttp_res));
  		($pnr->{TAS_ERROR} = 31) && last if (grep(/MODE DE PAIEMENT ERRONE/,@$ttp_res));
  		($pnr->{TAS_ERROR} = 31) && last if (grep(/CREDIT CARD ERROR/,@$ttp_res));
  		($pnr->{TAS_ERROR} = 31) && last if (grep(/CARTE DE CREDIT REFUSEE/,@$ttp_res));
  		($pnr->{TAS_ERROR} = 31) && last if (grep(/CARTE DE CREDIT NON VALIDE/,@$ttp_res));
  		($pnr->{TAS_ERROR} = 31) && last if (grep(/DBI REQUIS/,@$ttp_res));
  		($pnr->{TAS_ERROR} = 31) && last if (grep(/DBI REQUESTED/,@$ttp_res));
  		($pnr->{TAS_ERROR} = 31) && last if (grep(/REFUS CARTE CRED/,@$ttp_res));
  		($pnr->{TAS_ERROR} = 31) && last if (grep(/REFUS CARTE DE CREDIT/,@$ttp_res));
  		($pnr->{TAS_ERROR} = 31) && last if (grep(/CARTE DE CREDIT EXPIREE/,@$ttp_res));
  		($pnr->{TAS_ERROR} = 31) && last if (grep(/CREDIT CARD EXPIRED/,@$ttp_res));
  		($pnr->{TAS_ERROR} = 31) && last if (grep(/CREDIT CARD DENIAL/,@$ttp_res));
  		($pnr->{TAS_ERROR} = 31) && last if (grep(/PRENDRE LA CARTE/,@$ttp_res));
  		($pnr->{TAS_ERROR} = 31) && last if (grep(/NE PAS HONORER/,@$ttp_res));
  		($pnr->{TAS_ERROR} = 31) && last if (grep(/DO NOT HONOR/,@$ttp_res));
  		($pnr->{TAS_ERROR} = 31) && last if (grep(/CARTE DE CREDIT INCORRECTE/,@$ttp_res));
  		($pnr->{TAS_ERROR} = 31) && last if (grep(/TARJETA DE CREDITO NEGADA/,@$ttp_res));
  		($pnr->{TAS_ERROR} = 31) && last if (grep(/TARJETA CRED\. NEGADA/,@$ttp_res));
  		($pnr->{TAS_ERROR} = 31) && last if (grep(/CREDIT CARD NOT VALID FOR THIS NEGOTIATED FARE/,@$ttp_res));
  		($pnr->{TAS_ERROR} = 31) && last if (grep(/CREDIT CARD NOT ACCEPTED BY SYSTEM PROVIDER/,@$ttp_res));
  		($pnr->{TAS_ERROR} = 31) && last if (grep(/TARJETA DE CREDITO RECHAZADA/,@$ttp_res));
  		($pnr->{TAS_ERROR} = 39) && last if (grep(/COMMISSION NON VALIDEE/,@$ttp_res));
  		($pnr->{TAS_ERROR} = 39) && last if (grep(/COMMISSION NOT VALIDATED/,@$ttp_res));
  		($pnr->{TAS_ERROR} = 39) && last if (grep(/SE REQUIERE UNA COMISION/,@$ttp_res));
  		($pnr->{TAS_ERROR} = 34) && last if (grep(/TARIF E-TKT-FORCER RETARIFER/,@$ttp_res));
  		($pnr->{TAS_ERROR} = 43) && last if (grep(/MODE DE PAIEMENT NECESSAIRE/,@$ttp_res));
  		($pnr->{TAS_ERROR} = 43) && last if (grep(/NEED FORM OF PAYMENT/,@$ttp_res));
  		($pnr->{TAS_ERROR} = 43) && last if (grep(/SE REQUIERE FORMA DE PAGO/,@$ttp_res));
  		
  		($pnr->{TAS_ERROR} = 58) && last if (grep(/TITRE NON DEMATERIALISE DEJA CHOISI - OPTION TITRE DEMATERIALISE REFUSEE/,@$ttp_res));
  		($pnr->{TAS_ERROR} = 59) && last if (grep(/TITRE DEMATERIALISE DEJA CHOISI - OPTION TITRE DEMATERIALISE OBLIGATOIRE/,@$ttp_res));
  		($pnr->{TAS_ERROR} = 60) && last if (grep(/ORIGINE-DESTINATION-CODE EQUIPEMENT NON AUTORISE AU TITRE DEMATERIALISE/,@$ttp_res));
  
   		($pnr->{TAS_ERROR} = 61) && last if (grep(/SPECIFIED PRINTER ID INVALID FOR CRT\/OFFICE OR DOES NOT EXIST/,@$ttp_res));
   		($pnr->{TAS_ERROR} = 61) && last if (grep(/ID IMPRIMANTE SPECIFIE ERRONE POUR CRT\/AGENCE OU INEXISTANTE/,@$ttp_res));
  		($pnr->{TAS_ERROR} = 61) && last if (grep(/LINK DOWN - RETRY/,@$ttp_res));
  		($pnr->{TAS_ERROR} = 61) && last if (grep(/UNABLE TO PROCESS - TIMEOUT/,@$ttp_res));
   		($pnr->{TAS_ERROR} = 61) && last if (grep(/TRAITEMENT IMPOSSIBLE - EXPIRATION/,@$ttp_res));
  		($pnr->{TAS_ERROR} = 61) && last if (grep(/NO SE PUEDE PROCESAR: TIEMPO DE ESPERA SUPERADO/,@$ttp_res));
  		($pnr->{TAS_ERROR} = 61) && last if (grep(/UNABLE TO PROCESS LINK NOT FOUND/,@$ttp_res));
  		($pnr->{TAS_ERROR} = 61) && last if (grep(/TRAITEMENT IMPOSSIBLE - LIAISON INTROUVABLE/,@$ttp_res));
  	
  		($pnr->{TAS_ERROR} = 62) && last if (grep(/USE SEGMENT SELECT/,@$ttp_res));
  		($pnr->{TAS_ERROR} = 62) && last if (grep(/UTILISER LA SELECTION DU SEGMENT/,@$ttp_res));
  		($pnr->{TAS_ERROR} = 63) && last if (grep(/INVALID CREDIT CARD INPUT, CHECK AND TRY AGAIN/,@$ttp_res));
  		($pnr->{TAS_ERROR} = 64) && last if (grep(/TICKETING INHIBITED-SSR DOCS MISSING FOR P1/,@$ttp_res));
  		($pnr->{TAS_ERROR} = 64) && last if (grep(/EMISSION INTERDITE - SSR DOCS MANQUANTS POUR P1/,@$ttp_res));
  		($pnr->{TAS_ERROR} = 64) && last if (grep(/TICKETING INHIBITED-SSR DOCS MISSING FOR P2/,@$ttp_res));
  		($pnr->{TAS_ERROR} = 64) && last if (grep(/TICKETING INHIBITED-SSR DOCS MISSING FOR P3/,@$ttp_res));
  		($pnr->{TAS_ERROR} = 64) && last if (grep(/EMISSION INTERDITE - SSR DOCS NE CORRESPOND PAS A LA CIE POUR P1/,@$ttp_res));
  		($pnr->{TAS_ERROR} = 64) && last if (grep(/EMISSION INTERDITE - SSR DOCS NE CORRESPOND PAS A LA CIE POUR P2 /,@$ttp_res));
  		($pnr->{TAS_ERROR} = 64) && last if (grep(/TICKETING INHIBITED-SSR DOCS AIRLINE PROVIDER NOT MATCHING FOR P1/,@$ttp_res));
  		($pnr->{TAS_ERROR} = 64) && last if (grep(/TICKETING INHIBITED-SSR DOCS AIRLINE PROVIDER NOT MATCHING FOR P2/,@$ttp_res));
  		($pnr->{TAS_ERROR} = 64) && last if (grep(/EMISION INHIBIDA-FALTAN SSR DOCS DE P1/,@$ttp_res));
  		($pnr->{TAS_ERROR} = 65) && last if (grep(/CREDIT CARD NOT ACCEPTED BY TICKETING AIRLINE/,@$ttp_res));
  		($pnr->{TAS_ERROR} = 65) && last if (grep(/CARTE CREDIT REFUSEE PAR PRESTAT\. SYST\.\/TRANSPORT\. EMET. BILLET/,@$ttp_res));
  		($pnr->{TAS_ERROR} = 65) && last if (grep(/LA LINEA AEREA EMISORA NO ADMITE LA TARJETA DE CREDITO /,@$ttp_res));
  		notice('Unknown TTP result message detected [...]');
  	  debug(Dumper($ttp_res));
  		$pnr->{TAS_ERROR} = 12;
      $pnr->{TAS_MESSG} = $ttp_res->[0];
			last;
	  }
	  
	  # _______________________________________________________________________
	  # ENVOI D'UN MAIL DE RAPPORT D'ERREUR
	  if ((exists($pnr->{TAS_ERROR})) && ($pnr->{TAS_ERROR} == 12)) {
	    # -----------------------------------------------------------------------
  	  # Les adresses mails qui vont être utilisées pour l'envoi des messages 12
      my $from = 'tas@egencia.com';
      my $to   = 'tas12@egencia.fr';

      # -----------------------------------------------------------------------
      my $resMail = &tasSendError12({
        from    => $from,
        to      => $to,
        subject => "TAS Robotic Tool Error 12 - Booking '".$pnr->{PNRId}."'",
        data    => 'Hello,'.
                   "\n\nTas Error 12 detected for Booking '".$pnr->{PNRId}."'".
                   "\n\nAmadeus Message : ".$pnr->{TAS_MESSG}.
                   "\n\nZorro & Bernardo ;-)\n",
      });
      notice('Problem detected during email send operation !') unless ($resMail);
	  }
	  # _______________________________________________________________________

	  notice('> NO TAS_ERROR') if (!defined $pnr->{TAS_ERROR});

  return 1;  
}

1;
