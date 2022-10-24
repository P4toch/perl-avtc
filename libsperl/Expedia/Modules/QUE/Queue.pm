package Expedia::Modules::QUE::Queue;
#-----------------------------------------------------------------
# Package Expedia::Modules::QUE::Queue
#
# $Id: Queue.pm 589 2010-07-21 08:53:20Z pbressan $
#
# (c) 2002-2008 Expedia.                   www.expediacorporate.fr
#-----------------------------------------------------------------

use strict;
use Data::Dumper;

use Expedia::GDS::PNR;
use Expedia::Tools::Logger             qw(&debug &notice &warning &error);
use Expedia::Tools::GlobalVars         qw($cnxMgr);
use Expedia::Tools::GlobalFuncs        qw(&stringGdsOthers &getNavisionConnForAllCountry &setNavisionConnection);
use Expedia::Databases::MidSchemaFuncs qw(&updateTravellerTrackingNavisionDate &getQInfosAllMarkets &getNavCountrybycountry);
use Expedia::Tools::GlobalVars  qw($proxyNav);
use Expedia::WS::Back           qw(&GetTravelerCostCenter);

sub run {
  my $self   = shift;
  my $params = shift;

  my $globalParams = $params->{GlobalParams};
  my $moduleParams = $params->{ModuleParams};
  my $GDS          = $params->{GDS};
  my $market       = $params->{MARKET};
  my $task         = $params->{TaskName};
  
  #our use to transfert the variable to the others package
  our $log_id= '';
  
  my $dbh = $cnxMgr->getConnectionByName('navision');
  
  #Get the connexion information by country
  my $nav_conn = &getNavisionConnForAllCountry();
  
  #Get the complete name of the market
  my $country = &getNavCountrybycountry($market);
  
  #Set the nav connexion 
  &setNavisionConnection($country,$nav_conn,$task);
 	
  #Get all the information by Company for the market
  my $h_q = &getQInfosAllMarkets($market);

  my $dbh = $cnxMgr->getConnectionByName('navision');
  
  my $sauv_Seq  = undef;
  
  foreach my $ttCompany (@$h_q) {
  
    # __________________________________________________________
    # Récupération des éléments relatifs à cette exécution
    #my $id              = $ttCompany->{'Id'};
    my $comCode         = $ttCompany->{'ComCode'};
    my $comName         = $ttCompany->{'ComName'};
    my $country         = $ttCompany->{'Country'};
    my $destQueue       = $ttCompany->{'DestQueue'};
    my $destOfficeId    = $ttCompany->{'DestOfficeId'};
    my $securityElement = $ttCompany->{'SecurityElement'};
    my $seqNum          = $ttCompany->{'NavisionDate'};
    my $seqNum2nav      = $ttCompany->{'NavisionDate2nav'};
    my $newSeqNum       = $seqNum2nav;
    
    debug('comCode         = '.$comCode);
    debug('country         = '.$country);
    debug('destQueue       = '.$destQueue);
    debug('destOfficeId    = '.$destOfficeId);
    debug('securityElement = '.$securityElement);
    debug('seqNum          = '.$seqNum);

    notice('_______________________________________________________________');
    notice(" Queuing for Company '$comName' - $country");
    notice('_______________________________________________________________');
    # __________________________________________________________
  
    # __________________________________________________________
    # Récupération des nouveaux éléments à traiter
    
    my $query = "
  		SELECT [ID 2] PNRID,
             MAX(CONVERT(CHAR(17),RTRIM(CONVERT(CHAR,[Creation date],112))+' '+CONVERT(CHAR,[Creation Time],14))) ID,
             MAX(CONVERT(CHAR(17),RTRIM(CONVERT(CHAR,[Creation date],112))+REPLACE(CONVERT(CHAR,[Creation Time],14),':',''))) IDTOCMP,
             MAX([Service ID]) TYPE
        FROM [EGENCIA $country\$billing unit: Main] WITH (NOLOCK)
       WHERE ([Customer No_] = '$comCode')
         AND ISNUMERIC([Customer No_]) = 1
         AND CONVERT(CHAR(17),RTRIM(CONVERT(CHAR,[Creation date],112))+' '+CONVERT(CHAR,[Creation Time],14)) > '$seqNum'
         AND len([ID 2]) = 6
         AND [Service Group] IN (1)
       GROUP BY [ID 2]
       ORDER BY ID ASC ";
    my $res = $dbh->sahr($query, 'ID');
    debug('RES = '.Dumper($res));
    # __________________________________________________________
  
    # __________________________________________________________
    # Pour chacun des PNR on fait le queuing
    PNR: foreach my $key (keys %$res) {
      
	  $log_id=$res->{$key}->{PNRID};
      notice("     [ Working on PNR '".$res->{$key}->{PNRID}."' ]");
      
      notice("newSeqNum:".$newSeqNum);
      if ($res->{$key}->{IDTOCMP} > $newSeqNum)
      {
        $newSeqNum = $res->{$key}->{IDTOCMP};
        $sauv_Seq  = $res->{$key}->{ID};
      }
      
      # __________________________________________________________
      # Lecture du PNR dans Amadeus
      my $PNR = Expedia::GDS::PNR->new(PNR => $res->{$key}->{PNRID}, GDS => $GDS);
      if (!defined $PNR) {
        notice("Could not read PNR '".$res->{$key}->{PNRID}."' from GDS.");
        next PNR;
      }
      # __________________________________________________________
      
      # __________________________________________________________
      # Si je suis ici. Je dois requeuer !
      my @add = ();
      
      my $hasRMWlines = _hasRMWlines($PNR);
      debug('hasRMWlines = '.$hasRMWlines);

      if (!$hasRMWlines) {
        push (@add, { Data => 'RM W-COMCODE:'.$comCode });
        my $perCodes  = _getPerCodes($PNR);
        debug('perCodes = '.Dumper($perCodes));
        foreach (@$perCodes) {
		my $perCode  = $_->{PERCODE};
		my $paxNum   = $_->{PAXNUM};
		my $perInfos = _getPerInfos($perCode, $country, $res->{$key}->{PNRID});
		push (@add, { Data => 'RM W-MOBILE:'.$perInfos->{MOBILE}.'/'.$paxNum })            if ($perInfos->{MOBILE} ne '');
		push (@add, { Data => 'RM W-EMAIL:'.uc($perInfos->{EMAIL}).'/'.$paxNum })          if ($perInfos->{EMAIL}  ne '');
		push (@add, { Data => 'RM W-EMPNUMBER:'.stringGdsOthers($perInfos->{EMPNUM}).'/'.$paxNum })         if ($perInfos->{EMPNUM} ne '');
		push (@add, { Data => 'RM W-CC1:'.stringGdsOthers($perInfos->{CC1}).'/'.$paxNum }) if ($perInfos->{CC1}    ne '');
		push (@add, { Data => 'RM W-CC2:'.stringGdsOthers($perInfos->{CC2}).'/'.$paxNum }) if ($perInfos->{CC2}    ne '');

		#EGE-95102 -- add CC4 / CC5
		my ($CC4, $CC5,$EXP) = &GetTravelerCostCenter($proxyNav,$market,$comCode,$perCode);
		if($EXP ne '') 
		{
			notice("NAV EXPECTION:".$EXP);
		}
		else
		{
			push (@add, { Data => 'RM W-CC4:'.stringGdsOthers($CC4).'/'.$paxNum }) if ($CC4 ne '');
			push (@add, { Data => 'RM W-CC5:'.stringGdsOthers($CC5).'/'.$paxNum }) if ($CC5 ne '');
		}

	  }
      }
      
      push (@add, { Data => 'ES'.$securityElement });
      push (@add, { Data => 'QE/'.$destOfficeId.'/'.$destQueue });
      
      notice('Applying changes on PNR [...]');
      my $update = $PNR->update(
         add   => \@add,
         del   => [],
         mod   => [],
         NoGet => 1
      );
      # __________________________________________________________

	  
    }
	
	
    # __________________________________________________________
    
    # Sauvegarde de la séquence la plus haute traitée !
    debug('seqNum2nav    = '.$seqNum2nav);
    debug('newseqNum = '.$newSeqNum);
    &updateTravellerTrackingNavisionDate($country, $sauv_Seq, $comCode) if ($newSeqNum > $seqNum2nav);
  

	
  } # Fin foreach (@$h_q)

  return 1;  
}

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Est-ce que nous avons des lignes RM-W dans le PNR ?
sub _hasRMWlines {
  my $PNR = shift;
  
  foreach my $i (@{$PNR->{PNRData}}) {
    return 1 if ($i->{Data} =~ /^RM W-/);
  }
  
  return 0;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Récupération des "RM *PERCODES" présents dans le dossier
sub _getPerCodes {
  my $PNR = shift;
  
  my @perCodes = ();
  my $paxNums  = scalar(@{$PNR->{PAX}});
  
  foreach my $i (@{$PNR->{PNRData}}) {
  if ($i->{Data} =~ /^RM\s+\*PERCODE\s+(\d+)\/?(P\d)?/) {
      push @perCodes, {PERCODE => $1, PAXNUM => $2 };
    }
  }
  
  return [] if (scalar @perCodes == 0);
  
  # ______________________________________________________________
  # Vérification
  foreach (@perCodes) { $_->{PAXNUM}  = 'P1' if ($paxNums == 1); }
  foreach (@perCodes) { return [] if (!defined $_->{PAXNUM});    }
  # ______________________________________________________________
  
  return \@perCodes;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Récupération des infos relatives à un perCode et un PNR
#  TODO : Prévoir des WebServices avec BackOffice pour éviter
#         les requètes directes dans Navision.
sub _getPerInfos {
  my $perCode  = shift;
  my $table    = shift;
  my $pnr      = shift;

  my $dbh      = $cnxMgr->getConnectionByName('navision');
  my $query    = "
   select t.[Customer No_] comcode, t.[E-Mail] email, t.[Mobile Phone No_] mobile, t.[Analytical Code 3] empnum, m.[FLD_VALUE] cc1
     from [EGENCIA $table\$Traveller]          t (nolock),
          [EGENCIA $table\$Mapping_PNR_METAID]        w (nolock),
          [EGENCIA $table\$METAID_FIELD_VALUE] m (nolock)
    where t.[No_]     = '$perCode'
      and w.[PNR]     = '$pnr'
      and m.[FLD_KEY] = 'CC1_$perCode'
      and m.[METAID]  = w.[MetaId] ";
  my $res      = $dbh->saar($query);
  
    #this is soooooooooooooo ugly 
     $query    = "
   select m.[FLD_VALUE] cc2
     from [EGENCIA $table\$Traveller]          t (nolock),
          [EGENCIA $table\$Mapping_PNR_METAID]        w (nolock),
          [EGENCIA $table\$METAID_FIELD_VALUE] m (nolock)
    where t.[No_]     = '$perCode'
      and w.[PNR]     = '$pnr'
      and m.[FLD_KEY] = 'CC2_$perCode'
      and m.[METAID]  = w.[MetaId] ";
  my $res2      = $dbh->saar($query);
  
  my $comcode  = ''; $comcode = $res->[0][0] if ((defined $res->[0][0]) && ($res->[0][0] !~ /^\s+$/));
  my $email    = ''; $email   = $res->[0][1] if ((defined $res->[0][1]) && ($res->[0][1] !~ /^\s+$/));
  my $mobile   = ''; $mobile  = $res->[0][2] if ((defined $res->[0][2]) && ($res->[0][2] !~ /^\s+$/));
  my $empnum   = ''; $empnum  = $res->[0][3] if ((defined $res->[0][3]) && ($res->[0][3] !~ /^\s+$/));
  my $cc1      = ''; $cc1     = $res->[0][4] if ((defined $res->[0][4]) && ($res->[0][4] !~ /^\s+$/));
  my $cc2      = ''; $cc2     = $res2->[0][0] if ((defined $res2->[0][0]) && ($res2->[0][0] !~ /^\s+$/));
  
  my $perInfos = {
    COMCODE    => $comcode,
    EMAIL      => $email,
    MOBILE     => $mobile,
    EMPNUM     => $empnum,
    CC1        => $cc1,
	CC2		   => $cc2,
  };
  
  debug('perInfos = '.Dumper($perInfos));
  
  return $perInfos;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

1;
