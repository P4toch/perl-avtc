package Expedia::Workflow::ProcessManager;
#-----------------------------------------------------------------
# Package Expedia::Workflow::ProcessManager
#
# $Id: ProcessManager.pm 586 2010-04-07 09:26:34Z pbressan $
#
# (c) 2002-2008 Expedia.                   www.expediacorporate.fr
#-----------------------------------------------------------------

use POSIX qw(strftime);
use File::Slurp;
use Data::Dumper;
use Proc::ProcessTable;

use Expedia::Tools::Logger qw(&debug &notice &warning &error);
use Expedia::Tools::GlobalVars qw($h_maxProcDuration);

my $fileName = undef;
my $procMngr = undef;

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# CONSTRUCTEUR
sub new {
  my ($class, $processName) = @_;
  
  if ((!$processName) || ($processName =~ /^\s*$/)) {
    error("A valid 'processName' and 'userName' are needed. Aborting.");
    return 0;
  }

	$self = {};
	bless ($self, $class);
	$procMngr = $self;
	
	$self->{_PID}          = "$$";
	$self->{_PIDINFILE}    = 0;
  $self->{_PROCESSNAME}  = $processName;
  $self->{_USERNAME}     = `whoami`; chomp($self->{_USERNAME});
  
  #use to get the right ProcDuration with the processname (ex: tracking-FR in parameters, as to be catch with tracking- ) 
    foreach my $key (reverse sort keys %$h_maxProcDuration) {
     if ( $processName =~ /^$key/) { 
       $h_maxProcDuration->{$processName} = $h_maxProcDuration->{$key}; 
       debug("maxProcDuration:".$h_maxProcDuration->{$key});
       last ; 
     };
  }

  $self->{_MAXDURATION}  = $h_maxProcDuration->{$processName};
  $self->{_ISRUNNING}    = 0;
  $self->{_ISRUNNING}    = $self->_isProcessRunning();
  
  # Utilisé pour le monitoring dans Nagios
  # $self->{_XMLPROCESSED} = 0;
  # $self->{_DAYNOW}       = strftime("%Y%m%d", localtime());
  # $self->{_NAGIOSFNAME}  = '/tmp/btc-'.$self->{_DAYNOW}.'.nagios';
  
  if (!defined $self->{_MAXDURATION}) {
    notice('No maximum duration has been defined for this Task. Please Check !')
      unless($processName =~ /^(btc-train|meetings-train|btc-rail|meetings-rail)/);
    $self->{_MAXDURATION} = 3600;
  }
  
  # µµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµ
  # Create an archive if it's needed / Delete previous !
  # my $nagiosFileName = $self->{_NAGIOSFNAME};
  # if (!-e $nagiosFileName) {
  #   unlink($_) foreach glob('/tmp/*.nagios');
  #   `touch $nagiosFileName`;
  # }
  # µµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµµ
  
  if ($self->isRunning == 0) {
    $fileName = '/tmp/'.$processName.'.pid';
    debug("Ecriture du fichier pid : '$fileName'");
    write_file($fileName, $self->{_PID});
  } else {
    notice('One process is already running. Aborting [...]');
    notice('   PID = '.$self->{_PIDINFILE});
  }

  return $self;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
sub END {
  if (defined $fileName) {
    debug("Suppression du fichier PID : '$fileName'");
    unlink($fileName);
  }
  # $procMngr->nagiosReport if (defined $procMngr);
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Méthode publique pour savoir si le process tourne déjà ou non
sub isRunning {
  my ($self, $isRunning) = @_;
  
  $self->{_ISRUNNING} = $isRunning if (defined $isRunning);
  return $self->{_ISRUNNING};
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Méthode publique pour retourner ou setter le nombre d'items traités
#sub xmlProcessed {
#  my ($self, $xmlProcessed) = @_;
#
#  $self->{_XMLPROCESSED} = $xmlProcessed if (defined $xmlProcessed);
#  return $self->{_XMLPROCESSED};
#}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Ecriture d'un court descriptif du nombre d'éléments traités pour
#   monitoring dans NAGIOS.
#sub nagiosReport {
#  my $self = shift;
#  
#  return 1
#    unless ((defined $fileName) ||
#            ($self->{_PROCESSNAME} =~ /^(btc-train|meetings-train|btc-rail|meetings-rail)/));
#  
#  my $time         = '['._getTime().']';
#  my $processName  = '['.$self->{_PROCESSNAME}.']';
#  my $xmlProcessed = '['.$self->{_XMLPROCESSED}.']';
#  
#  append_file($self->{_NAGIOSFNAME}, "$time $processName $xmlProcessed\n");
#  
#  return 1;
#}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Retourne si le fichier .pid existe ou non
sub _isPidFileExists {
  my $self = shift;
  
  my $processName = $self->{_PROCESSNAME};
  
  return 1 if (-e '/tmp/'.$processName.'.pid');
  
  return 0;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Retourne le PID d'une application
sub _getPid {
  my $self = shift;
  
  my $processName = $self->{_PROCESSNAME};
  
  if (-e '/tmp/'.$processName.'.pid') {
    my $pid = read_file('/tmp/'.$processName.'.pid');
    $self->{_PIDINFILE} = $pid;
    return $pid;
  }
  
  return 0;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Retourne l'UID pour un nom d'utilisateur donné
sub _getUid {
  my $self     = shift;
  
  my $userName = $self->{_USERNAME};
  
  my $uid  = 0;
  my @list = ();
  my ($LOGIN, $PASSWORD, $UID, $GID, $QUOTA, $COMMENT, $GECOS, $HOMEDIR, $SHELL);

  setpwent();
  while (@list = getpwent())  {
    ($LOGIN, $PASSWORD, $UID, $GID, $QUOTA, $COMMENT, $GECOS, $HOMEDIR, $SHELL) = @list[0, 1, 2, 3, 4, 5, 6, 7, 8];
    next unless ($userName eq $LOGIN);
    $uid = $UID;
  }
  endpwent();

  return $uid;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Vérifie si un process est encore en train de tourner ou non
sub _isProcessRunning {
  my $self         = shift;
  
  my $processName  = $self->{_PROCESSNAME};
  my $userName     = $self->{_USERNAME};
  
  debug('processName = '.$processName);
  debug('userName    = '.$userName);
  
  my $pid = $self->_getPid();
  my $uid = $self->_getUid();
  
  debug('pid = '.$pid);
  debug('uid = '.$uid);
  
  error("No 'uid' can be found for userName '$userName'. Aborting.") if ($uid == 0);
  return 0 if ($pid == 0);
  return 1 if ($uid == 0); # On considère que le programme tourne si uid = 0
  return 0 if ($processName =~ /^(btc-train|meetings-train|btc-rail|meetings-rail)/); # Hack spécial btc-train
  
  my $t = new Proc::ProcessTable;
  
  my $time = time;
  
  foreach my $p (@{$t->table}) {
    my $pPid = $p->pid;
    my $pUid = $p->uid;

    next if (($pUid != $uid) || ($pPid !=  $pid));

    # Au dela du temps défini, on considère que le process s'est
    #  terminé anormalement et doit être tué.
    my $diff = ($time - $p->start); # En secondes
    debug('maxD = '.$self->{_MAXDURATION});
    debug('diff = '.$diff);
    if ($diff > $self->{_MAXDURATION}) {
      notice("Process is running more than '".$self->{_MAXDURATION}."' seconds. 'kill -9 $pid'.");
      kill 9, ($pid);
    } else {
      return 1;
    }
  }

  # Suppression du fichier s'il existe
  unlink('/tmp/'.$processName.'.pid') if ($pid != 0);
  return 0;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
sub _getTime {
  return strftime('%Y/%m/%d %H:%M:%S', localtime);
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

1;
