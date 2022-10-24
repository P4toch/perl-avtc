package Expedia::Modules::TAS::TrainConfirmationEmail;
#-----------------------------------------------------------------
# Package Expedia::Modules::TAS::TrainConfirmationEmail
#
# $Id: TrainConfirmationEmail.pm 572 2009-12-14 08:12:12Z pbressan $
#
# (c) 2002-2009 Expedia.                   www.expediacorporate.fr
#-----------------------------------------------------------------

use strict;
use Data::Dumper;

use Expedia::GDS::PNR;
use Expedia::Tools::Logger qw(&debug &notice &warning &error);
use Expedia::Databases::MidSchemaFuncs qw(&getPnrIdFromDv2Pnr);

sub run {
  my $self   = shift;
  my $params = shift;

  my $globalParams = $params->{GlobalParams};
  my $moduleParams = $params->{ModuleParams};
  my $changes      = $params->{Changes};
  my $item         = $params->{Item};
  my $GDS          = $params->{GDS};
  my $DVs          = $params->{DVs};
  my $tb           = $params->{ParsedXML};
  my $btcProceed   = $params->{BtcProceed};

  my $mdCode       = $tb->getMdCode;
  my $isPaper      = 0; $isPaper      = 1 if ($item->{TICKET_TYPE} eq 'paper');
  my $isEticket    = 0; $isEticket    = 1 if ($item->{TICKET_TYPE} eq 'etkt');
  my $isEbillet    = 0; $isEbillet    = 1 if ($item->{TICKET_TYPE} eq 'ebillet');
  my $isThalys     = 0; $isThalys     = 1 if ($item->{TICKET_TYPE} eq 'ttless');
  my $isTicketless = 0; $isTicketless = 1 if ($isEbillet || $isThalys);

  # ______________________________________________________________
  # Envoi des emails de confirmation ebillet et thalys ticketless
  if ($isTicketless) {
    
    if ($isEbillet) {
      
      foreach my $dv (@{$DVs}) {
      
        # On se replace sur le dossier
        $dv->{_GDS}->command(
          Command     => 'R//IG',
          NoIG        => 1,
          NoMD        => 1,
          PostIG      => 0,
          ProfileMode => 0);
        $dv->{_GDS}->command(
          Command     => 'R/RT'.$dv->{_DV},
          NoIG        => 1,
          NoMD        => 1,
          PostIG      => 0,
          ProfileMode => 0);
      
        my $lines = $dv->{_GDS}->command(
          Command     => 'R//SEND',
          NoIG        => 1,
          NoMD        => 1,
          PostIG      => 0,
          ProfileMode => 0);
          
        if (($lines->[0] =~ /^R\/\/SEND/) &&
            ($lines->[1] =~ /\*\*\s+2C\s+\-\s+RESARAIL\/SNCF\s+\*\*/)) {
        } else {
          $dv->{TAS_ERROR} = 16 if (grep(/ADRESSE E-MAIL MANQUANTE/, @$lines));
          return 1 if exists $dv->{TAS_ERROR};
          notice('Unknown R//SEND result message detected [...]');
          debug('R//SEND = '.Dumper($lines));
          notice('TAS_ERROR = 12');
          notice('TAS_MESSG = '.$lines->[1]);
    		  $dv->{TAS_ERROR} = 12;
          $dv->{TAS_MESSG} = $lines->[1];
        }
        
        notice("> NO TAS_ERROR ; DV = '".$dv->{_DV}."'")
          if (!exists $dv->{TAS_ERROR});
        
      } # FIN foreach my $dv (@{$DVs})
      
      return 1;
    }

## ________________________________________________________________
## Process non appliqué pour le moment. Développé dans le cadre Thalys TicketLess.
#    if ($isThalys) { # Open the booking with the Amdeus reference
#    
#      my $tryOfflineProc = 0;
#      my $pnrCanBeOpened = 0;
#      
#      foreach my $dv (@$DVs) {
#        my $PNR   = undef;
#        my $PNRId = getPnrIdFromDv2Pnr({MDCODE => $mdCode, DVID => $dv->{DVId}});
#        # Process Online
#        if (defined $PNRId) {
#          debug('Online. PNRId = '.$PNRId);
#          $PNR = Expedia::GDS::PNR->new(PNR => $PNRId, GDS => $GDS);
#          # Si cela ne fonctionne pas appliquer le process Offline
#          if (!defined $PNR) {
#            $tryOfflineProc = 1;
#          }
#          else {
#            $pnrCanBeOpened = 1;
#          }
#        }
#        if ((!defined $PNRId) || ($tryOfflineProc)) {
#          debug('Offline.');
#          if (defined $dv->{AMADEUSREF}) {
#            debug('Offline. PNRId = '.$dv->{AMADEUSREF});
#            $PNR = Expedia::GDS::PNR->new(PNR => $dv->{AMADEUSREF}, GDS => $GDS);
#            if (!defined $PNR) {
#              debug('### TAS MSG TREATMENT 56 ###');
#  	          $dv->{TAS_ERROR} = 56;
#              return 1;
#            }
#            # Nous essayons maintenant de voir s'il ne s'agit pas d'une mauvaise référence
#            else {
#              $GDS->RT(PNR => $dv->{AMADEUSREF});
#              my $lines = $GDS->command(Command => 'RL', NoIG => 1, NoMD => 1);
#              my $DVId  = $dv->{DVId};
#              if (grep(/2C\/$DVId/, @$lines)) { # Cela match !!!
#                $PNRId  = $dv->{AMADEUSREF};
#                $pnrCanBeOpened = 1;
#              }
#              else {
#                debug('### TAS MSG TREATMENT 56 ###');
#      	        $dv->{TAS_ERROR} = 56;
#                return 1;
#              }
#            }
#          }
#          else {
#            debug('### TAS MSG TREATMENT 55 ###');
#  	        $dv->{TAS_ERROR} = 55;
#            return 1;
#          }
#        }
#        if ($pnrCanBeOpened) {
#          my $ap_ok = 0;
#          foreach (@{$PNR->{'PNRData'}}) {
#            my $line_data = $_->{'Data'};
#            # debug('line_data = '.$line_data);
#            if ($line_data =~ /^APE.*/o) {
#  			      $ap_ok = 1 unless ($line_data =~ /^APE ETICKET_ARCHIVE/);
#  		      }
#  	      }
#          unless ($ap_ok) {
#            debug('### TAS MSG TREATMENT 14 ###');
#  	        $dv->{TAS_ERROR} = 14;
#            return 1;
#  	      }
#  	      # A ce stade, nous avons toutes les garanties. Nous pouvons envoyer la commande IEP-EMLA.
#  	      $GDS->RT(PNR => $PNRId);
#  	      $GDS->command(Command => 'IEP-EMLA',          NoIG => 1, NoMD => 1);
#  	      $GDS->command(Command => 'RF'.$GDS->modifsig, NoIG => 1, NoMD => 1);
#      	  $GDS->command(Command => 'ER',                NoIG => 1, NoMD => 1);
#      	  $GDS->command(Command => 'ER',                NoIG => 1, NoMD => 1);
#        }
#        else {
#          debug('### TAS MSG TREATMENT 55 ###');
#          $dv->{TAS_ERROR} = 55;
#          return 1;
#        }
#      } # FIN foreach my $dv (@$DVs)
#      
#    } # FIN if ($isThalys)
## ________________________________________________________________
    
  } # FIN if ($isTicketless)
  # ______________________________________________________________

  return 1;
}

1;
