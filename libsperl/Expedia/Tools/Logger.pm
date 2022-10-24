package Expedia::Tools::Logger;
#-----------------------------------------------------------------
# Package Expedia::Tools::Logger
#
# $Id: Logger.pm 410 2008-02-11 09:20:59Z pbressan $
#
# (c) 2002-2007 Expedia.                   www.expediacorporate.fr
#-----------------------------------------------------------------

use POSIX qw(strftime);
use IO::File;
use Exporter 'import';

use Expedia::Tools::GlobalVars qw($logPath $defaultLogFile $LogMonitoringFile);

@EXPORT_OK = qw(&debug &notice &warning &error &monitore);

my $SINGLETON = new Expedia::Tools::Logger;

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# CONSTRUCTEUR
sub new {
  my ($class, $logFile) = (@_);

  $self = {};
  bless ($self, $class);

  $self->{_LOG_FILE}   = undef;

  $self->{_LOG_POOL}   = [];
  $self->{_TRACE_POOL} = [];

  $self->{_LOG_FH}     = undef; # FileHandle du fichier LOG
  $self->{_TRACE_FH}   = undef; # FileHandle du fichier TRACE

  if (defined $logFile) {
    $self->{_LOG_FILE} = $logFile;
    $self->{_LOG_FH}   		= new IO::File(">> ".$logPath.$logFile.'.LOG');
    $self->{_TRACE_FH} 		= new IO::File(">> ".$logPath.$logFile.'.TRACE');
	$self->{_MONITORING_FH} = new IO::File(">> ".$logPath.$LogMonitoringFile.'.LOG');
  }

  return $self;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# DESTRUCTEUR
sub END {
  if (defined $SINGLETON) {
    $SINGLETON->{_LOG_FH}->close()   		unless (!defined $SINGLETON->{_LOG_FH});
    $SINGLETON->{_TRACE_FH}->close() 		unless (!defined $SINGLETON->{_TRACE_FH});
	$SINGLETON->{_MONITORING_FH}->close() 	unless (!defined $SINGLETON->{_MONITORING_FH});
    # Si aucun fichier de LOG n'a été spécifié, on écrit le POOL dans $defaultLogFile
    if (!defined $SINGLETON->{_LOG_FILE}) {
			Expedia::Tools::Logger->logFile($defaultLogFile);
			my $LOG_FH   		= $SINGLETON->{_LOG_FH};
			my $TRACE_FH 		= $SINGLETON->{_TRACE_FH};
			my $MONITORING_FH 	= $SINGLETON->{_MONITORING_FH};
			if (defined $LOG_FH)   { while (my $m = shift(@{$SINGLETON->{_LOG_POOL}}))   { print $LOG_FH   $m; } }
			if (defined $TRACE_FH) { while (my $m = shift(@{$SINGLETON->{_TRACE_POOL}})) { print $TRACE_FH $m; } }
			if (defined $MONITORING_FH) { while (my $m = shift(@{$SINGLETON->{_MONITORING_FH}})) { print $MONITORING_FH $m; } }
    }
  }
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
sub logFile {
  my $self    = shift;
  my $logFile = shift;

  if ((defined $SINGLETON) && (!defined $SINGLETON->{_LOG_FILE})) {
		$SINGLETON->{_LOG_FILE} = $logFile;
		$SINGLETON->{_LOG_FH}   		= new IO::File(">> ".$logPath.$logFile.'.LOG');
		$SINGLETON->{_TRACE_FH} 		= new IO::File(">> ".$logPath.$logFile.'.TRACE');
		$SINGLETON->{_MONITORING_FH} 	= new IO::File(">> ".$logPath.$LogMonitoringFile.'.LOG');
  } elsif ((defined $SINGLETON) && (defined $SINGLETON->{_LOG_FILE})) {
		$SINGLETON->{_LOG_FH}->close()   		unless (!defined $SINGLETON->{_LOG_FH});
		$SINGLETON->{_TRACE_FH}->close() 		unless (!defined $SINGLETON->{_TRACE_FH});
		$SINGLETON->{_MONITORING_FH}->close() 	unless (!defined $SINGLETON->{_MONITORING_FH});
		
		$SINGLETON->{_LOG_FILE} = $logFile;
		
		$SINGLETON->{_LOG_FH}   		= new IO::File(">> ".$logPath.$logFile.'.LOG');
		$SINGLETON->{_TRACE_FH} 		= new IO::File(">> ".$logPath.$logFile.'.TRACE'); 
		$SINGLETON->{_MONITORING_FH} 	= new IO::File(">> ".$logPath.$LogMonitoringFile.'.LOG'); 
  } else {
    $SINGLETON = Expedia::Tools::Logger->new($logFile);
  }
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
sub debug {
  my $message = shift;
  my $llog    = '';
  
  if($Expedia::Modules::AIQ::PnrGetInfos::log_id)
  {
        $llog=$Expedia::Modules::AIQ::PnrGetInfos::log_id;
  }

  if($Expedia::Modules::EMD::PnrGetInfos::log_id)
  {
        $llog=$Expedia::Modules::EMD::PnrGetInfos::log_id;
  }
  
  if($Expedia::Workflow::TasksProcessor::log_id)
  {
        $llog=$Expedia::Workflow::TasksProcessor::log_id;
  }
  
  my $package = '';
  my ($pack, $file, $line) = caller 0;

  $message = &_cryp_fop($message);

  chop($message) if ($message && ($message =~ /\n$/));

  if ($pack eq 'main') { $package = $file; } else { ($pack, $file, $line, $sub) = caller 1; $package = $sub; }

  my $msg = &_getTime()." [\@$$] [\@$llog] [debug] [$package] $message\n";

  my $LOG_FH   = $SINGLETON->{_LOG_FH};
  my $TRACE_FH = $SINGLETON->{_TRACE_FH};

  push (@{$SINGLETON->{_TRACE_POOL}}, $msg);

  if (defined $LOG_FH)   {
    $SINGLETON->_reOpen() unless (-e $logPath.$SINGLETON->{_LOG_FILE}.'.LOG');
    while (my $m = shift(@{$SINGLETON->{_LOG_POOL}}))   { print $LOG_FH   $m; }
  }
  if (defined $TRACE_FH) {
    $SINGLETON->_reOpen() unless (-e $logPath.$SINGLETON->{_LOG_FILE}.'.TRACE');
    while (my $m = shift(@{$SINGLETON->{_TRACE_POOL}})) { print $TRACE_FH $m; }
  }
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
sub notice {
  my $message = shift;
  my $llog    = '';
  
  if($Expedia::Modules::AIQ::PnrGetInfos::log_id)
  {
        $llog=$Expedia::Modules::AIQ::PnrGetInfos::log_id;
  }

  if($Expedia::Modules::EMD::PnrGetInfos::log_id)
  {
        $llog=$Expedia::Modules::EMD::PnrGetInfos::log_id;
  }
  
  if($Expedia::Workflow::TasksProcessor::log_id)
  {
        $llog=$Expedia::Workflow::TasksProcessor::log_id;
  }
  
  my $package = '';
  my ($pack, $file, $line) = caller 0;

  $message = &_cryp_fop($message);

  chop($message) if ($message && ($message =~ /\n$/));
  
  if ($pack eq 'main') { $package = $file; } else { ($pack, $file, $line, $sub) = caller 1; $package = $sub; }
 
  my $time = &_getTime();
  my $msg1 = "$time [\@$$] [\@$llog] [notice] [$package] $message\n";
  my $msg2 = "$time [\@$$] [\@$llog] [notice] $message\n";

  my $LOG_FH   = $SINGLETON->{_LOG_FH};
  my $TRACE_FH = $SINGLETON->{_TRACE_FH};

  push (@{$SINGLETON->{_LOG_POOL}},   $msg2);
  push (@{$SINGLETON->{_TRACE_POOL}}, $msg1);

  print STDOUT $msg2;

  if (defined $LOG_FH)   {
    $SINGLETON->_reOpen() unless (-e $logPath.$SINGLETON->{_LOG_FILE}.'.LOG');
    while (my $m = shift(@{$SINGLETON->{_LOG_POOL}}))   { print $LOG_FH   $m; }
  }
  if (defined $TRACE_FH) {
    $SINGLETON->_reOpen() unless (-e $logPath.$SINGLETON->{_LOG_FILE}.'.TRACE');
    while (my $m = shift(@{$SINGLETON->{_TRACE_POOL}})) { print $TRACE_FH $m; }
  }
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
sub warning {
  my $message = shift;
  my $llog    = '';
  
  if($Expedia::Modules::AIQ::PnrGetInfos::log_id)
  {
        $llog=$Expedia::Modules::AIQ::PnrGetInfos::log_id;
  }
  
  if($Expedia::Modules::EMD::PnrGetInfos::log_id)
  {
        $llog=$Expedia::Modules::EMD::PnrGetInfos::log_id;
  }
  if($Expedia::Workflow::TasksProcessor::log_id)
  {
        $llog=$Expedia::Workflow::TasksProcessor::log_id;
  }
  
  my ($pack1, $file1, $line1, $sub1) = caller 0;
  my ($pack2, $file2, $line2, $sub2) = caller 1;

  $message = &_cryp_fop($message);

  chop($message) if ($message && ($message =~ /\n$/));

  my $time = &_getTime();
  my $msg1 = "$time [\@$$] [\@$llog] [warning] [$sub2] [line:$line1] $message\n";
  my $msg2 = "$time [\@$$] [\@$llog] [warning:backtrace] [TOREPLACE] [line:$line2] $message\n";;
  $msg2 =~ s/TOREPLACE/$file2/ if ($pack2 eq 'main');
  $msg2 =~ s/TOREPLACE/$pack2/ if ($pack2 ne 'main');

  my $LOG_FH   = $SINGLETON->{_LOG_FH};
  my $TRACE_FH = $SINGLETON->{_TRACE_FH};

  push (@{$SINGLETON->{_LOG_POOL}},   $msg1);
  push (@{$SINGLETON->{_LOG_POOL}},   $msg2);
  push (@{$SINGLETON->{_TRACE_POOL}}, $msg1);
  push (@{$SINGLETON->{_TRACE_POOL}}, $msg2);
	
  print STDOUT $msg1;
  print STDOUT $msg2;

  if (defined $LOG_FH)   {
    $SINGLETON->_reOpen() unless (-e $logPath.$SINGLETON->{_LOG_FILE}.'.LOG');
    while (my $m = shift(@{$SINGLETON->{_LOG_POOL}}))   { print $LOG_FH   $m; }
  }
  if (defined $TRACE_FH) {
    $SINGLETON->_reOpen() unless (-e $logPath.$SINGLETON->{_LOG_FILE}.'.TRACE');
    while (my $m = shift(@{$SINGLETON->{_TRACE_POOL}})) { print $TRACE_FH $m; }
  }
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
sub error {
  my $message = shift;
  my $llog    = '';
  
  if($Expedia::Modules::AIQ::PnrGetInfos::log_id)
  {
        $llog=$Expedia::Modules::AIQ::PnrGetInfos::log_id;
  }

  if($Expedia::Modules::EMD::PnrGetInfos::log_id)
  {
        $llog=$Expedia::Modules::EMD::PnrGetInfos::log_id;
  }
  
  if($Expedia::Workflow::TasksProcessor::log_id)
  {
        $llog=$Expedia::Workflow::TasksProcessor::log_id;
  }

  my ($pack1, $file1, $line1, $sub1) = caller 0;
  my ($pack2, $file2, $line2, $sub2) = caller 1;

  $message = &_cryp_fop($message);

  chop($message) if ($message && ($message =~ /\n$/));

  my $time = &_getTime();
  my $msg1 = "$time [\@$$] [\@$llog] [error] [$sub2] [line:$line1] $message\n";
  my $msg2 = "$time [\@$$] [\@$llog] [error:backtrace] [TOREPLACE] [line:$line2] $message\n";;
  $msg2 =~ s/TOREPLACE/$file2/ if ($pack2 eq 'main');
  $msg2 =~ s/TOREPLACE/$pack2/ if ($pack2 ne 'main');

  my $LOG_FH   = $SINGLETON->{_LOG_FH};
  my $TRACE_FH = $SINGLETON->{_TRACE_FH};

  push (@{$SINGLETON->{_LOG_POOL}},   $msg1);
  push (@{$SINGLETON->{_LOG_POOL}},   $msg2);
  push (@{$SINGLETON->{_TRACE_POOL}}, $msg1);
  push (@{$SINGLETON->{_TRACE_POOL}}, $msg2);
	
  print STDOUT $msg1;
  print STDOUT $msg2;

  if (defined $LOG_FH)   {
    $SINGLETON->_reOpen() unless (-e $logPath.$SINGLETON->{_LOG_FILE}.'.LOG');
    while (my $m = shift(@{$SINGLETON->{_LOG_POOL}}))   { print $LOG_FH   $m; }
  }
  if (defined $TRACE_FH) {
    $SINGLETON->_reOpen() unless (-e $logPath.$SINGLETON->{_LOG_FILE}.'.TRACE');
    while (my $m = shift(@{$SINGLETON->{_TRACE_POOL}})) { print $TRACE_FH $m; }
  }
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
sub _getTime {
  return strftime('[%Y/%m/%d %H:%M:%S]', localtime);
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

sub _getTime_monitore {
  return strftime('%Y-%m-%dT%H:%M:%S', localtime);
}

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Dans le cas d'une rotation de fichier logRotate,
# le FILEHANDLE reste toujours ouvert mais le fichier n'est pas recréé. 
sub _reOpen {
  my $self = shift;

	if (defined $SINGLETON && defined $SINGLETON->{_LOG_FILE}) {
		$SINGLETON->{_LOG_FH}   		= new IO::File(">> ".$logPath.$SINGLETON->{_LOG_FILE}.'.LOG');
		$SINGLETON->{_TRACE_FH} 		= new IO::File(">> ".$logPath.$SINGLETON->{_LOG_FILE}.'.TRACE');
		$SINGLETON->{_MONITORING_FH} 	= new IO::File(">> ".$logPath.$LogMonitoringFile.'.LOG');
  }
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

sub _cryp_fop {
        my $reply = shift;
        my @lines = split("\n", $reply);
        # _____________________________________________________________
    # Norme PCI DSS - Masquage partiel du numero de carte de crédit
    #  Générique à TC-AIR, BTC-TRAIN (MEETINGS) et SYNCRO-PROFILS
      my @tmpLines = @lines;
      foreach my $line (@tmpLines) {
        if (($line =~ /^(.*?)(FP\s+CC\w{2},?)(\d+)\/(\d+)?(.*)$/) ||
            ($line =~ /^(.*?)(FP-CC\w{2},?)(\d+)\/(\d+)?(.*)$/) ||
			($line =~ /^(.*?)(FP\s+PAX\s+CC\w{2},?)(\d+)\/(\d+)?(.*)$/) ||
            ($line =~ /^(.*?)(FP\s+O\/\w+\+\/CC\w{2},?)(\d+)\/(\d+)?(.*)$/) ||
            ($line =~ /^(.*?)(RC\s+CC\s+HOTEL\s+ONLY\s+\w{2})(\d+)\/(\d+)?(.*)?$/) ||
            ($line =~ /^(.*?)(RC\s+PMEAN\s+FP\s+CC\w{2})(\d+)\/(\d+)?(.*)?$/)) {
          my $start  = $1;
          my $begin  = $2;
          my $nums   = $3;
          my $exp    = $4 || '';
          my $end    = $5 || '';
          my $length = length($nums);
          my $substr = substr($nums, $length -4, 4);
          my $tmp    = '*'x($length -4);
          $line = $start.$begin.$tmp.$substr.'/'.$exp.$end;
        }
      }
        my $test = '';
       foreach (@tmpLines)
        { $test.= $_."\n";}

      return $test;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
sub monitore {

  my $job_name = shift;
  my $task_name= shift;
  my $type_log = shift;
  my $country  = shift;
  my $product  = shift;
  my $pnr      = shift;
  my $reject   = shift;
  my $message  = shift;

  if($type_log =~ /INFO/) { $type_log='INFO ';}
  else{ $type_log='ERROR';}
  
  $message = &_cryp_fop($message);

  chop($message) if ($message && ($message =~ /\n$/));

  my $time = &_getTime_monitore();
  my $host = `hostname`;
  $host =~ s/\n//g;
  $pnr       = "pnr=".$pnr unless ! defined $pnr || $pnr eq "";
  $task_name = "task_name=".$task_name unless ! defined $task_name || $task_name eq "";
  $reject    = "reject='".$reject."'" unless ! defined $reject|| $reject eq "";
  $product   = "product=".$product unless ! defined $product|| $product eq "";

  my $msg1 = "$time $type_log [job_pos=$country job_name=$job_name job_id=$$ job_server=$host $product $task_name $pnr $reject] $message \n";

  my $MONITORE_FH   = $SINGLETON->{_MONITORING_FH};

  push (@{$SINGLETON->{_MONITORING_POOL}},   $msg1);

  if (defined $MONITORE_FH)   {
    $SINGLETON->_reOpen() unless (-e $logPath.$LogMonitoringFile.'.LOG');
    while (my $m = shift(@{$SINGLETON->{_MONITORING_POOL}}))   { print $MONITORE_FH   $m; }
  }

}

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

1;

