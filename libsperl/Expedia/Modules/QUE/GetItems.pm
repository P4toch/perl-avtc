package Expedia::Modules::QUE::GetItems;
#-----------------------------------------------------------------
# Package Expedia::Modules::QUE::GetItems
#
# $Id: GetItems.pm 410 2008-02-11 09:20:59Z pbressan $
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
