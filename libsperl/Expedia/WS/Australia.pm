package Expedia::WS::Australia;
#-----------------------------------------------------------------
# Package Expedia::WS::Back
#
# $Id: Australia.pm 713 2011-07-04 15:45:26Z pbressan $
#
# (c) 2002-2010 Expedia.                   www.expediacorporate.fr
#-----------------------------------------------------------------

use Exporter 'import';
use SOAP::Lite;
#use SOAP::Lite +trace => [ all => \&logSoap ];
use XML::LibXML;
use Data::Dumper;
use Unicode::String qw(utf8 latin1);

use Expedia::Tools::Logger qw(&debug &notice &warning &error);
use Expedia::Tools::GlobalVars qw($proxyAustralia $h_creditCardTypes);

@EXPORT_OK = qw(&ECTEAddCommission);

use strict;

my $wsBack = undef;

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# CONSTRUCTEUR
sub new {
  my ($class, $ws) = @_;

  if (!defined $wsBack) {
    
    my $proxy = $proxyAustralia;
    
    notice("proxy = $proxy");

  	my $self = {};
    bless ($self, $class);
  #-> uri('urn:'.$ws) 
    $self->{_SOAP} = new SOAP::Lite
      -> uri($ws) 
      -> on_action(sub{sprintf '%s/%s', @_ })
      -> proxy($proxy);
    
    $self->{_SOAP}->transport->timeout(15); # SOAP calls will timeout sooner.
    
    $wsBack = $self;
  
    return $self->soap;
    
  } else { return $wsBack->soap; }
  
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
sub soap {
  my $self = shift;

  return $self->{_SOAP};
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
sub ECTEAddCommission {

my ($ws_number, $ws, $ValidatingCarrierCode, $FareType, $PCC, $BookingReference, $FormOfPayment, $PaxType, $StartCityCode, $EndCityCode, $MarketingAirlineCode, $FareBasisCode) = @_;
  
 my @tab="";
 my @tabFB="";
 my $cpt=1;
 my $cpt_t=0;
 
  foreach my $SCC (@{$StartCityCode})
    {
     push @tab, SOAP::Data->name(AirSegment      => \SOAP::Data->value(
              SOAP::Data->name(SegmentNumber      => SOAP::Data->type('xsd:int' =>  $cpt)),
              SOAP::Data->name(StartCityCode      => SOAP::Data->type('xsd:string' =>  $SCC)),
              SOAP::Data->name(EndCityCode      => SOAP::Data->type('xsd:string' =>  @{$EndCityCode}[$cpt_t])),
              SOAP::Data->name(MarketingAirlineCode      => SOAP::Data->type('xsd:string' =>  @{$MarketingAirlineCode}[$cpt_t]))
            )),;
      $cpt++;
      $cpt_t++;
    }

    foreach my $FB (@{$FareBasisCode})
    {
        push @tabFB, SOAP::Data->name(FareBasisCode      => SOAP::Data->type('xsd:string' =>  $FB)),              ;
    }
    
  my $soap   = Expedia::WS::Australia->new($ws);
  my $result = undef;
  my $result_FP = undef;
  my $ret   = undef;
 
     eval {
              
        my $segment=SOAP::Data->value(@tab);
        my $fareB  =SOAP::Data->value(@tabFB);
            
  	    my $SOAP_DATA=  SOAP::Data->name(FareQuote      => \SOAP::Data->value(
        SOAP::Data->name(ValidatingCarrierCode      => SOAP::Data->type('xsd:string' =>  $ValidatingCarrierCode)),
        SOAP::Data->name(FareType                   => SOAP::Data->type('xsd:int'    =>  $FareType)),
        SOAP::Data->name(PCC                        => SOAP::Data->type('xsd:string'    =>  $PCC)),
        SOAP::Data->name(BookingReference           => SOAP::Data->type('xsd:string'    =>  $BookingReference)),
        SOAP::Data->name(FormOfPayment           => SOAP::Data->type('xsd:string'    =>  $FormOfPayment)),
        SOAP::Data->name(PaxType           => SOAP::Data->type('xsd:string'    =>  $PaxType)), 
          SOAP::Data->name(Segments      => \$segment
         
         ),    
         SOAP::Data->name(FareBasisCodes      => \$fareB  
         ),
         )),;   
    #   SOAP::Data->name(FareBasisCodes      => \SOAP::Data->value(
    #      SOAP::Data->name(FareBasisCode      => SOAP::Data->type('xsd:string' =>  $FareBasisCode)),
    #   )),   
    #   )),   ;
  	  
  	debug('SOAP_DATA = '.Dumper($SOAP_DATA));
  	   
  	  my $user=SOAP::Data->name(UserID         => SOAP::Data->type('xsd:string' =>  'Test')),;
      	
          if($ws_number == 1)
          {
                eval {
                        $result = $soap->GetCommission($SOAP_DATA,$user);
                  };
                if ($@) {
                        notice('Problem during GetCommission. '.$@);
                        return $ret="KOTECH;Technical Error";
                        }
                else
                {
                        $result = $result->result;

                        if(defined($result->{ErrorText}) &&  $result->{ErrorText} ne "")
                        {
                                $ret="KOFONC;".$result->{ErrorText};
                        }
                        elsif(!defined($result->{ErrorText}) &&  !defined($result->{Commission}))
                        {
                                $ret="KOTECH;Technical Error";
                        }
                        else
                        {
                                $ret="OK;".$result->{Commission};
                        }
                }

          }

          if($ws_number == 2)
          {
                eval {
                        $result = $soap->ValidateFormOfPayment($SOAP_DATA,$user);
                  };
                if ($@) {
                        notice('Problem during GetCommission. '.$@);
                        return $ret="KOTECH;Technical Error";
                        }
                else
                {
                        $result = $result->result;
                        if(defined($result->{ErrorText}) &&  $result->{ErrorText} ne "")
                        {
                                $ret="KOFONC;".$result->{ErrorText};
                        }
                        elsif(!defined($result->{ErrorText}) &&  !defined($result->{ValidFOP}))
                        {
                                $ret="KOTECH;Technical Error";
                                debug("DETAIL TECH ERROR:".Dumper($result));
                        }
                        else
                        {
                                $ret="OK;".$result->{ValidFOP};
                        }

                }

          }

		  
        };  # FIN Eval global
         if ($@) {
            notice('Problem during WS AU. '.$@);
           }

notice("FIN WS");
  return $ret #$result->{Commission}



}

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Méthode de conversion de la date fournie par l'appel au webService BackOffice
# ~ Exemple : 31/12/2008 00:00:00
sub _convertDate {
  my $date = shift;
  
  my $month = substr($date, 3, 2);
  my $year  = substr($date, 8, 2);
  
  return $month.$year;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
sub _convertOrigin {
  my $origin = shift;
  
  my $h_origin = {
    'customer'   => 'COMPANY',
    'cc'         => 'ENTITY',
    'traveller'  => 'INDIV',
  };
  
  return $h_origin->{$origin};
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

sub logSoap { print STDERR $_[0]."\n"; }

1;
