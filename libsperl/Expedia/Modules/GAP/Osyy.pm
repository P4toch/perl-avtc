package Expedia::Modules::GAP::Osyy;
#-----------------------------------------------------------------
# Package Expedia::Modules::GAP::Osyy
#
# $Id: Osyy.pm 410 2008-02-11 09:20:59Z pbressan $
#
# (c) 2002-2007 Expedia.                   www.expediacorporate.fr
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

  my $travellers   = $pnr->{Travellers};
  my $nbPax        = scalar @$travellers;

  # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
  # MONO PAX
  if ($nbPax == 1) {
    my $Osyy = $ab->getOsyy({trvPos => $ab->getWhoIsMain });
    return 1 if ($Osyy =~ /^\s*$/);
    $Osyy = stringGdsOthers($Osyy);
    $Osyy = substr($Osyy, 0, 58) if (length($Osyy) > 58);
    push (@{$changes->{add}}, { Data => 'OSYY'.$Osyy });
  }
  # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
  # MULTI PAX    
  elsif ($nbPax > 1) {
    PAX: foreach my $traveller (@$travellers) {
      my $Osyy = $ab->getOsyy({trvPos => $traveller->{Position} });
      next PAX if ($Osyy =~ /^\s*$/);
      $Osyy = stringGdsOthers($Osyy);
      $Osyy = substr($Osyy, 0, 58) if (length($Osyy) > 58);
      push (@ {$changes->{add}}, { Data => 'OSYY'.$Osyy.'/'.$traveller->{PaxNum} });
    }
  }
  # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

  return 1;  
}

1;
