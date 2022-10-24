package Expedia::Databases::SQLServer;
#-----------------------------------------------------------------
# Package Expedia::Databases::SQLServer
#
# $Id: SQLServer.pm 671 2011-04-19 13:46:02Z pbressan $
#
# (c) 2002-2007 Expedia.                   www.expediacorporate.fr
#-----------------------------------------------------------------

use base qw(Expedia::Databases::Connection);

use DBI;
use DBD::Sybase;
use Data::Dumper;

use Expedia::Tools::Logger qw(&debug &notice &warning &error);

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# CONSTRUCTEUR
sub new {
  my ($class) = @_;

	my $self = new Expedia::Databases::Connection();
  bless ($self, $class);
  
  $self->{_TYPE}           = 'SQLServer';
	$self->{_DATABASE}       = undef;
	$self->{_LOGIN}          = undef;
	$self->{_PASSWORD}       = undef;
  $self->{_DISCONNECTABLE} = 1;
  
  return $self;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
sub type {
	my ($self, $type) = @_;

  $self->{_TYPE} = $type if (defined $type);
  return $self->{_TYPE};
}

sub database {
  my ($self, $database) = @_;

  $self->{_DATABASE} = $database if (defined $database);
  return $self->{_DATABASE};
}

sub login {
  my ($self, $login) = @_;

  $self->{_LOGIN} = $login if (defined $login);
  return $self->{_LOGIN};
}

sub password {
  my ($self, $password) = @_;

  $self->{_PASSWORD} = $password if (defined $password);
  return $self->{_PASSWORD};
}

sub disconnectable {
	my ($self) = @_;

  return $self->{_DISCONNECTABLE};
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
sub connect {
	my ($self) = @_;
	
	foreach(qw(_NAME _DATABASE _LOGIN _PASSWORD)) {
	  if (!defined($self->{$_})) {
	    error("Missing parameter '$_'.");
      return 0
	  }
	}

notice("DATABASE:".$self->database());

eval {
	$self->handler(
	  DBI->connect(
	    $self->database(),
			$self->login(),
			$self->password(),
			{AutoCommit => 1, RaiseError => 1, PrintError => 0}
		)
	);
}; if ($@) { notice('TOTO'); }
	
	if (defined $self->{_HANDLER}) {
		debug("Connected to database : '".$self->name()."'");
    $self->{_CONNECTED} = 1;
	  return 1;
	} else {
	  error("Cannot connect to '".$self->database()."'.\n$DBI::errstr");
	}
	
  return 0;
}

sub disconnect {
	my ($self) = @_;	

	$self->handler()->disconnect();
	$self->{_CONNECTED} = 0;
  debug("Disconnected from database : '".$self->name()."'");

  return 1;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# do : Used for SQL INSERT / UPDATE Queries
#      Returns Affected Rows
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
sub do {
  my ($self, $query) = @_;
  
 # $query = 'Use BaseTest3; '.$query;
#  $query = 'Use FrEgen_B; '.$query;
  
  my $rowsAffected = 0;
  
  if ($self->handler() && $query) {
    debug("Query = $query");
		eval {
			$rowsAffected = $self->handler()->do($query);
		};
		if ($@) {
	  # $self->handler()->rollback;
			error("Query = $query");
			error("Query failed. Error = $@");
			return 0;
		} else {
    # $self->handler()->commit;
			debug("Rows affected = $rowsAffected.");
    }
  } else {
    error("DB Connection and SQL Query needed.");
    return 0;
  }
  
  return $rowsAffected;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# sahr : Used for SQL SELECT Queries
#        Returns Hash Reference
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
sub sahr {
  my ($self, $query, $key) = @_;
   
  my $result = {};
  
  if ($self->handler() && $query && $key) {
		debug("Query = $query");
		eval {
			$result = $self->handler()->selectall_hashref($query, $key);
		};
		if ($@) {
			error("sahr: Query = $query");
			error("sahr: Query failed. Error = $@");
			return {};
		}
	} else {
    error("DB Connection, SQL Query and Key needed.");
    return {};
  }
  
  return $result;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# sar : Used for SQL SELECT Queries
#       Returns Array Reference
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
sub saar {
  my ($self, $query) = @_;
  
#  $query = 'Use FrEgen_B; '.$query;
  #$query = 'Use BaseTest3; '.$query;
   
  my $result = [];
  
	if ($self->handler() && $query) {
		debug("Query = $query");
		eval {
			$result = $self->handler()->selectall_arrayref($query);
		};
		if ($@) {
			error("Query = $query");
			error("Query failed. Error = $@");
			return [];
		}
	} else {
		error("DB Connection and SQL Query needed.");
    return [];
	}

  return $result;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# saarBind : Used for SQL SELECT Queries / * Bind Variables Mode *
#            Returns Array Reference
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
sub saarBind {
  my ($self, $query, $array) = @_;
   
  my $result = [];

# my $nbSelectElements = 0;
  my $nbQmarkElements  = 0;
  my $arraySize        = scalar @$array;
  
  if ($self->handler() && $query && (ref($array) eq 'ARRAY')) {
    debug("Query = $query");
    debug('Array = '.Dumper($array));
		
    # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    # ~ Cette méthode ne supporte pas les " SELECT * "
    #  Sinon on calcule le nombre d'arguments que l'on souhaite en sortie
    if ($query =~ /SELECT\s*\*\s*/i) {
      notice("Can't execute a bind query like 'SELECT <*>'");
      return [];
    } else {
      # my  $tmpQuery =  $query;
      #     $tmpQuery =~ s/\n//g;
      #     $tmpQuery =~ s/\s+/ /g;
      # if ($tmpQuery =~ /SELECT\s*(.*[^\s*FROM\s*])\s*FROM/i) {
      #   debug('SELECT = '.$1);
      #   my $selectQuery    = $1;
      #   my @selectElements = split(/,/, $selectQuery);
      #   $nbSelectElements  = scalar @selectElements;
      #   debug('$nbSelectElements = '.$nbSelectElements);
      # }
      my $pos = -1;
      while (($pos = index($query, '?', $pos)) > -1) {
      # debug("'?' Trouvé en Position = $pos");
        $pos++;
        $nbQmarkElements++;
      }
    # debug('$nbQmarkElements = '.$nbQmarkElements);
      if ($arraySize != $nbQmarkElements) {
        notice("ArraySize = $arraySize cannot be different of nbQmarkElements = $nbQmarkElements. Aborting [...]");
        return $result;
      } else {
        my $dbh = $self->handler();
        eval {
          my $sth = $dbh->prepare($query);
             $sth->execute(@$array);
          $result = $sth->fetchall_arrayref;
        };
        if ($@) {
			    error("Query = $query");
			    error("Query failed. Error = $@");
			    return [];
		    }
      }
    }
    # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  } else {
		error('DB Connection, SQL Query and ArrayRef needed.');
    return $result;
	}

  return $result;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# doBind : Used for SQL SELECT Queries / * Bind Variables Mode *
#          Returns Array Reference
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
sub doBind {
  my ($self, $query, $array, $silent) = @_;
  
  my $rows            = 0;
  my $nbQmarkElements = 0;
  my $arraySize       = scalar @$array;
     $silent          = defined $silent ? 1 : 0;
  
  if ($self->handler() && $query && (ref($array) eq 'ARRAY')) {
    debug("Query = $query"); 
    debug('Array = '.Dumper($array));

    my $pos = -1;
    while (($pos = index($query, '?', $pos)) > -1) {
    # debug("'?' Trouvé en Position = $pos");
      $pos++;
      $nbQmarkElements++;
    }
  # debug('$nbQmarkElements = '.$nbQmarkElements);
    if ($arraySize != $nbQmarkElements) {
      notice("ArraySize = $arraySize cannot be different of nbQmarkElements = $nbQmarkElements. Aborting [...]");
      return 0;
    } else {
      my $dbh = $self->handler();
      my $sth = undef;
      eval {
        $sth = $dbh->prepare($query);
        $sth->execute(@$array); 
      };
      if ($@) {
        $self->handler()->rollback;
        if ($silent) {
          debug("Query = $query");
		      debug("Query failed. Error = $@");
        } else {
		      error("Query = $query");
		      error("Query failed. Error = $@");
        }
		    return 0;
	    } else {
	      #$self->handler()->commit;
	      $rows = 1; # TODO ATTENTION
	      #$rows = $sth->rows;
			  debug("Rows affected = $rows."); # TODO ATTENTION
	    }
    }

  } else {
		error('DB Connection, SQL Query and ArrayRef needed.');
    return 0;
	}

  return $rows;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# sproc : Used for SQL proc stock Queries
#         Returns ARRAY Reference
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
sub sproc {
  my ($self, $query) = @_;
   
  my $result = [];
     
	if ($self->handler() && $query) {
		debug("Query = $query");
		eval {
		  my $dbh = $self->handler();
			$result = $sth = $dbh->prepare($query);
         
			  $sth->execute();
        
          do
          { 
            while($d = $sth->fetch)
              {
                if($sth->{syb_result_type} eq 4040) #ROW RESULT
                {
                      $msgId=$d->[0];
                      debug("$msgId:".$msgId);
                }
              }   
          } while ($sth->{syb_more_results});
        
		};
		if ($@) {
			error("Query = $query");
			error("Query failed. Error = $@");
			return [];
		}
	} else {
		error("DB Connection and SQL Query needed.");
    return [];
	}

  return $msgId;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# sproc : Used for SQL proc stock Queries
#         Returns ARRAY Reference
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
sub sproc_array {
  my ($self, $query) = @_;

  my $result = [];

        if ($self->handler() && $query) {
                debug("Query = $query");
                eval {
                  my $dbh = $self->handler();
                        $result = $sth = $dbh->prepare($query);
                        $sth->execute();
                        $result = $sth->fetchall_arrayref;
                };
                if ($@) {
                        error("Query = $query");
                        error("Query failed. Error = $@");
                        return [];
                }
        } else {
                error("DB Connection and SQL Query needed.");
    return [];
        }

  return $result;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

1;
