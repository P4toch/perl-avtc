#!/usr/bin/perl

use strict;
use Data::Dumper;
use lib '/var/egencia/libsperl';

use Expedia::XML::Config;
use Expedia::Tools::GlobalVars qw($cnxMgr $proxyBack $proxyBackBis $hashWSLogin $cds_hours);
use Expedia::Databases::ConnectionsManager;
use Expedia::XML::Config;
use Expedia::WS::Front qw(changeDeliveryState);
use Expedia::Tools::TasFuncs qw(soapProblems);
use Expedia::Tools::Logger qw(&debug &notice &warning &error);







my $task="btc-air-FR";
my $config        = Expedia::XML::Config->new('/var/egencia/libsperl/Expedia/Tools/config_DDB.xml',$task);
my $dbh      = $cnxMgr->getConnectionByName('mid');
my $error_status=0;
my $query= " SELECT DELIVERY_ID,DELIVERY_STATUS,PNR,COUNTRY,PRODUCT,CREATION_DATE
             FROM MIDADMIN.CHANGE_DELIVERY_STATE
             WHERE IN_ERROR= ?";
my  $finalRes = $dbh->saarBind($query, [$error_status]);

foreach (@$finalRes) {

        my $deliveryID = $_->[0];
        my $deliveryStatus =  $_->[1];
        my $pnrId = $_->[2];
        my $country = $_->[3];
        my $product = $_->[4];
        my $creation_date = $_->[5];
        my $soapOut = undef;
        $soapOut = changeDeliveryState('DeliveryWS', {deliveryId => $deliveryID, deliveryStatus => $deliveryStatus});

        if (!defined($soapOut)) {
                       notice('soapRetry: PNR = $pnrId / UPDATE = ERROR');

        } else {
                       notice("soapRetry: PNR = $pnrId / UPDATE = OK");
                       my $delete_query = "DELETE FROM MIDADMIN.CHANGE_DELIVERY_STATE
                                           WHERE DELIVERY_ID= ? AND DELIVERY_STATUS= ? AND PNR= ?" ;
                       my $rows  = $dbh->doBind($delete_query, [$deliveryID, $deliveryStatus, $pnrId]);
                       warning('Problem detected !') if ((!defined $rows) || ($rows < 1));

       }


}



my $query_problems= "SELECT DELIVERY_ID,DELIVERY_STATUS,PNR,COUNTRY,PRODUCT,TAS_CODE,CREATION_DATE
                     FROM MIDADMIN.CHANGE_DELIVERY_STATE
                     WHERE CREATION_DATE < DATEADD(HOUR,CONVERT(INT,?), GETDATE()) AND IN_ERROR= ?" ;
my  $Res = $dbh->saarBind($query_problems, [$cds_hours, $error_status]);
my $soap_errors;
foreach (@$Res) {


        my $deliveryID = $_->[0];
        my $deliveryStatus =  $_->[1];
        my $pnrId = $_->[2];
        my $country = $_->[3];
        my $product = $_->[4];
        my $tas_code = $_->[5];
        my $creation_date = $_->[6];
        my $task = undef;

   
		push (@{$soap_errors->{$country}->{$product}->{$tas_code}},$pnrId);
		
        
        my $update_query="UPDATE MIDADMIN.CHANGE_DELIVERY_STATE
                          SET IN_ERROR=1
                          WHERE DELIVERY_ID= ? AND DELIVERY_STATUS= ? AND PNR= ?";
        my $rows = $dbh->doBind($update_query, [$deliveryID, $deliveryStatus, $pnrId]);
        warning('Problem detected !') if ((!defined $rows) || ($rows != 1));		

}



### Send the mail only by country and by product 
 my $task = undef;
foreach my $pos (keys (%$soap_errors)) {
        foreach my $produit (keys (%{$soap_errors->{$pos}})){

                &soapProblems($task,$pos,$produit,$soap_errors->{$pos}->{$produit});

        }
}

