package Expedia::WS::Front;
#-----------------------------------------------------------------
# Package Expedia::WS::Front
#
# $Id: Front.pm 462 2008-05-22 15:45:13Z pbressan $
#
# (c) 2002-2007 Expedia.                   www.expediacorporate.fr
#-----------------------------------------------------------------

use Exporter 'import';
use SOAP::Lite;
# use SOAP::Lite +trace => [ all => \&_logSoap ];
use Data::Dumper;
use POSIX qw(strftime);

use Expedia::Tools::Logger qw(&debug &notice &warning &error);
use Expedia::Tools::GlobalVars qw($proxyFront $WSLogin_front $tssURL $urlToken $authorizationToken);
use Expedia::XML::MsgGenerator;

@EXPORT_OK = qw(&changeDeliveryState &addBookingComment &getDeliveryStatus &aqh_ticketingdeadline &aqh_unidentified &aqh_serviceconfirmation &aqh_schedulechange &aqh_waitlistfeedback &aqh_flightcancellation &aqh_UnidentifiedAmadeusCarMessage &wsTSSCall);

use strict;
use JSON;
use warnings;
#no warnings 'closure'; #POUR SUPPRIMER LES WARNING (Variable "$GDS" will not stay shared at ../libsperl/Expedia/Modules/AIQ/PnrGetInfos.pm line 143)

my $wsFront = undef;

# sub _logSoap { notice $_[0] }

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# CONSTRUCTEUR
sub new {
  my ($class, $ws) = @_;

  if (!defined $wsFront) {
    
  	my $self = {};
    bless ($self, $class);
  
    $self->{_SOAP} = new SOAP::Lite
      -> uri  ($proxyFront.$ws)
      -> proxy($proxyFront.$ws);
      
    $self->{_SOAP}->transport->timeout(30); # SOAP calls will timeout sooner.
    
    $wsFront = $self;
  
    return $self->soap;
    
  } else { return $wsFront->soap; }
  
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
sub soap {
  my $self = shift;

  return $self->{_SOAP};
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

sub wsTSSCall{
   my $market = shift;
   my $recLoc = shift;
   my $response = "";

   eval{ 
      my $token = getToken();

      my $req = HTTP::Request->new(POST => $tssURL.$recLoc.'/ticket');

      $req->header('Authorization' => 'Bearer '.$token);
      $req->content_type('application/json');
      $req->content('{"pos" : {"jurisdiction_code" : "'.$market.'"}}');

      my $ua = LWP::UserAgent->new;
      my $resp = $ua->request($req);
      my $messageFormated = $resp->decoded_content;
      $response = decode_json $messageFormated;
   }or do{
      notice('Error with TSS WS');
   };

   return $response; 
}

sub getToken {
   my $req = HTTP::Request->new(POST => $urlToken);
   my $ua = LWP::UserAgent->new;

   $req->header('Authorization' => 'Basic '.$authorizationToken);
   $req->content_type('application/x-www-form-urlencoded');
   $req->content('grant_type=client_credentials');

   my $resp = $ua->request($req);
   if ($resp->is_success) {
      my $message = $resp->decoded_content;
      $message = decode_json $message;
      $resp = $message->{'access_token'};
   }
   else {
      notice('Get token ERROR = '. $resp->message);
      $resp = undef;
   }
   return $resp;
}

# ----------------------------------------------------------------------

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
sub changeDeliveryState {
  my $ws     = shift;
  my $params = shift;

  my $deliveryId     = $params->{deliveryId};
  my $deliveryStatus = $params->{deliveryStatus};

  my $soap   = Expedia::WS::Front->new($ws);
  my $result = undef;
  
  eval {
    $result = $soap->changeDeliveryState(
      SOAP::Data->name('Context' =>
        \SOAP::Data->value(
  		    SOAP::Data->name('user'  => SOAP::Data->type('xsd:string'  => $WSLogin_front)),
  			  SOAP::Data->name('agent' => SOAP::Data->type('xsd:boolean' => 'true'))
        )
      ),
      SOAP::Data->type('xsd:long' => $deliveryId),
      SOAP::Data->type('xsd:long' => $deliveryStatus)
    );
  };
  
  debug("ChangeDeliveryState:".$deliveryId."|".$deliveryStatus);
  
  if ($@) {
    error $@;
    return undef;
  }

  if ($result->fault) {
    error($result->faultstring);
    error($soap->transport->status);
		return undef;
  }

  my $soapOut = undef;
  
  eval {
    $soapOut = $result->result;
  };
  if ($@) {
    error $@;
    $soapOut = undef;
  }

  debug("Result ChangeDeliveryState:".Dumper($soapOut));
  return $soapOut;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Ajoute une annotation à un Booking
sub addBookingComment {
  my $ws     = shift;
  my $params = shift;

  my $language  = $params->{language};
  my $mdCode    = $params->{mdCode};
  my $eventType = $params->{eventType};
  my $eventDesc = $params->{eventDesc} || '';
  
  my $soap   = Expedia::WS::Front->new($ws);
  my $result = undef;
  
  eval {
    $result = $soap->addBookingComment(
      SOAP::Data->name('Context' =>
        \SOAP::Data->value(
  		    SOAP::Data->name('user'  => SOAP::Data->type('xsd:string'  => $WSLogin_front)),
  			  SOAP::Data->name('agent' => SOAP::Data->type('xsd:boolean' => 'true'))
        )
      ),
      SOAP::Data->type('xsd:string' => $language),
      SOAP::Data->type('xsd:string' => $mdCode),
      SOAP::Data->type('xsd:string' => $eventDesc),
      SOAP::Data->type('xsd:int'    => $eventType),
    );
  };
  if ($@) {
    error $@;
    return undef;
  }

  if ($result->fault) {
    error($result->faultstring);
    error($soap->transport->status);
		return undef;
  }

  my $soapOut = undef;
  
  eval {
    $soapOut = $result->result;
  };
  if ($@) {
    error($@);
    $soapOut = undef;
  }

  return $soapOut;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Ajoute une annotation à un Booking
sub ECTEAddBookingAnnotationRQ {
  my $ws      = shift;
  my $content = shift;

  my $oMsg = Expedia::XML::MsgGenerator->new({
               context       => { 'language'    => 'FR',
                                  'userAgent'   => $WSLogin_front,                       
                                  'application' => 'RTL'
                                },
               type          => 'COMMENT_FROM_TICKETING',
               date          =>  _formatTimeToXmlDateTime(),
               content       =>  $content
             }, 'ECTEAddBookingAnnotationRQ.tmpl');

  my $msg = $oMsg->getMessage();
  debug("msg = ".$msg);
  
  my $soap   = Expedia::WS::Front->new($ws);
  my $result = undef;
  
  eval {
    $result = $soap->ECTEAddBookingAnnotationRQ(
      SOAP::Data->type('xsd:string' => $msg),
    );
  };
  if ($@) {
    error $@;
    return undef;
  }

  if ($result->fault) {
    error($result->faultstring);
    error($soap->transport->status);
		return undef;
  }

  my $soapOut = undef;
  
  eval {
    $soapOut = $result->result;
  };
  if ($@) {
    error($@);
    $soapOut = undef;
  }

  return $soapOut;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Utilisé pour la génération d'une date pour XML
sub _formatTimeToXmlDateTime {
  return strftime "%Y-%m-%dT%H:%M:%S.000Z", localtime;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
sub getDeliveryStatus {
  my $ws     = shift;
  my $params = shift;

  my $deliveryId     = $params->{deliveryId};

  my $soap   = Expedia::WS::Front->new($ws);
  my $result = undef;
  
  eval {
    $result = $soap->getDeliveryStatus(
      SOAP::Data->name('Context' =>
        \SOAP::Data->value(
  		    SOAP::Data->name('user'  => SOAP::Data->type('xsd:string'  => $WSLogin_front)),
  			  SOAP::Data->name('agent' => SOAP::Data->type('xsd:boolean' => 'true'))
        )
      ),
      SOAP::Data->type('xsd:long' => $deliveryId)
    );
  };
  if ($@) {
    error $@;
    return undef;
  }

  if ($result->fault) {
    error($result->faultstring);
    error($soap->transport->status);
		return undef;
  }

  my $soapOut = undef;
  
  eval {
    $soapOut = $result->result;
  };
  if ($@) {
    error $@;
    $soapOut = undef;
  }

  return $soapOut;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
sub aqh_ticketingdeadline {
  my $ws     = shift;
  my $params = shift;

  my $percode   = $params->{percode};
  my $pnr       = $params->{pnr};
  my $pos       = $params->{pos};
  my $date      = $params->{date};
  my $heure     = $params->{heure};
  my $attr      = '';
  
  if($date eq '')
  {
    $attr="true"; 
  }       
  
  my $soap   = Expedia::WS::Front->new($ws);
  my $result = undef;

$date = "$date";

  eval {
    $result = $soap->handleTicketingDeadline(
      SOAP::Data->type('xsd:string'   => $percode),
      SOAP::Data->type('xsd:string'   => $pnr),
      SOAP::Data->type('xsd:string'   => $pos),
      SOAP::Data->type('xsd:datetime' => $date)->attr({'xsi:nil' => $attr}),
      SOAP::Data->type('xsd:boolean'  => $heure),
    );
  };
  
  if ($@) {
    error $@;
    return undef;
  }

  if ($result->fault) {
    error($result->faultstring);
    error($soap->transport->status);
		return undef;
  }

  my $soapOut = undef;
  
  eval {
    $soapOut = $result->result;
  };
  
  if ($@) {
    error $@;
    $soapOut = undef;
  }


  return $soapOut;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
sub aqh_flightcancellation {
  my $ws     = shift;
  my $params = shift;

  my $percode   = $params->{percode};
  my $pnr       = $params->{pnr};
  my $pos       = $params->{pos};
        
  my $soap   = Expedia::WS::Front->new($ws);
  my $result = undef;

  eval {
    $result = $soap->handleFlightCancellation(
      SOAP::Data->type('xsd:string'   => $percode),
      SOAP::Data->type('xsd:string'   => $pnr),
      SOAP::Data->type('xsd:string'   => $pos),
    );
  };
  if ($@) {
    error $@;
    return undef;
  }

  if ($result->fault) {
    error($result->faultstring);
    error($soap->transport->status);
		return undef;
  }

  my $soapOut = undef;
  
  eval {
    $soapOut = $result->result;
  };
  if ($@) {
    error $@;
    $soapOut = undef;
  }


  return $soapOut;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
sub aqh_waitlistfeedback {
  my $ws     = shift;
  my $params = shift;

  my $percode   = $params->{percode};
  my $pnr       = $params->{pnr};
  my $pos       = $params->{pos};
        
  my $soap   = Expedia::WS::Front->new($ws);
  my $result = undef;

  eval {
    $result = $soap->handleWaitListFeedback(
      SOAP::Data->type('xsd:string'   => $percode),
      SOAP::Data->type('xsd:string'   => $pnr),
      SOAP::Data->type('xsd:string'   => $pos),
    );
  };
  if ($@) {
    error $@;
    return undef;
  }

  if ($result->fault) {
    error($result->faultstring);
    error($soap->transport->status);
		return undef;
  }

  my $soapOut = undef;
  
  eval {
    $soapOut = $result->result;
  };
  if ($@) {
    error $@;
    $soapOut = undef;
  }


  return $soapOut;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
sub aqh_schedulechange {
  my $ws     = shift;
  my $params = shift;

  my $percode   = $params->{percode};
  my $pnr       = $params->{pnr};
  my $pos       = $params->{pos};
        
  my $soap   = Expedia::WS::Front->new($ws);
  my $result = undef;

  eval {
    $result = $soap->handleScheduleChange(
      SOAP::Data->type('xsd:string'   => $percode),
      SOAP::Data->type('xsd:string'   => $pnr),
      SOAP::Data->type('xsd:string'   => $pos),
    );
  };
  if ($@) {
    error $@;
    return undef;
  }

  if ($result->fault) {
    error($result->faultstring);
    error($soap->transport->status);
		return undef;
  }

  my $soapOut = undef;
  
  eval {
    $soapOut = $result->result;
  };
  if ($@) {
    error $@;
    $soapOut = undef;
  }


  return $soapOut;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
sub aqh_serviceconfirmation {
  my $ws     = shift;
  my $params = shift;

  my $service       = $params->{service};
  my $percode       = $params->{percode};
  my $pnr           = $params->{pnr};
  my $codeservice   = $params->{codeservice};
  my $pos           = $params->{pos};
        
  my $soap   = Expedia::WS::Front->new($ws);
  my $result = undef;

  eval {
    $result = $soap->handleServiceConfirmation(
    SOAP::Data->type('xsd:string'     => $service),
      SOAP::Data->type('xsd:string'   => $percode),
      SOAP::Data->type('xsd:string'   => $pnr),
      SOAP::Data->type('xsd:string'   => $pos),
      SOAP::Data->type('xsd:string'   => $codeservice),
    );
  };
  if ($@) {
    error $@;
    return undef;
  }

  if ($result->fault) {
    error($result->faultstring);
    error($soap->transport->status);
		return undef;
  }

  my $soapOut = undef;
  
  eval {
    $soapOut = $result->result;
  };
  if ($@) {
    error $@;
    $soapOut = undef;
  }


  return $soapOut;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
sub aqh_unidentified {
  my $ws     = shift;
  my $params = shift;


  my $percode   = $params->{percode};
  my $pnr       = $params->{pnr};
  my $pos       = $params->{pos};
  my $queue     = $params->{unidentified};
            
  my $soap   = Expedia::WS::Front->new($ws);
  my $result = undef;

  eval {
    $result = $soap->handleUnidentifiedAirlineMessage(
      SOAP::Data->type('xsd:string'   => $percode),
      SOAP::Data->type('xsd:string'   => $pnr),
      SOAP::Data->type('xsd:string'   => $pos),
      SOAP::Data->type('xsd:string'   => $queue),
    );
  };
  if ($@) {
    error $@;
    return undef;
  }

  if ($result->fault) {
    error($result->faultstring);
    error($soap->transport->status);
		return undef;
  }

  my $soapOut = undef;
  
  eval {

    $soapOut = $result->result;
  
  };
  if ($@) {
    error $@;
    $soapOut = undef;
  }


  return $soapOut;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@


# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
sub aqh_UnidentifiedAmadeusCarMessage {
  my $ws     = shift;
  my $params = shift;


  my $percode   = $params->{percode};
  my $pnr       = $params->{pnr};
  my $pos       = $params->{pos};
  my $message   = $params->{message};
            
  my $soap   = Expedia::WS::Front->new($ws);
  my $result = undef;

  eval {
    $result = $soap->handleUnidentifiedAmadeusCarMessage(
      SOAP::Data->type('xsd:string'   => $percode),
      SOAP::Data->type('xsd:string'   => $pnr),
      SOAP::Data->type('xsd:string'   => $pos),
      SOAP::Data->type('xsd:string'   => $message),
    );
  };
  if ($@) {
    error $@;
    return undef;
  }

  if ($result->fault) {
    error($result->faultstring);
    error($soap->transport->status);
		return undef;
  }

  my $soapOut = undef;
  
  eval {

    $soapOut = $result->result;
  
  };
  if ($@) {
    error $@;
    $soapOut = undef;
  }


  return $soapOut;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

1;
