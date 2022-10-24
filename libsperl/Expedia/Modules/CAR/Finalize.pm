package Expedia::Modules::CAR::Finalize;
#-----------------------------------------------------------------
# Package Expedia::Modules::CAR::Finalize
#
# $Id: Finalize.pm 608 2010-12-14 13:27:03Z pbressan $
#
# (c) 2002-2008 Expedia.                   www.expediacorporate.fr
#-----------------------------------------------------------------

use Data::Dumper;

use Expedia::Tools::Logger qw(&debug &notice &warning &error);
use Expedia::Tools::GlobalFuncs qw(&stringGdsOthers &stringGdsPaxName);
use Expedia::Tools::GlobalVars qw($h_AmaMonths);

sub run {
  my $self   = shift;
  my $params = shift;

  my $globalParams 		= $params->{GlobalParams};
  my $moduleParams 		= $params->{ModuleParams};
  my $changes      		= $params->{Changes};
  my $item         		= $params->{Item};
  my $pnr          		= $params->{PNR};
  my $ab           		= $params->{ParsedXML};
  my $GDS          		= $params->{GDS};
  
  my $btccarp		= 0;
  my $ir			= 0;
  
  # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
  # On commence par recharger le PNR
  $pnr->reload;
  # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
  
  # Suppression des anciennes lignes RM @@ BTC-AIR PROCEED @@
  foreach (@{$pnr->{PNRData}}) {
  	if ($_->{'Data'} =~ /BTC-CAR PROCEED/) {
      		$btccarp = 1;
      		last;
    }
  }

  if($btccarp != 0)
  {
  	notice('BTC CAR already proceed.');
  	return 1;	
  }
  
  my $ctds         = $ab->getDriverStruct;   
  notice("ATDS:".Dumper($ctds));

  my $nbPax        = scalar @$ctds;


  if($nbPax == 0)
  {
  	notice('No driver information founded in XML booking !');
  	return 1;
  }
  else
  {
  	
  #ADD THE METADDOSIER IF NOT EXISTS   
   unless ( grep { $_->{Data} =~ /RM \*METADOSSIER/ } @{$pnr->{PNRData}} ) {
               $lines    = $GDS->command(Command => 'RM *METADOSSIER '.$params->{ParsedXML}->getMdCode, NoIG => 1, NoMD => 0); 
    }
    
  # ______________________________________________________________
  my $market= $ab->getCountryCode({trvPos => $ab->getWhoIsMain });
  notice("MARKET:".$market);
  my $CCR_POS='';
  my $APB='';
  my $NUM_PAX_MAIN='';
  my $COUNT_ERROR=0;

while($COUNT_ERROR == 0)
{
   foreach (@{$pnr->{PNRData}}) 
   {
    if ($_->{'Data'} =~ /CCR\s.*/) 
    {
      notice("CRR:".$_->{'LineNo'});
      $CRR_POS=$_->{'LineNo'};
      $command=$_->{'LineNo'}."/**-DELCOL";
      $lines    = $GDS->command(Command => $command, NoIG => 1, NoMD => 0); 
    }
    if($_->{'Data'} =~ /APB\s(.*)/)
    {
       $APB=$1; 
    }

   } #end foreach 


      notice(Dumper($lines));
  	#MAIN DRIVER
	my $position = 0;
   	my $M_FirstName = $ctds->[$position]->{M_FirstName};
   	my $M_LastName = $ctds->[$position]->{M_LastName};
   	my $M_DateOfBirth = $ctds->[$position]->{M_DateOfBirth};
   	my $M_PlaceOfBirth = $ctds->[$position]->{M_PlaceOfBirth};
   	my $M_DrivingLicenceIssueDate= $ctds->[$position]->{M_DrivingLicenceIssueDate};
   	my $M_DrivingLicenceNumber= $ctds->[$position]->{M_DrivingLicenceNumber};
   	my $M_DrivingLicenceIssuePlace= $ctds->[$position]->{M_DrivingLicenceIssuePlace};
   	my $M_DrivingLicenceIssueCountry = $ctds->[$position]->{M_DrivingLicenceIssueCountry};
        #COMPLEMENTARY INFORMATION
        my $DeliveryContactInstructions     =  $ctds->[$position]->{DeliveryContactInstructions}; 
        my $CollectionContactInstructions   =  $ctds->[$position]->{CollectionContactInstructions};
        my $PickUpInformationCode =  $ctds->[$position]->{PickUpInformationCode};
        my $DeliveryContactName =  $ctds->[$position]->{DeliveryContactName};
        my $CollectionContactName=  $ctds->[$position]->{CollectionContactName};
        
  	#SECOND DRIVER
	   $position = 1;
   	my $S_FirstName = $ctds->[$position]->{S_FirstName};
   	my $S_LastName = $ctds->[$position]->{S_LastName};
   	my $S_DateOfBirth = $ctds->[$position]->{S_DateOfBirth};
   	my $S_PlaceOfBirth = $ctds->[$position]->{S_PlaceOfBirth};
   	my $S_DrivingLicenceIssueDate= $ctds->[$position]->{S_DrivingLicenceIssueDate};
   	my $S_DrivingLicenceNumber= $ctds->[$position]->{S_DrivingLicenceNumber};
   	my $S_DrivingLicenceIssuePlace= $ctds->[$position]->{S_DrivingLicenceIssuePlace};
   	my $S_DrivingLicenceIssueCountry = $ctds->[$position]->{S_DrivingLicenceIssueCountry};
        my $S_TravelerLoyaltyNumber		= $ctds->[$position]->{S_TravelerLoyaltyNumber}; 	

        if(defined($M_DateOfBirth) && $M_DateOfBirth ne ''){
        my ($locYear, $locMonth, $locDay) = ($M_DateOfBirth =~ /(\d{4})-(\d{2})-(\d{2})/);
        $M_DateOfBirth = $locDay.$h_AmaMonths->{$locMonth}.$locYear;}

        if(defined($M_DrivingLicenceIssueDate) && $M_DrivingLicenceIssueDate ne ''){
        my ($locYear, $locMonth, $locDay) = ($M_DrivingLicenceIssueDate=~ /(\d{4})-(\d{2})-(\d{2})/);
        $M_DrivingLicenceIssueDate= $locDay.$h_AmaMonths->{$locMonth}.$locYear;}

        if(defined($S_DateOfBirth) && $S_DateOfBirth ne ''){
        my ($locYear, $locMonth, $locDay) = ($S_DateOfBirth =~ /(\d{4})-(\d{2})-(\d{2})/);
        $S_DateOfBirth = $locDay.$h_AmaMonths->{$locMonth}.$locYear;}

        if(defined($S_DrivingLicenceIssueDate) && $S_DrivingLicenceIssueDate ne ''){
        my ($locYear, $locMonth, $locDay) = ($S_DrivingLicenceIssueDate=~ /(\d{4})-(\d{2})-(\d{2})/);
        $S_DrivingLicenceIssueDate= $locDay.$h_AmaMonths->{$locMonth}.$locYear;}

	if(!defined($M_FirstName) && !defined($M_LastName) && !defined($M_DateOfBirth) && !defined($M_PlaceOfBirth) && !defined($M_DrivingLicenceIssueDate) && !defined($M_DrivingLicenceNumber) && !defined($M_DrivingLicenceIssuePlace) && !defined($M_DrivingLicenceIssueCountry))
        { return 1; }

$lab1= {
	'FRA'	=> '2ND CONDUCTEUR',
	'ALL'	=> '2ND DRIVER',
};

$lab2= {
	'FRA'	=> 'CARTE LOUEUR',
	'ALL'	=> 'LOYALTY CARD',
};

$lab3= {
	'FRA'	=> 'NE(E) LE',
	'ALL'	=> 'BORN ON',
};

$lab4= {
	'FRA'	=> 'A',
	'ALL'	=> 'IN',
};

$lab5= {
	'FRA'	=> 'NUM PERMIS CONDUIRE',
	'ALL'	=> 'DRIVING LICENSE NB',
};

$lab6= {
	'FRA'	=> 'DELIVRE LE',
	'ALL'	=> 'ISSUED ON',
};

	if($PickUpInformationCode !~ /FRA/){$PickUpInformationCode='ALL';}

   #Search for the segement number associate to the pax name 
   #foreach (@{$pnr->{PAX}})
   #{
   # if ($_->{'Data'} =~ /(.*)\/(.*)/)
   # {
   #		notice("NOM:".$1);
   #     notice("PRENOM:".$2);
   #     notice("M FIRST:".$M_FirstName);
   #     notice("M LAST:".$M_LastName);
   #     if(uc($2) eq  stringGdsPaxName(uc($M_FirstName),$market) && uc($1) eq  stringGdsPaxName(uc($M_LastName),$market))
   #	{ 
#	   $NUM_PAX_MAIN=$_->{'LineNo'};
#	}	
#    }
#   }
  
#   if($NUM_PAX_MAIN eq '')
#   {
#	notice("Cannot associate traveller with the main driver");
#	return 1;
#   }

	    $command="APA-".$APB;
        $lines    = $GDS->command(Command => $command, NoIG => 1, NoMD => 0); 

	    $command="RM DC DL-".$M_DrivingLicenceIssueCountry.",".$M_DrivingLicenceNumber.",".$M_DrivingLicenceIssueDate.", ,".$M_DrivingLicenceIssuePlace.",".$M_DateOfBirth.",".$M_PlaceOfBirth."/S".$CRR_POS."/P1"; #.$NUM_PAX_MAIN;
        $lines    = $GDS->command(Command => $command, NoIG => 1, NoMD => 0); 

        $command="RM DC DEL INSTR-CONTACT ".$DeliveryContactName."/".$DeliveryContactInstructions."/S".$CRR_POS;
        $lines    = $GDS->command(Command => $command, NoIG => 1, NoMD => 0);

        $command="RM DC COL INSTR-CONTACT ".$CollectionContactName."/".$CollectionContactInstructions."/S".$CRR_POS;
        $lines    = $GDS->command(Command => $command, NoIG => 1, NoMD => 0);
        notice(Dumper($lines));

	if($S_FirstName ne '')
	{
        $command="RM DC MIS-".$lab1->{$PickUpInformationCode}.":".$S_FirstName." ".$S_LastName."/".$lab2->{$PickUpInformationCode}.":".$S_TravelerLoyaltyNumber."/".$lab3->{$PickUpInformationCode}." ".$S_DateOfBirth." ".$lab4->{$PickUpInformationCode}." ".$S_PlaceOfBirth."/S".$CRR_POS;
        $lines    = $GDS->command(Command => $command, NoIG => 1, NoMD => 0); 

        $command="RM DC MIS-".$lab5->{$PickUpInformationCode}.":".$S_DrivingLicenceNumber."/".$lab6->{$PickUpInformationCode}." ".$S_DrivingLicenceIssueDate." ".$lab4->{$PickUpInformationCode}." ".$S_DrivingLicenceIssuePlace."/".$S_DrivingLicenceIssueCountry."/S".$CRR_POS;
        $lines    = $GDS->command(Command => $command, NoIG => 1, NoMD => 0); 
	}

        $GDS->command(Command => 'RM @@ BTC-CAR PROCEED @@', NoIG => 1, NoMD => 1); #add this remark to not retreated this booking after
        
        $GDS->command(Command => 'RF'.$GDS->modifsig, NoIG => 1, NoMD => 1);
        $ET = $GDS->command(Command => 'ET', NoIG => 1, NoMD => 1);
        if (grep(/(FIN|END) (DE|OF) (TRANSACTION|TRANSACCION)/, @$ET)) {
			$COUNT_ERROR++; # for leave the while
			notice("End of process:".@ET);
        	last;
        }
        else 
        {
        	if($ir == 1){
        		notice("Already retried, stop processing:".$ET);
        		return 1;
        	}
        	else
        	{
        		$GDS->command(Command => 'IR', NoIG => 1, NoMD => 1); # IR + not increasing the counter. Redo the script on this PNR
        		notice("Procees not successfully, retried:".$ET);
        		$ir++;
        	}
        }
  }#end else

  return 1;  
}

}

1;

