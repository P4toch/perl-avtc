package Expedia::Modules::FLW::getBooking;
#-----------------------------------------------------------------
# Package Expedia::Modules::FLW::getBooking
#
# $Id: getBooking.pm 410 2008-02-11 09:20:59Z pbressan $
#
# (c) 2002-2007 Expedia.                   www.expediacorporate.fr
#-----------------------------------------------------------------

use strict;
use Data::Dumper;

use Expedia::Tools::Logger              qw(&debug &notice &warning &error);
use Expedia::Databases::WorkflowManager qw(&getNewMsgRelatedToBookings);

sub run {
  my $self   = shift;
  my $params = shift;

  my $globalParams = $params->{GlobalParams};
  my $moduleParams = $params->{ModuleParams};
  my $changes      = $params->{Changes};

  # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
  # Recupération des messages liés aux traitements des BOOKINGS

  my $items = &getNewMsgRelatedToBookings;

  # Fin : Recupération des messages liés aux traitements des BOOKINGS
  # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

  return [] if ((!defined $items) || (scalar @$items == 0));  
  
  return $items;
}

1;
