package Expedia::WS::Commun;

use Exporter 'import';
use SOAP::Lite;
use Data::Dumper;
use POSIX qw(strftime);

use Expedia::Tools::Logger qw(&debug &notice &warning &error);
use Expedia::Tools::GlobalVars qw($urlToken $authorizationToken $configServiceURL $fbsTicketingURL $claimURL $tssBookingsURL $quality_control_serviceURL);
use Expedia::XML::MsgGenerator;

@EXPORT_OK = qw(&ticketingIssue &isAuthorize &claim &getTssRecLoc &isAuthorize_repricing &quality_control_service &getPnrAndTstInXml &getToken &isAuthorize_LC);

use JSON;
use strict;

sub isAuthorize_repricing {
	my $configName = shift;
	my $pos = shift;
	my $comCode = shift;
	my $listPosComCode = getConfigService($configName);


	debug("POS:".$pos);
	debug("comCode:".$comCode);
	my $stripes='';
	my $result='';
	my $x=0;
	my $config_pos='';
	my $config_comcode='';
	my $isFound=0;
	my $isFoundPos=0;
	my $isFoundComcode=0;
	my $saveRes='';

	while(1)
	{
		$stripes= $listPosComCode->{'values'}->[$x]->{'stripes'};
		$result= $listPosComCode->{'values'}->[$x]->{'value'};
		debug("VAL:".Dumper($stripes));
		debug("RES:".Dumper($result));

		$config_pos= $listPosComCode->{'values'}->[$x]->{'stripes'}->{tpid};
		$config_comcode= $listPosComCode->{'values'}->[$x]->{'stripes'}->{comcode};

		# search by tpid
		foreach my $element_pos (@$config_pos)
		{
			if($element_pos eq $pos){
				if($config_comcode eq "")
				{
					$isFound = 1;
					notice("ACTIVATION TPID:".$element_pos);
					last;
				}
				else
				{
					foreach my $element_comcode (@$config_comcode)
					{
						if($element_comcode eq $comCode)
						{
							$isFound = 1;
							notice("ACTIVATION TPID:".$element_pos." AND COMCODE:".$element_comcode);
							last;
						}
					}
				}
			}
		}

		$x++;

		if(!$stripes|| $stripes eq 'undef')
		{
			last;
		}
		
	} #end while 

    return $isFound;
}


sub quality_control_service{
        my $pnr                 = shift;
        my $tpid                = shift;
        my $gpid                = shift;
        my $account_code        = shift;

        my $req = HTTP::Request->new(PUT => $quality_control_serviceURL.'v1/tpid/'.$tpid.'/pnr/'.$pnr.'/check');

        $req->content_type('application/json');
        $req->content('{"comcode": "'.$gpid.'","corporateCode":"'.$account_code.'"}');
		debug("REQ:".Dumper($req));
        my $ua = LWP::UserAgent->new;
        my $resp = $ua->request($req);
        my $messageFormated = $resp->decoded_content;
		debug("FORMATED:".Dumper($messageFormated));
        return  decode_json $messageFormated;
}


sub getPnrAndTstInXml{
	my $tpid = shift;
	my $pnr  = shift;

	my $req = HTTP::Request->new(GET => $quality_control_serviceURL.'v1/tpid/'.$tpid.'/pnr/'.$pnr);
	$req->header('Accept' => 'application/xml');
	debug('Request:'.Dumper($req));
	my $ua = LWP::UserAgent->new;
	my $resp = $ua->request($req);
	my $decodedContent = $resp->decoded_content;
	debug('Response content:'.Dumper($decodedContent));
	return $decodedContent;
}


sub getTssRecLoc {

   my $token = shift;	
      
   my $req = HTTP::Request->new(POST => $tssBookingsURL);	
   $req->header('Authorization' => 'Bearer '.$token);
   $req->content_type('application/json');
   my $ua = LWP::UserAgent->new;
   my $resp = $ua->request($req);
   my $messageFormated = $resp->decoded_content;
   return decode_json $messageFormated;
} 

sub claim {
	my $recLoc 	   	= shift;
	my $pnr	   		= shift;
	my $reference   = shift;
	my $metadossier = shift;
	my $percode     = shift;
	my $DossierPnr  = shift;
	my $token 	   	= shift;
   
	my $listOfPnrs = "";
	if($DossierPnr =~ /,/){
        my @DosPNRs = split(/,/,$DossierPnr);
        my $pnrs = '';
        foreach my $opnr (@DosPNRs) {
			if($opnr ne $pnr){
				$pnrs = $pnrs.' '.uc($opnr);
			}
        }
		$listOfPnrs = ', "@@ PNR LIES'.$pnrs.' @@"';
	}

	my $req = HTTP::Request->new(POST => $claimURL.$recLoc.'/claim');
	$req->header('Authorization' => 'Bearer '.$token);
	$req->content_type('application/json');
	$req->content('{"supplier_reference" : "'.$pnr.'", "remarks" : ["* BOOKSOURCE WEB", "* METADOSSIER '.$metadossier.'", "* PERCODE '.$percode.'"'.$listOfPnrs.']}');

	my $ua = LWP::UserAgent->new;
	my $resp = $ua->request($req);
	my $messageFormated = $resp->decoded_content;
	return  decode_json $messageFormated;
} 

sub ticketingIssue {
	my $pnr       		= shift;
	my $tpid      		= shift;
	my $gpid      		= shift;
	my $type      		= shift;
	my $reference 		= shift;

	my $req = HTTP::Request->new(POST => $fbsTicketingURL.$pnr.'/issue');

	$req->content_type('application/json');
	$req->content('{"tpid": '.$tpid.', "gpid": '.$gpid.' ,"type": "'.$type.'", "reference" : "'.$reference.'"}');

	my $ua = LWP::UserAgent->new;
	my $resp = $ua->request($req);
	my $messageFormated = $resp->decoded_content;
	return  decode_json $messageFormated;
}

sub isAuthorize_LC {
	my $configName = shift;

	my $x=0;
	my $listLC = getConfigService($configName);
	my $airline='';
	my $stripes='';
	my %h_airline={};
	my @results=();

	while(1)
	{
		$stripes = $listLC->{'values'}->[$x]->{'stripes'};
		$airline = $listLC->{'values'}->[$x]->{'value'} if($listLC->{'values'}->[$x]->{'value'} ne 'undef' || $listLC->{'values'}->[$x]->{'value'} ne '[]');

		foreach my $value (@$airline)
		{
			if(!exists($h_airline{$value}) && $value ne '')
			{
				$h_airline{$value}=$value;
				push @results, { AIRLINE  => $value };
			}
		}

		if(!$stripes || $stripes eq 'undef')
		{
			last;
		}
		
		$x++;
	}
	
	return \@results;
}


sub isAuthorize {
	my $configName = shift;
	my $pos = shift;
	my $comCode = shift;

	my $listPosComCode = getConfigService($configName);

	my $isFound = 0;
	if($listPosComCode->{'values'}->[0]->{'value'}->{$pos}->{'comcode'}->[0] eq 'ALL'){
		$isFound = 1;
	}
	else{
		my $rec = $listPosComCode->{'values'}->[0]->{'value'}->{$pos}->{'comcode'};
        foreach my $element (@$rec){
            if($element eq $comCode){
                $isFound = 1;
            }
        }
    }
    return $isFound;
}

sub getConfigService {
	my $configName = shift;

	my $token = getToken();
	my $req = HTTP::Request->new(GET => $configServiceURL.$configName);

	$req->header('Authorization' => 'Bearer '.$token);
	$req->content_type('application/json');

	my $ua = LWP::UserAgent->new;
	my $resp = $ua->request($req);
	my $messageFormated = $resp->decoded_content;
	return  decode_json $messageFormated;
}

sub getToken {
    my $req = HTTP::Request->new(POST => $urlToken);
    $req->header('Authorization' => 'Basic '.$authorizationToken);
    $req->content_type('application/x-www-form-urlencoded');
    $req->content('grant_type=client_credentials');

    my $ua = LWP::UserAgent->new;
    debug('Start request to auth service to get token');
    my $resp = $ua->request($req);
    if ($resp->is_success) {
        my $message = $resp->decoded_content;
        $message = decode_json $message;
        $resp = $message->{'access_token'};
        debug('Success getting auth token');
    } else {
        error('ERROR getting auth token : code='.$resp->code.', message='.$resp->message);
        $resp = undef;
    }
    return $resp;
}
