package Expedia::Databases::Connection;
#-----------------------------------------------------------------
# Package Expedia::Databases::Connection
#
# $Id: Connection.pm 410 2008-02-11 09:20:59Z pbressan $
#
# (c) 2002-2007 Expedia.                   www.expediacorporate.fr
#-----------------------------------------------------------------

use Expedia::Tools::Logger qw(&debug &notice &warning &error);

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# CONSTRUCTEUR
sub new {
  my ($class) = @_;

	$self = {};
	bless ($self, $class);
	
  $self->{_NAME}        = undef;
  $self->{_HANDLER}     = undef;
  $self->{_AUTOCONNECT} = 0;
  $self->{_CONNECTED}   = 0;

  return $self;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
sub name {
	my ($self, $name) = @_;
  
  $self->{_NAME} = $name if (defined $name);
  return $self->{_NAME};	
}

sub handler {
	my ($self, $handler) = @_;
  
  $self->{_HANDLER} = $handler if (defined $handler);
  return $self->{_HANDLER};	
}

sub autoconnect {
	my ($self, $autoconnect) = @_;
  
  $self->{_AUTOCONNECT} = $autoconnect if (defined $autoconnect);
  return $self->{_AUTOCONNECT};	
}

sub connected {
	my ($self, $connected) = @_;
  
  $self->{_CONNECTED} = $connected if (defined $connected);
  return $self->{_CONNECTED};	
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
sub database {
  my $self = (@_);
	error("Cannot invoke a virtual 'database' method.");
}

sub login {
  my $self = (@_);
	error("Cannot invoke a virtual 'login' method.");
}

sub password {
	my $self = (@_);
	error("Cannot invoke a virtual 'password' method.");
}

sub disconnectable {
  my $self = (@_);
	error("Cannot invoke a virtual 'disconnectable' method.");
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
sub connect {
  my $self = (@_);
  error("Cannot invoke a virtual 'connect' method.");
}

sub disconnect {
  my $self = (@_);
  error("Cannot invoke a virtual 'disconnect' method.");
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

1;

