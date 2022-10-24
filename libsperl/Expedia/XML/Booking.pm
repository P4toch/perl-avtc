package Expedia::XML::Booking;
#-----------------------------------------------------------------
# Package Expedia::XML::Booking
#
# $Id: Booking.pm 589 2010-07-21 08:53:20Z pbressan $
#
# (c) 2002-2010 Egencia.                            www.egencia.eu
#-----------------------------------------------------------------

use XML::LibXML;
use Data::Dumper;

use Expedia::Tools::Logger qw(&debug &notice &warning &error);
use Expedia::Tools::GlobalVars qw($h_statusCodes);
use Expedia::Tools::GlobalFuncs qw(&fielddate2amaddate);

use strict;

my $xmlParser = undef;

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# CONSTRUCTEUR
sub new {
	
	my ($class, $XML) = @_;

	my $self = {};
  bless ($self, $class);

  if (!defined $xmlParser) {
    $self->{_PARSER} = XML::LibXML->new();
    $xmlParser       = $self->{_PARSER};
  }
  else {
    $self->{_PARSER} = $xmlParser;
  }
  
  eval {
    $self->{_XML}  = $XML;
    $self->{_DOC}  = $self->{_PARSER}->parse_string($self->{_XML});
  };
  if ($@) {
    error($@);
    return undef;
  }

  return $self;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
sub parser {
	my $self = shift;

  return $self->{_PARSER};
}

sub xml {
	my ($self, $xml) = @_;

  $self->{_XML} = $xml if (defined $xml);
  return $self->{_XML};
}

sub doc {
	my ($self, $doc) = @_;

  $self->{_DOC} = $doc if (defined $doc);
  return $self->{_DOC};
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Retourne le nombre de TravelDossier Train dans un Booking
#   mais ne vérifie pas les <Status></Status> des lightweightDossiers 
sub hasTrain {
  my $self = shift;

  my $nbDossierTrain = 0;
  my @travelDossiers = $self->doc->findnodes('*/Metadossier/TravelDossiers/TravelDossier');

  foreach (@travelDossiers) {
    my $DossierType = $_->find('DossierType')->to_literal->value();
    $nbDossierTrain++ if ($DossierType =~ /^(SNCF_TC|RG_TC)$/);
  }

  return $nbDossierTrain;  
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@ 

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Retourne le nombre de TravelDossier Avion dans un Booking
#   mais ne vérifie pas les <Status></Status> des lightweightDossiers 
sub hasAir {
  my $self = shift;

  my $nbDossierAvion = 0;
  my @travelDossiers = $self->doc->findnodes('*/Metadossier/TravelDossiers/TravelDossier');

  foreach (@travelDossiers) {
    my $DossierType = $_->find('DossierType')->to_literal->value();
    $nbDossierAvion++ if ($DossierType =~ /^(GAP_TC|WAVE_TC)$/);
  }

  return $nbDossierAvion;  
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Renvoie une structure des différents TravelDossier TRAIN ou AVION  ou CAR
#   -> TravelDossierPosition
#   -> TravelDossierCode
#   -> TravelDossierType
#   -> TravelDossierPnr
#   -> TravelDossierStatus
sub getTravelDossierStruct {
  my $self = shift;
  
  my @struct   = ();
  my $compteur = -1;

  my @travelDossiers = $self->doc->findnodes('*/Metadossier/TravelDossiers/TravelDossier');
  
  foreach (@travelDossiers) {
   
    $compteur++;
    
    my $DossierType   =  $_->find('DossierType')->to_literal->value();
 
    # On ne s'intéresse qu'aux TravelDossiers Train et Avion [...]
	#EGE-87684 : if we are leaving we have to decrement the counter in order to avoid a mismatching in the position
    do {$compteur--;next;} unless ($DossierType =~ /^(GAP_TC|WAVE_TC|SNCF_TC|RG_TC|MASERATI_CAR_TC)$/);
    
    my $DossierPnr    =  $_->find('PNR')->to_literal->value();
       $DossierPnr    =~ s/(^\s*|\s*|\s*$)//ig;
	my $pnrGds        =  $_->find('PnrGds')->to_literal->value();
    my $tssRecLoc     =  $_->find('TssRecLoc')->to_literal->value();
    my $DossierStatus =  $_->find('Status')->to_literal->value();
    my $DossierMarkup =  $_->find('HasMarkup')->to_literal->value();
    my $TicketType    =  $_->find('TicketType')->to_literal->value();
    my $TEMP          =  'AirDossier';
       $TEMP          =  'TrainDossier' if ($DossierType =~ /^(SNCF_TC|RG_TC)$/);
       $TEMP          =  'MaseratiCarDossier' if ($DossierType =~ /^MASERATI_CAR_TC$/);
    my $DossierNode   =  $_->findnodes($TEMP);
    my $DossierCode   =  '';
       $DossierCode   =  $DossierNode->[0]->getAttribute('Code') if ($DossierNode->size == 1);
    my $IsLowCost     =  '';
       $IsLowCost     =  $DossierNode->[0]->getAttribute('IsLowCost') if ($DossierNode->size == 1 && $TEMP eq 'AirDossier');
    my $TripType      =  '';
       $TripType      =  $DossierNode->[0]->findnodes('ItineraryInfo')->[0]->find('TripType')->to_literal->value()
         if ($DossierNode->size == 1 && $TEMP eq 'AirDossier');

       #EGE-56482
    my $fareType ='';
    	if($DossierType =~ /^(GAP_TC|WAVE_TC)$/){
        $fareType      =  $DossierNode->[0]->findnodes('ProductPricing')->[0]->find('FareType')->to_literal->value();}

    # On ne s'intéresse pas aux dossier AIR LOW_COST
    if (($TicketType eq 'LOW_COST') || ($IsLowCost eq 'true')) {
      notice('LowCost Booking.');
	  $compteur--;
      next;
    }
    
	
    # Multi DV RAIL only 
    if($DossierPnr =~ /,/) {
           my @DosPNRs = split(/,/,$DossierPnr);
		   my $taille= @DosPNRs;
		   my $i=0;
		   
		   my $pos = 0;
           my @listTssPnrGds = split(/,/, $pnrGds);
           my @listTssRecLoc = split(/,/, $tssRecLoc);

		   
           foreach my $opnr (@DosPNRs) {
			 $i++;
             push @struct, { lwdPos        => $compteur,
                    lwdPnr        => uc($opnr),
					lwdListPnr 	  => $DossierPnr,
                    lwdPnrGds     => @listTssPnrGds->[$pos],
                    lwdTssRecLoc  => @listTssRecLoc->[$pos],
                    lwdType       => $DossierType,
                    lwdCode       => $DossierCode,     # RefDossierCode ou SncfTrainCartId
                    lwdStatus     => $DossierStatus,
                    lwdHasMarkup  => $DossierMarkup,
                    lwdTicketType => $TicketType,
                    lwdTripType   => $TripType,
                    lwdFareType   => $fareType
             };
			 $compteur++ unless ($i == $taille) ;
			 $pos = $pos+1;
          }
     
    } 
	
	# Multi AIR (OWP) or single AIR or single RAIL 
	else {
			
           push @struct, { lwdPos        => $compteur,
                    lwdPnr        => uc($DossierPnr),
					lwdListPnr 	  => $DossierPnr,
					lwdPnrGds     => $pnrGds,
					lwdTssRecLoc  => $tssRecLoc,
                    lwdType       => $DossierType,
                    lwdCode       => $DossierCode,     # RefDossierCode ou SncfTrainCartId
                    lwdStatus     => $DossierStatus,
                    lwdHasMarkup  => $DossierMarkup,
                    lwdTicketType => $TicketType,
                    lwdTripType   => $TripType,
                    lwdFareType   => $fareType
           };

    }

  }
  
  return \@struct;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

sub getTravelDossierStruct_LC {
  my $self = shift;
  
  my @struct   = ();
  my $compteur = -1;

  my @travelDossiers = $self->doc->findnodes('*/Metadossier/TravelDossiers/TravelDossier');
  
  foreach (@travelDossiers) {
   
    $compteur++;
    
    my $DossierType   =  $_->find('DossierType')->to_literal->value();
 
	#TBC , does all LC are on this list ? 
    do {$compteur--;next;} unless ($DossierType =~ /^(GAP_TC|WAVE_TC|SNCF_TC|RG_TC|MASERATI_CAR_TC)$/);
    
    my $DossierPnr    =  $_->find('PNR')->to_literal->value();
       $DossierPnr    =~ s/(^\s*|\s*|\s*$)//ig;
	my $pnrGds        =  $_->find('PnrGds')->to_literal->value();
    my $tssRecLoc     =  $_->find('TssRecLoc')->to_literal->value();
    my $DossierStatus =  $_->find('Status')->to_literal->value();
    my $DossierMarkup =  $_->find('HasMarkup')->to_literal->value();
    my $TicketType    =  $_->find('TicketType')->to_literal->value();
    my $TEMP          =  'AirDossier';
       $TEMP          =  'TrainDossier' if ($DossierType =~ /^(SNCF_TC|RG_TC)$/);
       $TEMP          =  'MaseratiCarDossier' if ($DossierType =~ /^MASERATI_CAR_TC$/);
    my $DossierNode   =  $_->findnodes($TEMP);
    my $DossierCode   =  '';
       $DossierCode   =  $DossierNode->[0]->getAttribute('Code') if ($DossierNode->size == 1);
    my $IsLowCost     =  '';
       $IsLowCost     =  $DossierNode->[0]->getAttribute('IsLowCost') if ($DossierNode->size == 1 && $TEMP eq 'AirDossier');
    my $TripType      =  '';
       $TripType      =  $DossierNode->[0]->findnodes('ItineraryInfo')->[0]->find('TripType')->to_literal->value()
         if ($DossierNode->size == 1 && $TEMP eq 'AirDossier');

       #EGE-56482
    my $fareType ='';
    	if($DossierType =~ /^(GAP_TC|WAVE_TC)$/){
        $fareType      =  $DossierNode->[0]->findnodes('ProductPricing')->[0]->find('FareType')->to_literal->value();}

    # We want only AIR LOW_COST
    if (($TicketType ne 'LOW_COST') || ($IsLowCost ne 'true')) {
      notice('Not LowCost Booking.');
	  $compteur--;
      next;
    }
	
	#debug('segment = '.$_->getAirSegments({lwdPos => $compteur}));
    #my $airline  = _formatSegments($_->getAirSegments({lwdPos => $compteur}), 1);
    my $airline='';
	
           push @struct, { lwdPos        => $compteur,
                    lwdPnr        => uc($DossierPnr),
					lwdListPnr 	  => $DossierPnr,
					lwdPnrGds     => $pnrGds,
					lwdTssRecLoc  => $tssRecLoc,
                    lwdType       => $DossierType,
                    lwdCode       => $DossierCode,     # RefDossierCode ou SncfTrainCartId
                    lwdStatus     => $DossierStatus,
                    lwdHasMarkup  => $DossierMarkup,
                    lwdTicketType => $TicketType,
                    lwdTripType   => $TripType,
                    lwdFareType   => $fareType,
					lwdAirLine	  => $airline
           };

   

  }
  
  return \@struct;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@


# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Renvoie une structure des différents TravelDossier Avion
#  du MetaDossier en Status "Reservé" ou "En attente d'approbation" ! 
#   -> TravelDossierPosition
#   -> TravelDossierCode
#   -> TravelDossierType
#   -> TravelDossierPnr
#   -> TravelDossierStatus
sub getAirTravelDossierStruct {
  my $self = shift;
  
  my @struct   = ();
  my $compteur = -1;
  my @travelDossiers = $self->doc->findnodes('*/Metadossier/TravelDossiers/TravelDossier');
  foreach (@travelDossiers) {
    
    $compteur++;
    
    my $DossierType      =  $_->find('DossierType')->to_literal->value();
    my $DossierPnr       =  $_->find('PNR')->to_literal->value();
       $DossierPnr       =~ s/(^\s*|\s*|\s*$)//ig;
    my $DossierStatus    =  $_->find('Status')->to_literal->value();
    my $DossierMarkup    =  $_->find('HasMarkup')->to_literal->value();
    my $TicketType       =  $_->find('TicketType')->to_literal->value();
    my $AirDossierNode   =  $_->findnodes('AirDossier');
    my $DossierCode      =  '';
       $DossierCode      =  $AirDossierNode->[0]->getAttribute('Code')      if ($AirDossierNode->size == 1);
    my $IsLowCost        =  '';
       $IsLowCost        =  $AirDossierNode->[0]->getAttribute('IsLowCost') if ($AirDossierNode->size == 1);
    my $TripType         =  '';
       $TripType         =  $AirDossierNode->[0]->findnodes('ItineraryInfo')->[0]->find('TripType')->to_literal->value()
         if ($AirDossierNode->size == 1);
    
    # On ne s'intéresse qu'aux TravelDossiers Avion [...]
    next unless ($DossierType =~ /^(GAP_TC|WAVE_TC)$/);

    # On ne s'intéresse qu'aux Dossiers en Status = V ou Q [...]
    if ($DossierStatus !~ /^(V|Q)$/) {
      debug('DossierStatus = '.$DossierStatus);
      notice("Booking '$DossierPnr' is in status '".$h_statusCodes->{$DossierStatus}."'.")
        if (defined $h_statusCodes->{$DossierStatus});
      next;
    }
    
    # On ne s'intéresse pas aux dossier AIR LOW_COST
    if (($TicketType eq 'LOW_COST') || ($IsLowCost eq 'true')) {
      notice('LowCost Booking Air.');
      next;
    }

    push @struct, { lwdPos        => $compteur,
                    lwdPnr        => uc($DossierPnr),
                    lwdType       => $DossierType,
                    lwdCode       => $DossierCode,     # RefDossierCode
                    lwdStatus     => $DossierStatus,
                    lwdHasMarkup  => $DossierMarkup,
                    lwdTicketType => $TicketType,
                    lwdTripType   => $TripType };

  }
  
  return \@struct;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Renvoie une structure des différents TravelDossier Train
#  du MetaDossier en Status "Reservé" ou "En attente d'approbation" ! 
#   -> TravelDossierPosition
#   -> TravelDossierCode
#   -> TravelDossierType
#   -> TravelDossierPnr
#   -> TravelDossierStatus
sub getTrainTravelDossierStruct {
  my $self = shift;
  
  my @struct   = ();
  my $compteur = -1;

  my @travelDossiers = $self->doc->findnodes('*/Metadossier/TravelDossiers/TravelDossier');
  
  foreach (@travelDossiers) {

    $compteur++;
    
    my $DossierType      =  $_->find('DossierType')->to_literal->value();
    my $DossierPnr       =  $_->find('PNR')->to_literal->value();
       $DossierPnr       =~ s/(^\s*|\s*|\s*$)//ig;
    my $DossierStatus    =  $_->find('Status')->to_literal->value();
    my $DossierMarkup    =  $_->find('HasMarkup')->to_literal->value();
    my $TicketType       =  $_->find('TicketType')->to_literal->value();
    my $TrainDossierNode =  $_->findnodes('TrainDossier');
    my $DossierCode      =  '';
       $DossierCode      =  $TrainDossierNode->[0]->getAttribute('Code') if ($TrainDossierNode->size == 1);
    
    # On ne s'intéresse qu'aux TravelDossiers Train [...]
    next unless ($DossierType =~ /^(SNCF_TC|RG_TC)$/);

    # On ne s'intéresse qu'aux Dossiers en Status = V ou Q [...]
    if ($DossierStatus !~ /^(V|Q)$/) {
      debug('DossierStatus = '.$DossierStatus);
      notice("Booking '$DossierPnr' is in status '".$h_statusCodes->{$DossierStatus}."'.")
        if (defined $h_statusCodes->{$DossierStatus});
      next;
    }
    
    push @struct, { lwdPos        => $compteur,
                    lwdPnr        => uc($DossierPnr),
                    lwdType       => $DossierType,
                    lwdCode       => $DossierCode,     # SncfTrainCartId
                    lwdStatus     => $DossierStatus,
                    lwdHasMarkup  => $DossierMarkup,
                    lwdTicketType => $TicketType };

  }
  
  return \@struct;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@


# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Renvoie une structure des différents TravelDossier Avion
#  du MetaDossier en Status "Reservé" ou "En attente d'approbation" ! 
#   -> TravelDossierPosition
#   -> TravelDossierCode
#   -> TravelDossierType
#   -> TravelDossierPnr
#   -> TravelDossierStatus
sub getAirCancelledTravelDossierStruct {
  my $self = shift;
  
  my @struct   = ();
  my $compteur = -1;
  my @travelDossiers = $self->doc->findnodes('*/Metadossier/TravelDossiers/TravelDossier');
  
  foreach (@travelDossiers) {
    
    $compteur++;
    
    my $DossierType      =  $_->find('DossierType')->to_literal->value();
    my $DossierPnr       =  $_->find('PNR')->to_literal->value();
       $DossierPnr       =~ s/(^\s*|\s*|\s*$)//ig;
    my $DossierStatus    =  $_->find('Status')->to_literal->value();
    my $DossierMarkup    =  $_->find('HasMarkup')->to_literal->value();
    my $TicketType       =  $_->find('TicketType')->to_literal->value();
    my $AirDossierNode   =  $_->findnodes('AirDossier');
    my $DossierCode      =  '';
       $DossierCode      =  $AirDossierNode->[0]->getAttribute('Code')      if ($AirDossierNode->size == 1);
    my $IsLowCost        =  '';
       $IsLowCost        =  $AirDossierNode->[0]->getAttribute('IsLowCost') if ($AirDossierNode->size == 1);
    my $TripType         =  '';
       $TripType         =  $AirDossierNode->[0]->findnodes('ItineraryInfo')->[0]->find('TripType')->to_literal->value()
         if ($AirDossierNode->size == 1);
    
    # On ne s'intéresse qu'aux TravelDossiers Avion [...]
    next unless ($DossierType =~ /^(GAP_TC|WAVE_TC)$/);

    # On ne s'intéresse qu'aux Dossiers en Status = C [...]
    if ($DossierStatus !~ /^(C)$/) {
      debug('DossierStatus = '.$DossierStatus);
      notice("Booking '$DossierPnr' is in status '".$h_statusCodes->{$DossierStatus}."'.")
        if (defined $h_statusCodes->{$DossierStatus});
      next;
    }
    
    # On ne s'intéresse pas aux dossier AIR LOW_COST
    if (($TicketType eq 'LOW_COST') || ($IsLowCost eq 'true')) {
      notice('LowCost Booking Air Cancel.');
      next;
    }

    push @struct, { lwdPos        => $compteur,
                    lwdPnr        => uc($DossierPnr),
                    lwdType       => $DossierType,
                    lwdCode       => $DossierCode,     # RefDossierCode
                    lwdStatus     => $DossierStatus,
                    lwdHasMarkup  => $DossierMarkup,
                    lwdTicketType => $TicketType,
                    lwdTripType   => $TripType };

  }
  
  return \@struct;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@


# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Renvoie une structure des différents TravelDossier Train
#  du MetaDossier en Status "Reservé" ou "En attente d'approbation" ! 
#   -> TravelDossierPosition
#   -> TravelDossierCode
#   -> TravelDossierType
#   -> TravelDossierPnr
#   -> TravelDossierStatus
sub getTrainCancelledTravelDossierStruct {
  my $self = shift;
  
  my @struct   = ();
  my $compteur = -1;

  my @travelDossiers = $self->doc->findnodes('*/Metadossier/TravelDossiers/TravelDossier');
  
  foreach (@travelDossiers) {

    $compteur++;
    
    my $DossierType      =  $_->find('DossierType')->to_literal->value();
    my $DossierPnr       =  $_->find('PNR')->to_literal->value();
       $DossierPnr       =~ s/(^\s*|\s*|\s*$)//ig;
    my $DossierStatus    =  $_->find('Status')->to_literal->value();
    my $DossierMarkup    =  $_->find('HasMarkup')->to_literal->value();
    my $TicketType       =  $_->find('TicketType')->to_literal->value();
    my $TrainDossierNode =  $_->findnodes('TrainDossier');
    my $DossierCode      =  '';
       $DossierCode      =  $TrainDossierNode->[0]->getAttribute('Code') if ($TrainDossierNode->size == 1);
    
    # On ne s'intéresse qu'aux TravelDossiers Train [...]
    next unless ($DossierType =~ /^(SNCF_TC|RG_TC)$/);

    # On ne s'intéresse qu'aux Dossiers en Status = C [...]
    if ($DossierStatus !~ /^(C)$/) {
      debug('DossierStatus = '.$DossierStatus);
      notice("Booking '$DossierPnr' is in status '".$h_statusCodes->{$DossierStatus}."'.")
        if (defined $h_statusCodes->{$DossierStatus});
      next;
    }
    
    push @struct, { lwdPos        => $compteur,
                    lwdPnr        => uc($DossierPnr),
                    lwdType       => $DossierType,
                    lwdCode       => $DossierCode,     # SncfTrainCartId
                    lwdStatus     => $DossierStatus,
                    lwdHasMarkup  => $DossierMarkup,
                    lwdTicketType => $TicketType };

  }
  
  return \@struct;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Renvoie le nombre de TravelDossiers Train ou Avion
#   du MetaDossier en Status "Reservé" ou "En attente d'approbation" ! 
sub getNbOfTravelDossiers {
  my $self = shift;
  
  my $travelDossierStruct = $self->getTravelDossierStruct;
  
  return scalar (@$travelDossierStruct);
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# SEnd the number of low-cost traveldossier  
sub getNbOfTravelDossiers_LC {
  my $self = shift;
  
  my $travelDossierStruct = $self->getTravelDossierStruct_LC;
  
  return scalar (@$travelDossierStruct);
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Renvoie le nombre de TravelDossiers Avion
#   du MetaDossier en Status "Reservé" ou "En attente d'approbation" ! 
sub getNbOfAirTravelDossiers {
  my $self = shift;
  
  my $travelDossierStruct = $self->getAirTravelDossierStruct;
  
  return scalar (@$travelDossierStruct);
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Renvoie le nombre de TravelDossiers Train
#   du MetaDossier en Status "Reservé" ou "En attente d'approbation" ! 
sub getNbOfTrainTravelDossiers {
  my $self = shift;
  
  my $travelDossierStruct = $self->getTrainTravelDossierStruct;
  
  return scalar (@$travelDossierStruct);
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# Renvoie une structure des différents Travellers du MetaDossier
sub getNbOfAirTrainCancelledTravelDossiers {
  my $self = shift;

  my $cancelled = 0;
   
  my @travelDossiers = $self->doc->findnodes('*/Metadossier/TravelDossiers/TravelDossier');
  
  foreach (@travelDossiers) {
    
    my $DossierType =  $_->find('DossierType')->to_literal->value();
    
    # On ne s'intéresse qu'aux TravelDossiers Train et Avion [...]
    next unless ($DossierType =~ /^(GAP_TC|WAVE_TC|SNCF_TC|RG_TC)$/);
    
    my $DossierStatus =  $_->find('Status')->to_literal->value();
    if ($DossierStatus eq 'C')
    {
      $cancelled = 1;
      next;
    }    

    
  }

  return $cancelled;
  
}
  
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Renvoie une structure des différents Travellers du MetaDossier
sub getTravellerStruct {
  my $self = shift;
  
  my @struct   = ();
  my $compteur = -1;

  my @travellers = $self->doc->findnodes('*/Metadossier/Travellers/Traveller');
  
  foreach (@travellers) {

    $compteur++;

    my $IsMain       = $_->find('IsMain')->to_literal->value();
    my $Title        = $_->find('Title')->to_literal->value();
    my $amadeusTitle = $_->find('AmadeusTitle')->to_literal->value();
    my $FirstName    = $_->find('FirstName')->to_literal->value();
    my $LastName     = $_->find('LastName')->to_literal->value();
    my $isCancelled  = $_->find('Cancelled')->to_literal->value();
    
    next if ($isCancelled eq 'true');
       
    $_ =~ s/^\s*|\s*$//g           foreach ($FirstName, $LastName, $Title);
    $_ =~ s/\s+/ /g                foreach ($FirstName, $LastName);
    $_ =~ s/(Prénom|Nom) (.*)/$2/g foreach ($FirstName, $LastName); # Spécial Hack pour les boulets du TRAIN !
    
    my $UserNode   = $_->findnodes('User');
    my $PerCode    = $UserNode->[0]->getAttribute('PerCode');
    my $EmailMode  = $UserNode->[0]->find('EmailMode')->to_literal->value();
    my $IsVIP      = $UserNode->[0]->findnodes('PersonalInfo')->[0]->find('IsVIP')->to_literal->value();
    my $OTFlag     = $UserNode->[0]->findnodes('PersonalInfo')->[0]->find('OTFlag')->to_literal->value();
    my $BirthDate  = $UserNode->[0]->findnodes('PersonalInfo')->[0]->find('BirthDate')->to_literal->value();
    my $Email      = $UserNode->[0]->findnodes('PersonalInfo/Email')->[0]->find('Value')->to_literal->value();
    my $MobPhoneNo = '';
    my $EmpNum     = $self->getEmployeeNumber({trvPos => $compteur});

    my @ContactNumberNode = $UserNode->[0]->findnodes('ContactNumbers/ContactNumber');
    if (scalar(@ContactNumberNode) > 0) {
      NODES: foreach my $node (@ContactNumberNode) {
        my $value   = $node->find('Value')->to_literal->value();
        my $code    = $node->findnodes('Type')->[0]->find('Code')->to_literal->value();
        if ($code eq 'MOBILE') {
          $MobPhoneNo = $value;
          last NODES;
        }
      }
    }

    push @struct, { Position     => $compteur,
                    IsMain       => $IsMain,
                    Title        => $Title,
                    AmadeusTitle => $amadeusTitle,
                    FirstName    => $FirstName,
                    LastName     => $LastName,
                    PerCode      => $PerCode,
                    IsVIP        => $IsVIP,
                    Email        => $Email,
                    OTFlag       => $OTFlag,
                    MobPhoneNo   => $MobPhoneNo,
                    EmployeeNo   => $EmpNum,
                    BirthDate    => $BirthDate,
                    EmailMode    => $EmailMode };

  }
  
  return \@struct;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Récupère uniquement les informations du voyageur principal
sub getMainTravellerInfos {
  my $self = shift;
  
  my $trvStruct = $self->getTravellerStruct;
  
  foreach my $trv (@$trvStruct) {
    return $trv if ($trv->{IsMain} eq 'true');
  }
  
  # Procédure de secours si on ne trouve pas de Main Traveller
  my $trvPos = $self->getWhoIsMain;
  return $trvStruct->[$trvPos];
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Renvoie le nombre de Travellers dans un MetaDossier
sub getNbOfTravellers {
  my $self = shift;
  
  my $travellerStruct = $self->getTravellerStruct;
  
  return scalar (@$travellerStruct);
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Retourne le "code" du MetaDossier = MdCode
sub getMdCode {
  my $self = shift;
  
  my $mdNode = $self->doc->findnodes('*/Metadossier');
  my $mdCode = $mdNode->[0]->getAttribute('MdCode');
  
  return $mdCode;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Retourne le "status" du MetaDossier
sub getMdStatus {
  my $self = shift;
  
  my $mdNode   = $self->doc->findnodes('*/Metadossier');
  my $mdStatus = $mdNode->[0]->find('Status')->to_literal->value();
  
  return $mdStatus;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Retourne les Events du MetaDossier
sub getMdEvents {
  my $self = shift;
  
  my @events = $self->doc->findnodes('*/Metadossier/Events/Event');
  
  return [] if (scalar @events == 0);
  
  my @res = ();

  foreach my $eNode (@events) {
    my $eventDate      = $eNode->find('EventDate')->to_literal->value();
    my $eventAction    = $eNode->find('EventAction')->to_literal->value();
    my $eventDesc      = $eNode->find('EventDescription')->to_literal->value();
  # my $eventUserNode  = $eNode->findnodes('EventUser/PersonalInfo');
  # my $euTitle        = $eventUserNode->[0]->find('Title')->to_literal->value();
  # my $euFirstName    = $eventUserNode->[0]->find('FirstName')->to_literal->value();
  # my $euLastName     = $eventUserNode->[0]->find('LastName')->to_literal->value();
    my $eventAgentNode = $eNode->findnodes('EventAgent');
    my $eaLogin        = '';
       $eaLogin        = $eventAgentNode->[0]->find('Login')->to_literal->value()
         if ($eventAgentNode->size == 1);

    push (@res, { EventDate        => $eventDate,
                  EventAction      => $eventAction,
                  EventDescription => $eventDesc,
                  EventAgentLogin  => $eaLogin,  });
  }
  
  return \@res;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Retourne si oui ou non un dossier a été inséré manuellement
sub hasBeenManualyInserted {
  my $self = shift;
  
  my $events = $self->getMdEvents;
  
  EVENT: foreach my $event (@$events) {
    if ((exists $event->{EventAction}) &&
        ($event->{EventAction} =~ /^(AIRINSERTION|TRAININSERTION)$/)) {
      return 1;
    }
  }
  
  return 0;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Retourne les Annotations du MetaDossier
sub getMdAnnotations {
  my $self = shift;
  
  my @annotations = $self->doc->findnodes('*/Metadossier/Annotations/Annotation');
  
  return [] if (scalar @annotations == 0);
  
  my @res = ();

  foreach my $aNode (@annotations) {
    my $content = $aNode->find('Content')->to_literal->value();
    my $type    = $aNode->getAttribute('Type');
    push (@res, { Content => $content, Type  => $type })
      if (($content !~ /^\s+$/) && (defined $type) && ($type !~ /^\s+$/));
  }
  
  return \@res;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Retourne si OUI ou NON, ce dossier possède un
#   COMMENT_TO_TICKETING bloquant pour l'émission TAS.
sub hasTicketingComment {
  my $self = shift;
  
  my $annotations = $self->getMdAnnotations;
  
  return 0 if (scalar @$annotations == 0);
  
  foreach my $annotation (@$annotations) {
    return 1
      if (($annotation->{Type} eq 'COMMENT_TO_TICKETING') && ($annotation->{Content} !~ /^\s*$/));
  }
  
  return 0;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Retourne les informations contenues dans la node GDSQueue
sub getGDSQueue {
  my $self   = shift;
  my $params = shift;

  my $lwdPos  = $params->{lwdPos};
  my $lwdType = $params->{lwdType};
  
  my @travelDossiers = $self->doc->findnodes('*/Metadossier/TravelDossiers/TravelDossier');
  
  my $GdsQNode = undef;
     $GdsQNode = $travelDossiers[$lwdPos]->findnodes('AirDossier/GDSQueue')   if ($lwdType  =~ /^(GAP_TC|WAVE_TC)$/);
     $GdsQNode = $travelDossiers[$lwdPos]->findnodes('TrainDossier/GDSQueue') if ($lwdType  =~ /^(SNCF_TC|RG_TC)$/);

  return {} if (!(defined $GdsQNode) || ($GdsQNode->size == 0)); 
 
  my $GdsQ = {};      
     $GdsQ->{Queue}                   = $GdsQNode->[0]->find('Queue')->to_literal->value();
     $GdsQ->{OfficeId}                = $GdsQNode->[0]->find('OfficeId')->to_literal->value();
     $GdsQ->{IsReleaseResponsibility} = $GdsQNode->[0]->find('IsReleaseResponsibility')->to_literal->value();
     $GdsQ->{CancelQueue}             = $GdsQNode->[0]->find('CancelQueue')->to_literal->value();
     $GdsQ->{UpdateQueue}             = $GdsQNode->[0]->find('UpdateQueue')->to_literal->value();
     $GdsQ->{CnxName}                 = $GdsQNode->[0]->find('CnxName')->to_literal->value();
     
  return $GdsQ;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Retourne les CC1 & CC2 d'un traveller utilisés pour cette réservation.
# Attention à ne pas confondre avec les centres de coûts qui lui sont
# paramétrés par défaut [...]
sub getCcUsed {
  my $self   = shift;
  my $params = shift;

  my $trvPos = $params->{trvPos};   # Position du Traveller dans le XML
  
  my $ccUsed = {};
  
  my @travellers     = $self->doc->findnodes('*/Metadossier/Travellers/Traveller');
  my @reportingItems = $travellers[$trvPos]->findnodes('ReportingData/ReportingItem');
  
  return $ccUsed if (scalar @reportingItems == 0);
  
  foreach (@reportingItems) {
    my $Code   = $_->getAttribute('Code');
    next unless ($Code =~ /^(CC1|CC2)$/);
    my $ivNode =  $_->findnodes('ItemValues/ItemValue');
    my $Value  = ''; 
       $Value  = $ivNode->[0]->find('Value')->to_literal->value() if ($ivNode->size == 1);
    $ccUsed->{$Code} = $Value;
  }

  return $ccUsed;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Retourne les identifiant (Code) des CC1 & CC2 d'un traveller utilisés pour cette réservation.

sub getCcUsedCode {
  my $self   = shift;
  my $params = shift;

  my $trvPos = $params->{trvPos};   # Position du Traveller dans le XML
  
  my $ccUsed = {};
  
  my @travellers     = $self->doc->findnodes('*/Metadossier/Travellers/Traveller');
  my @reportingItems = $travellers[$trvPos]->findnodes('ReportingData/ReportingItem');
  
  return $ccUsed if (scalar @reportingItems == 0);
  
  foreach (@reportingItems) {
    my $Code_number   = $_->getAttribute('Code');
    next unless ($Code_number =~ /^(CC1|CC2)$/);
    my $ivNode =  $_->findnodes('ItemValues/ItemValue');
    my $Id_code  = ''; 
       $Id_code  = $ivNode->[0]->find('Code')->to_literal->value() if ($ivNode->size == 1);
    $ccUsed->{$Code_number} = $Id_code;
  }

  return $ccUsed;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@


# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Retourne les CC1 & CC2 d'un traveller paramétrés sur son profil
sub getCcProfil {
  my $self   = shift;
  my $params = shift;

  my $trvPos = $params->{trvPos};   # Position du Traveller dans le XML
  
  my $ccProf = {};
  
  my @travellers     = $self->doc->findnodes('*/Metadossier/Travellers/Traveller/User');
  my @reportingItems = $travellers[$trvPos]->findnodes('ReportingData/ReportingItem');
  
  return $ccProf if (scalar @reportingItems == 0);
  
  foreach (@reportingItems) {
    my $Code   = $_->getAttribute('Code');
    next unless ($Code =~ /^(CC1|CC2)$/);
    my $ivNode =  $_->findnodes('ItemValues/ItemValue');
    my $Value  = ''; 
       $Value  = $ivNode->[0]->find('Value')->to_literal->value() if ($ivNode->size == 1);
    $ccProf->{$Code} = $Value;
  }

  return $ccProf;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

sub getGpid {
  my $self   = shift;
  my $params = shift;
  
  my $trvPos = $params->{trvPos};   # Position du Traveller dans le XML

  my @travellers = $self->doc->findnodes('*/Metadossier/Travellers/Traveller');
  my @company    = $travellers[$trvPos]->findnodes('User/Company');
  
  return $company[0]->getAttribute('Gpid');
}

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Cette fonction récupère le comName en se basant sur la section
# <CompanyCoreInfo> d'un traveller.
# SYNOPSIS : $self->getPerComName({trvPos => $self->getWhoIsMain});
sub getPerComName {
  my $self   = shift;
  my $params = shift;
  
  my $trvPos = $params->{trvPos};   # Position du Traveller dans le XML

  my @travellers = $self->doc->findnodes('*/Metadossier/Travellers/Traveller');
  my @company    = $travellers[$trvPos]->findnodes('User/Company/CompanyCoreInfo');
  
  return $company[0]->find('Name')->to_literal->value();
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Cette fonction récupère le ComCode d'un traveller
# SYNOPSIS : $self->getPerComCode({trvPos => $self->getWhoIsMain});
sub getPerComCode {
  my $self   = shift;
  my $params = shift;
  
  my $trvPos = $params->{trvPos};   # Position du Traveller dans le XML

  my @travellers = $self->doc->findnodes('*/Metadossier/Travellers/Traveller');
  my @company    = $travellers[$trvPos]->findnodes('User/Company');
  
  return $company[0]->getAttribute('ComCode');
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Cette fonction récupère le UpComCode en se basant sur la section
# <CompanyCoreInfo><POS> d'un traveller.
# SYNOPSIS : $self->getUpComCode({trvPos => $self->getWhoIsMain});
sub getUpComCode {
  my $self   = shift;
  my $params = shift;
  
  my $trvPos = $params->{trvPos};   # Position du Traveller dans le XML

  my @travellers = $self->doc->findnodes('*/Metadossier/Travellers/Traveller');
  my @company    = $travellers[$trvPos]->findnodes('User/Company/CompanyCoreInfo/POS/Company');
  
  return $company[0]->getAttribute('ComCode');
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

sub getTpid {
  my $self   = shift;
  my $params = shift;
  
  my $trvPos = $params->{trvPos};   # Position du Traveller dans le XML

  my @travellers = $self->doc->findnodes('*/Metadossier/Travellers/Traveller');
  my @company    = $travellers[$trvPos]->findnodes('User/Company/CompanyCoreInfo/POS');
  
  return $company[0]->getAttribute('Tpid');
}

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Cette fonction récupère le CountryCode en se basant sur la section
# <CompanyCoreInfo><POS> d'un traveller.
# SYNOPSIS : $self->getCountryCode({trvPos => $self->getWhoIsMain});
sub getCountryCode {
  my $self   = shift;
  my $params = shift;
  
  my $trvPos = $params->{trvPos};   # Position du Traveller dans le XML

  my @travellers = $self->doc->findnodes('*/Metadossier/Travellers/Traveller');
  my $company    = $travellers[$trvPos]->findnodes('User/Company/CompanyCoreInfo/POS');
  
  return $company->[0]->find('Code')->to_literal->value();
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Récupère si oui ou non, il s'agit d'une société de TEST
# Se base sur le <CompanyCoreInfo> d'un traveller.
# SYNOPSIS : $self->isDummyCompany({trvPos => $self->getWhoIsMain});
sub isDummyCompany {
  my $self   = shift;
  my $params = shift;
  
  my $trvPos = $params->{trvPos};   # Position du Traveller dans le XML

  my @travellers = $self->doc->findnodes('*/Metadossier/Travellers/Traveller');
  my $company    = $travellers[$trvPos]->findnodes('User/Company/CompanyCoreInfo');
  
  my $dummy = $company->[0]->find('IsDummy')->to_literal->value();
  
  return 1 if $dummy eq 'true';
  return 0;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Cette fonction renvoie l'indice du Traveller qui est le$loyaltyCard
#  voyageur principal.
sub getWhoIsMain {
  my $self   = shift;
  
  my $struct = $self->getTravellerStruct;
  
  foreach (@$struct) {
    return $_->{Position} if ($_->{IsMain} eq 'true'); 
  }
  
  notice('Warning No Main Traveller found in Booking !');
  
  return 0; # Si on a pas trouvé, on considère que ce sera le premier !
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Retourne un hash des moyens de paiement utilisés pour cette
#   réservation, par ce voyageur, pour ce TravelDossier.
sub getPaymentMean {
  my $self   = shift;
  my $params = shift;

  my $trvPos  = $params->{trvPos};   # Position du Traveller dans le XML
  my $lwdCode = $params->{lwdCode};  # Code du Metadossier dans le XML
  
  my $paymentMean = {};
  
  my @travellers         = $self->doc->findnodes('*/Metadossier/Travellers/Traveller');
  my @travellerPMeanNode = $travellers[$trvPos]->findnodes('TravellerPaymentMeans/TravellerPaymentMean');
  
  return $paymentMean if (scalar(@travellerPMeanNode) == 0);
    
  my $idx = 0;

  foreach (@travellerPMeanNode) {
    my $CcCode      = '';
       $CcCode      = $travellerPMeanNode[$idx]->find('CcCode')->to_literal->value();
     
    my $DossierCode = '';
       $DossierCode = $travellerPMeanNode[$idx]->find('DossierCode')->to_literal->value();
       
    my @pMeanNode   = $travellerPMeanNode[$idx]->findnodes('PaymentMean');
       
    $idx++;
   
    next if ($DossierCode ne $lwdCode);
    return {} if (scalar(@pMeanNode) == 0);

    my $Service     = $pMeanNode[0]->find('Service')->to_literal->value();
    my $PaymentType = $pMeanNode[0]->find('PaymentType')->to_literal->value();

    $paymentMean->{Service}     = $Service;
    $paymentMean->{PaymentType} = $PaymentType;
    $paymentMean->{CcCode}      = $CcCode;
    
    return $paymentMean;
  }

  return $paymentMean;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Récupération des contrats valables pour ce TravelDossier
sub getTravelDossierContracts {
  my $self   = shift;
  my $params = shift;

  my $lwdPos    = $params->{lwdPos};
  my @contracts = ();
  
  my @travelDossiers = $self->doc->findnodes('*/Metadossier/TravelDossiers/TravelDossier');
  my @corpoC;
  if (scalar @travelDossiers == 1 ) 
  {
    # For single AIR or single RAIL or Multi DV RAIL only : there is only one TravelDossier by XML
	@corpoC = $travelDossiers[0]->findnodes('CorporateContracts/CorporateContract');
  }elsif (scalar @travelDossiers > 1 )  
   {
	# For Multi AIR (OWP) : several TravelDossier by XML
	@corpoC = $travelDossiers[$lwdPos]->findnodes('CorporateContracts/CorporateContract');
  }  
  return [] if scalar(@corpoC == 0);

  foreach (@corpoC) {
    my $contractType    = $_->find('ContractType')->to_literal->value();
    my $corporateNumber = $_->find('CorporateNumber')->to_literal->value();
    my $supplierNode    = $_->findnodes('Supplier');
    my $supplierCode    = '';
       $supplierCode    = $supplierNode->[0]->getAttribute('Code') if ($supplierNode->size == 1);
    my $supplierService = '';
       $supplierService = $supplierNode->[0]->find('Service')->to_literal->value();
    
    push @contracts, { ContractType    => $contractType,
                       CorporateNumber => $corporateNumber,
                       SupplierCode    => $supplierCode,
                       SupplierService => $supplierService, }
  }

  return \@contracts;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Retourne le champ OSIYY d'un Traveller donné par sa position
sub getOsyy {
  my $self   = shift;
  my $params = shift;

  my $trvPos = $params->{trvPos};   # Position du Traveller dans le XML
  
  my $ccUsed = {};
  
  my @travellers  = $self->doc->findnodes('*/Metadossier/Travellers/Traveller');
  my $AddInfoNode = $travellers[$trvPos]->findnodes('User/AdditionalInfo');
  
  return '' if ($AddInfoNode->size == 0);
  
  my $Osyy = $AddInfoNode->[0]->find('OSIYY')->to_literal->value();
  
  return $Osyy;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Retourne le champ EmployeeNumber d'un Traveller donné par sa position
sub getEmployeeNumber {
  my $self   = shift;
  my $params = shift;

  my $trvPos = $params->{trvPos};   # Position du Traveller dans le XML
  
  my $ccUsed = {};
  
  my @travellers  = $self->doc->findnodes('*/Metadossier/Travellers/Traveller');
  my $AddInfoNode = $travellers[$trvPos]->findnodes('User/AdditionalInfo');
  
  return '' if ($AddInfoNode->size == 0);
  
  my $empNum = $AddInfoNode->[0]->find('EmployeeNumber')->to_literal->value();
  
  return $empNum;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Fonction d'extraction des informations des Segments Aériens
sub getAirSegments {
  my $self   = shift;
  my $params = shift;

  my $lwdPos    = $params->{lwdPos};
  
  my @travelDossiers = $self->doc->findnodes('*/Metadossier/TravelDossiers/TravelDossier');
  my @airSegments    = $travelDossiers[$lwdPos]->findnodes('AirDossier/AirSegments/AirSegment');
  
  return [] if (scalar(@airSegments) == 0);
  
  my @airSegs = ();
  
  foreach my $segNode (@airSegments) {
    my $zone           = $segNode->find('Zone')->to_literal->value();
    my $flightNumber   = $segNode->find('FlightNumber')->to_literal->value();
    my $rank           = $segNode->getAttribute('Rank');
    my $conveyorNode   = $segNode->findnodes('Conveyor');
    my $conveyorCode   = '';
       $conveyorCode   = $conveyorNode->[0]->getAttribute('Code') if ($conveyorNode->size == 1);
    my $vendorNode     = $segNode->findnodes('Vendor');
    my $vendorCode     = '';
       $vendorCode     = $vendorNode->[0]->getAttribute('Code')   if ($conveyorNode->size == 1);
    my $depNode        = $segNode->findnodes('Departure');
    my $depLocNode     = $segNode->findnodes('Departure/Location');
    my $arrLocNode     = $segNode->findnodes('Arrival/Location');
    my $depIata        = '';
       $depIata        = $depLocNode->[0]->find('IATAcode')->to_literal->value() if ($depLocNode->size == 1);
    my $arrIata        = '';
       $arrIata        = $arrLocNode->[0]->find('IATAcode')->to_literal->value() if ($arrLocNode->size == 1);
    my $depDateTime    = '';
       $depDateTime    = $depNode->[0]->getAttribute('dateTime') if ($depNode->size == 1);
    my $depLocCounNode = $segNode->findnodes('Departure/Location/Country');
    my $arrLocCounNode = $segNode->findnodes('Arrival/Location/Country');
    my $depCountryCode = '';
       $depCountryCode = $depLocCounNode->[0]->getAttribute('Code') if ($depLocCounNode->size == 1);
    my $arrCountryCode = '';
       $arrCountryCode = $arrLocCounNode->[0]->getAttribute('Code') if ($arrLocCounNode->size == 1);
    
    push (@airSegs, { Rank           => $rank,
                      Zone           => $zone,
                      FlightNumber   => $flightNumber,
                      VendorCode     => $vendorCode,
                      ConveyorCode   => $conveyorCode,
                      DepIATA        => $depIata,
                      DepCountryCode => $depCountryCode,
                      DepDateTime    => $depDateTime,
                      ArrIATA        => $arrIata,
                      ArrCountryCode => $arrCountryCode,  } );
  }
  
  return \@airSegs;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Fonction d'extraction des informations des Segments Train
sub getTrainSegments {
  my $self   = shift;
  my $params = shift;

  my $lwdPos    = $params->{lwdPos};
  
  my @travelDossiers = $self->doc->findnodes('*/Metadossier/TravelDossiers/TravelDossier');
  my @trainSegments  = $travelDossiers[$lwdPos]->findnodes('TrainDossier/TrainSegments/TrainSegment');
  
  return [] if (scalar(@trainSegments) == 0);
  
  my @trainSegs = ();
  
  foreach my $segNode (@trainSegments) {
    my $code           = $segNode->getAttribute('Code');
    my $depNode        = $segNode->findnodes('Departure');
    my $depLocNode     = $segNode->findnodes('Departure/Location');
    my $arrLocNode     = $segNode->findnodes('Arrival/Location');
    my $depIata        = '';
       $depIata        = $depLocNode->[0]->find('IATAcode')->to_literal->value() if ($depLocNode->size == 1);
    my $arrIata        = '';
       $arrIata        = $arrLocNode->[0]->find('IATAcode')->to_literal->value() if ($arrLocNode->size == 1);
    my $depDateTime    = '';
       $depDateTime    = $depNode->[0]->getAttribute('dateTime') if ($depNode->size == 1);
    
    push (@trainSegs, { DV             => $code,
                        DepIATA        => $depIata,
                        DepDateTime    => $depDateTime,
                        ArrIATA        => $arrIata, } );
  }
  
  return \@trainSegs;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Fonction de récupération des LoyaltyCards utilisées en tant que
#   identifiant ETICKET pour un booking Aérien.
# Relatif au module GAP/Srfoid.pm
sub getSrfoids {
  my $self   = shift;
  my $params = shift;

  my $lwdPos = $params->{lwdPos};
  
  my @travelDossiers = $self->doc->findnodes('*/Metadossier/TravelDossiers/TravelDossier');
  my @eticketIds     = $travelDossiers[$lwdPos]->findnodes('AirDossier/EticketIds/TravellerEticketId');
  
  return [] if (scalar(@eticketIds) == 0);
  
  my $docTypes = {
    PASSPORT  => 'PP',
    DL        => 'DL',
    ID        => 'NI', };
  
  my @srfoids = ();
  
  NODE: foreach my $eticketNode (@eticketIds) {

    my $loyaltyCard = $eticketNode->findnodes('LoyaltyCard');
    my $idDocument  = $eticketNode->findnodes('IDDocument');
    
    my $sLoyaltyCard = $loyaltyCard->size;
    my $sIdDocument  = $idDocument->size;
    
    if ($sLoyaltyCard + $sIdDocument == 0) {
      notice('No eticket document founded ! Cannot proceed.');
      next NODE;
    }
    elsif ($sLoyaltyCard + $sIdDocument > 1) {
      notice('Multiple etickets documents for one user ! Cannot proceed.');
      next NODE;
    } else {
      # -------------------------------------------------------------------------------
      # LoyaltyCard      
      if ($sLoyaltyCard == 1) {
        my $cardType        = $loyaltyCard->[0]->getAttribute('Type');
        next NODE if ($cardType ne 'LC');
        my $perCode         = $eticketNode->findnodes('User')->[0]->getAttribute('Code');
        my $cardNumber      = $loyaltyCard->[0]->find('CardNumber')->to_literal->value();
        my $supplierNode    = $loyaltyCard->[0]->findnodes('IssuingSuppliers/Supplier');
        my $supplierCode    = '';
           $supplierCode    = $supplierNode->[0]->getAttribute('Code') if ($supplierNode->size == 1);
        my $supplierService = '';
           $supplierService = $supplierNode->[0]->find('Service')->to_literal->value() if ($supplierNode->size == 1);;
        next NODE unless ($supplierService =~ /^(AIR|ETICKET)$/);
        
        push (@srfoids, { EticketType     => 'LoyaltyCard',
                          PerCode         => $perCode,
                          DocNumber       => $cardNumber,
                          DocType         => 'FF',
                          SupplierCode    => $supplierCode,
                          SupplierService => $supplierService } );
      }
      # -------------------------------------------------------------------------------
      # IDDocument
      if ($sIdDocument == 1) {
        my $docType         = $idDocument->[0]->find('DocumentType')->to_literal->value();
        next NODE if ($docType !~ /^(PASSPORT|DL|ID)$/);
        my $perCode         = $eticketNode->findnodes('User')->[0]->getAttribute('Code');
        my $docNumber       = $idDocument->[0]->find('Number')->to_literal->value();
        
        push (@srfoids, { EticketType  => 'IDDocument',
                          PerCode      => $perCode,
                          DocNumber    => $docNumber,
                          DocType      => $docTypes->{$docType}  } );        
      }
      # -------------------------------------------------------------------------------
    }

  }

  return \@srfoids;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Fonction de récupération de l'élément XML ProductPricing dans un AirDossier
sub getAirProductPricing {
  my $self   = shift;
  my $params = shift;

  my $lwdPos = $params->{lwdPos};
  
  my @travelDossiers = $self->doc->findnodes('*/Metadossier/TravelDossiers/TravelDossier');
  my $productPricing = $travelDossiers[$lwdPos]->findnodes('AirDossier/ProductPricing');
  
  return {} if ($productPricing->size == 0);
  
  my $fareType      = $productPricing->[0]->find('FareType')->to_literal->value();
  my $corporateCode = $productPricing->[0]->find('CorporateCode')->to_literal->value();
  
  return {
    FareType      => $fareType,
    CorporateCode => $corporateCode,
  };
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
sub getTravellerLoyaltySubscriptionCards {
  my $self   = shift;
  my $params = shift;

  my $trvPos = $params->{trvPos};     # Position du Traveller dans le XML

  my @travellers = $self->doc->findnodes('*/Metadossier/Travellers/Traveller');
  my @LSCards    = $travellers[$trvPos]->findnodes('User/LoyaltySubscriptionCards/Card');

  return [] if scalar (@LSCards == 0);

  my $lsCards = [];

  foreach my $lsCardNode (@LSCards) {

    my $CardType        =  $lsCardNode->getAttribute('Type');
    my $CardCode        =  $lsCardNode->getAttribute('Code');

    my $CardName        =  $lsCardNode->find('Name')->to_literal->value();
    my $CardValidFrom   =  $lsCardNode->find('ValidFrom')->to_literal->value();
    my $CardValidTo     =  $lsCardNode->find('ValidTo')->to_literal->value();
    my $CardClass       =  $lsCardNode->find('Class')->to_literal->value();
    my $CardPtc         =  $lsCardNode->find('DefaultPtc')->to_literal->value();
    my $CardNumber      =  $lsCardNode->find('CardNumber')->to_literal->value();
       $CardNumber      =~ s/^\s*|\s*|\s*$//g;
    
    my $iSupplierNode   =  $lsCardNode->findnodes('IssuingSuppliers/Supplier');
    my $eSupplierNode   =  $lsCardNode->findnodes('EligibleSuppliers/Supplier');
    
    my $supplierCode    =  '';
       $supplierCode    =  $iSupplierNode->[0]->getAttribute('Code')                 if ($iSupplierNode->size == 1);
    my $supplierService =  '';
       $supplierService =  $iSupplierNode->[0]->find('Service')->to_literal->value() if ($iSupplierNode->size == 1);

    push (@$lsCards, { CardType        => $CardType,
                       CardCode        => $CardCode,    # STC_CODE = Supplier Card Type Code
                       CardName        => $CardName,
                       CardNumber      => $CardNumber,
                       CardClass       => $CardClass,
                       CardPtc         => $CardPtc,
                       CardValidFrom   => $CardValidFrom,
                       CardValidTo     => $CardValidTo,
                       SupplierCode    => $supplierCode,
                       SupplierService => $supplierService, } );
  }

  return $lsCards;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Fonction de récupération du nom de la tourne
sub getDeliveryRun {
  my $self = shift;
  
  my @delivery = $self->doc->findnodes('*/Metadossier/Delivery');
  
  return undef if (scalar(@delivery == 0));
  
  my @deliveryRun = $delivery[0]->findnodes('DeliveryRun');
  
  return undef if (scalar(@deliveryRun == 0));
  
  return $deliveryRun[0]->find('Value')->to_literal->value();
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Fonction de récupération de la date d'emission
sub getTicketingDate {
  my $self = shift;
  
  my $mdNode = $self->doc->findnodes('*/Metadossier');
  my $tDate  = $mdNode->[0]->find('TicketingDate')->to_literal->value();
  
  return $tDate;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Fonction de récupération de la date de départ
sub getDepartureDate {
  my $self = shift;
  
  my $mdNode = $self->doc->findnodes('*/Metadossier');
  my $dDate  = $mdNode->[0]->find('DepartureDate')->to_literal->value();
  
  return $dDate;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Fonction de récupération de la date de delivery
sub getDeliveryDate {
  my $self = shift;
  
  my @delivery = $self->doc->findnodes('*/Metadossier/Delivery');
  
  return '' if (scalar(@delivery == 0));
  
  return $delivery[0]->find('DeliveryDate')->to_literal->value();
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Fonction de récupération de l'élément IsOnHold de "Delivery"
sub getDeliveryIsOnHold {
  my $self = shift;

  my @delivery = $self->doc->findnodes('*/Metadossier/Delivery');

  return 0 if (scalar(@delivery == 0));

  my $res = $delivery[0]->find('IsOnHold')->to_literal->value();

  my $isOnHold = 0;
     $isOnHold = 1 if ((defined $res) && ($res eq 'true'));

  return $isOnHold;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Fonction de récupération de l'élément IsBlockedByApproval de "Delivery"
sub getDeliveryIsBlockedByApproval {
  my $self = shift;

  my @delivery = $self->doc->findnodes('*/Metadossier/Delivery');

  return 0 if (scalar(@delivery == 0));

  my $res = $delivery[0]->find('IsBlockedByApproval')->to_literal->value();

  my $isBbA = 0;
     $isBbA = 1 if ((defined $res) && ($res eq 'true'));

  return $isBbA;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Fonction qui regarde si le dossier a été booké par
#   un travel consultant en utilisant une prise de controle 
sub hasBeenBookedByTC {
  my $self = shift;
  
  my $travelConsultantNode = $self->doc->findnodes('*/Metadossier/BookedBy/TravelConsultant');
  return 0 if ($travelConsultantNode->size == 0);
  return 1;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Fonction de récupération des infos du travel consultant qui a booké pour [...]
sub getTravelConsultantInfos {
  my $self = shift;
  
  my $travelConsultantNode = $self->doc->findnodes('*/Metadossier/BookedBy/TravelConsultant');
  
  return {} if ($travelConsultantNode->size == 0);
  
  my $login     = $travelConsultantNode->[0]->find('Login')->to_literal->value();
  my $lastName  = $travelConsultantNode->[0]->find('LastName')->to_literal->value();
  my $firstName = $travelConsultantNode->[0]->find('FirstName')->to_literal->value();
  
  return {
    Login     => $login,
    LastName  => $lastName,
    FirstName => $firstName,
  };
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Fonction de récupération des informations Booker
sub getBookerInfos {
  my $self = shift;
  
  my $bookerNode = $self->doc->findnodes('*/Metadossier/BookedBy/Booker');
  my $EmailMode  = $bookerNode->[0]->find('EmailMode')->to_literal->value();
  my $perCode    = $bookerNode->[0]->getAttribute('PerCode') if ($bookerNode->size == 1);
  
  my $personalInfoNode = $bookerNode->[0]->findnodes('PersonalInfo');
  
  return {} if ($personalInfoNode->size == 0);
  
  my $bookerTitle     = $personalInfoNode->[0]->find('Title')->to_literal->value();
  my $bookerFirstName = $personalInfoNode->[0]->find('FirstName')->to_literal->value();
  my $bookerLastName  = $personalInfoNode->[0]->find('LastName')->to_literal->value();
  my $bookerEmailNode = $personalInfoNode->[0]->findnodes('Email');
  my $bookerEmail     = '';
     $bookerEmail     = $bookerEmailNode->[0]->find('Value')->to_literal->value()
       if ($bookerEmailNode->size == 1);
  
  my $companyNode = $bookerNode->[0]->findnodes('Company/CompanyCoreInfo');
  
  my $comName = '';
     $comName = $companyNode->[0]->find('Name')->to_literal->value()
       if ($companyNode->size == 1);
  
  return {
    BookerPerCode => $perCode,
    BookerName    => $bookerTitle.' '.$bookerFirstName.' '.$bookerLastName,
    BookerEmail   => lc($bookerEmail),
    BookerComName => $comName,
    BookerEmailMode => $EmailMode,
  }
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Fonction de récupération de l'Email du Booker en prenant en
#   compte l'aspect Travel and Expense T&E
sub getBookerEmail {
  my $self = shift;
  
  my $bookerNode = $self->doc->findnodes('*/Metadossier/BookedBy/Booker');
  my $tandeNode  = $self->doc->findnodes('*/Metadossier/EmailTAndERecipient');
  
  my $bookerEmail        = '';
  my $emailType          = '';
  my $getFromBookerNode  = 0;
  
  if ($tandeNode->size  == 1) {
    my $personalInfoNode = $tandeNode->[0]->findnodes('PersonalInfo');
    $bookerEmail         = '' if ($personalInfoNode->size == 0);
    my $bookerEmailNode  = $personalInfoNode->[0]->findnodes('Email');
    $bookerEmail         = '' if ($bookerEmailNode->size  == 0);
    $bookerEmail         = $bookerEmailNode->[0]->find('Value')->to_literal->value();
    $getFromBookerNode   = 1 if ($bookerEmail eq '');
  } else {
    $getFromBookerNode   = 1;
  }
  
  if ($getFromBookerNode) {
    my $emailType        = $bookerNode->[0]->find('EmailMode')->to_literal->value();
    return '' if ($emailType eq 'NONE');
    my $personalInfoNode = $bookerNode->[0]->findnodes('PersonalInfo');
    return '' if ($personalInfoNode->size == 0);
    my $bookerEmailNode  = $personalInfoNode->[0]->findnodes('Email');
    return '' if ($bookerEmailNode->size  == 0);
    $bookerEmail         = $bookerEmailNode->[0]->find('Value')->to_literal->value();
  }
  
  return $bookerEmail;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
sub getDeliveryAddress {
  my $self = shift;
  
  my @delivery = $self->doc->findnodes('*/Metadossier/Delivery');
  
  return {} if (scalar(@delivery == 0));
  
  my $pdiNode = $delivery[0]->findnodes('PhysicalDeliveryInformation');
  
  return {} if ($pdiNode->size == 0);
  
  my $res = {};
  
  my $recipient     = $pdiNode->[0]->find('Recipient')->to_literal->value();
  $res->{Recipient} = $recipient;

  my $addressNode   = $pdiNode->[0]->findnodes('Address');
  
  return $res if ($addressNode->size == 0);
  
  my $addressType   = $addressNode->[0]->find('Type')->to_literal->value();
  
  if ($addressNode->size == 1) {
    my $addressN    = $addressNode->[0]->findnodes('Address');
    my $name        = $addressN->[0]->find('Name')->to_literal->value();
    my $street1     = $addressN->[0]->find('Street1')->to_literal->value();
    my $street2     = $addressN->[0]->find('Street2')->to_literal->value();
    my $postalCode  = $addressN->[0]->find('PostalCode')->to_literal->value();
    my $city        = $addressN->[0]->find('City')->to_literal->value();
    my $countryNode = $addressN->[0]->findnodes('Country');
    my $country     = '';
       $country     = $countryNode->[0]->getAttribute('Code') if ($countryNode->size == 1);
    
    $res->{AddressName} = $name;
    $res->{Type}        = $addressType;
    $res->{Street1}     = $street1;
    $res->{Street2}     = $street2;
    $res->{PostalCode}  = $postalCode;
    $res->{City}        = $city;
    $res->{Country}     = $country;
  }
  
  return $res;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Retourne si oui 1 ou non 0 ce TravelDossier est en attente de confirmation
sub isOnHold {
  my $self   = shift;
  my $params = shift;
  
  my $lwdPos = $params->{lwdPos};
  
  my @travelDossiers = $self->doc->findnodes('*/Metadossier/TravelDossiers/TravelDossier');
  
  my $status;
  if (scalar @travelDossiers == 1 ) 
  {
    # For single AIR or single RAIL or Multi DV RAIL only : there is only one TravelDossier by XML
	$status = $travelDossiers[0]->find('Status')->to_literal->value();
  }elsif (scalar @travelDossiers > 1 )  
   {
	# For Multi AIR (OWP) : several TravelDossier by XML
	$status = $travelDossiers[$lwdPos]->find('Status')->to_literal->value();
  }
  
  return 1 if ($status eq 'Q');
  return 0;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Vérifie s'il s'agit d'un dossier APIS ou non
#  - Refonte APIS du 04 Mai 2010
sub isApisBooking {
  my $self = shift;
  
  my $travellers = $self->getTravellerStruct;
  
  foreach (@$travellers) {
    return 1 if defined $self->getApisInfos({trvPos => $_->{Position}});
  }
  
  return 0;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Récupère les informations APIS d'un traveller donne
# Récupère les informations APIS d'un traveller donne
sub getApisInfos {
  my $self   = shift;
  my $params = shift;

  my $trvPos = $params->{trvPos};     # Position du Traveller dans le XML

  my @travellers = $self->doc->findnodes('*/Metadossier/Travellers/Traveller');
  my $apisNode   = $travellers[$trvPos]->findnodes('APIS');
  
  return undef if ($apisNode->size == 0);

  my $SSRType                = $apisNode->[0]->find('SSRType')->to_literal->value();
  my $idcardNumber           = $apisNode->[0]->find('IdentityCardNumber')->to_literal->value();
  my $passportNumber         = $apisNode->[0]->find('PassportNumber')->to_literal->value();
  my $expiryDate             = $apisNode->[0]->find('ExpiryDate')->to_literal->value();
  my $birthDate              = $apisNode->[0]->find('BirthDate')->to_literal->value();
  my $destinationAddress     = $apisNode->[0]->find('DestinationAddress')->to_literal->value();
  my $destinationCity        = $apisNode->[0]->find('DestinationCity')->to_literal->value();
  my $destinationZipCode     = $apisNode->[0]->find('DestinationZipCode')->to_literal->value();
  my $destinationState       = $apisNode->[0]->find('DestinationState')->to_literal->value();
  my $nationality            = $apisNode->[0]->find('Nationality')->to_literal->value();

  my $apisCountryNode        = $apisNode->[0]->findnodes('ApisCountry');
  my $residenceCountryNode   = $apisNode->[0]->findnodes('ResidenceCountry');
  my $destinationCountryNode = $apisNode->[0]->findnodes('DestinationCountry');
  
  my $apisCountry            = '';
     $apisCountry            = $apisCountryNode->[0]->getAttribute('Code') if ($apisCountryNode->size == 1);
  my $residenceCountry       = '';
     $residenceCountry       = $residenceCountryNode->[0]->getAttribute('Code') if ($residenceCountryNode->size == 1);
  my $destinationCountry     = '';
     $destinationCountry     = $destinationCountryNode->[0]->getAttribute('Code') if ($destinationCountryNode->size == 1);

  return {
    SSRType            => $SSRType,
    IdentityCardNumber => $idcardNumber,
    PassportNumber     => $passportNumber,
    ExpiryDate         => $expiryDate,
    BirthDate          => $birthDate,
    DestinationAddress => $destinationAddress,
    DestinationCity    => $destinationCity,
    DestinationZipCode => $destinationZipCode,
    DestinationState   => $destinationState,
    ApisCountry        => $apisCountry,
    Nationality        => $nationality,
    ResidenceCountry   => $residenceCountry,
    DestinationCountry => $destinationCountry,
  };
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Récupère les préférences de siège d'un traveller donne
sub getSeatPref {
  my $self   = shift;
  my $params = shift;

  my $trvPos = $params->{trvPos};     # Position du Traveller dans le XML

  my @travellers     = $self->doc->findnodes('*/Metadossier/Travellers/Traveller');
  my $travelPrefNode = $travellers[$trvPos]->findnodes('User/TravelPreferences/AirPreferences/Seat');
  
  my $seatPref = 'UNDEFINED';
     $seatPref = $travelPrefNode->[0]->find('Value')->to_literal->value()
       if ($travelPrefNode->size == 1);

  return $seatPref;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Récupère si OUI ou NON un dossier est de type E-TICKET.
#   Se base désormais sur le TicketType du TravelDossier
sub isEticket {
  my $self   = shift;
  my $params = shift;
  
  my $lwdPos = $params->{lwdPos};
  
  my $isEticket = 0;
     $isEticket = 1 if ($self->getTicketType({lwdPos => $lwdPos}) eq 'ELECTRONIC_TICKET');

  return $isEticket;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Récupère si OUI ou NON un dossier est de type E-BILLET.
#   Se base désormais sur le TicketType du TravelDossier
sub isEbillet {
  my $self   = shift;
  my $params = shift;
  
  my $lwdPos = $params->{lwdPos};
  
  my $isEbillet = 0;
     $isEbillet = 1 if ($self->getTicketType({lwdPos => $lwdPos}) eq 'ELECTRONIC_BILLET');

  return $isEbillet;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Récupère si OUI ou NON un dossier est de type THALYS TICKETLESS.
#   Se base désormais sur le TicketType du TravelDossier
sub isThalysTicketless {
  my $self   = shift;
  my $params = shift;
  
  my $lwdPos = $params->{lwdPos};
  
  my $isThalysTicketless = 0;
     $isThalysTicketless = 1 if ($self->getTicketType({lwdPos => $lwdPos}) eq 'THALYS_TICKETLESS');

  return $isThalysTicketless;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Récupère si OUI ou NON un dossier est de type PAPIER.
#   Se base désormais sur le TicketType du TravelDossier
sub isPaper {
  my $self   = shift;
  my $params = shift;
  
  my $lwdPos = $params->{lwdPos};
  
  my $isPaper = 0;
     $isPaper = 1 if ($self->getTicketType({lwdPos => $lwdPos}) eq 'PAPER_TICKET');

  return $isPaper;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Récupère la balise TicketType dans un TravelDossier
sub getTicketType {
  my $self   = shift;
  my $params = shift;
  
  my $lwdPos = $params->{lwdPos};
  
  return 'UNKNOWN' unless defined $lwdPos;
  
  my @travelDossiers = $self->doc->findnodes('*/Metadossier/TravelDossiers/TravelDossier');
  
  my $ticketType = '';

  if (scalar @travelDossiers == 1 ) 
  {
    # For single AIR or single RAIL or Multi DV RAIL only : there is only one TravelDossier by XML
	$ticketType = $travelDossiers[0]->find('TicketType')->to_literal->value(); 
  }elsif (scalar @travelDossiers > 1 )  
  {
	# For Multi AIR (OWP) : several TravelDossier by XML
	$ticketType = $travelDossiers[$lwdPos]->find('TicketType')->to_literal->value();
  }
     
	 
  return $ticketType;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Fonction de récupération des identifiants E-Tickets utilisés
# par les voyageurs pour un booking Train.
# ~ Similaire à getSrfoids mais plus complet [...]
sub getEticketIds {
  my $self   = shift;
  my $params = shift;

  my $lwdPos = $params->{lwdPos};
  
  my @travelDossiers = $self->doc->findnodes('*/Metadossier/TravelDossiers/TravelDossier');
  my @eticketIds     = $travelDossiers[$lwdPos]->findnodes('TrainDossier/EticketIds/TravellerEticketId');
  
  return [] if (scalar(@eticketIds) == 0);

  my $docTypes = {
    PASSPORT  => 'PP',
    DL        => 'DL',
    ID        => 'NI', };
  
  my @srfoids = ();
  
  NODE: foreach my $eticketNode (@eticketIds) {

    my $loyaltyCard  = $eticketNode->findnodes('LoyaltyCard');
    my $idDocument   = $eticketNode->findnodes('IDDocument');
    my $noId         = $eticketNode->findnodes('NoID');
    my $paymentMean  = $eticketNode->findnodes('PaymentMean');
    my $birthDate    = $eticketNode->findnodes('BirthDate');
    my $perCode      = $eticketNode->findnodes('User')->[0]->getAttribute('PerCode');
    
    my $sLoyaltyCard = $loyaltyCard->size;
    my $sIdDocument  = $idDocument->size;
    my $sNoId        = $noId->size;
    my $sPaymentMean = $paymentMean->size;
    my $sBirthDate   = $birthDate->size; 
    
    if ($sLoyaltyCard + $sIdDocument + $sNoId + $sPaymentMean + $sBirthDate == 0) {
      notice("No eticket document founded for PerCode = $perCode - Cannot proceed.");
      next NODE;
    }
    # elsif ($sLoyaltyCard + $sIdDocument + $sNoId + $sPaymentMean > 1) {
    #   notice('Multiple etickets documents for one user ! Cannot proceed.');
    #   next NODE;
    # }
    else {
      # -------------------------------------------------------------------------------
      # LoyaltyCard      
      if ($sLoyaltyCard == 1) {
        my $cardType        = $loyaltyCard->[0]->getAttribute('Type');
        my $cardCode        = $loyaltyCard->[0]->getAttribute('Code');
        next NODE if ($cardType ne 'LC');
        my $cardNumber      = $loyaltyCard->[0]->find('CardNumber')->to_literal->value();
        my $supplierNode    = $loyaltyCard->[0]->findnodes('IssuingSuppliers/Supplier');
        my $supplierCode    = '';
           $supplierCode    = $supplierNode->[0]->getAttribute('Code') if ($supplierNode->size == 1);
        my $supplierService = '';
           $supplierService = $supplierNode->[0]->find('Service')->to_literal->value() if ($supplierNode->size == 1);;
        next NODE unless ($supplierService =~ /^(RAIL|ETICKET)$/);
        
        push (@srfoids, { EticketType     => 'LoyaltyCard',
                          PerCode         => $perCode,
                          DocNumber       => $cardNumber,
                          DocType         => 'FF',
                          CardCode        => $cardCode,
                          SupplierCode    => $supplierCode,
                          SupplierService => $supplierService  } );
      }
      # -------------------------------------------------------------------------------
      # IDDocument
      if ($sIdDocument == 1) {
        my $docType         = $idDocument->[0]->find('DocumentType')->to_literal->value();
        next NODE if ($docType !~ /^(PASSPORT|DL|ID)$/);
        my $docNumber       = $idDocument->[0]->find('Number')->to_literal->value();
        
        push (@srfoids, { EticketType  => 'IDDocument',
                          PerCode      => $perCode,
                          DocNumber    => $docNumber,
                          DocType      => $docTypes->{$docType}  } );
      }
      # -------------------------------------------------------------------------------
      # PaymentMean
      if ($sPaymentMean == 1) {
        my $paymentMeanNode = $paymentMean->[0]->findnodes('PaymentMean');
        my $CcCode          = '';
           $CcCode          = $paymentMean->[0]->find('CcCode')->to_literal->value();
        my $Service         = $paymentMeanNode->[0]->find('Service')->to_literal->value();
        my $PaymentType     = $paymentMeanNode->[0]->find('PaymentType')->to_literal->value();

        push (@srfoids, { EticketType  => 'PaymentMean',
                          PerCode      => $perCode,
                          CcCode       => $CcCode,
                          Service      => $Service,
                          PaymentType  => $PaymentType } );
      }
      # -------------------------------------------------------------------------------
      # BirthDate
      if ($sBirthDate == 1) {
        my $BIRTHDATE       = $eticketNode->find('BirthDate')->to_literal->value();

        push (@srfoids, { EticketType  => 'BirthDate',
                          PerCode      => $perCode,
                          BirthDate    => fielddate2amaddate($BIRTHDATE) } );

      }
      # -------------------------------------------------------------------------------
      # NoID
      if ($sNoId == 1) {
        my $NOID            = $eticketNode->find('NoID')->to_literal->value();
        next NODE if ($NOID eq 'false');

        push (@srfoids, { EticketType  => 'NoID',
                          PerCode      => $perCode,  } );
      }

    }

  } # Fin NODE: foreach my $eticketNode (@eticketIds)

  return \@srfoids;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Retourne la "DepartureDate" du MetaDossier
sub getMdDepartureDate {
  my $self = shift;
  
  my $mdNode   = $self->doc->findnodes('*/Metadossier');
  my $depDate  = $mdNode->[0]->find('DepartureDate')->to_literal->value();
  
  return '' if ((!defined $depDate) || ($depDate =~ /^\s*$/));
  return $depDate;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Retourne la "BookDate" du MetaDossier
sub getMdBookDate {
  my $self = shift;
  
  my $mdNode   = $self->doc->findnodes('*/Metadossier');
  my $bookDate = $mdNode->[0]->find('BookDate')->to_literal->value();
  
  return '' if ((!defined $bookDate) || ($bookDate =~ /^\s*$/));
  return $bookDate;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Retourne la supposée vraie "BookDate" du MetaDossier.
#  ~ Basé sur les évènements BOOK ou TRAINBOOK. ~
sub getMdRealBookDate {
  my $self = shift;
  
  my $bookDate = undef;
  my $events   = $self->getMdEvents;
    
  EVENT: foreach my $event (@$events) {
    if ((exists $event->{EventAction}) &&
        ($event->{EventAction} =~ /^(BOOK|TRAINBOOK)$/)) {
      $bookDate = $event->{EventDate};
      last EVENT;
    }
  }
  
  return '' if ((!defined $bookDate) || ($bookDate =~ /^\s*$/));
  return $bookDate;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Renvoie la date de naissance d'un voyageur identifié par sa
#  position dans le fichier XML.
sub getTravellerBirthDate {
  my $self         = shift;
  my $trvPos       = shift;
     
  my $compteur     =  0;
  my $birthDate    = '';
  
  my @travellers   = $self->doc->findnodes('*/Metadossier/Travellers/Traveller');

  foreach (@travellers) {
    if ($compteur == $trvPos) {
      my $UserNode = $_->findnodes('User');
      $birthDate   = $UserNode->[0]->findnodes('PersonalInfo')->[0]->find('BirthDate')->to_literal->value();
      last;
    }
    $compteur++;
  }
  
  return $birthDate;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# S'agit-il d'une MeetingCompany ?
sub isMeetingCompany {
  my $self = shift;
  
  my $bookerNode  = $self->doc->findnodes('*/Metadossier/BookedBy/Booker');
  my $companyNode = $bookerNode->[0]->findnodes('Company/CompanyCoreInfo');
  
  my $isMeeting   = 0;
     $isMeeting   = $companyNode->[0]->find('IsMeeting')->to_literal->value() || 0;
     $isMeeting   = ($isMeeting eq 'true') ? 1 : 0;
  
  return $isMeeting;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Retourne le Meeting Order Number
sub getMeetingOrderNumber {
  my $self = shift;
  
  my $mdNode  = $self->doc->findnodes('*/Metadossier');
  my $meeting = $mdNode->[0]->find('MeetingOrderNumber')->to_literal->value();
  
  return '' if ((!defined $meeting) || ($meeting =~ /^\s*$/));
  return $meeting;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Est-ce que le booker est un voyageur ?
sub isBookerTraveller {
  my $self = shift;
  
  my $bookerInfos     = $self->getBookerInfos;
  my $travellerStruct = $self->getTravellerStruct;

  foreach (@$travellerStruct) {
    return 1 if ($bookerInfos->{BookerPerCode} eq $_->{PerCode});
  }
  
  return 0;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Donne moi le PerCode du Booker
sub getBookerPerCode {
  my $self = shift;
  
  my $res  = $self->getBookerInfos->{BookerPerCode} || -1;
  
  return $res;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Vérifie si le voyageur est configuré comme ne recevant pas d'email (ShadowUser)
sub isTravellerShadowUser {
  my $self       = shift;
  my $params     = shift;

  my $trvPos     = $params->{trvPos};   # Position du Traveller dans le XML
  my @travellers = $self->doc->findnodes('*/Metadossier/Travellers/Traveller');
  
  my $EmailType  = '';
  my $compteur   =  0;
  
  foreach (@travellers) {
    if ($compteur == $trvPos) {
      my $UserNode = $_->findnodes('User');
      $EmailType   = $UserNode->[0]->find('EmailMode')->to_literal->value();
      last;
    }
    $compteur++;
  }
  
  return 1 if ($EmailType eq 'NONE');
  return 0;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Projet RavelGold : Récupère les informations du nouveau noeud
#    <PaxPnrInformations> ... </PaxPnrInformations>
sub getPaxPnrInformations {
  my $self      = shift;
  my $params    = shift;

  my $lwdPos    = $params->{lwdPos};
  
  my @travelDossiers  = $self->doc->findnodes('*/Metadossier/TravelDossiers/TravelDossier');
  my @paxPnrInfoNodes;
  if (scalar @travelDossiers == 1 ) 
  {
    # For single AIR or single RAIL or Multi DV RAIL only : there is only one TravelDossier by XML
	@paxPnrInfoNodes = $travelDossiers[0]->findnodes('TrainDossier/PaxPnrInformations/PaxPnrInformation');;
  }elsif (scalar @travelDossiers > 1 )  
   {
	# For Multi AIR (OWP) : several TravelDossier by XML
	@paxPnrInfoNodes = $travelDossiers[$lwdPos]->findnodes('TrainDossier/PaxPnrInformations/PaxPnrInformation');
  }
  
  my @paxPnrInfoNodes = $travelDossiers[$lwdPos]->findnodes('TrainDossier/PaxPnrInformations/PaxPnrInformation');
  
  return [] if (scalar(@paxPnrInfoNodes) == 0);
  
  my @paxPnrInfo = ();

  NODE: foreach my $paxPnrInfoNode (@paxPnrInfoNodes) {
    my $PerCode     = $paxPnrInfoNode->find('PerCode')->to_literal->value();
    my $Pnr         = $paxPnrInfoNode->find('Pnr')->to_literal->value();
    my $FirstName   = $paxPnrInfoNode->find('FirstName')->to_literal->value();
    my $LastName    = $paxPnrInfoNode->find('LastName')->to_literal->value();
    my $ResarailId  = $paxPnrInfoNode->find('ResarailId')->to_literal->value();
    push (@paxPnrInfo, { PerCode     => $PerCode,
                         DV          => $Pnr,
                         FirstName   => $FirstName,
                         LastName    => $LastName,
                         ResarailId  => $ResarailId } );
  }
  
  return \@paxPnrInfo;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Renvoie une structure des différents driver CAR
sub getDriverStruct {
  my $self = shift;
  
  my @struct   = ();
  my $compteur = 0;

  my $PickUpInformation = $self->doc->findnodes('*/Metadossier/TravelDossiers/TravelDossier/MaseratiCarDossier/MaseratiCarSegments/MaseratiCarSegment/PickUp/Station/Address/Country');
  my $PickUpInformationCode = $PickUpInformation->[0]->getAttribute('Code');

  my @DriverDossiers = $self->doc->findnodes('*/Metadossier/TravelDossiers/TravelDossier/MaseratiCarDossier/MaseratiCarSegments/MaseratiCarSegment/DeliveryInformations');
  my @SecondDriver   = $self->doc->findnodes('*/Metadossier/TravelDossiers/TravelDossier/MaseratiCarDossier/MaseratiCarSegments/MaseratiCarSegment/DeliveryInformations/secondDriver/FirstName');  
     
  foreach (@DriverDossiers) {
    
    my $compteur = 1;
    
    # at this point, the control on the dossiertype has been made by the workflow and getTravellerStruct
    # we are sure it's a maserati booking
 
    my $DeliveryContactInstructions     =  $_->find('deliveryContactInstructions')->to_literal->value();
    my $CollectionContactInstructions   =  $_->find('collectionContactInstructions')->to_literal->value();
    my $DeliveryContactName             =  $_->find('deliveryContactName')->to_literal->value();
    my $CollectionContactName           =  $_->find('collectionContactName')->to_literal->value();
     
    my $M_FirstName    				 	=  $_->find('mainDriver/FirstName')->to_literal->value();
    my $M_LastName     				 	=  $_->find('mainDriver/LastName')->to_literal->value();
    my $M_DateOfBirth  				 	=  $_->find('mainDriver/DateOfBirth')->to_literal->value();
    my $M_PlaceOfBirth				 	=  $_->find('mainDriver/PlaceOfBirth')->to_literal->value();
    my $M_DrivingLicenceIssueDate    	=  $_->find('mainDriver/DrivingLicenceIssueDate')->to_literal->value();
    my $M_DrivingLicenceNumber    	 	=  $_->find('mainDriver/DrivingLicenceNumber')->to_literal->value();
    my $M_DrivingLicenceIssuePlace   	=  $_->find('mainDriver/DrivingLicenceIssuePlace')->to_literal->value();
    my $TMP_DrivingLicenceIssueCountry  =  $_->findnodes('mainDriver/DrivingLicenceIssueCountry');
    my $M_DrivingLicenceIssueCountry 	= $TMP_DrivingLicenceIssueCountry->[0]->getAttribute('Code');
 
     push @struct, { 
    	Pos                			 => 1,
    	M_FirstName        			 => $M_FirstName,
    	M_LastName        			 => $M_LastName,
    	M_DateOfBirth        		 => $M_DateOfBirth,
    	M_PlaceOfBirth       		 => $M_PlaceOfBirth,
    	M_DrivingLicenceIssueDate    => $M_DrivingLicenceIssueDate,
    	M_DrivingLicenceNumber       => $M_DrivingLicenceNumber,
    	M_DrivingLicenceIssuePlace   => $M_DrivingLicenceIssuePlace,
    	M_DrivingLicenceIssueCountry => $M_DrivingLicenceIssueCountry,
    	DeliveryContactInstructions	 => $DeliveryContactInstructions,
    	CollectionContactInstructions=> $CollectionContactInstructions,
        PickUpInformationCode        => $PickUpInformationCode,
        DeliveryContactName          => $DeliveryContactName,
        CollectionContactName        => $CollectionContactName,
        
                     };   
  
   if (scalar(@SecondDriver) != 0)
   {
    my $S_FirstName    				 	=  $_->find('secondDriver/FirstName')->to_literal->value();
    my $S_LastName     				 	=  $_->find('secondDriver/LastName')->to_literal->value();
    my $S_DateOfBirth  				 	=  $_->find('secondDriver/DateOfBirth')->to_literal->value();
    my $S_PlaceOfBirth				 	=  $_->find('secondDriver/PlaceOfBirth')->to_literal->value();
    my $S_DrivingLicenceIssueDate    	=  $_->find('secondDriver/DrivingLicenceIssueDate')->to_literal->value();
    my $S_DrivingLicenceNumber    	 	=  $_->find('secondDriver/DrivingLicenceNumber')->to_literal->value();
    my $S_DrivingLicenceIssuePlace   	=  $_->find('secondDriver/DrivingLicenceIssuePlace')->to_literal->value();
       $TMP_DrivingLicenceIssueCountry  =  $_->findnodes('secondDriver/DrivingLicenceIssueCountry');
    my $S_DrivingLicenceIssueCountry 	= $TMP_DrivingLicenceIssueCountry->[0]->getAttribute('Code');
     my $S_TravelerLoyaltyNumber         =  $_->find('secondDriver/TravelerLoyaltyNumber')->to_literal->value();          

	push @struct, { 
    	Pos                			 => 2,
    	S_FirstName        			 => $S_FirstName,
    	S_LastName        			 => $S_LastName,
    	S_DateOfBirth        		 => $S_DateOfBirth,
    	S_PlaceOfBirth       		 => $S_PlaceOfBirth,
    	S_DrivingLicenceIssueDate    => $S_DrivingLicenceIssueDate,
    	S_DrivingLicenceNumber       => $S_DrivingLicenceNumber,
    	S_DrivingLicenceIssuePlace   => $S_DrivingLicenceIssuePlace,
    	S_DrivingLicenceIssueCountry => $S_DrivingLicenceIssueCountry,
        S_TravelerLoyaltyNumber	 => $S_TravelerLoyaltyNumber,
                     }; 
   }
   
  }
  
  return \@struct;
}

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Fonction visant à applanir les segments
sub _formatSegments {
  my $h_segments = shift;
  my $substitute = shift;
  
  $substitute = 1 if (!defined $substitute);

  my @vendors = ();

  foreach (@$h_segments) { push (@vendors, $_->{VendorCode}); }
  
  my $vendors = join(' ', @vendors);
     $vendors =~ s/(KL|NW|KQ)/AF/ig if ($substitute == 1);

  debug('Vendors = '.$vendors);

  return $vendors;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

1;
