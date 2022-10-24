package Expedia::Databases::ConnectionsManager;
#-----------------------------------------------------------------
# Package Expedia::Databases::ConnectionsManager
#
# $Id: ConnectionsManager.pm 410 2008-02-11 09:20:59Z pbressan $
#
# (c) 2002-2007 Expedia.                   www.expediacorporate.fr
#-----------------------------------------------------------------

our $CONNECTIONS = []; # Peut contenir plusieurs objets ConnectionsManager

use Expedia::Tools::Logger qw(&debug &notice &warning &error);
use Expedia::Tools::GlobalVars qw($cnxMgr);

use Expedia::Databases::Amadeus;
use Expedia::Databases::SQLServer;
use Expedia::Databases::Connection;

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# CONSTRUCTEUR
sub new {
  my ($class, $h_connections) = @_;

	$self = {};
	bless ($self, $class);
	
  $self->{_CONNECTIONS} = []; # Liste d'objets Connection

  my $connection   = undef;
  my $h_connection = undef;

  foreach my $connectionType (keys %$h_connections) {
    foreach my $connectionName (keys %{$h_connections->{$connectionType}}) {
      $connection   = undef;
      $h_connection = undef;
      $h_connection->{$connectionName} = $h_connections->{$connectionType}->{$connectionName};
      $connection = $self->_newConnection($h_connection);
      $self->_addConnection($connection) unless (!$connection);
    }
  }

  $self->connect();

  push(@$CONNECTIONS, $self);

  $cnxMgr = $self;

  return $self;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
sub connections {
	my ($self, $connections) = @_;
  
  $self->{_CONNECTIONS} = $connections if (defined $connections);
  return $self->{_CONNECTIONS};	
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Cette méthode retourne le handler de connection correspondant
# au nom passé en paramètre. La fonction retourne undef sinon.
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
sub getConnectionByName {
	my ($self, $name) = @_;

  my $nbConnectionsFound  = 0;
  my $connection          = undef;

  if ((!$name) || ($name =~ /^\s*$/)) {
    error("Param 'connectionName' is needed.");
    return undef;
  } else {
    foreach my $cnx (@{$self->connections()}) {
      next if ($cnx->name() ne $name);
      $nbConnectionsFound++;
      $connection = $cnx;
    }
  }

	if ($nbConnectionsFound == 0) {
  	warning("No connection called '".$name."' was found.");
    return undef;
  }
  if ($nbConnectionsFound  > 1) {
  	warning("Ambiguous connectionName '".$name."'. Multiple results found.");
    return undef;
  }
  if ($nbConnectionsFound == 1) {
    if ($connection->connected() == 0) {
      if ($connection->type ne 'Amadeus') {
        error("Requested connection '".$name."' is not connected.");
        return undef;
      }
    }
  }

  return $connection;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Cette méthode va connecter tous les objets Connections s'ils ne sont
# pas déjà connectés et qu'ils ont la propriété 'autoconnect'.
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
sub connect {
  my ($self) = @_;

  foreach my $connection (@{$self->connections()}) {
    next if ($connection->connected());
    next if ($connection->autoconnect() == 0);
    error("Problem during connection of '".$connection->name()."'.")
      unless ($connection->connect());
  }

  return 1;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Cette méthode va déconnecter tous les objets Connections
# s'ils sont connectés et s'ils sont "déconnectables".
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
sub disconnect {
  my ($self) = @_;

  foreach my $connection (@{$self->connections()}) {
    next unless ($connection->connected());
    next unless ($connection->disconnectable());
    error("Problem during disconnection from '".$connection->name()."'.")
      unless ($connection->disconnect());
  }

  return 1;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Cette méthode privée ajoute les objets Connection dans _CONNECTIONS
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
sub _addConnection {
	my ($self, $connectionObject) = @_;

  if (!$connectionObject) {
    error("Param 'connectionObject' is needed.");
    return 0;
  }

  if ((ref($connectionObject) ne 'Expedia::Databases::SQLServer') &&
      (ref($connectionObject) ne 'Expedia::Databases::Amadeus')) {
    error("Param 'connectionObject' given is not an instance of 'Connection'.");
    return 0;
  }

  push (@{$self->connections()}, $connectionObject);

  return 1;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@a

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Cette méthode privée s'occupe de créer l'objet Connection en
# fonction d'un Hash extrait depuis le fichier de config.
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
sub _newConnection {
  my ($self, $h_connection) = @_;

  if (!$h_connection) {
    error("Param 'h_connection' is needed.");
    return undef;
  }

  my @size = keys %$h_connection;

  if (scalar(@size) != 1) {
    error("Number of hash keys should be 1.");
    return undef;
  }

  my $connectionName = $size[0];

  if ((!exists($h_connection->{$connectionName}->{type})) ||
      ($h_connection->{$connectionName}->{type} !~ /SQLServer|Amadeus/)) {
    error("Type of connection should match 'SQLServer' or 'Amadeus'.");
    return undef;
  }

  my $connection = undef;

  $connection = Expedia::Databases::SQLServer->new() if ($h_connection->{$connectionName}->{type} eq 'SQLServer');
  $connection = Expedia::Databases::Amadeus->new()   if ($h_connection->{$connectionName}->{type} eq 'Amadeus');

  if ($connection->type() =~ /SQLServer/) {
    $connection->name        ($connectionName);
    $connection->database    ($h_connection->{$connectionName}->{database});
    $connection->login       ($h_connection->{$connectionName}->{login});
    $connection->password    ($h_connection->{$connectionName}->{password});
    $connection->autoconnect ($h_connection->{$connectionName}->{autoconnect});
  }

  if ($connection->type() =~ /Amadeus/) {
    $connection->name                ($connectionName);
    $connection->signin              ($h_connection->{$connectionName}->{signin});
    $connection->modifsig            ($h_connection->{$connectionName}->{modifsig});
    $connection->tcp                 ($h_connection->{$connectionName}->{tcp});
    $connection->port                ($h_connection->{$connectionName}->{port});
    $connection->corpoid             ($h_connection->{$connectionName}->{corpoid});
    $connection->login               ($h_connection->{$connectionName}->{login});
    $connection->password            ($h_connection->{$connectionName}->{password});
    $connection->officeid            ($h_connection->{$connectionName}->{officeid});
    $connection->language            ($h_connection->{$connectionName}->{language});
    $connection->autoconnect         ($h_connection->{$connectionName}->{autoconnect});
    $connection->use_cryptic_service ($h_connection->{$connectionName}->{use_cryptic_service});
  }

  return $connection;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
sub END {
  $_->disconnect() foreach (@$CONNECTIONS);
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

1;
