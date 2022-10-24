package Expedia::Modules::TJQ::GetItems;
#-----------------------------------------------------------------
# Package Expedia::Modules::TJQ::GetItems
#
# $Id: GetItems.pm 410 2013-03-14 09:20:59Z sdubuc $
#
# (c) 2002-2007 Expedia.                   www.expediacorporate.fr
#-----------------------------------------------------------------

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
