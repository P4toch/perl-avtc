package Expedia::Modules::TAS::GetTas;
#-----------------------------------------------------------------
# Package Expedia::Modules::TAS::GetTas
#
# $Id: GetTas.pm 686 2011-04-21 12:33:02Z pbressan $
#
# (c) 2002-2007 Expedia.                   www.expediacorporate.fr
#-----------------------------------------------------------------

use strict;
use POSIX qw(strftime);
use Data::Dumper;

use DateTime;
use DateTime::Duration;

use Expedia::Tools::Logger     qw(&debug &notice &warning &error);
use Expedia::Tools::GlobalVars qw($cnxMgr);
use Expedia::Tools::TasFuncs         qw(&setTimeZone &getDeliveryForTas);
use Expedia::Databases::MidSchemaFuncs qw(&getTZbycountry);

sub run {
  my $self   = shift;
  my $params = shift;
  
  my $taskName     = $params->{TaskName};
  my $globalParams = $params->{GlobalParams};
  my $moduleParams = $params->{ModuleParams};
  my $changes      = $params->{Changes};
  
  my $market       = $globalParams->{market};
  my $agency       = $globalParams->{agency};
  my $product      = $globalParams->{product};
  my $delivery     = &getDeliveryForTas($market,$product);
  my $PNRs         = $globalParams->{pnr};        #$moduleParams->{PNRs};
  if(defined($PNRs) && $PNRs ne ''){notice("PNR:".$PNRs);}
  
  notice('Market      = '.$market);                                # OBLIGATOIRE
  notice('Agency      = '.$agency);                                # OBLIGATOIRE
  notice('Product     = '.$product);                              # OBLIGATOIRE  
  notice('Delivery    = '.$delivery);                              # OBLIGATOIRE
  notice('PNRs        = '.$PNRs)        if (defined $PNRs);        # OPTIONNEL
  
  if ((!defined $market) || (!defined $delivery) || (!defined $agency)) {
    notice("'Market' parameter is mandatory. Aborting.")   unless (defined $market);
    notice("'Delivery' parameter is mandatory. Aborting.") unless (defined $delivery);
    notice("'Agency' parameter is mandatory. Aborting.")   unless (defined $agency);
    return 0;
  }
  
  # -----------------------------------------------------------------------
  # Si dossierType n'existe pas, alors il est égal à AVION et TRAIN
  my $dossierType = "'WAVE_TC','GAP_TC','SNCF_TC','RG_TC'";
    #if ((!defined $dossierType) || ($dossierType =~ /^\s*$/));
  # -----------------------------------------------------------------------
    
  # -----------------------------------------------------------------------
  # Si une liste de PNRs est passée dans le fichier de CONF alors
  # on ne traite que ceux ci... (Pour le Debug / Test)
  my $PNRQuery = undef;
  my @PNRs     = ();
     @PNRs     = split (/,/, $PNRs) if ((defined $PNRs) && ($PNRs !~ /^\s*$/));
  if (scalar(@PNRs) > 0) {
    foreach (@PNRs) { $_ =~ s/\s*//g; $_ = "'".$_."'"; }
    $PNRQuery  = '      AND PNR IN ';
    $PNRQuery .= '('.join(',', @PNRs).') '
  }
  # -----------------------------------------------------------------------
  
  # -----------------------------------------------------------------------
  # Si on a une clause Order By dans les paramètres
  my $orderbyQuery = 'ORDER BY DEPARTURE_DATE ASC';
  # -----------------------------------------------------------------------
  
 
  # -----------------------------------------------------------------------
  # FORMATAGE DE LA DATE EN REMPLACEMENT DE LA SYSDATE ORACLE POUR LA GESTION DES TIMEZONES
  my $dt_tas = shift;
  
    my $tz = &getTZbycountry($market);
    if (!$tz) {
    error("No timezone is defined for market '$market'. Aborting.");
    return 0;
   }
   else
   {
     $dt_tas = setTimeZone($tz);  
   }
  

  
  # -----------------------------------------------------------------------
  
  # -----------------------------------------------------------------------
  # Si on a une clause "planned" dans les paramètres
  my $plannedQuery = undef;
  my $planned      = "today";
  
  if ((defined $planned) && ($planned !~ /^\s*$/)) {
    if    ($planned eq 'today')                    { $plannedQuery = " AND CONVERT(DATETIME,DFD.EMISSION_DATE,103) >= CONVERT(DATETIME,CONVERT(VARCHAR(10),'".$dt_tas."'  , 103),103) AND CONVERT(DATETIME,DFD.EMISSION_DATE,103) - CONVERT(DATETIME,CONVERT(VARCHAR(10),'".$dt_tas."', 103),103) < 1"; }
    elsif ($planned eq 'tomorrow')                 { $plannedQuery = " AND CONVERT(DATETIME,DFD.EMISSION_DATE,103) >= DATEADD(DAY,1,CONVERT(DATETIME,CONVERT(VARCHAR(10),'".$dt_tas."' , 103),103)) AND CONVERT(DATETIME,DFD.EMISSION_DATE,103) - DATEADD(DAY,1,CONVERT(DATETIME,CONVERT(VARCHAR(10),'".$dt_tas."' , 103),103)) < 1"; }
    elsif ($planned eq 'the_day_after_tomorrow')   { $plannedQuery = " AND CONVERT(DATETIME,DFD.EMISSION_DATE,103) >= DATEADD(DAY,2,CONVERT(DATETIME,CONVERT(VARCHAR(10),'".$dt_tas."' , 103),103))) AND CONVERT(DATETIME,DFD.EMISSION_DATE,103) - DATEADD(DAY,2,CONVERT(DATETIME,CONVERT(VARCHAR(10),'".$dt_tas."' , 103),103)) < 1"; }
    elsif ($planned eq 'yesterday')                { $plannedQuery = " AND CONVERT(DATETIME,DFD.EMISSION_DATE,103) >= DATEADD(DAY,-1,CONVERT(DATETIME,CONVERT(VARCHAR(10),'".$dt_tas."' , 103),103)) AND CONVERT(DATETIME,DFD.EMISSION_DATE,103) - DATEADD(DAY,-1,CONVERT(DATETIME,CONVERT(VARCHAR(10),'".$dt_tas."' , 103),103)) < 1"; }
    elsif ($planned eq 'the_day_before_yesterday') { $plannedQuery = " AND CONVERT(DATETIME,DFD.EMISSION_DATE,103) >= DATEADD(DAY,-2,CONVERT(DATETIME,CONVERT(VARCHAR(10),'".$dt_tas."' , 103),103)) AND CONVERT(DATETIME,DFD.EMISSION_DATE,103) - DATEADD(DAY,-2,CONVERT(DATETIME,CONVERT(VARCHAR(10),'".$dt_tas."' , 103),103)) < 1"; }
    else                                           { $plannedQuery = " AND CONVERT(DATETIME,DFD.EMISSION_DATE,103) >= CONVERT(DATETIME,CONVERT(VARCHAR(10),'".$dt_tas."', 103),103) AND CONVERT(DATETIME,DFD.EMISSION_DATE,103) - CONVERT(DATETIME,CONVERT(VARCHAR(10),'".$dt_tas."', 103),103) < 1"; }
  } else {                                           $plannedQuery = " AND CONVERT(DATETIME,DFD.EMISSION_DATE,103) >= CONVERT(DATETIME,CONVERT(VARCHAR(10),'".$dt_tas."', 103),103) AND CONVERT(DATETIME,DFD.EMISSION_DATE,103) - CONVERT(DATETIME,CONVERT(VARCHAR(10),'".$dt_tas."', 103),103) < 1"; }
  # -----------------------------------------------------------------------
  
    if(uc($product) eq 'AIR')
	{
		$product="AND PRDCT_TP_ID in (1,5,6)";
	}
	else
	{
		$product="AND PRDCT_TP_ID in (2)";
	}


  my $dbh = $cnxMgr->getConnectionByName('mid');
  
  # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  # Requète d'extraction des dossiers à émettre de la table DELIVERY_FOR DISPATCH
  #La requète à changer pour OWP, supprimer de la contrainte sur la longeur
  my $query  = "
   SELECT DFD.META_DOSSIER_ID, DFD.PNR, DFD.DELIVERY_ID, DFD.TCAT_ID, DFD.MESSAGE_ID, DFD.MESSAGE_VERSION, DFD.BILLING_COMMENTS
     ,DFD.PRDCT_TP_ID
     FROM DELIVERY_FOR_DISPATCH DFD
  
    WHERE DFD.DELIVERY_STATUS_ID = 1
      AND DFD.PNR IS NOT NULL
      AND DFD.PNR NOT LIKE 'null' "; # AND DFD.EMISSION_DATE = TO_DATE('05072010', 'DDMMYYYY') ";
      
     $query .= $PNRQuery      if (defined($PNRQuery));
     $query .= $plannedQuery  if (defined($planned));

     $query .= "
      AND DFD.TCAT_ID IN ( $delivery )
      AND DFD.MARKET = '$market' ";
     $query .= $product;
     $query .="
      AND DFD.BLOCKED_BY_APPROVAL = 0
      AND DFD.ON_HOLD =  0
      AND DFD.MESSAGE_ID IS NOT NULL
      AND DFD.MESSAGE_VERSION IS NOT NULL ";
    $query .= $orderbyQuery;

  my $dbres = $dbh->saar($query);  
  # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    
  # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
  # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
  # LE TRAITEMENT DE TROP XML PREND TROP DE TEMPS - LE TRAITEMENT DES DOSSIERS
  #  EST EFFECTUE DESORMAIS AU COUP PAR COUP. PB DU MERCREDI 31 OCTOBRE 2007.
  # __________________________________________________________________________
  # Section ajoutée. Objectif : Ne pas modifier trop de code source dans GetTas.pm
  my @items = (); 
  foreach (@$dbres) {
    my $PNR =  uc($_->[1]);
       $PNR =~ s/(^\s*|\s*|\s*$)//g;
    push @items, { REF             => $_->[0],
                   PNR             => $PNR,
                   DELIVERY_ID     => $_->[2],
                   TCAT_ID         => $_->[3],
                   MESSAGE_ID      => $_->[4],
                   MESSAGE_VERSION => $_->[5],
                   DELIVERY        => $delivery,
                   MARKET          => $market,
                   AGENCY          => $agency,
                   BILLING_COMMENT => $_->[6],
                   PRDCT_TP_ID     => $_->[7] #EGE-41180
                 };
  }
  # __________________________________________________________________________  
  # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
  # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@    
  #notice("GETITEMS:".Dumper(@items));
  
  return @items; 
}

1;
