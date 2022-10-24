package Expedia::Modules::EMD::GetItems;
#-----------------------------------------------------------------
# Package Expedia::Modules::EMD::GetItems
#
# $Id: GetItems.pm 410 2014-06-17 09:20:59Z sdubuc $
#
# (c) 2002-2007 Expedia.                   www.expediacorporate.fr
#-----------------------------------------------------------------
use Expedia::Tools::Logger              qw(&debug &notice &warning &error);

sub run {

  my $self   = shift;
  my $params = shift;

  my $taskName     = $params->{TaskName};
  my $globalParams = $params->{GlobalParams};
  my $moduleParams = $params->{ModuleParams};
  my $changes      = $params->{Changes};


  return ();
}

1;

