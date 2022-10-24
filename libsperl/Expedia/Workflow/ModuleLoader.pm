package Expedia::Workflow::ModuleLoader;
#-----------------------------------------------------------------
# Package Expedia::Workflow::ModuleLoader
#
# $Id: ModuleLoader.pm 410 2008-02-11 09:20:59Z pbressan $
#
# (c) 2002-2007 Expedia.                   www.expediacorporate.fr
#-----------------------------------------------------------------

# use Expedia::Tools::Logger qw(&debug &notice &warning &error);

sub new {
  my $class  = shift;
  my $module = shift;

  $class = "Expedia::Modules::$module";
  
	no  strict 'refs';
	eval "use $class";
	die $@ if $@;
	use strict 'refs';

	my $self = bless {}, $class;

  # TODO Passer les paramètres au module

	return $self;
}

1;
