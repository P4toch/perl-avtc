package Expedia::Databases::Cryptic;

use File::Slurp;
use Data::Dumper;

use Expedia::Tools::Logger     qw(&debug &notice &warning &error);
use Expedia::Tools::GlobalVars qw($urlToken $authorizationToken $authToken $crypticURL);
use Expedia::WS::Commun        qw(&getToken);

use HTTP::Request;
use LWP::UserAgent;
use JSON;
use String::Util;

use Exporter 'import';
@EXPORT_OK = qw(&getConversationID &executeCrypticCommand &closeConnection);

my $contextPnrId = undef;

sub setCommonHeaders {
    my $req  = shift;
    
    my $clientName = $0;
    $clientName =~ s/^\.\/|\.pl$//ig;
    
    $req->header('Authorization' => 'Bearer '.$authToken);
    $req->header('client-name' => $clientName);
    
    return 1;
}

# A function to get new conversationID
sub getConversationID {
    my $oid = shift;
    
    # Override to use the following OID because we don't have rights on XXXXX38DD OIDs
    # $oid = 'PAREC3100';
    
    my $ua = LWP::UserAgent->new;
    my $response = undef;

    # Renew auth token
    $authToken = getToken();

    debug("Start requesting Cryptic service to get a conversation...");
    my $req = HTTP::Request->new(POST => $crypticURL);

    # Set headers and body
    setCommonHeaders($req);
    $req->content_type('application/json');
    $req->content('{"oid":"'.$oid.'"}');

    # Get the response and handle it
    my $resp = $ua->request($req);

    if ($resp->is_success) {
        $response =$resp->decoded_content;
        $response = String::Util::unquote($response);
        debug("Success getting a conversationID : ".$response);
    }
    else{
        error("Error when calling Cryptic service to get a conversation id...");
    }
    return $response;
}

# A function to execute one cryptic command
sub executeCrypticCommand {
    my $oid  = shift;
    my $wcmd = shift;
    my $conversationID = shift;
    
    # Override to use the following OID because we don't have rights on XXXXX38DD OIDs
    # $oid = 'PAREC3100';
    
    if ($wcmd =~ /^RT(.+)/) {
        $contextPnrId = $1;
    }
    
    my $response = undef;
    my $ua = LWP::UserAgent->new;

    my $req = HTTP::Request->new(PUT => $crypticURL);
    # Set headers and body
    setCommonHeaders($req);
    $req->content_type('application/json');
    
    my $contextBody = ',"oid":"'.$oid.'"';
    if (defined $contextPnrId) {
        $contextBody .= ',"pnrId":"'.$contextPnrId.'"';
    }
    $req->content('{"command":"'.$wcmd.'","conversationID":"'.$conversationID.'"'.$contextBody.'}');

    debug("Start requesting Cryptic service to execute the command : " .$wcmd);
    my $resp = $ua->request($req);

    if ($resp->is_success) {
        my $messageFormated = $resp->decoded_content;
        debug('Success executing the command '.$wcmd.'. Response is :  '.$messageFormated );
        $response = decode_json $messageFormated;
        $response = $response->{'command_reply_lst'}[0]->{'reply'};
    }
    else {
        error('Error calling Cryptic service for executing the command : '.$wcmd);
    }

    #my @lines= split /\n/, $response;
    #delete the last element because it contain white space
    #pop @lines;
    #$response = \@lines;
    $response =~ s/\/\$?//;
    
    if ($wcmd =~ /^(IG|ET)/) {
        $contextPnrId = undef;
    }
    
    return $response;
}

# A function to close a conversation based on indicated conversationId
sub closeConnection {
    my $conversationId = shift;
    
    my $response = undef;
    my $ua = LWP::UserAgent->new;

    my $req = HTTP::Request->new(DELETE => $crypticURL.'/'.$conversationId);

    # Set headers
    setCommonHeaders($req);

    debug("Start requesting Cryptic service to end the conversation : " .$conversationId);
    my $resp = $ua->request($req);

    if ($resp->is_success) {
        my $messageFormated = $resp->decoded_content;
        $response = $messageFormated;
        debug('Success ending the conversation:  '.$conversationId);
    }
    else{
        error('Error ending the conversation : '.$conversationId);
    }

    return $response;
}
1;

