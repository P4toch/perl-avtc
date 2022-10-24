package Expedia::Modules::TAS::DoApVerif;
#-----------------------------------------------------------------
# Package Expedia::Modules::TAS::DoApVerif
#
# $Id: DoApVerif.pm 601 2010-08-10 13:25:48Z pbressan $
#
# (c) 2002-2007 Expedia.                   www.expediacorporate.fr
#-----------------------------------------------------------------

use strict;
use Data::Dumper;

use Expedia::Tools::Logger qw(&debug &notice &warning &error);
use Expedia::Tools::GlobalFuncs qw(&stringGdsPaxName);

sub run {
  my $self   = shift;
  my $params = shift;

  my $globalParams = $params->{GlobalParams};
  my $moduleParams = $params->{ModuleParams};
  my $changes      = $params->{Changes};
  my $item         = $params->{Item};
  my $pnr          = $params->{PNR};
  my $ab           = $params->{ParsedXML};

  my $atds = $ab->getAirTravelDossierStruct;
  my $market     = $ab->getCountryCode({trvPos => $ab->getWhoIsMain});

  my @add = ();
  my @del = ();
  my $WBMI = '';

   	my $ap_ok = 0;

	#search for APE
    foreach (@{$pnr->{'PNRData'}}) {
      my $line_data = $_->{'Data'};
      # debug('line_data = '.$line_data);
      if ($line_data =~ /^APE.*/o) {
  		  $ap_ok = 1 unless ($line_data =~ /^APE ETICKET_ARCHIVE/);
  	  }
  	  if ($line_data =~ /^APE VOTRE VALIDATEUR NOTILUS/) {
  	    $ap_ok = 0;
  	    last;
  	  }
    }
    
	#APE NOT FOUND 
    unless ($ap_ok) 
    {
        notice("APE MISSING -- Search for APE in the XML file");
        #EMAIL IS MISSING
        $ab = $params->{ParsedXML};
        my $travellers= $ab->getTravellerStruct;
        my $nbPaxXML     = scalar(@$travellers);
        debug(Dumper($travellers));
        my $booker = $ab->getBookerInfos;
        debug(Dumper($booker));

    	my $GDS    = $pnr->{_GDS};
    	my $add_mail_booker = 1;
    	my %h_mail_booker =();
    	my $email_traveller = '';
    	my $email_booker    = '';

    	# -------------------------------------------------------------
    	# <CAS 1> Il n'y a qu'un seul passager dans le dossier
    	if ($nbPaxXML == 1) 
    	{
        	$email_traveller = $travellers->[0]->{Email};
        	$email_booker    = $booker->{BookerEmail};

			#$email_traveller= 'c.perdriau@egencia.fr';
			#$booker->{BookerEmailMode}='NONE';
			#$travellers->[0]->{EmailMode}='NONE';
	
	  	    notice("email traveller:".$email_traveller);
	        notice("email booker:".$email_booker);
	        notice("booker mode:".$booker->{BookerEmailMode});
	        notice("traveller mode:".$travellers->[0]->{EmailMode});

	        if($travellers->[0]->{EmailMode} ne 'NONE' && $email_traveller !~ /tn.egencia.fr$/ )
	        {
	                $GDS->command(Command=>'APE-'.$email_traveller, NoIG=>1, NoMD=>1);
	                $add_mail_booker=0;
	                notice("add traveller email");
	        }
	
	        #check if traveller email and traveller booker are different
	        if(($email_booker ne $email_traveller || $add_mail_booker == 1) && $booker->{BookerEmailMode} ne 'NONE' && $email_booker !~ /tn.egencia.fr$/ )
	        {
	                $GDS->command(Command=>'APE-'.$email_booker, NoIG=>1, NoMD=>1);
	                notice("add booker email");
	        }

            # ---------------------------------------------------------------------
            # Validation des modifications
            $GDS->command(Command=>'RF'.$GDS->modifsig, NoIG=>1, NoMD=>1);
            $GDS->command(Command=>'ER',                NoIG=>1, NoMD=>1);
            $GDS->command(Command=>'ER',                NoIG=>1, NoMD=>1);
            # ---------------------------------------------------------------------
    }
    # -------------------------------------------------------------
    # <CAS 2> MultiPax

    elsif ($nbPaxXML> 1) 
    {

		my $paxNum = 0;
        $email_booker    = $booker->{BookerEmail};

        #we add the booker, he has the priority
        if($booker->{BookerEmailMode} ne 'NONE' && $email_booker !~ /tn.egencia.fr$/ )
        {
			$GDS->command(Command=>'APE-'.$email_booker, NoIG=>1, NoMD=>1);
            notice("add booker email");
            $h_mail_booker{$email_booker}=1;
        }

      	PNRPAX: foreach my $pnrPax (@{$pnr->{PAX}}) {

        $paxNum++;

        my $pnrLastName;
        my $pnrFirstName;

        if (($pnrPax->{'Data'} =~ /^(.*)\/(.*[^\(])(\(.*)$/) ||
            ($pnrPax->{'Data'} =~ /^(.*)\/(.*)$/)) {
          $pnrLastName  = $1;
          $pnrFirstName = $2;
          $_ = stringGdsPaxName($_, $market) foreach ($pnrFirstName, $pnrLastName);
          debug("pnrFirstName = $pnrFirstName.");
          debug("pnrLastName  = $pnrLastName.");

          XMLPAX: foreach my $xmlPax (@$travellers) {

            next XMLPAX if (exists $xmlPax->{PaxNum});

            my $xmlFirstName = $xmlPax->{FirstName}.' '.$xmlPax->{AmadeusTitle};
            my $xmlLastName  = $xmlPax->{LastName};
            $_ = stringGdsPaxName($_, $market) foreach ($xmlFirstName, $xmlLastName);
            debug("xmlFirstName = $xmlFirstName.");
            debug("xmlLastName  = $xmlLastName.");

            next XMLPAX unless ($pnrFirstName eq $xmlFirstName);
            next XMLPAX unless ($pnrLastName  eq $xmlLastName);

            $xmlPax->{PaxNum}    = 'P'.$paxNum;
            $pnrPax->{PerCode}   = $xmlPax->{PerCode};
            $pnrPax->{Position}  = $xmlPax->{Position};
            $xmlPax->{FIRSTNAME} = $pnrFirstName;
            $xmlPax->{LASTNAME}  = $pnrLastName;

			debug(Dumper($xmlPax));
			debug(Dumper($pnrPax));
            $email_traveller = $travellers->[$xmlPax->{Position}]->{Email};

			#$email_traveller= 'c.perdriau@egencia.fr';
			#$booker->{BookerEmailMode}='NONE';
			#$travellers->[0]->{EmailMode}='NONE';

	        notice("email traveller:".$email_traveller);
	        notice("email booker:".$email_booker);
	        notice("booker mode:".$booker->{BookerEmailMode});
	        notice("traveller mode:".$travellers->[$xmlPax->{Position}]->{EmailMode});
	
	        if(!exists($h_mail_booker{$email_traveller}) && $travellers->[$xmlPax->{Position}]->{EmailMode} ne 'NONE' && $email_traveller !~ /tn.egencia.fr$/ )
	        {
	                $GDS->command(Command=>'APE-'.$email_traveller.'/'.$xmlPax->{PaxNum}, NoIG=>1, NoMD=>1);
	                notice("add traveller email");
	        }
	
	            last XMLPAX;
	          } # Fin XMLPAX: foreach (@$travellers)
	
	        }
	        else {
	          notice("Pax LineNo = '".$pnrPax->{'LineNo'}."' doesn't match regexp !");
	          debug ("Pax Data   = '".$pnrPax->{'Data'}."'.");
	          return 0;
	        }

      } # Fin PNRPAX: foreach my $pnrPax (@{$pnr->{PAX}})

          # ---------------------------------------------------------------------
          # Validation des modifications
          $GDS->command(Command=>'RF'.$GDS->modifsig, NoIG=>1, NoMD=>1);
          $GDS->command(Command=>'ER',                NoIG=>1, NoMD=>1);
          $GDS->command(Command=>'ER',                NoIG=>1, NoMD=>1);
          # ---------------------------------------------------------------------

    } #fin pax > 1
    
    #reload the Pnr to check if the APE are still missing
    # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
    # Vérification que le PNR existe encore dans AMADEUS.
    my $PNR_tmp = Expedia::GDS::PNR->new(PNR => $item->{PNR}, GDS => $GDS);
    if (!defined $PNR_tmp) 
    {
        notice("Could not read PNR '".$item->{PNR}."' from GDS.");
    }
    my $pnr_tmp = $PNR_tmp;

	#check for new APE
    foreach (@{$pnr_tmp->{'PNRData'}}) 
    {
      my $line_data = $_->{'Data'};
      if ($line_data =~ /^APE.*/o) {
		notice($line_data);
                  $ap_ok = 1 unless ($line_data =~ /^APE ETICKET_ARCHIVE/);
          }
          if ($line_data =~ /^APE VOTRE VALIDATEUR NOTILUS/) {
            $ap_ok = 0;
            last;
          }
    }

	#if no APE again , then error 
  	unless ($ap_ok) {
      debug("### TAS MSG TREATMENT 14 ###");
  	  $pnr->{TAS_ERROR} = 14;
      return 1;
  	}

    } #fin premier unless

  return 1;  
}

1;
