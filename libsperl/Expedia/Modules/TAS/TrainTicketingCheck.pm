package Expedia::Modules::TAS::TrainTicketingCheck;
#-----------------------------------------------------------------
# Package Expedia::Modules::TAS::TrainTicketingCheck
#
# $Id: TrainTicketingCheck.pm 572 2009-12-14 08:12:12Z pbressan $
#
# (c) 2002-2009 Expedia.                   www.expediacorporate.fr
#-----------------------------------------------------------------

use strict;
use Data::Dumper;

use Expedia::Tools::Logger qw(&debug &notice &warning &error);

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
  # VERIFICATION DE L'EMISSION DES BILLETS
  foreach my $dv (@{$DVs}) {
    
    my $scanWP8 = 0;
       $scanWP8 = $dv->_scanWP8 while ($scanWP8 != 1);
       
    my $h_paxSegsToTicket = $dv->{H_PAXSEGS_TOTICKET};
    debug('$h_paxSegsToTicket = '.Dumper($h_paxSegsToTicket));
    
    # ==========================================================
    # Réorganisation du résultat de WP8 pour comparaison avec
    #   ce que l'on a fait lors TrainCheckPricing.pm
    my $h_paxSegsTicketed = {};
    my @WP8INFO           = @{$dv->{WP8INFO}};
    foreach my $wp8info (@WP8INFO) {
      my @paxList = @{$wp8info->{paxList}};
      my @segList = @{$wp8info->{segList}};
      foreach my $paxNum (@paxList) {
        push @{$h_paxSegsTicketed->{$paxNum}}, $_ foreach (@segList);
      }
    }
    debug('$h_paxSegsTicketed = '.Dumper($h_paxSegsTicketed));
    # ==========================================================
    
    # ==========================================================
    # Effectue une comparaison entre les deux hash suivants
    #    $h_paxSegTicketed   et   $h_paxSegToTicket
    foreach my $paxNum (keys %$h_paxSegsToTicket) {
      if (!exists $h_paxSegsTicketed->{$paxNum}) {
        debug('### TAS MSG TREATMENT 25 ###');
        $dv->{TAS_ERROR} = 25;
        return 1;
      }
      else {
        my $segsToTicket = $h_paxSegsToTicket->{$paxNum};
        my $segsTicketed = $h_paxSegsTicketed->{$paxNum};
        foreach my $segToTicket (@$segsToTicket) {
          my $segFound = 0;
          foreach my $segTicketed (@$segsTicketed) {
            $segFound = 1 if ($segToTicket == $segTicketed);
          }
          # _____________________________________________________________
          # Règle Désactivée le 26 Mars 2009 - Dysfonctionnement ResaRail
          # Règle  Réactivée le 11 Mai  2009 - Correctif Resarail =P
          if ($segFound == 0) {
            debug('### TAS MSG TREATMENT 24 ###');
            $dv->{TAS_ERROR} = 24;
            return 1;
          }
          # _____________________________________________________________
        }
      }
    }
    # ==========================================================
    
    notice("> NO TAS_ERROR ; DV = '".$dv->{_DV}."'")
      if ((!exists $dv->{TAS_ERROR}) && ($item->{TICKET_TYPE} ne 'ebillet'));
    
  }
  # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
  
  return 1;
}

1;
