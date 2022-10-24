package Expedia::WS::Back;
#-----------------------------------------------------------------
# Package Expedia::WS::Back
#
#
# $Id: Back.pm 611 2011-01-06 11:42:10Z pbressan $
#
# (c) 2002-2010 Expedia.                   www.expediacorporate.fr
#-----------------------------------------------------------------

use Exporter 'import';
use SOAP::Lite;
use XML::LibXML;
use Data::Dumper;
use Unicode::String qw(utf8 latin1);
use LWP::UserAgent;
use HTTP::Request::Common;
use XML::LibXML::XPathContext;
use Expedia::Tools::Logger qw(&debug &notice &warning &error);
use Expedia::Tools::GlobalVars qw($proxyBack $proxyBackBis $h_creditCardTypes $hashWSLogin $WSLogin_back $WSLogin_nav $proxyNav_intra $GetBookingFormOfPayment_errors);
use MIME::Lite;

@EXPORT_OK = qw(&GetTravelerUnusedCredits &GetUnusedCreditsActivatedCust &GetTravelerCostCenter &BO_GetBookingFormOfPayment &SetUnusedticketAsUsed);

use strict;

my $wsBack = undef;

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# CONSTRUCTEUR
sub new {
  my ($class, $ws, $bis) = @_;

  if (!defined $wsBack) {
    
    my $proxy = !defined $bis ? $proxyBack : $proxyBackBis;
    
    notice("proxy = $proxy");

  	my $self = {};
    bless ($self, $class);
  
    $self->{_SOAP} = new SOAP::Lite
      -> uri('urn:'.$ws) 
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




sub BO_GetBookingFormOfPayment {

 ##Mandatory
 my $ws             = shift;
  my $pos            = shift;
  my $comcode   = shift;

  ## optionnal
  
  my $token =shift||undef;
  my $percode = shift||undef;
  my $service = shift||undef;
  my $corporationCode = shift||undef;
  my $CostCenter = shift||undef;
  my $pnr  = shift || undef;


  START:

  my $soap   = Expedia::WS::Back->new($ws);
  my $result = undef;
  
  eval {
    $result = $soap->GetBookingFormOfPayment(
          SOAP::Data->name(login             => SOAP::Data->type('xsd:string' => $WSLogin_back)), #MidCard
          SOAP::Data->name(password   => SOAP::Data->type('xsd:string' => $hashWSLogin->{$WSLogin_back})), #MidCard
          SOAP::Data->name(pos => SOAP::Data->type('xsd:string' =>  $pos)),
          SOAP::Data->name(percode => SOAP::Data->type('xsd:string' =>  $percode)),
          SOAP::Data->name(comcode => SOAP::Data->type('xsd:string' =>  $comcode)),
          SOAP::Data->name(service => SOAP::Data->type('xsd:string' =>  $service)),
          SOAP::Data->name(costcenter => SOAP::Data->type('xsd:string' =>  $CostCenter)),
          SOAP::Data->name(corporation => SOAP::Data->type('xsd:string' =>  $corporationCode)),
          SOAP::Data->name(token => SOAP::Data->type('xsd:string' =>  $token)),
    );
  };
  
  
  if ($@ || $result->fault) {
  
  
	  eval {
			   if ($result->fault) {
				   error($result->faultstring);
				   error($soap->transport->status);
				   return undef;
			   }
			};
		   
			  

			  if ($@) {
			  		  
			   error $@;   
			   notice ('Error on  WS GetBookingFormOfPayment on pos '.$pos.' for comcode '.$comcode.' : '.$@ );
			   push (@$GetBookingFormOfPayment_errors, {comcode     => $comcode,
			   											    percode 	=> $percode,
														    errMsg      => $@, 
														    pnr			=> $pnr		});	
															
				return undef;										
			   
			  };
			  
    
  }

  $result = $result->result;

  # --------------------------------------------------------------
  # Phase d'analyse du résulat SOAP obtenu
  my $parser = XML::LibXML->new();
  my $doc    = undef;

  eval { $doc = $parser->parse_string(utf8($result)->latin1); };
  if ($@) {
    error("Parser Error !#! ".$@);
    return undef;
  }
 print "BO_GetBookingFormOfPayment = \n".$doc->toString(1);
 my @contextNode  = $doc->findnodes('Response/Exception');
 if (scalar @contextNode > 0){
        my $errorMsg=$contextNode[0]->find('Message')->to_literal->value();
        notice('Error Message= '.$errorMsg);
        notice('Error Code= '.$contextNode[0]->find('Code')->to_literal->value());
        return {
                     ErrorMsg        => $errorMsg
				};
  }
  my @responseNode = $doc->findnodes('Response/Value');
  return undef if (scalar @responseNode != 1);


  my $PaymentType     = $responseNode[0]->find('PaymentType')->to_literal->value();
  my $Origin      = _convertOrigin($responseNode[0]->find('Origin')->to_literal->value());
  my $Service = $responseNode[0]->find('Service')->to_literal->value();

  print 'Service     = '.$Service."\n"     if defined $Service;
  print 'Origin      = '.$Origin."\n"      if defined $Origin;
  print 'PaymentType = '.$PaymentType."\n" if defined $PaymentType;

        #If it is a credit card, we can find card infos
  if($PaymentType eq 'CC'){

		my @card=$doc->findnodes('Response/Value/Card');
		my $form_of_payment = $card[0]->find('FormOfPayment')->to_literal->value();
		my $cardtype=$card[0]->find('CardType')->to_literal->value();
		my $shortcardtype=$card[0]->find('ShortCardType')->to_literal->value();
		my $token=$card[0]->find('CardToken')->to_literal->value();
		my $exp_date=_convertDate($card[0]->find('ExpirationDate')->to_literal->value());
		my $short_exp_date=$card[0]->find('ShortExpirationDate')->to_literal->value() ;
		$short_exp_date=~ s/\///;  ## Removing slash caracter : "12/17"--> "1217"
		my $MerchantFlow=$card[0]->find('MerchantFlow')->to_literal->value();
        my $CardNumber=$card[0]->find('CardNumber')->to_literal->value();

        return {
                        CardNumber     => $CardNumber,
                        Service        =>  $Service,
                        Origin         =>  $Origin,
                        PaymentType    =>  $PaymentType,
                        CardType       =>  $shortcardtype,
                        Token          =>  $token,
                        CardExpiry     => $short_exp_date,
                        Financial      => $MerchantFlow,
						FormOfPayment  => $form_of_payment,

		}
    }
	
	return {
			Service         =>  $Service,
			Origin          =>  $Origin,
			PaymentType     =>  $PaymentType
	}


 }





sub GetUnusedCreditsActivatedCust
{
my $ws = shift;
my $pos= shift;

if($pos eq 'GB') { $pos='UK';}

        ########## I was unable to correctly created the SOAP request, so we recreate the SOAP message and send it via POST method on port 7047
        my $message="
        <soapenv:Envelope
        xmlns:soapenv=\"http://schemas.xmlsoap.org/soap/envelope/\"
        xmlns:nav=\"".$proxyNav_intra."\"
        xmlns:exp=\"urn:microsoft-dynamics-nav/xmlports/ExportUnusedCreditsActivCust\">
           <soapenv:Body>
                  <nav:GetUnusedCreditsActivatedCust>
                         <!--Optional:-->
                         <nav:login>".$WSLogin_nav."</nav:login>
                         <!--Optional:-->
                         <nav:password>".$hashWSLogin->{$WSLogin_nav}."</nav:password>
                         <!--Optional:-->
                         <nav:POS>".$pos."</nav:POS>
                         <!--Optional:-->
                         <nav:exportCustomerUnusedCredits>
                                e
                                <!--Zero or more repetitions:-->
                                <exp:NAV_Customer>
                                   <!--Optional:-->
                                   <exp:Comcode>?</exp:Comcode>
                                </exp:NAV_Customer>
                                gero
                                <!--Zero or more repetitions:-->
                                <exp:NavException>
                                   cum
                                   <!--Zero or more repetitions:-->
                                   <exp:NavExceptionCode>?</exp:NavExceptionCode>
                                   sonoras
                                   <!--Zero or more repetitions:-->
                                   <exp:NavExceptionDesc>?</exp:NavExceptionDesc>
                                   aeoliam
                                </exp:NavException>
                                quae
                         </nav:exportCustomerUnusedCredits>
                  </nav:GetUnusedCreditsActivatedCust>
           </soapenv:Body>
        </soapenv:Envelope>
        ";

debug("GetUnusedCreditsActivatedCust:".$message);

        my $userAgent = LWP::UserAgent->new(agent => 'perl post');
        my $response = $userAgent->request(POST $ws,
        Content_Type => 'text/xml',
        Content => $message);

        debug($response->as_string);

        # --------------------------------------------------------------
        # Phase d'analyse du rÃ©lat SOAP obtenu
        my @liste_comcode = ();
        my $exp           = '';
        my $xml    = $response->content;
        my $parser = XML::LibXML->new();
        my $doc    = $parser->parse_string($xml);

        my $xpath = "/*/*/*/*/*/*";
        my $xpc   = XML::LibXML::XPathContext->new();
        my $nodes = $xpc->findnodes( $xpath, $doc->documentElement );

        my $result = XML::LibXML::NodeList->new;
        foreach my $test ($nodes->get_nodelist)
        {
                if($test->nodeName =~ m/Comcode/ )
                {
                        debug("Comcode:".$test->string_value());
                        push @liste_comcode, $test->string_value();
                }
                if($test->nodeName =~ m/NavExceptionDesc/ && $test->string_value() ne '')
                {
                        notice("NavExceptionDesc:".$test->string_value());
                        $exp = $test->string_value();
                }
        }

	if($exp ne '')
	{
			return $exp;
	}
	else
	{
		return @liste_comcode;
	}

}

sub GetTravelerUnusedCredits
{
my $ws                  = shift;
my $pos                 = shift;
my $comcode             = shift;
my $percode             = shift;
my $traveller_name      = shift;
my $traveller_firstname = shift;
my $traveller_title     = shift;
my $airline             = shift;

if($pos eq 'GB') { $pos='UK';}

        ########## I was unable to correctly created the SOAP request, so we recreate the SOAP message and send it via POST method on port 7047
        my $message="
<soapenv:Envelope
xmlns:soapenv=\"http://schemas.xmlsoap.org/soap/envelope/\"
xmlns:nav=\"".$proxyNav_intra."\"
xmlns:exp=\"urn:microsoft-dynamics-nav/xmlports/ExportTravelerUnusedCredits\">
   <soapenv:Header/>
   <soapenv:Body>
      <nav:GetTravelerUnusedCredits>
         <!--Optional:-->
         <nav:login>".$WSLogin_nav."</nav:login>
         <!--Optional:-->
         <nav:password>".$hashWSLogin->{$WSLogin_nav}."</nav:password>
         <!--Optional:-->
         <nav:POS>".$pos."</nav:POS>
         <!--Optional:-->
         <nav:comCode>".$comcode."</nav:comCode>
         <!--Optional:-->
         <nav:perCode>".$percode."</nav:perCode>
         <!--Optional:-->
         <nav:travellerName>".$traveller_name."</nav:travellerName>
         <!--Optional:-->
         <nav:travellerFirstName>".$traveller_firstname."</nav:travellerFirstName>
         <!--Optional:-->
         <nav:travellerTitle>".$traveller_title."</nav:travellerTitle>
         <!--Optional:-->
         <nav:airLine>".$airline."</nav:airLine>
         <!--Optional:-->
         <nav:exportTravellerUnusedCredits>
            e
            <!--Zero or more repetitions:-->
            <exp:NAV_TravelerUnusedCredit>
               <!--Optional:-->
               <exp:TicketNumber>?</exp:TicketNumber>
               <!--Zero or more repetitions:-->
               <exp:ExpiryDate>?</exp:ExpiryDate>
               <!--Optional:-->
               <exp:Percode>?</exp:Percode>
               <!--Optional:-->
               <exp:TravelerName>?</exp:TravelerName>
               <!--Optional:-->
               <exp:Airline>?</exp:Airline>
            </exp:NAV_TravelerUnusedCredit>
            gero
            <!--Zero or more repetitions:-->
            <exp:NavException>
               cum
               <!--Zero or more repetitions:-->
               <exp:NavExceptionCode>?</exp:NavExceptionCode>
               sonoras
               <!--Zero or more repetitions:-->
               <exp:NavExceptionDesc>?</exp:NavExceptionDesc>
               aeoliam
            </exp:NavException>
            quae
         </nav:exportTravellerUnusedCredits>
      </nav:GetTravelerUnusedCredits>
   </soapenv:Body>
</soapenv:Envelope>
 ";

debug("GetTravelerUnusedCredits:".$message);

        my $userAgent = LWP::UserAgent->new(agent => 'perl post');
        my $response = $userAgent->request(POST $ws,
        Content_Type => 'text/xml',
        Content => $message);

        debug($response->as_string);

        # --------------------------------------------------------------
        # Phase d'analyse du rÃ©lat SOAP obtenu
        my @results          = ();
        my $res_ticketnumber = '';
        my $res_expirydate   = '';
        my $res_percode      = '';
        my $res_travelername = '';
        my $res_airline      = '';
        my $exp                 = '';
        my $xml    = $response->content;
        my $parser = XML::LibXML->new();
        my $doc    = $parser->parse_string($xml);

        my $xpath = "/*/*/*/*/*/*";
        my $xpc   = XML::LibXML::XPathContext->new();
        my $nodes = $xpc->findnodes( $xpath, $doc->documentElement );

        my $result = XML::LibXML::NodeList->new;
        foreach my $test ($nodes->get_nodelist)
        {
                if($test->nodeName =~ m/TicketNumber/ )
                {
                        $res_ticketnumber=$test->string_value();
                }
                if($test->nodeName =~ m/ExpiryDate/ )
                {
                        $res_expirydate=$test->string_value();
                }
                if($test->nodeName =~ m/Percode/ )
                {
                        $res_percode=$test->string_value();
                }
                if($test->nodeName =~ m/TravelerName/ )
                {
                        $res_travelername=$test->string_value();
                }
                if($test->nodeName =~ m/Airline/ )
                {
                        $res_airline=$test->string_value();
						push @results, { RC  => "RC * ".$res_airline." ".$res_travelername." ".$res_ticketnumber." ".$res_expirydate,
            						     TKT => "TWD/TKT".substr($res_ticketnumber,0,3)."-".substr($res_ticketnumber,3,length($res_ticketnumber))
									   };
                }
                if($test->nodeName =~ m/NavExceptionDesc/ && $test->string_value() ne '')
                {
                        notice("NavExceptionDesc:".$test->string_value());
                        $exp = "EXP|".$test->string_value();
                        push @results, { ERROR => $test->string_value()};
                }
        }

	if($exp ne '')
	{
		return @results;
	}
	else
	{
		return @results;
	}

}




sub SetUnusedticketAsUsed
{
my $params              = shift;
my $ws                  = $params->{WS};
my $pos                 = $params->{pos};

if($pos eq 'GB') { $pos='UK';}

   ########## I was unable to correctly created the SOAP request, so we recreate the SOAP message and send it via POST method on port 7047
   my $message="
   <soap:Envelope xmlns:soap=\"http://www.w3.org/2003/05/soap-envelope\" xmlns:nav=\"".$proxyNav_intra."\"  xmlns:exp=\"urn:microsoft-dynamics-nav/xmlports/ExportUnusedTktNumber\">
   <soap:Header/>
   <soap:Body>
      <nav:SetUnusedticketAsUsed>
            <!--Optional:-->
            <nav:login>".$WSLogin_nav."</nav:login>
            <!--Optional:-->
            <nav:password>".$hashWSLogin->{$WSLogin_nav}."</nav:password>
            <!--Optional:-->
          	<nav:POS>".$pos."</nav:POS>
            <!--Optional:-->
            <nav:comCode>".$params->{comCode}."</nav:comCode>
            <!--Optional:-->
            <nav:perCode>".$params->{perCode}."</nav:perCode>
            <!--Optional:-->
            <nav:TicketNumber>".$params->{ticketNumber}."</nav:TicketNumber>
            <!--Optional:-->

         <nav:ExportUnusedTicketNumber>
            e
            <!--Zero or more repetitions:-->
            <exp:Unused_Ticket>
               <!--Optional:-->
               <exp:Ticket_Number>?</exp:Ticket_Number>
               <!--Optional:-->
               <exp:Comcode>?</exp:Comcode>
               <!--Optional:-->
               <exp:Traveler>?</exp:Traveler>
               <!--Optional:-->
               <exp:Used_Credit>?</exp:Used_Credit>
            </exp:Unused_Ticket>
            gero
            <!--Zero or more repetitions:-->
            <exp:NavException>
               cum
               <!--Zero or more repetitions:-->
               <exp:NavExceptionCode>?</exp:NavExceptionCode>
               sonoras
               <!--Zero or more repetitions:-->
               <exp:NavExceptionDesc>?</exp:NavExceptionDesc>
               aeoliam
            </exp:NavException>
            quae
         </nav:ExportUnusedTicketNumber>
      </nav:SetUnusedticketAsUsed>
   </soap:Body>
</soap:Envelope>
   
   
 ";

debug("SetUnusedticketAsUsed:".$message);

        my $userAgent = LWP::UserAgent->new(agent => 'perl post');
        my $response = $userAgent->request(POST $params->{WS},
        Content_Type => 'text/xml',
        Content => $message);

        debug($response->as_string);

        # --------------------------------------------------------------
        # Phase d'analyse du rÃ©lat SOAP obtenu
        my @results          = ();
        my $res_ticketnumber = '';
        my $exp                 = '';
        my $xml    = $response->content;
        my $parser = XML::LibXML->new();
        my $doc    = $parser->parse_string($xml);

        my $xpath = "/*/*/*/*/*/*";
        my $xpc   = XML::LibXML::XPathContext->new();
        my $nodes = $xpc->findnodes( $xpath, $doc->documentElement );

        my $result = XML::LibXML::NodeList->new;
        foreach my $test ($nodes->get_nodelist)
        {
        	    print "".$test->string_value();
                if($test->nodeName =~ m/Ticket_Number/ )
                {
                        $res_ticketnumber=$test->string_value();
                        notice ("Updated Unsed Ticket Credits for TicketNumber:".$res_ticketnumber." Successfully")
                }
                if($test->nodeName =~ m/NavExceptionDesc/ && $test->string_value() ne '')
                {
                        notice("NavExceptionDesc:".$test->string_value());
                        $exp = "EXP|".$test->string_value();
                        push @results, { ERROR => $test->string_value()};
                }
        }

	if($exp ne '')
	{
		return @results;
	}
	else
	{
		return @results;
	}

}

sub GetTravelerCostCenter
{
	my $ws = shift;
	my $pos= shift;
	my $comcode = shift;
	my $percode = shift;

	my $CC4 = '';
	my $CC5 = '';

	if($pos eq 'GB') { $pos='UK';}


	my $message=
	"<soapenv:Envelope xmlns:soapenv=\"http://schemas.xmlsoap.org/soap/envelope/\"
	 xmlns:nav=\"".$proxyNav_intra."\"
	 xmlns:get=\"urn:microsoft-dynamics-nav/xmlports/GetTravelerCostCenter\">
	   <soapenv:Header/>
	   <soapenv:Body>
		  <nav:GetTravelerCostCenter>
			 <!--Optional:-->
			 <nav:login>".$WSLogin_nav."</nav:login>
			 <!--Optional:-->
			 <nav:password>".$hashWSLogin->{$WSLogin_nav}."</nav:password>
			 <!--Optional:-->
			 <nav:POS>".$pos."</nav:POS>
			 <!--Optional:-->
			 <nav:comcode>".$comcode."</nav:comcode>
			 <!--Optional:-->
			 <nav:Percode>".$percode."</nav:Percode>
			 <!--Optional:-->
			 <nav:TravInfo>
				e
				<!--Zero or more repetitions:-->
				<get:Traveler_Info>
				   <!--Optional:-->
				   <get:PerCode>?</get:PerCode>
				   <!--Optional:-->
				   <get:PercodeName>?</get:PercodeName>
				   <!--Optional:-->
				   <get:Comcode>?</get:Comcode>
				   <!--Optional:-->
				   <get:CC4>?</get:CC4>
				   <!--Optional:-->
				   <get:CC5>?</get:CC5>
				</get:Traveler_Info>
				gero
				<!--Zero or more repetitions:-->
				<get:NavException>
				   cum
				   <!--Zero or more repetitions:-->
				   <get:NavExceptionCode>?</get:NavExceptionCode>
				   sonoras
				   <!--Zero or more repetitions:-->
				   <get:NavExceptionDesc>?</get:NavExceptionDesc>
				   aeoliam
				</get:NavException>
				quae
			 </nav:TravInfo>
		  </nav:GetTravelerCostCenter>
	   </soapenv:Body>
	</soapenv:Envelope>
	";

	debug("GetTravelerCostCenter:".$message);

	my $userAgent = LWP::UserAgent->new(agent => 'perl post');
	my $response = $userAgent->request(POST $ws,
	Content_Type => 'text/xml',
	Content => $message);

	debug($response->as_string);

	my $exp           = '';
	my $xml    = $response->content;
	my $parser = XML::LibXML->new();
	my $doc    = $parser->parse_string($xml);

	my $xpath = "/*/*/*/*/*/*";
	my $xpc   = XML::LibXML::XPathContext->new();
	my $nodes = $xpc->findnodes( $xpath, $doc->documentElement );

	
	foreach my $test ($nodes->get_nodelist)
	{ 
			if($test->nodeName =~ m/CC4/ )
			{
					notice("CC4:".$test->string_value());
					$CC4 = $test->string_value();
			}
			if($test->nodeName =~ m/CC5/ )
			{
					notice("CC5:".$test->string_value());
					$CC5 = $test->string_value();
			}
			if($test->nodeName =~ m/NavExceptionDesc/ )
			{
					notice("NavExceptionDesc:".$test->string_value());
					$exp = $test->string_value();
			}
		
	}

		return $CC4,$CC5,$exp;

}

		
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Méthode de conversion de la date fournie par l'appel au webService BackOffice
# ~ Exemple : 31/12/2008 00:00:00
sub _convertDate_reverse {
  my $date = shift;

  my $month = substr($date, 5, 2);
  my $year  = substr($date, 2, 2);

  return $month.$year;
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
    'Customer'   => 'COMPANY',
	'customer'   => 'COMPANY',
    'cc'         => 'ENTITY', # check if upper case is needed
    'traveller'  => 'INDIV', # check if upper case is needed
	'Traveller'  => 'INDIV',
  };
  
  return $h_origin->{$origin};
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

1;
