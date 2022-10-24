package Expedia::Modules::GAP::SeniorYouthFares;
#-----------------------------------------------------------------
# Package Expedia::Modules::GAP::SeniorYouthFares
#
# $Id: SeniorYouthFares.pm 560 2009-11-30 10:32:38Z pbressan $
#
# (c) 2002-2009 Expedia.                   www.expediacorporate.fr
#-----------------------------------------------------------------

use strict;
use Data::Dumper;

use Expedia::Tools::GlobalFuncs qw(fielddate2srdocdate);
use Expedia::Tools::Logger qw(&debug &notice &warning &error);

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
sub run {
  my $self   = shift;
  my $params = shift;

  my $globalParams = $params->{GlobalParams};
  my $moduleParams = $params->{ModuleParams};
  my $changes      = $params->{Changes};
  my $item         = $params->{Item};
  my $pnr          = $params->{PNR};
  my $ab           = $params->{ParsedXML};
  my $WBMI         = $params->{WBMI};
    
  my $travellers   = $pnr->{Travellers};
  
  my $h_pnr        = $params->{Position};
  my $refpnr       = $params->{RefPNR};
  
  my $position        = $h_pnr->{$refpnr};      

  my $atds = $ab->getTravelDossierStruct; 

  my $pp           = $ab->getAirProductPricing({lwdPos => $atds->[$position]->{lwdPos}});
  my $fareType     = '';
     $fareType     = $pp->{FareType} if (exists $pp->{FareType}); debug(' fareType = '.$pp->{FareType});

  # _______________________________________________________________________
  if ($fareType =~ /^(TARIF_JEUNE|TARIF_SENIOR)$/) {
    
    my $GDS = $pnr->{_GDS};
       $GDS->RT(PNR=>$pnr->{'PNRId'}, NoMD=>1, NoPostIG=>1);
    
    foreach my $traveller (@$travellers) {
      
      if ($fareType eq 'TARIF_JEUNE') {
        
        my $birthDate = '';
           $birthDate = fielddate2srdocdate($ab->getTravellerBirthDate($traveller->{Position}));
        debug('birthDate = '.$birthDate);
        if ($birthDate eq '') {
          $WBMI->addReport({ Code      => 27,
                             PnrId     => $pnr->{_PNR},
                             PaxNumber => $traveller->{PaxNum},
                             PerCode   => $traveller->{PerCode}});
        } else {
          my $lines   = [];
          my $command = 'FDZZ'.$birthDate.'/'.$traveller->{PaxNum};
          BOUCLE: {
            $lines = $GDS->command(Command=>$command,               NoIG=>1, NoMD=>1);
            $lines = $GDS->command(Command=>'FXP',                  NoIG=>1, NoMD=>1);
                     $GDS->command(Command=>'RF'.$GDS->{_MODIFSIG}, NoIG=>1, NoMD=>1);
            $lines = $GDS->command(Command=>'ER',                   NoIG=>1, NoMD=>1);
              if ( (grep (/CHANGTS SIMULT DANS PNR/, @$lines)) ||
				   (grep (/VERIFIER LE PNR ET REESSAYER/ ,   @$lines)) ||
		           (grep (/VERIFIER LE CONTENU DU PNR/ ,   @$lines)) )
			 {
              $GDS->command(Command=>'IG',   NoIG=>0, NoMD=>1);
              $GDS->RT(PNR=>$pnr->{'PNRId'}, NoMD=>1, NoPostIG=>1);
              redo BOUCLE;
            }
            $GDS->command(Command=>'ER', NoIG=>1, NoMD=>1);
          }
        }
        
      } elsif ($fareType eq 'TARIF_SENIOR') {
        
        my $lines   = [];
        my $command = 'FDCD/'.$traveller->{PaxNum};
        BOUCLE: {
          $lines = $GDS->command(Command=>$command,               NoIG=>1, NoMD=>1);
          $lines = $GDS->command(Command=>'FXP',                  NoIG=>1, NoMD=>1);
                   $GDS->command(Command=>'RF'.$GDS->{_MODIFSIG}, NoIG=>1, NoMD=>1);
          $lines = $GDS->command(Command=>'ER',                   NoIG=>1, NoMD=>1);
          if ( (grep (/CHANGTS SIMULT DANS PNR/, @$lines)) ||
			   (grep (/VERIFIER LE PNR ET REESSAYER/ ,   @$lines)) ||
		       (grep (/VERIFIER LE CONTENU DU PNR/ ,   @$lines)) ) 
		  {
            $GDS->command(Command=>'IG',   NoIG=>0, NoMD=>1);
            $GDS->RT(PNR=>$pnr->{'PNRId'}, NoMD=>1, NoPostIG=>1);
            redo BOUCLE;
          }
          $GDS->command(Command=>'ER', NoIG=>1, NoMD=>1);
        }
        
      }

    }
  }
  # _______________________________________________________________________

  return 1;  
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

1;
