package Expedia::Tools::SendMail;
#-----------------------------------------------------------------
# Package Expedia::Tools::SendMail
#
# $Id: SendMail.pm 589 2010-07-21 08:53:20Z pbressan $
#
# (c) 2002-2009 Expedia.                   www.expediacorporate.fr
#-----------------------------------------------------------------

use MIME::Lite;
use Exporter 'import';
use Data::Dumper;
use Clone qw(clone);
use Expedia::Tools::Logger     qw(&debug &notice &warning &error);
use Expedia::Tools::GlobalVars qw($sendmailProtocol $sendmailIP $sendmailTimeout $GetBookingFormOfPayment_errors);
use Expedia::Tools::GlobalVars qw($cnxMgr);

@EXPORT_OK = qw(&tasSendReport &tasSendSoapPb &tasSendError12 &trainSendReport &BackWSSendError &getMailForEmd);

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
sub tasSendReport {
  my $path    = shift;
  my $sTask   = shift; # tas ou tasmeetings
  my $agency  = shift;
  my $product = shift;
  my $excelpath = shift;
  my $excelfile = shift;
  my $country = shift;
  
  if (!$path || $path =~ /^\s*$/) {
    warning('Path message to send cannot be empty !');
    return 0;
  }
  
  my $meetings = '';
     $meetings = '[MEETINGS] ' if ((defined $sTask) && ($sTask =~ /^tasmeetings$/));

  $my_from = 'tas@egencia.com';
  $my_to   = &getMailForTas($country);
  $my_cc   = '';

  eval {
    my $mail = MIME::Lite->new(
      From     => $my_from,
    	To       => $my_to,
    	Cc       => $my_cc,
    	Subject  => 'TAS Robotic Tool Report - '.$meetings.$agency.' Agency ( '.uc($product).' )',
    	Type     => 'TEXT',
    	Encoding => 'quoted-printable',
    	Path     => $path);
    if ($excelpath) {
       $mail->attach(
        Type     => 'application/vnd.ms-excel',
        Path     => $excelpath,
        Filename => $excelfile,
        Disposition => 'attachment'
       );
    }
    MIME::Lite->send($sendmailProtocol, $sendmailIP, Timeout => $sendmailTimeout);
    $mail->send;
  };
  if ($@) {
    error('Problem during email send process. '.$@);
    return 0;
  }
  
  notice('TAS report correctly mailed.');
  
  return 1;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
sub tasSendSoapPb {
  my $msg      = shift;
  my $sTask    = shift;
  my $country   = shift;
  my $product  = shift;
  
  if (!$msg || $msg =~ /^\s*$/) {
    warning('Message to send cannot be empty !');
    return 0;
  }
  
  my $meetings = '';
     $meetings = '[MEETINGS] ' if ((defined $sTask) && ($sTask =~ /^tasmeetings$/));

  $my_to   = &getMailForTas($country);
  $my_cc   = '';
    
  eval {
    my $mail = MIME::Lite->new(
      From     => 'noreply@egencia.eu',
      To       => $my_to,
    	Cc       => $my_cc,
    	Subject  => 'TAS Robotic Tool Problem - '.$meetings.$country.' Agency ( '.uc($product).' )', # Remplacer Agency ?
    	Data     => $msg);
    
    MIME::Lite->send($sendmailProtocol, $sendmailIP, Timeout => $sendmailTimeout);
    $mail->send;
  };
  if ($@) {
    error('Problem during email send process. '.$@);
    return 0;
  }
  
  notice('Problems with SOAP detected. Mail sended.');
  
  return 1;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
sub tasSendError12 {
  my $params  = shift;

  my $from    = $params->{from};
  my $to      = $params->{to};
  my $subject = $params->{subject};
  my $data    = $params->{data};
  
  eval {
    my $mail = MIME::Lite->new(
      From     => $from,
    	To       => $to,
    	Subject  => $subject,
    	Data     => $data);
    
    MIME::Lite->send($sendmailProtocol, $sendmailIP, Timeout => $sendmailTimeout);
    $mail->send;
  };
  if ($@) {
    error('Problem during email send process. '.$@);
    return 0;
  }
  
  return 1
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
sub trainSendReport {
  my $path   = shift;
  my $total  = shift;
  
  if (!$path || $path =~ /^\s*$/) {
    warning('Path message to send cannot be empty !');
    return 0;
  }
  
  eval {
    my $mail = MIME::Lite->new(
      From     => 'btc-train@expediacorporate.fr',
    	To       => 'all-service-client@expediacorporate.fr',
    	Subject  => "Rapport d'erreurs BTC-TRAIN [$total]",
    	Type     => 'TEXT',
    	Encoding => 'quoted-printable',
    	Path     => $path);
    
    MIME::Lite->send($sendmailProtocol, $sendmailIP, Timeout => $sendmailTimeout);
    $mail->send;
  };
  if ($@) {
    error('Problem during email send process. '.$@);
    return 0;
  }
  
  notice('BTC-TRAIN report correctly mailed.');
  
  return 1;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Get mail for TAS
sub getMailForTas {
  my $country = shift;
  
  
  my $midDB = $cnxMgr->getConnectionByName('mid');
  
  my $query = "
    SELECT TAS_TO
    FROM MO_CFG_MAIL 
    WHERE COUNTRY = ? ";

  my $finalRes = $midDB->saarBind($query, [$country])->[0][0];
notice("REQUEST:".$query);

notice("RES:".Dumper(@finalRes));

  return $finalRes;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Send Back WS errors
sub BackWSSendError {      

	
	my $pos 				  =	shift;
	my $taskname              = shift || undef;
	my $my_to ;

	if (defined($taskname) && $taskname =~ m/tas/)
	{
		
		$my_to = getMailForTas($pos);
		
	}
	
	else {
		
		$my_to= getMailForEmd($pos);
	}
	
			
	my $data ='';
					
	foreach my $error (@$GetBookingFormOfPayment_errors) {
				
		my $comcode=$error->{comcode};
		my $percode=$error->{percode};
		my $pnr=$error->{pnr};
		my $errmsg=$error->{errMsg};
		$data=$data."\n\n- Comcode : $comcode, Percode: $percode, PNR : $pnr, Error Message : $errmsg";
	
	}
	
	
	
	my $msg_error = MIME::Lite->new(
	  From     => 'noreply@egencia.eu',
	  To       => $my_to,
	  Subject  => '['.uc($taskname).']Error encountered when calling WS GetBookingFormOfPayment - POS '.$pos,
	  Type     => 'TEXT',
	  Encoding => 'quoted-printable',
	  Data     => 'Following errors have been raised by on '.$pos.' when calling WS GetBookingFormOfPayment :'.$data,
		  
   );
   
   

   MIME::Lite->send($sendmailProtocol, $sendmailIP, Timeout => $sendmailTimeout);
   $msg_error->send;

  if ($@) {
     notice('Problem during email send process. '.$@);
  }
}


# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Get mail for EMD
sub getMailForEmd {
  my $market    = shift;
  my $champ     = shift || undef;
  
  my $midDB = $cnxMgr->getConnectionByName('mid');
  my $query = "
    SELECT EMD_TO
        FROM MO_CFG_MAIL
     WHERE COUNTRY= ?  ";
  my $finalRes = $midDB->saarBind($query, [$market])->[0][0];
  return $finalRes;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

1;


