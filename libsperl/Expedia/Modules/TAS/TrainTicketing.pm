package Expedia::Modules::TAS::TrainTicketing;
#-----------------------------------------------------------------
# Package Expedia::Modules::TAS::TrainTicketing
#
# $Id: TrainTicketing.pm 572 2009-12-14 08:12:12Z pbressan $
#
# (c) 2002-2008 Expedia.                   www.expediacorporate.fr
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
  my $DVs          = $params->{DVs};
  my $tb           = $params->{ParsedXML};
  my $btcProceed   = $params->{BtcProceed};

  # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
  # EMISSION DES BILLETS
  foreach my $dv (@{$DVs}) {
    
    my $tktCommand = undef;
       $tktCommand = 'R/TTP//TKE$FCA' if ($item->{TICKET_TYPE} eq 'etkt');
       $tktCommand = 'R/TTP//TKD$FCA' if ($item->{TICKET_TYPE} eq 'ebillet');
       $tktCommand = 'R/TTP//TKL$FCA' if ($item->{TICKET_TYPE} eq 'ttless');
    
    my $GDS = $dv->{_GDS};
       $GDS->command(
          Command     => 'JGU/DSR-F1', # Sélection de l'imprimante ATB
          NoIG        => 1,
          NoMD        => 1,
          PostIG      => 0,
          ProfileMode => 0);
       $GDS->command(
          Command     => 'R//IG',
          NoIG        => 1,
          NoMD        => 1,
          PostIG      => 0,
          ProfileMode => 0);
       $GDS->command(
          Command     => 'R/RT'.$dv->{_DV},
          NoIG        => 1,
          NoMD        => 1,
          PostIG      => 0,
          ProfileMode => 0);
    my $res = $GDS->command( # Format d'émission du billet
          Command     => $tktCommand,
          NoIG        => 1,
          NoMD        => 1,
          PostIG      => 0,
          ProfileMode => 0);
    
    # ==========================================================
    # Si l'émission du billet a réussi nous devrions avoir sur
    #  la première ligne la commande que nous avons envoyée et
    #  sur la seconde "** 2C - RESARAIL/SNCF **"
    # ==========================================================
    if (($res->[0] =~ /^R\/TTP\/\/TK\D\$FCA/) &&
        ($res->[1] =~ /\*\*\s+2C\s+\-\s+RESARAIL\/SNCF\s+\*\*/)) {
    }
    else {
      $dv->{TAS_ERROR} =  4   if (grep(/ANNULER D'ABORD LES TCN SUIVANTS/, @$res));
      $dv->{TAS_ERROR} = 10   if (grep(/DISCONTINUITE SEGMENT\/DATE\/HEURE/, @$res));
      $dv->{TAS_ERROR} = 16   if (grep(/RENTRER NUMERO DE CARTE RETRAIT/, @$res));
      $dv->{TAS_ERROR} = 16   if (grep(/SAISIR LA DATE DE NAISSANCE/, @$res));
      $dv->{TAS_ERROR} = 17   if (grep(/OPTION TKE IMPOSSIBLE/, @$res));
      $dv->{TAS_ERROR} = 17   if (grep(/NON AUTORISE AU BILLET ELECTRONIQUE/, @$res));
      $dv->{TAS_ERROR} = 19   if (grep(/DOSSIER VOYAGE NON LIBERE/, @$res));
      $dv->{TAS_ERROR} = 19   if ( (grep(/UTILISATION SIMULTANEE DU PNR/, @$res)) || (grep (/VERIFIER LE PNR ET REESSAYER/, @$res)) || (grep (/VERIFIER LE CONTENU DU PNR/,@$res)) ) ;
      $dv->{TAS_ERROR} = 21   if (grep(/AUCUN PRIX NE CORRESPOND A CE TYPE DE PASSAGER/, @$res));
      $dv->{TAS_ERROR} = 21   if (grep(/CLASSE DE SERVICE NON AUTORISEE AVEC CE CODE TARIF/, @$res));
      $dv->{TAS_ERROR} = 27   if (grep(/TICKETING NOMINAL AVEC UN SEUL PASSAGER OBLIGATOIRE/, @$res));
      $dv->{TAS_ERROR} = 54   if (grep(/OPTION TKL IMPOSSIBLE/, @$res));
      $dv->{TAS_ERROR} = 57   if (grep(/OPTION TKD IMPOSSIBLE/, @$res));
      return 1 if exists $dv->{TAS_ERROR};
      notice('Unknown TTP result message detected [...]');
      debug('TTP = '.Dumper($res));
      notice('TAS_ERROR = 12');
      notice('TAS_MESSG = '.$res->[1]);
  		$dv->{TAS_ERROR} = 12;
      $dv->{TAS_MESSG} = $res->[1];
      
      # _______________________________________________________________________
      # ENVOI D'UN MAIL DE RAPPORT D'ERREUR
      if ((exists($dv->{TAS_ERROR})) && ($dv->{TAS_ERROR} == 12)) {
  	    # -----------------------------------------------------------------------
    	  # Les adresses mails qui vont être utilisées pour l'envoi des messages 12
        my $from = 'tas@egencia.com';
        my $to   = 'tas12@egencia.fr';

        # -----------------------------------------------------------------------
        my $resMail = &tasSendError12({
          from    => $from,
          to      => $to,
          subject => "TAS Robotic Tool Error 12 - Booking '".$dv->{_DV}."'",
          data    => 'Hello,'.
                     "\n\nTas Error 12 detected for Booking '".$dv->{_DV}."'".
                     "\n\nSocrate Message : ".$dv->{TAS_MESSG}.
                     "\n\nZorro & Bernardo ;-)\n",
        });
        notice('Problem detected during email send operation !') unless ($resMail);
  	  }
	    # _______________________________________________________________________

      return 1;
    }
    # ==========================================================
  }
  # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
  
  return 1;
}

1;
