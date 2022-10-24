package Expedia::XML::Config;
#-----------------------------------------------------------------
# Package Expedia::XML::Config
#
# $Id: Config.pm 410 2008-02-11 09:20:59Z pbressan $
#
# (c) 2002-2007 Expedia.                   www.expediacorporate.fr
#-----------------------------------------------------------------

use XML::LibXML;
use Data::Dumper;
use File::Slurp qw(read_file);

use Expedia::Tools::Logger qw(&debug &notice &warning &error);
use Expedia::Databases::ConnectionsManager;
use Expedia::Tools::GlobalVars          qw($cnxMgr $nav_task);

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# CONSTRUCTEUR
sub new {
  my ($class, $configFileDDB, $task) = @_;

 # if (!$configFile || !(-e $configFile)) {
 #   error("A valid configFile is required.");
 #   exit(1);
 # }

#notice("TASK:".$task);

	my $self = {};
  bless ($self, $class);

  $self->{_PARSER}         = XML::LibXML->new();
#  $self->{_CONFIGFILE}     = $configFile;
  $self->{_CONFIGFILEDDB}  = $configFileDDB;
  $self->{_PARSEDFILE}     = undef;

  $self->{_CONNECTIONS} = {};
  $self->{_CONNECTIONS_DATABASE} = {};
  $self->{_TASKS}       = {};
  $self->{_SOURCES}     = {};
  $self->{_PROCESSES}   = {}; # Utilisé dans le cadre de TAS

  $self->{IN}           = $task;
  
  return undef unless ($self->_parse());

  my $name    = $self->{IN};
  my $product = "";
  
  #SPECIFICITE TAS
  if($name =~ /(tas-.*):(.*)/){
      $name=$1;
      $product=uc($2);
  }

   my $db_connection_mid = 'mid';
   my $db_connection_nav =undef;	
	
  

  foreach (@$nav_task) {
     if ($name =~ m/$_/) {
	    $db_connection_nav='navision';
     }
   }

	
	
    return undef unless ($self->_getConnections_database($db_connection_mid,$db_connection_nav) );
    return undef unless ($self->_getConnections_amadeus($name,$product) );
    return undef unless ($self->_getTasks($name,$product) );
    return undef unless ($self->_getSources($name,$product) );
    #return undef unless ($self->_getProcesses() );
    return undef unless ($self->_checkValidity());
  
  return $self;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
sub parser {
  my ($self) = @_;

  return $self->{_PARSER};
}

sub configfile {
  my ($self) = @_;

  return $self->{_CONFIGFILE};
}

sub configfileDDB {
  my ($self) = @_;

  return $self->{_CONFIGFILEDDB};
}

#sub parsedfile {
#  my ($self, $parsedfile) = @_;
#
#  $self->{_PARSEDFILE} = $parsedfile if (defined $parsedfile);
#  return $self->{_PARSEDFILE};
#}

sub parsedfileDDB {
  my ($self, $parsedfileDDB) = @_;

  $self->{_PARSEDFILEDDB} = $parsedfileDDB if (defined $parsedfileDDB);
  return $self->{_PARSEDFILEDDB};
}

sub connections {
  my ($self, $connections) = @_;

  $self->{_CONNECTIONS} = $connections if (defined $connections);
  return $self->{_CONNECTIONS};
}

sub tasks {
  my ($self, $tasks) = @_;

  $self->{_TASKS} = $tasks if (defined $tasks);
  return $self->{_TASKS};
}

sub sources {
  my ($self, $sources) = @_;

  $self->{_SOURCES} = $sources if (defined $sources);
  return $self->{_SOURCES};
}

sub processes {
  my ($self, $processes) = @_;

  $self->{_PROCESSES} = $processes if (defined $processes);
  return $self->{_PROCESSES};
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Parse le fichier de Config XML et le stocke dans $self->{_PARSEDFILE}
sub _parse {
  my ($self) = @_;

#  if (!defined($self->{_CONFIGFILE})) {
#    error("Missing parameter _CONFIGFILE.");
#    return 0;
#  }

#  my $parsedFile = undef;
  my $parsedFileDDB = undef;
  
#  my $configFile    = read_file($self->configfile());
  my $configFileDDB = read_file($self->configfileDDB());
  
#  eval {
#    $parsedFile = $self->{_PARSER}->parse_string($configFile);
#  };
#  if ($@) {
#    error("Parser Error !#! ".$@);
#    return 0;
#  }

  eval {
    $parsedFileDDB = $self->{_PARSER}->parse_string($configFileDDB);
  };
  if ($@) {
    error("Parser Error !#! ".$@);
    return 0;
  }
  
#  $parsedFile->indexElements();
  $parsedFileDDB->indexElements();

#  $self->{_PARSEDFILE} = $parsedFile;
  $self->{_PARSEDFILEDDB} = $parsedFileDDB;

  return 1;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Convertit tous les noeuds Connections dans une HashRef
sub _getConnections_amadeus {
  my ($self,$name,$product) = @_;

  my $dbh     = $cnxMgr->getConnectionByName('mid');

   my $request="SELECT O.ID,O.OID,O.NAME,O.CORPOID,O.MODIFSIG,O.SIGNIN,O.TCP,O.PORT,O.LOGIN,O.PASSWORD,O.LANGUAGE,O.AUTOCONNECT,O.USE_CRYPTIC_SERVICE 
               FROM MO_CFG_TASK T, MO_CFG_OID O WHERE T.AMADEUS= O.NAME AND T.ATTACH= O.ID AND UPPER(T.NAME) =UPPER(?) AND UPPER(T.PRODUCT)=UPPER(?)";
   my $connections = $dbh->saarBind($request,[$name,$product]);    
 
  #notice("connections:".Dumper($connections));

  if ((scalar @$connections == 0)) {
    error("No match in MO_CFG_TASK for:".$self->{IN}." (_getConnections_amadeus)");
    return 0;
  }

#notice("RES:".Dumper($connections));
  #my @connections = $self->{_PARSEDFILE}->getElementsByTagName('Connections');
 
  CNX: foreach my $connectionNode (@$connections) {

    my @amadeus   = undef;

    #@amadeus   = $connectionNode->findnodes('Amadeus');

    #AMD: foreach (@amadeus)   {
      my $officeid            = $connectionNode->[1];
      my $name                = $connectionNode->[2];
      my $corpoid             = $connectionNode->[3];
      my $modifsig            = $connectionNode->[4];
      my $signin              = $connectionNode->[5];      
      my $tcp                 = $connectionNode->[6];
      my $port                = $connectionNode->[7];
      my $login               = $connectionNode->[8];
      my $password            = $connectionNode->[9];
      my $language            = $connectionNode->[10];
      my $autoconnect         = $connectionNode->[11];
      my $use_cryptic_service = $connectionNode->[12];

#notice("CONN:".$connectionNode->[1]);
#notice("CONN:".$connectionNode->[2]);
#notice("CONN:".$connectionNode->[3]);
#notice("CONN:".$connectionNode->[4]);
#notice("CONN:".$connectionNode->[5]);
#notice("CONN:".$connectionNode->[6]);
#notice("CONN:".$connectionNode->[7]);
#notice("CONN:".$connectionNode->[8]);
#notice("CONN:".$connectionNode->[9]);
#notice("CONN:".$connectionNode->[10]);
#notice("CONN:".$connectionNode->[11]);
#notice("CONN:".$connectionNode->[12]);

      $autoconnect = 0 unless ($autoconnect);

      if (!$name    || !$signin || !$modifsig || !$tcp      || !$port ||
          !$corpoid || !$login  || !$password || !$officeid || !$language) {
        error("Missing parameter for Amadeus connection.");
        next CNX;
      } else {
        if (exists($self->{_CONNECTIONS}->{Amadeus}->{$name})) {
          error("This HashKey '".$name."' already exists under _CONNECTIONS::Amadeus.");
          next CNX;
        } else {
          $self->{_CONNECTIONS}->{Amadeus}->{$name}->{signin}              = $signin;
          $self->{_CONNECTIONS}->{Amadeus}->{$name}->{modifsig}            = $modifsig;
          $self->{_CONNECTIONS}->{Amadeus}->{$name}->{tcp}                 = $tcp;
          $self->{_CONNECTIONS}->{Amadeus}->{$name}->{port}                = $port;
          $self->{_CONNECTIONS}->{Amadeus}->{$name}->{corpoid}             = $corpoid;
          $self->{_CONNECTIONS}->{Amadeus}->{$name}->{login}               = $login;
          $self->{_CONNECTIONS}->{Amadeus}->{$name}->{password}            = $password;
          $self->{_CONNECTIONS}->{Amadeus}->{$name}->{officeid}            = $officeid;
          $self->{_CONNECTIONS}->{Amadeus}->{$name}->{language}            = $language;
          $self->{_CONNECTIONS}->{Amadeus}->{$name}->{autoconnect}         = $autoconnect;
          $self->{_CONNECTIONS}->{Amadeus}->{$name}->{use_cryptic_service} = $use_cryptic_service;
          $self->{_CONNECTIONS}->{Amadeus}->{$name}->{type}                = 'Amadeus';
        }
      }
    #}

  } # Fin CNX: foreach my $connectionNode (@connections)
  
  # notice('getConnections: '.Dumper($self->{_CONNECTIONS}));

  # ---------------------------------------------------------------
  # Initialisation des connexions aux bases de données
  Expedia::Databases::ConnectionsManager->new($self->{_CONNECTIONS});


  return 1;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Convertit tous les noeuds Connections dans une HashRef
sub _getConnections_database {
  my ($self,$db_name_mid,$db_name_nav) = @_;

  if (!defined($self->{_PARSEDFILEDDB})) {
    error("configFile DDB hasn't been parsed.");
    return 0;
  }

  my @connectionsDDB = $self->{_PARSEDFILEDDB}->getElementsByTagName('Connections');

  CNX: foreach my $connectionNode (@connectionsDDB) {

    my @sqlserver = undef;

    @sqlserver = $connectionNode->findnodes('SQLServer');

    SQL: foreach (@sqlserver) {
      my $dbname      = $_->find('dbname')->to_literal->value();
	  next SQL if (($dbname eq 'navision') && (!defined($db_name_nav)));   #### On sort si la connection à NAV n'est pas necessaire
      my $database    = $_->find('database')->to_literal->value();
      my $login       = $_->find('login')->to_literal->value();
      my $password    = $_->find('password')->to_literal->value();
      my $autoconnect = $_->find('autoconnect')->to_literal->value();

      $autoconnect = 0 unless ($autoconnect);

      if (!$dbname || !$database || !$login || !$password) {
        error("Missing parameter for SQLServer connection.");
        next SQL;
      } else {
        if (exists($self->{_CONNECTIONS}->{SQLServer}->{$dbname})) {
          error("This HashKey '".$dbname."' already exists under _CONNECTIONS::SQLServer.");
          next SQL;
        } else {
          $self->{_CONNECTIONS}->{SQLServer}->{$dbname}->{database}    = $database;
          $self->{_CONNECTIONS}->{SQLServer}->{$dbname}->{login}       = $login;
          $self->{_CONNECTIONS}->{SQLServer}->{$dbname}->{password}    = $password;
          $self->{_CONNECTIONS}->{SQLServer}->{$dbname}->{autoconnect} = $autoconnect;
          $self->{_CONNECTIONS}->{SQLServer}->{$dbname}->{type}        = 'SQLServer';
        }
      }
    }

  } # Fin CNX: foreach my $connectionNode (@connectionsDDB)
  
  #notice('getConnections Databases: '.Dumper($self->{_CONNECTIONS}));

  # ---------------------------------------------------------------
  # Initialisation des connexions aux bases de données
  Expedia::Databases::ConnectionsManager->new($self->{_CONNECTIONS});

  return 1;

}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@


# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Convertit tous les noeuds Tasks dans une HashRef
sub _getTasks {
  my ($self,$name,$product) = @_;

  my $dbh     = $cnxMgr->getConnectionByName('mid');
  my $request="SELECT T.NAME, S.MODULE, T.AMADEUS, T.LOGFILE, T.ID_MODULE, T.MARKET, T.AGENCY
               FROM MO_CFG_TASK T , MO_CFG_SOURCE S WHERE S.ID= T.ID_SOURCE AND UPPER(T.NAME) = UPPER(?) AND UPPER(T.PRODUCT)=UPPER(?)";               
  my $tasks = $dbh->saarBind($request,[$name,$product]); 

  notice("tasks:".Dumper($tasks));
  
  if ((scalar @$tasks == 0)) {
    error("No match in MO_CFG_TASK for:".$self->{IN}." (_getTasks)");
    return 0;
  }
 
 # my @tasks = $self->{_PARSEDFILE}->getElementsByTagName('Tasks');
 #foreach (@$tasks) {
 # my @task = $_->getElementsByTagName('Task');
 TSK: foreach my $taskNode (@$tasks) {

  my $name      = undef;
  my $source    = undef;
  my $amadeus   = undef;
  my $logFile   = undef;
  my $process   = undef;
  my $id_module = undef;
  my $market    = undef;
  my $agency    = undef;
  my @modules = ();

  $name      = $taskNode->[0];
  $source    = $taskNode->[1];
  $amadeus   = $taskNode->[2];
  $logFile   = $taskNode->[3];
  $id_module = $taskNode->[4];
  $market    = $taskNode->[5];
  $agency    = $taskNode->[6];
    

     $request="SELECT M.MODULE, M.RANK, M.INTERACTIVE FROM MO_CFG_MODULES M WHERE M.ID=?";
  my $modules = $dbh->saarBind($request,[$id_module]);
   
      #@modules = $taskNode->getElementsByTagName('module');

      if (!$name || !$source || !$amadeus || !$logFile){ # && (!$process))) {    
        error("Missing parameter for Task definition.");
        error("It should be at least one Module or Process defined in Task $name.") if ($name && (scalar(@modules) == 0));# && (!$process)));
        error("It should be at least one Source defined in Task $name.")            if ($name &&  (scalar(@sources) == 0));          
        #next TSK;
      } else {
        if (exists($self->{_TASKS}->{$name})) {
          error("This HashKey '".$name."' already exists under _TASKS.");
          #next TSK;
        } else {
          $self->{_TASKS}->{$name}->{name}    = $name;
          $self->{_TASKS}->{$name}->{source}  = $source;
          $self->{_TASKS}->{$name}->{amadeus} = $amadeus;
          $self->{_TASKS}->{$name}->{logFile} = $logFile;
          $self->{_TASKS}->{$name}->{market}  = $market;
          $self->{_TASKS}->{$name}->{agency}  = $agency;
          
          # Récupération des Tags supplémentaires sous Task
          #my @childNodes = $taskNode->childNodes();
          #CHILD: foreach my $childNode (@childNodes) {
          #  my $nodeType = $childNode->nodeType();
          #  if ($nodeType == 1) { # Le nodeType est un "Element"
          #    my $tagName = $childNode->tagName();
          #    next CHILD if ($tagName =~ /name|source|amadeus|modules|process/);
          #    $self->{_TASKS}->{$name}->{$tagName} = $taskNode->find($tagName)->to_literal->value();
          #  }
          #}

        }
        
          # ---------------------------------------------------------------
          # Récupération des Modules et des Tags supplémentaires de Modules
          my $h_modules  = {};
          my $h_imodules = {}; # Modules "interactifs" utilisé pour "BTC-AIR"
          my $h_tags     = {};

          MOD: foreach my $moduleNode (@$modules) {

            my $modName = undef;
            my $modRank = undef;
            my $modIntr = undef; # Modules "interactifs" utilisé pour "BTC-AIR"

						$modName = $moduleNode->[0];
						$modRank = $moduleNode->[1];
						$modIntr = $moduleNode->[2];

            if (!$modName || !$modRank) {
							error("Missing parameter for Module in Task $name.");
              next MOD;
            } else {
              
              if ((!$modIntr) || (($modIntr) && ($modIntr == 0))) {
              
                if (exists($h_modules->{$modRank})) {
                  error("Rank '".$modRank."' already exists for Module $modName in Task $name.");
                  next MOD;
                } else {
                  $h_modules->{$modRank}->{name} = $modName;
            
                  # Récupération des Tags supplémentaires sous Module
                  #my @childNodes = $moduleNode->childNodes();
                  #CHILD: foreach my $childNode (@childNodes) {
                  #  my $nodeType = $childNode->nodeType();
                  #  if ($nodeType == 1) { # Le nodeType est un "Element"
                  #    my $tagName = $childNode->tagName();
                  #    next CHILD if ($tagName =~ /name|rank/);
                  #    $h_tags->{$modRank}->{$tagName} = $moduleNode->find($tagName)->to_literal->value();
                  #  }
                  #}
                }
              }
              elsif (($modIntr) && ($modIntr == 1)) {
                if (exists($h_imodules->{$modRank})) {
                  error("Rank '".$modRank."' already exists for iModule $modName in Task $name.");
                  next MOD;
                } else {
                  $h_imodules->{$modRank}->{name} = $modName;
                  # Récupération des Tags supplémentaires sous Module
                  #my @childNodes = $moduleNode->childNodes();
                  #CHILD: foreach my $childNode (@childNodes) {
                  #  my $nodeType = $childNode->nodeType();
                  #  if ($nodeType == 1) { # Le nodeType est un "Element"
                  #    my $tagName = $childNode->tagName();
                  #    next CHILD if ($tagName =~ /name|rank|interactive/);
                  #    $h_tags->{$modRank}->{$tagName} = $moduleNode->find($tagName)->to_literal->value();
                  #  }
                  #}
                }
              }
            }
          }
          # ---------------------------------------------------------------

          # debug("_getTasks: h_modules  = ".Dumper($h_modules));
          # debug("_getTasks: h_imodules = ".Dumper($h_imodules));          
          # debug("_getTasks: h_tags     = ".Dumper($h_tags));

          # ---------------------------------------------------------------
          # Réorganisation des Modules et des Paramètres de Modules [NON INTERACTIFS]
          my $mod     = [];
          my $h_empty = {};
          foreach my $rank (sort triCroissant (keys %$h_modules)) {
            if (exists($h_tags->{$rank})) {
              push (@$mod, { $h_modules->{$rank}->{name} => $h_tags->{$rank} } );
            } else {
              $h_empty = {};
              push (@$mod, { $h_modules->{$rank}->{name} => $h_empty } );
            }
          }
          $self->{_TASKS}->{$name}->{modules} = $mod;
          # Réorganisation des Modules et des Paramètres de Modules [INTERACTIFS]
          $mod     = [];
          $h_empty = {};
          foreach my $rank (sort triCroissant (keys %$h_imodules)) {
            if (exists($h_tags->{$rank})) {
              push (@$mod, { $h_imodules->{$rank}->{name} => $h_tags->{$rank} } );
            } else {
              $h_empty = {};
              push (@$mod, { $h_imodules->{$rank}->{name} => $h_empty } );
            }
          }
          $self->{_TASKS}->{$name}->{imodules} = $mod;
          # ---------------------------------------------------------------

        }
     # }

    #}

  }
  return 1;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Convertit tous les noeuds Sources dans une HashRef
sub _getSources {
  my ($self,$name,$product) = @_;

  my $dbh     = $cnxMgr->getConnectionByName('mid');
  my $request="SELECT S.MODULE
               FROM MO_CFG_TASK T, MO_CFG_SOURCE S WHERE S.ID= T.ID_SOURCE AND UPPER(T.NAME)=UPPER(?) AND UPPER(T.PRODUCT)=UPPER(?)";
  my $source = $dbh->saarBind($request,[$name,$product]);

#notice("SOURCE:".Dumper($source));

  if ((scalar @$source == 0)) {
    error("No match in MO_CFG_TASK for:".$self->{IN}." (_getSources)");
    return 0;
  }

  #my @sources = $self->{_PARSEDFILE}->getElementsByTagName('Sources');

  #foreach (@sources) {

    #my @source = $_->getElementsByTagName('Source');

    SRC: foreach my $sourceNode (@$source) {

      my $name    = undef;
      my $type    = undef;
      my @modules = ();

      $name    = $sourceNode->[0];
      $type    = "module";
      @modules = $sourceNode->[0];

      if (!$name || !$type) {
        error("Missing parameter 'name' for Source definition.")             if (!$name);
        error("Missing parameter 'type' for Source definition '".$name."'.") if (!$type && $name);
        next SRC;
      } else {
        if (exists($self->{_SOURCES}->{$name})) {
          error("This HashKey '".$name."' already exists under _SOURCES.");
          next SRC;
        } else {

          if ($type !~ /module|queue/) {
            error("Type of Source '".$name."' can only be 'module' or 'queue'.");
            next SRC;
          }

          if (($type =~ /module/) && (scalar(@modules) == 0)) {
            error("It should be at least one Module defined in Source '".$name."'.");
            next SRC;
          } elsif (($type =~ /module/) && (scalar(@modules) > 0)) {

            my $h_modules = {};
						my $mod       = [];

            MOD: foreach my $moduleNode (@modules) {

              my $modName = undef;
              
              $h_modules = {};

							$modName = $moduleNode;

							if (!$modName) {
								error("Missing parameter 'name' for Module in Source '".$name."'.");
								next MOD;
							} else {

                $h_modules->{$modName} = {};

                # Récupération des Tags supplémentaires sous Source / Module
                #my @childNodes = $moduleNode->childNodes();
                #CHILD: foreach my $childNode (@childNodes) {
                #  my $nodeType = $childNode->nodeType();
                #  if ($nodeType == 1) { # Le nodeType est un "Element"
                #    my $tagName = $childNode->tagName();
                #    next CHILD if ($tagName =~ /name/);
                #    # $self->{_SOURCES}->{$name}->{$tagName} = $childNode->find($tagName)->to_literal->value();
                #    $h_modules->{$modName}->{$tagName} = $moduleNode->find($tagName)->to_literal->value();
                #  }
                #}

                push (@$mod, $h_modules);

              }
							
              # debug("_getSources: h_modules = ".Dumper($h_modules));

            } # MOD: foreach my $moduleNode (@modules)

            if (scalar(@$mod) > 0) { 
              $self->{_SOURCES}->{$name}->{type}    = $type;
              $self->{_SOURCES}->{$name}->{modules} = $mod;
            } else {
              error("It should be at least one valid Module defined in Source '".$name."'.");
              next SRC;
            }

          } elsif ($type =~ /queue/) {
            # TODO Si le type est queue ! 
          }
        }
      }
   # }
  }

  return 1;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Convertit tous les noeuds Processes dans une HashRef ~ TAS treatment.
sub _getProcesses {
  my ($self) = @_;

  if (!defined($self->{_PARSEDFILE})) {
    error("configFile hasn't been parsed.");
    return 0;
  }

  my @processes = $self->{_PARSEDFILE}->getElementsByTagName('Processes');

  foreach (@processes) {

    my @process = $_->getElementsByTagName('Process');

    SRC: foreach my $processNode (@process) {

      my $name    = undef;
      my $type    = undef;
      my $task    = undef;
      my @modules = ();
      
      $name    = $processNode->find('name')->to_literal->value();
      $type    = $processNode->find('type')->to_literal->value();
      $task    = $processNode->find('task')->to_literal->value();
      @modules = $processNode->getElementsByTagName('module') if ($type =~ /module/);

      if (!$name || !$type || !$task) {
        error("Missing parameter for Process definition.");
        error("Missing parameter 'name' for Process definition.")             if (!$name);
        error("Missing parameter 'type' for Process definition '".$name."'.") if ($name && !$task);
        error("Missing parameter 'task' for Process definition '".$name."'.") if ($name && !$task);
        next SRC;
      } else {
        my $key = $name.'|'.$task;
        if (exists($self->{_PROCESSES}->{$key})) {
          error("This HashKey '".$key."' already exists under _PROCESSES.");
          next SRC;
        } else {

          if ($type !~ /module/) {
            error("Type of Process '".$name."' can only be 'module'.");
            next SRC;
          }

          if (($type =~ /module/) && (scalar(@modules) == 0)) {
            error("It should be at least one Module defined in Process '".$key."'.");
            next SRC;
          } elsif (($type =~ /module/) && (scalar(@modules) > 0)) {

            my $h_modules = {};
						my $mod       = [];

            MOD: foreach my $moduleNode (@modules) {

              my $modName = undef;
              
              $h_modules = {};

							$modName = $moduleNode->find('name')->to_literal->value();

							if (!$modName) {
								error("Missing parameter 'name' for Module in Process '".$key."'.");
								next MOD;
							} else {

                $h_modules->{$modName} = {};

                # Récupération des Tags supplémentaires sous Source / Module
                my @childNodes = $moduleNode->childNodes();
                CHILD: foreach my $childNode (@childNodes) {
                  my $nodeType = $childNode->nodeType();
                  if ($nodeType == 1) { # Le nodeType est un "Element"
                    my $tagName = $childNode->tagName();
                    next CHILD if ($tagName =~ /name/);
                    # $self->{_SOURCES}->{$name}->{$tagName} = $childNode->find($tagName)->to_literal->value();
                    $h_modules->{$modName}->{$tagName} = $moduleNode->find($tagName)->to_literal->value();
                  }
                }

                push (@$mod, $h_modules);

              }
							
              # debug("_getSources: h_modules = ".Dumper($h_modules));

            } # MOD: foreach my $moduleNode (@modules)

            if (scalar(@$mod) > 0) { 
              $self->{_PROCESSES}->{$key}->{type}    = $type;
              $self->{_PROCESSES}->{$key}->{modules} = $mod;
            } else {
              error("It should be at least one valid Module defined in Process '".$key."'.");
              next SRC;
            }

          }
        }
      }
    }
  }
  
  return 1;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Fonction vérifiant la validité du fichier de Config XML
# @ La source d'une Task doit être définié dans _SOURCES
# @ La source Amadeus doit être définie dans _CONNECTIONS
# Retourne 1 si valide, 0 sinon.
sub _checkValidity {
  my ($self) = @_;

  my $connections = $self->connections();
  my $tasks       = $self->tasks();
  my $sources     = $self->sources();

  if (scalar(keys %$tasks) == 0) {
    error("No Valid Tasks defined in configFile.");
    return 0;
  } else {
		foreach my $task (keys %$tasks) {
      my $source  = $tasks->{$task}->{source};
      my $amadeus = $tasks->{$task}->{amadeus};
      if (!exists($sources->{$source})) {
				error("Source '".$source."' defined in Task '".$task."' doesn't exist in _SOURCES.");
        return 0;
      }
      if (!exists($connections->{Amadeus}->{$amadeus})) {
				error("Amadeus '".$amadeus."' defined in Task '".$task."' doesn't exist in _CONNECTIONS.");
        return 0;
      }
		}
  }

  return 1;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Fonctions de tri Numérique
sub triDecroissant { $b <=> $a } 
sub triCroissant   { $a <=> $b }
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Convertit tous les noeuds Connections dans une HashRef
sub _getConnections_to_remove {
  my ($self) = @_;

  if (!defined($self->{_PARSEDFILE})) {
    error("configFile hasn't been parsed.");
    return 0;
  }


  my @connections = $self->{_PARSEDFILE}->getElementsByTagName('Connections');
  my @connectionsDDB = $self->{_PARSEDFILEDDB}->getElementsByTagName('Connections');
  
  CNX: foreach my $connectionNode (@connections) {

	  my @oracle    = undef;
    my @sqlserver = undef;
    my @amadeus   = undef;

    @sqlserver = $connectionNode->findnodes('SQLServer');
    @amadeus   = $connectionNode->findnodes('Amadeus');

    SQL: foreach (@sqlserver) {
      my $dbname      = $_->find('dbname')->to_literal->value();
      my $database    = $_->find('database')->to_literal->value();
      my $login       = $_->find('login')->to_literal->value();
      my $password    = $_->find('password')->to_literal->value();
      my $autoconnect = $_->find('autoconnect')->to_literal->value();

      $autoconnect = 0 unless ($autoconnect);

      if (!$dbname || !$database || !$login || !$password) {
        error("Missing parameter for SQLServer connection.");
        next SQL;
      } else {
        if (exists($self->{_CONNECTIONS}->{SQLServer}->{$dbname})) {
          error("This HashKey '".$dbname."' already exists under _CONNECTIONS::SQLServer.");
          next SQL;
        } else {
          $self->{_CONNECTIONS}->{SQLServer}->{$dbname}->{database}    = $database;
          $self->{_CONNECTIONS}->{SQLServer}->{$dbname}->{login}       = $login;
          $self->{_CONNECTIONS}->{SQLServer}->{$dbname}->{password}    = $password;
          $self->{_CONNECTIONS}->{SQLServer}->{$dbname}->{autoconnect} = $autoconnect;
          $self->{_CONNECTIONS}->{SQLServer}->{$dbname}->{type}        = 'SQLServer';
        }
      }
    }

    AMD: foreach (@amadeus)   {
      my $name        = $_->find('name')->to_literal->value();
      my $signin      = $_->find('signin')->to_literal->value();
      my $modifsig    = $_->find('modifsig')->to_literal->value();
      my $tcp         = $_->find('tcp')->to_literal->value();
      my $port        = $_->find('port')->to_literal->value();
      my $corpoid     = $_->find('corpoid')->to_literal->value();
      my $login       = $_->find('login')->to_literal->value();
      my $password    = $_->find('password')->to_literal->value();
      my $officeid    = $_->find('officeid')->to_literal->value();
      my $language    = $_->find('language')->to_literal->value();
      my $autoconnect = $_->find('autoconnect')->to_literal->value();

      $autoconnect = 0 unless ($autoconnect);

      if (!$name    || !$signin || !$modifsig || !$tcp      || !$port ||
          !$corpoid || !$login  || !$password || !$officeid || !$language) {
        error("Missing parameter for Amadeus connection.");
        next AMD;
      } else {
        if (exists($self->{_CONNECTIONS}->{Amadeus}->{$name})) {
          error("This HashKey '".$name."' already exists under _CONNECTIONS::Amadeus.");
          next AMD;
        } else {
          $self->{_CONNECTIONS}->{Amadeus}->{$name}->{signin}      = $signin;
          $self->{_CONNECTIONS}->{Amadeus}->{$name}->{modifsig}    = $modifsig;
          $self->{_CONNECTIONS}->{Amadeus}->{$name}->{tcp}         = $tcp;
          $self->{_CONNECTIONS}->{Amadeus}->{$name}->{port}        = $port;
          $self->{_CONNECTIONS}->{Amadeus}->{$name}->{corpoid}     = $corpoid;
          $self->{_CONNECTIONS}->{Amadeus}->{$name}->{login}       = $login;
          $self->{_CONNECTIONS}->{Amadeus}->{$name}->{password}    = $password;
          $self->{_CONNECTIONS}->{Amadeus}->{$name}->{officeid}    = $officeid;
          $self->{_CONNECTIONS}->{Amadeus}->{$name}->{language}    = $language;
          $self->{_CONNECTIONS}->{Amadeus}->{$name}->{autoconnect} = $autoconnect;
          $self->{_CONNECTIONS}->{Amadeus}->{$name}->{type}        = 'Amadeus';
        }
      }
    }

  } # Fin CNX: foreach my $connectionNode (@connections)

  CNX: foreach my $connectionNode (@connectionsDDB) {

	  my @oracle    = undef;
    my @sqlserver = undef;
    my @amadeus   = undef;

    @sqlserver = $connectionNode->findnodes('SQLServer');
    @amadeus   = $connectionNode->findnodes('Amadeus');

    SQL: foreach (@sqlserver) {
      my $dbname      = $_->find('dbname')->to_literal->value();
      my $database    = $_->find('database')->to_literal->value();
      my $login       = $_->find('login')->to_literal->value();
      my $password    = $_->find('password')->to_literal->value();
      my $autoconnect = $_->find('autoconnect')->to_literal->value();

      $autoconnect = 0 unless ($autoconnect);

      if (!$dbname || !$database || !$login || !$password) {
        error("Missing parameter for SQLServer connection.");
        next SQL;
      } else {
        if (exists($self->{_CONNECTIONS}->{SQLServer}->{$dbname})) {
          error("This HashKey '".$dbname."' already exists under _CONNECTIONS::SQLServer.");
          next SQL;
        } else {
          $self->{_CONNECTIONS}->{SQLServer}->{$dbname}->{database}    = $database;
          $self->{_CONNECTIONS}->{SQLServer}->{$dbname}->{login}       = $login;
          $self->{_CONNECTIONS}->{SQLServer}->{$dbname}->{password}    = $password;
          $self->{_CONNECTIONS}->{SQLServer}->{$dbname}->{autoconnect} = $autoconnect;
          $self->{_CONNECTIONS}->{SQLServer}->{$dbname}->{type}        = 'SQLServer';
        }
      }
    }

    AMD: foreach (@amadeus)   {
      my $name        = $_->find('name')->to_literal->value();
      my $signin      = $_->find('signin')->to_literal->value();
      my $modifsig    = $_->find('modifsig')->to_literal->value();
      my $tcp         = $_->find('tcp')->to_literal->value();
      my $port        = $_->find('port')->to_literal->value();
      my $corpoid     = $_->find('corpoid')->to_literal->value();
      my $login       = $_->find('login')->to_literal->value();
      my $password    = $_->find('password')->to_literal->value();
      my $officeid    = $_->find('officeid')->to_literal->value();
      my $language    = $_->find('language')->to_literal->value();
      my $autoconnect = $_->find('autoconnect')->to_literal->value();

      $autoconnect = 0 unless ($autoconnect);

      if (!$name    || !$signin || !$modifsig || !$tcp      || !$port ||
          !$corpoid || !$login  || !$password || !$officeid || !$language) {
        error("Missing parameter for Amadeus connection.");
        next AMD;
      } else {
        if (exists($self->{_CONNECTIONS}->{Amadeus}->{$name})) {
          error("This HashKey '".$name."' already exists under _CONNECTIONS::Amadeus.");
          next AMD;
        } else {
          $self->{_CONNECTIONS}->{Amadeus}->{$name}->{signin}      = $signin;
          $self->{_CONNECTIONS}->{Amadeus}->{$name}->{modifsig}    = $modifsig;
          $self->{_CONNECTIONS}->{Amadeus}->{$name}->{tcp}         = $tcp;
          $self->{_CONNECTIONS}->{Amadeus}->{$name}->{port}        = $port;
          $self->{_CONNECTIONS}->{Amadeus}->{$name}->{corpoid}     = $corpoid;
          $self->{_CONNECTIONS}->{Amadeus}->{$name}->{login}       = $login;
          $self->{_CONNECTIONS}->{Amadeus}->{$name}->{password}    = $password;
          $self->{_CONNECTIONS}->{Amadeus}->{$name}->{officeid}    = $officeid;
          $self->{_CONNECTIONS}->{Amadeus}->{$name}->{language}    = $language;
          $self->{_CONNECTIONS}->{Amadeus}->{$name}->{autoconnect} = $autoconnect;
          $self->{_CONNECTIONS}->{Amadeus}->{$name}->{type}        = 'Amadeus';
        }
      }
    }

  } # Fin CNX: foreach my $connectionNode (@connections)
  
  # notice('getConnections: '.Dumper($self->{_CONNECTIONS}));

  # ---------------------------------------------------------------
  # Initialisation des connexions aux bases de données
  Expedia::Databases::ConnectionsManager->new($self->{_CONNECTIONS});
  

  return 1;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Convertit tous les noeuds Tasks dans une HashRef
sub _getTasks_to_remove {
  my ($self) = @_;

  if (!defined($self->{_PARSEDFILE})) {
    error("configFile hasn't been parsed.");
    return 0;
  }

  my @tasks = $self->{_PARSEDFILE}->getElementsByTagName('Tasks');

  foreach (@tasks) {

    my @task = $_->getElementsByTagName('Task');

    TSK: foreach my $taskNode (@task) {

      my $name    = undef;
      my $source  = undef;
      my $amadeus = undef;
      my $logFile = undef;
      my $process = undef;
      my @modules = ();
    
      $name    = $taskNode->find('name')->to_literal->value();
      $source  = $taskNode->find('source')->to_literal->value();
      $amadeus = $taskNode->find('amadeus')->to_literal->value();
      $logFile = $taskNode->find('logFile')->to_literal->value();
      $process = $taskNode->find('process')->to_literal->value();
      @modules = $taskNode->getElementsByTagName('module');

      if (!$name || !$source || !$amadeus || !$logFile || ((scalar(@modules) == 0) && (!$process))) {    
        error("Missing parameter for Task definition.");
        error("It should be at least one Module or Process defined in Task $name.") if ($name && ((scalar(@modules) == 0) && (!$process)));
        error("It should be at least one Source defined in Task $name.")            if ($name &&  (scalar(@sources) == 0));          
        next TSK;
      } else {
        if (exists($self->{_TASKS}->{$name})) {
          error("This HashKey '".$name."' already exists under _TASKS.");
          next TSK;
        } else {
          $self->{_TASKS}->{$name}->{source}  = $source;
          $self->{_TASKS}->{$name}->{amadeus} = $amadeus;

          # Récupération des Tags supplémentaires sous Task
          my @childNodes = $taskNode->childNodes();
          CHILD: foreach my $childNode (@childNodes) {
            my $nodeType = $childNode->nodeType();
            if ($nodeType == 1) { # Le nodeType est un "Element"
              my $tagName = $childNode->tagName();
              next CHILD if ($tagName =~ /name|source|amadeus|modules|process/);
              $self->{_TASKS}->{$name}->{$tagName} = $taskNode->find($tagName)->to_literal->value();
            }
          }

          # ---------------------------------------------------------------
          # Récupération des Modules et des Tags supplémentaires de Modules
          my $h_modules  = {};
          my $h_imodules = {}; # Modules "interactifs" utilisé pour "BTC-AIR"
          my $h_tags     = {};

          MOD: foreach my $moduleNode (@modules) {

            my $modName = undef;
            my $modRank = undef;
            my $modIntr = undef; # Modules "interactifs" utilisé pour "BTC-AIR"

						$modName = $moduleNode->find('name')->to_literal->value();
						$modRank = $moduleNode->find('rank')->to_literal->value();
						$modIntr = $moduleNode->find('interactive')->to_literal->value();

            if (!$modName || !$modRank) {
							error("Missing parameter for Module in Task $name.");
              next MOD;
            } else {
              
              if ((!$modIntr) || (($modIntr) && ($modIntr ne 'true'))) {
              
                if (exists($h_modules->{$modRank})) {
                  error("Rank '".$modRank."' already exists for Module $modName in Task $name.");
                  next MOD;
                } else {
                  $h_modules->{$modRank}->{name} = $modName;
            
                  # Récupération des Tags supplémentaires sous Module
                  my @childNodes = $moduleNode->childNodes();
                  CHILD: foreach my $childNode (@childNodes) {
                    my $nodeType = $childNode->nodeType();
                    if ($nodeType == 1) { # Le nodeType est un "Element"
                      my $tagName = $childNode->tagName();
                      next CHILD if ($tagName =~ /name|rank/);
                      $h_tags->{$modRank}->{$tagName} = $moduleNode->find($tagName)->to_literal->value();
                    }
                  }
                }
              }
              elsif (($modIntr) && ($modIntr eq 'true')) {
                if (exists($h_imodules->{$modRank})) {
                  error("Rank '".$modRank."' already exists for iModule $modName in Task $name.");
                  next MOD;
                } else {
                  $h_imodules->{$modRank}->{name} = $modName;
            
                  # Récupération des Tags supplémentaires sous Module
                  my @childNodes = $moduleNode->childNodes();
                  CHILD: foreach my $childNode (@childNodes) {
                    my $nodeType = $childNode->nodeType();
                    if ($nodeType == 1) { # Le nodeType est un "Element"
                      my $tagName = $childNode->tagName();
                      next CHILD if ($tagName =~ /name|rank|interactive/);
                      $h_tags->{$modRank}->{$tagName} = $moduleNode->find($tagName)->to_literal->value();
                    }
                  }
                }
              }

            }

          }
          # ---------------------------------------------------------------

          # debug("_getTasks: h_modules  = ".Dumper($h_modules));
          # debug("_getTasks: h_imodules = ".Dumper($h_imodules));          
          # debug("_getTasks: h_tags     = ".Dumper($h_tags));

          # ---------------------------------------------------------------
          # Réorganisation des Modules et des Paramètres de Modules [NON INTERACTIFS]
          my $mod     = [];
          my $h_empty = {};
          foreach my $rank (sort triCroissant (keys %$h_modules)) {
            if (exists($h_tags->{$rank})) {
              push (@$mod, { $h_modules->{$rank}->{name} => $h_tags->{$rank} } );
            } else {
              $h_empty = {};
              push (@$mod, { $h_modules->{$rank}->{name} => $h_empty } );
            }
          }
          $self->{_TASKS}->{$name}->{modules} = $mod;
          # Réorganisation des Modules et des Paramètres de Modules [INTERACTIFS]
          $mod     = [];
          $h_empty = {};
          foreach my $rank (sort triCroissant (keys %$h_imodules)) {
            if (exists($h_tags->{$rank})) {
              push (@$mod, { $h_imodules->{$rank}->{name} => $h_tags->{$rank} } );
            } else {
              $h_empty = {};
              push (@$mod, { $h_imodules->{$rank}->{name} => $h_empty } );
            }
          }
          $self->{_TASKS}->{$name}->{imodules} = $mod;
          # ---------------------------------------------------------------

        }
      }

    }

  }

  return 1;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Convertit tous les noeuds Sources dans une HashRef
sub _getSources_to_remove {
  my ($self) = @_;

  if (!defined($self->{_PARSEDFILE})) {
    error("configFile hasn't been parsed.");
    return 0;
  }

  my @sources = $self->{_PARSEDFILE}->getElementsByTagName('Sources');

  foreach (@sources) {

    my @source = $_->getElementsByTagName('Source');

    SRC: foreach my $sourceNode (@source) {

      my $name    = undef;
      my $type    = undef;
      my @modules = ();

      $name    = $sourceNode->find('name')->to_literal->value();
      $type    = $sourceNode->find('type')->to_literal->value();
      @modules = $sourceNode->getElementsByTagName('module') if ($type =~ /module/);

      if (!$name || !$type) {
        error("Missing parameter 'name' for Source definition.")             if (!$name);
        error("Missing parameter 'type' for Source definition '".$name."'.") if (!$type && $name);
        next SRC;
      } else {
        if (exists($self->{_SOURCES}->{$name})) {
          error("This HashKey '".$name."' already exists under _SOURCES.");
          next SRC;
        } else {

          if ($type !~ /module|queue/) {
            error("Type of Source '".$name."' can only be 'module' or 'queue'.");
            next SRC;
          }

          if (($type =~ /module/) && (scalar(@modules) == 0)) {
            error("It should be at least one Module defined in Source '".$name."'.");
            next SRC;
          } elsif (($type =~ /module/) && (scalar(@modules) > 0)) {

            my $h_modules = {};
						my $mod       = [];

            MOD: foreach my $moduleNode (@modules) {

              my $modName = undef;
              
              $h_modules = {};

							$modName = $moduleNode->find('name')->to_literal->value();

							if (!$modName) {
								error("Missing parameter 'name' for Module in Source '".$name."'.");
								next MOD;
							} else {

                $h_modules->{$modName} = {};

                # Récupération des Tags supplémentaires sous Source / Module
                my @childNodes = $moduleNode->childNodes();
                CHILD: foreach my $childNode (@childNodes) {
                  my $nodeType = $childNode->nodeType();
                  if ($nodeType == 1) { # Le nodeType est un "Element"
                    my $tagName = $childNode->tagName();
                    next CHILD if ($tagName =~ /name/);
                    # $self->{_SOURCES}->{$name}->{$tagName} = $childNode->find($tagName)->to_literal->value();
                    $h_modules->{$modName}->{$tagName} = $moduleNode->find($tagName)->to_literal->value();
                  }
                }

                push (@$mod, $h_modules);

              }
							
              # debug("_getSources: h_modules = ".Dumper($h_modules));

            } # MOD: foreach my $moduleNode (@modules)

            if (scalar(@$mod) > 0) { 
              $self->{_SOURCES}->{$name}->{type}    = $type;
              $self->{_SOURCES}->{$name}->{modules} = $mod;
            } else {
              error("It should be at least one valid Module defined in Source '".$name."'.");
              next SRC;
            }

          } elsif ($type =~ /queue/) {
            # TODO Si le type est queue ! 
          }
        }
      }
    }
  }

  return 1;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Convertit tous les noeuds Processes dans une HashRef ~ TAS treatment.
sub _getProcesses_to_remove {
  my ($self) = @_;

  if (!defined($self->{_PARSEDFILE})) {
    error("configFile hasn't been parsed.");
    return 0;
  }

  my @processes = $self->{_PARSEDFILE}->getElementsByTagName('Processes');

  foreach (@processes) {

    my @process = $_->getElementsByTagName('Process');

    SRC: foreach my $processNode (@process) {

      my $name    = undef;
      my $type    = undef;
      my $task    = undef;
      my @modules = ();
      
      $name    = $processNode->find('name')->to_literal->value();
      $type    = $processNode->find('type')->to_literal->value();
      $task    = $processNode->find('task')->to_literal->value();
      @modules = $processNode->getElementsByTagName('module') if ($type =~ /module/);

      if (!$name || !$type || !$task) {
        error("Missing parameter for Process definition.");
        error("Missing parameter 'name' for Process definition.")             if (!$name);
        error("Missing parameter 'type' for Process definition '".$name."'.") if ($name && !$task);
        error("Missing parameter 'task' for Process definition '".$name."'.") if ($name && !$task);
        next SRC;
      } else {
        my $key = $name.'|'.$task;
        if (exists($self->{_PROCESSES}->{$key})) {
          error("This HashKey '".$key."' already exists under _PROCESSES.");
          next SRC;
        } else {

          if ($type !~ /module/) {
            error("Type of Process '".$name."' can only be 'module'.");
            next SRC;
          }

          if (($type =~ /module/) && (scalar(@modules) == 0)) {
            error("It should be at least one Module defined in Process '".$key."'.");
            next SRC;
          } elsif (($type =~ /module/) && (scalar(@modules) > 0)) {

            my $h_modules = {};
						my $mod       = [];

            MOD: foreach my $moduleNode (@modules) {

              my $modName = undef;
              
              $h_modules = {};

							$modName = $moduleNode->find('name')->to_literal->value();

							if (!$modName) {
								error("Missing parameter 'name' for Module in Process '".$key."'.");
								next MOD;
							} else {

                $h_modules->{$modName} = {};

                # Récupération des Tags supplémentaires sous Source / Module
                my @childNodes = $moduleNode->childNodes();
                CHILD: foreach my $childNode (@childNodes) {
                  my $nodeType = $childNode->nodeType();
                  if ($nodeType == 1) { # Le nodeType est un "Element"
                    my $tagName = $childNode->tagName();
                    next CHILD if ($tagName =~ /name/);
                    # $self->{_SOURCES}->{$name}->{$tagName} = $childNode->find($tagName)->to_literal->value();
                    $h_modules->{$modName}->{$tagName} = $moduleNode->find($tagName)->to_literal->value();
                  }
                }

                push (@$mod, $h_modules);

              }
							
              # debug("_getSources: h_modules = ".Dumper($h_modules));

            } # MOD: foreach my $moduleNode (@modules)

            if (scalar(@$mod) > 0) { 
              $self->{_PROCESSES}->{$key}->{type}    = $type;
              $self->{_PROCESSES}->{$key}->{modules} = $mod;
            } else {
              error("It should be at least one valid Module defined in Process '".$key."'.");
              next SRC;
            }

          }
        }
      }
    }
  }
  
  return 1;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

1;
