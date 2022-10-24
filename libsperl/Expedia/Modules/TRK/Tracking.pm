package Expedia::Modules::TRK::Tracking;
#-----------------------------------------------------------------
# Package Expedia::Modules::TRK::Tracking
#
# $Id: Tracking.pm 410 2008-02-11 09:20:59Z pbressan $
#
# (c) 2002-2008 Expedia.                   www.expediacorporate.fr
#-----------------------------------------------------------------

use Data::Dumper;

use Expedia::Tools::Logger             qw(&debug &notice &warning &error);
use Expedia::Tools::GlobalFuncs        qw(&stringGdsOthers);
use Expedia::Databases::MidSchemaFuncs qw(&getQInfosForComCode);
use Expedia::WS::Back           qw(&GetTravelerCostCenter);
use Expedia::Tools::GlobalVars  qw($proxyNav);

sub run {
  my $self   = shift;
  my $params = shift;

  my $globalParams   = $params->{GlobalParams};
  my $moduleParams   = $params->{ModuleParams};
  my $changes        = $params->{Changes};
  my $item           = $params->{Item};
  my $pnr            = $params->{PNR};
  my $b              = $params->{ParsedXML};
  my $travellers     = $pnr->{Travellers};

    # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
    # Récupération du comCode dans le fichier XML
    my $comCode = $b->getPerComCode({trvPos => $b->getWhoIsMain});
    # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
    
    # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
    # Récupération des éléments paramétrés en BDD / Table QUEUE_PNR
    notice("COMCODE:".$comCode);
  	
    my $qInfos          = &getQInfosForComCode($comCode);
    
    my $destOfficeId    = $qInfos->{DestOfficeId};
    my $destQueue       = $qInfos->{DestQueue};
    my $securityElement = $qInfos->{SecurityElement};
    
    debug('destOfficeId    = '.$destOfficeId);
    debug('destQueue       = '.$destQueue);
    debug('securityElement = '.$securityElement);
    # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
    
	my $country = $params->{GlobalParams}->{market}  ; 
    # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
    # Récupération des "RM *PERCODES" présents dans le dossier
    my $perCode = '';
    foreach my $i (@{$pnr->{PNRData}}) {
      if ($i->{Data} =~ /^RM\s+\*PERCODE\s+(\d+)(\/P\d)?/) {
        $perCode= $1;
		last;
      }
    }
    # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

    my $ES = 'ES'.$securityElement;
    my $QE = 'QE/'.$destOfficeId.'/'.$destQueue;

    # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
    # Traveller Tracking
    
    # Delete old remarks
    my @oldRemarks = ();
    foreach (@{$pnr->{'PNRData'}}) {
      if ($_->{'Data'} =~ /^RM W-(COMCODE|MOBILE|EMAIL|EMPNUMBER|CC1|CC2|CC4|CC5):/) {
        push (@oldRemarks, $_->{'Data'});
        push (@{$changes->{del}}, $_->{'LineNo'});
      }
    }
    
    # Add new remarks
    my @newRemarks = ();
    push (@newRemarks, 'RM W-COMCODE:'.$comCode);
    foreach my $traveller (@$travellers) {
      my $paxNum = $traveller->{PaxNum};
      my $mobile = $traveller->{MobPhoneNo};
      my $email  = $traveller->{Email};
      my $empNum = $traveller->{EmployeeNo};
      my $ccUsed  = $b->getCcUsed({trvPos => $traveller->{Position}})->{CC1} || '';
      my $ccUsed2 = $b->getCcUsed({trvPos => $traveller->{Position}})->{CC2} || '';
      push (@newRemarks, 'RM W-MOBILE:'.$mobile.'/'.$paxNum)                if ($mobile ne '');
      push (@newRemarks, 'RM W-EMAIL:'.uc($email).'/'.$paxNum)              if ($email  ne '');
      push (@newRemarks, 'RM W-EMPNUMBER:'.$empNum.'/'.$paxNum)             if ($empNum ne '');
      push (@newRemarks, 'RM W-CC1:'.stringGdsOthers($ccUsed).'/'.$paxNum)  if ($ccUsed ne '');
      push (@newRemarks, 'RM W-CC2:'.stringGdsOthers($ccUsed2).'/'.$paxNum) if ($ccUsed2 ne '');
      
      #EGE-95102 -- add CC4 / CC5
      my ($CC4, $CC5,$EXP) = &GetTravelerCostCenter($proxyNav,$country,$comCode,$perCode);
      if($EXP ne '') 
      {
        notice("NAV EXPECTION:".$EXP);
      }
      else
      {
        push (@newRemarks, 'RM W-CC4:'.stringGdsOthers($CC4).'/'.$paxNum) if ($CC4 ne '');
        push (@newRemarks, 'RM W-CC5:'.stringGdsOthers($CC5).'/'.$paxNum) if ($CC5 ne '');
      }
    }
    foreach my $newRemark (@newRemarks) {
      push (@{$changes->{add}}, { Data => $newRemark });
    }
    # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

    # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
    # Queuing
    push (@{$changes->{add}}, { Data => $ES });
    push (@{$changes->{add}}, { Data => $QE });
    # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
    
    my $sep1 = ';';
    my $sep2 = ',';
    notice('Tracking PNR processing report'
           .$sep1.'PNR:'.$pnr->{'PNRId'}
           .$sep1.'COMCODE:'.$comCode
           .$sep1.'QUEUE:'.$QE
           .$sep1.'ES:'.$ES
           .$sep1.'OLD_REMARKS:'.join($sep2, @oldRemarks)
           .$sep1.'NEW_REMARKS:'.join($sep2, @newRemarks));
    
  return 1;
}

1;
