package Expedia::GDS::DV;
#-----------------------------------------------------------------
# Package Expedia::GDS::DV
#
# $Id: DV.pm 619 2011-02-24 13:26:18Z pbressan $
#
# (c) 2002-2009 Expedia.                   www.expediacorporate.fr
#-----------------------------------------------------------------

use strict;
use Data::Dumper;

use Expedia::GDS::PNR;
use Expedia::Tools::Logger qw(&debug &notice &warning &error);
use Expedia::Tools::GlobalVars qw($cnxMgr);

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# CONSTRUCTEUR
sub new {
  my ($class, %params) = @_;

  # Les paramètres obligatoires sont les suivants :
  #   $params  = { DV => $DV, GDS => $GDS }   # EXEMPLE
  my $DV   = $params{DV}  || undef;
  my $GDS  = $params{GDS} || undef;

  # -------------------------------------------------------------------
  # Gestion des paramètres obligatoires
  if ((!$DV) || ($DV !~ /^\w{6}$/)) {
    error('A valid DV parameter must be provided to this constructor. Aborting.');
    return undef;
  }
  if ((!$GDS) || (ref($GDS) ne 'Expedia::Databases::Amadeus')) {
    error('A valid Amadeus connection must be provided to this constructor. Aborting.');
    return undef;
  }
  unless ($GDS->connected) {
    error('Amadeus needs to be connected. Aborting.');
    return undef;
  }
  # -------------------------------------------------------------------
  
  # -------------------------------------------------------------------
  # Paramètres non obligatoires
  my $doWP9 = 1; # Par défaut on effectue une requète de tarification
     $doWP9 = 0 if ((exists $params{doWP9}) && ($params{doWP9} eq '0'));
  # -------------------------------------------------------------------  
  
  my $self = {};
  bless ($self, $class);

  $self->{_DV}          = $DV;     # L'identifiant DV - Dossier Voyage Ravel - Exemple : QOQKFG
  $self->{_GDS}         = $GDS;    # Le handle de connection à AMADEUS
  $self->{_SCREEN}      = [];      # Affichage complet de la DV
  $self->{_WP9}         = [];      # Affichage de la tarification de la DV
  $self->{_WP8}         = [];      # Affichage de la page d'émission de la DV
  $self->{_RTN}         = [];      # Affichage de la page des Birthdate / @ email
  $self->{_SCAN}        = {};      # Temporairement utilisé pour traitement de _SCAN et _WP9
  
  $self->{ITINERAIRE}   = [];      # Informations d'itinéraire extraites de la DV
  $self->{PAX}          = [];      # Informations des PAX extraites de la DV
  $self->{EMISSION}     = [];      # Informations d'émission extraites de la DV
  
  $self->{FAREINFO}     = [];      # Stockage des fareInfo dans l'ordre trouvé dans _WP9
  $self->{WP8INFO}      = [];      # Stockage des infos dans l'ordre trouvé dans _WP8
  $self->{RTNINFO}      = undef;   # Stockage des infos dans l'ordre trouvé dans _RTN
  
  $self->{DVId}         = '';      # Doit normalement correspondre à _DV
  
  $self->{PAXNUM}       = 0;       # Nombre de passagers dans la DV
  $self->{ITANUM}       = 0;       # Nombre de IMAGE-TITRE ACTIVE dans la _WP9
  $self->{TCNNUM}       = 0;       # Nombre de Blocs TCN dans la _WP8
  $self->{COMCODE}      = undef;
  $self->{BOOKTIME}     = undef;
  $self->{TPE}          = 0;       # Titres Pre-Enregistrés présent ou non dans la DV ?
  $self->{ISSUED}       = 0;       # Est-ce que le dossier est émis ou pas ?
  
  $self->{BROKENLINK}   = 1;       # Communication aves ResaRail indisponible par défaut !
  $self->{DVNOTFULL}    = 0;       # 1 lorsque la DV n'a pas pu être récupérée en intégralité
  $self->{SECUREDPNR}   = 0;       # 1 lorsque le message "ACCES INTERDIT A CE PNR" apparait
  $self->{NOTEXISTS}    = 0;       # 1 lorsque le message "ERREUR SUR ADRESSE DOSSIER VOYAGE" apparait
  
  $self->{BOOKINGEMAIL} = undef;   # Est renseigné lorsque figure un email at booking level (Ebillet) Section: ADRESSE MAIL-
  $self->{AMADEUSREF}   = undef;   # Est renseigné lorsque figure la référence AMADEUS (Thalys) Section: PARTICULARITE-
  
  my $resGet = $self->get($doWP9); # Récupération de la DV
  
  notice('Problem detected during "get" operation.')      
    if ($resGet == 0);
  
  notice('No lines were returned when getting this DV !')
    if (scalar(@{$self->{_SCREEN}}) == 0);
  
  # ____________________________________________________________________
  # Problème étrange | La dernière lettre semble tronquée parfois 
  #    FRTCX.FRTCX4WEB 1010/20MAY08 QNGHJ     <<
  if ($self->{_DV} ne $self->{DVId}) {
    my $tmpDV = substr($self->{_DV}, 0, 5);
    if ($tmpDV eq $self->{DVId}) {
      $self->{DVId} = $self->{_DV};
    } else {
      notice('Problem detected with DV Identifier.');
    }
  }
  # ____________________________________________________________________

  return $self;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
sub get {
  my $self  = shift;
  my $doWP9 = shift;

  if ($self->{_DV} && ($self->{_DV} ne '')) {

    # ---------------------------------------------------------
    # Enter in RESARAIL
    my $lines   =  $self->{_GDS}->command(
                     Command     => 'R//IG',
                     NoIG        => 1,
                     NoMD        => 1,
                     PostIG      => 0,
                     ProfileMode => 0);
    unless (grep(/\*\*\s+2C\s+\-\s+RESARAIL\/SNCF\s+\*\*/, @$lines)) {
      notice('Cannot enter Resarail SNCF. Aborting [...]');
      return 0;
    }
    # Message Socrate =
    # ~ COMMUNICATION ACTUELLEMT NON DISPONIBLE - RECOMMENCER PLUS TARD ~
    # ~ TRAITEMENT IMPOSSIBLE - CONTACTER LE HELP DESK D'AMADEUS ~
    if (grep(/RECOMMENCER PLUS TARD/,                          @$lines) ||
        grep(/TRAITEMENT IMPOSSIBLE - CONTACTER LE HELP DESK/, @$lines)) {
      notice('Cannot enter Resarail SNCF. Aborting [...]');
      return 0;
    }
    # ---------------------------------------------------------
    
    $self->{BROKENLINK} = 0;
    
    # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
    # Capture d'écran des informations contenues dans la DV !!!
    $lines = $self->{_GDS}->command(
               Command     => 'R/RT'.$self->{_DV},
               NoIG        => 1,
               NoMD        => 1,
               PostIG      => 0,
               ProfileMode => 0);
               
    $self->{SECUREDPNR} = 1 if (grep(/ACCES INTERDIT A CE PNR/, @$lines));
    $self->{NOTEXISTS}  = 1 if (grep(/ERREUR SUR ADRESSE DOSSIER VOYAGE/, @$lines));

#    unless (grep(/PLACES ATTRIBUEES/,      @$lines) ||
#            grep(/DATE LIMITE DE RETRAIT/, @$lines)) {
#      $lines = $self->{_GDS}->command(
#                 Command     => 'R/RT'.$self->{_DV},
#                 NoIG        => 1,
#                 NoMD        => 1,
#                 PostIG      => 0,
#                 ProfileMode => 0);
#    }

    if (($self->{SECUREDPNR} == 0) && ($self->{NOTEXISTS} == 0)) {
      # Try 3 Move Down
      my $nbTries = 3; 
      TRY: while ($nbTries != 0) {
        my $tmpLines = $self->{_GDS}->command(Command=>'R/MD', NoIG=>1, NoMD=>1, PostIG=>0);
        if (grep(/PLUS RIEN A AFFICHER/, @$tmpLines) || 
            grep(/FIN D\'AFFICHAGE/,     @$tmpLines)) {
          push @$lines, @$tmpLines;
          last TRY;
        } elsif (grep(/RECOMMENCER PLUS TARD/,                          @$tmpLines) ||
                 grep(/TRAITEMENT IMPOSSIBLE - CONTACTER LE HELP DESK/, @$tmpLines)) {
          $self->{DVNOTFULL} = 1; # La DV n'a pas pu être récupérée en intégralité
          last TRY;
        } else { push @$lines, @$tmpLines; }
        $nbTries--;
      }
    } # Fin if (($self->{SECUREDPNR} = 0) && ($self->{NOTEXISTS} == 0))

    $self->{_SCREEN} = $self->_cleanLines($lines);
    # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
    
    my $scan = 0;
       $scan = $self->_scan if (scalar(@{$self->{_SCREEN}}) > 0);
    
    # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
    # Capture d'écran des informations de tarification de la DV !!!
    if ( ($self->{ISSUED}     == 0)                         &&
        (($self->{DVNOTFULL}  == 0) && ($self->{TPE} == 1)) &&
         ($self->{SECUREDPNR} == 0)                         &&
         ($self->{NOTEXISTS}  == 0)) {
      if ($doWP9) {
        $lines = $self->{_GDS}->command(
                   Command     => 'R//W*P9',
                   NoIG        => 1,
                   NoMD        => 1,
                   PostIG      => 0,
                   ProfileMode => 0);
    
        if (grep(/RECOMMENCER PLUS TARD/,                          @$lines) ||
            grep(/TRAITEMENT IMPOSSIBLE - CONTACTER LE HELP DESK/, @$lines)) {
          notice('Cannot enter Resarail SNCF. Aborting [...]');
          $self->{BROKENLINK} = 1;
          return 0;
        }
    
        # Try many Move Down
        my $segNums = scalar @{$self->{ITINERAIRE}};
           $segNums = 1 if ($segNums == 0);
        my $nbTries    = $self->{PAXNUM} * $segNums;
        TRY: while ($nbTries != 0) {
          my $tmpLines = $self->{_GDS}->command(Command=>'R/MD', NoIG=>1, NoMD=>1, PostIG=>0);
          if (grep(/PLUS RIEN A AFFICHER/, @$tmpLines) || 
              grep(/FIN D\'AFFICHAGE/,     @$tmpLines)) {
            push @$lines, @$tmpLines;
            last TRY;
          } elsif (grep(/RECOMMENCER PLUS TARD/,                          @$tmpLines) ||
                   grep(/TRAITEMENT IMPOSSIBLE - CONTACTER LE HELP DESK/, @$tmpLines)) {
            last TRY;
          } else { push @$lines, @$tmpLines; }
          $nbTries--;
        }
        
        $self->{_WP9} = $self->_cleanLines($lines);
        
        my $scanWP9 = 0;
           $scanWP9 = $self->_scanWP9;
        
      } # Fin if ($doWP9)
    } else {
      notice('Secured PNR detected')                  if  ($self->{SECUREDPNR} == 1);
      notice('Reference does not exist in Resarail')  if  ($self->{NOTEXISTS}  == 1);
      notice('Booking already issued detected [...]') if  ($self->{ISSUED}     == 1);
      notice('No fare found in booking [...]')        if (($self->{DVNOTFULL}  == 0) && ($self->{TPE} == 0));
    } 
    # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
       
    $self->{_GDS}->command(
      Command     => 'R//IG',
      NoIG        => 1,
      NoMD        => 1,
      PostIG      => 0,
      ProfileMode => 0);       
    
  } else {
    error('A valid DV parameter must be provided to this method. Aborting.');
    return 0;
  }

  return 1;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Methode permettant la réouverture "facile" d'une DV sans MD.
sub RT {
  my $self  = shift;
  
  my $lines = undef;
  
  if ($self->{_DV} && ($self->{_DV} ne '')) {
    # ---------------------------------------------------------
       $lines   =  $self->{_GDS}->command(
                     Command     => 'R//IG',
                     NoIG        => 1,
                     NoMD        => 1,
                     PostIG      => 0,
                     ProfileMode => 0);
    unless (grep /\*\*\s+2C\s+\-\s+RESARAIL\/SNCF\s+\*\*/, @$lines) {
      warning('Cannot enter Resarail SNCF. Aborting.');
      return undef;
    }
    # ---------------------------------------------------------                     
    
    # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
    # Capture d'écran des informations contenues dans la DV !!!
    $lines = $self->{_GDS}->command(
               Command     => 'R/RT'.$self->{_DV},
               NoIG        => 1,
               NoMD        => 1,
               PostIG      => 0,
               ProfileMode => 0);

    unless (grep(/PLACES ATTRIBUEES/, @$lines) or
            grep(/DATE LIMITE DE RETRAIT/, @$lines)) {
      $lines = $self->{_GDS}->command(
                 Command     => 'R/RT'.$self->{_DV},
                 NoIG        => 1,
                 NoMD        => 1,
                 PostIG      => 0,
                 ProfileMode => 0);
    }
  }
  
  return $lines;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Scan la DV et range les informations contenues dedans...
sub _scan {
  my $self  = shift;

  my $line  = undef;
  my @lines = @{$self->{_SCREEN}};

  return 0 if (!$self->{_SCREEN} || scalar(@{$self->{_SCREEN}}) == 0);
  return 0 if  ($self->{_SCREEN}->[0] ne 'R/RT'.$self->{_DV});
  
  # $$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$
  # Scan de la DV
  debug('Scan de la DV en cours...');
  my $section = undef;
  LINE: while (scalar @lines > 0) {
    $line = shift @lines;
    # -----------------------------------------
    # Passenger lines
    if ($line =~ /^(\s*\d+\.\d+\s*[A-Z- ]+\/[A-Z-]+.*)\s*$/x) {
      $section = 'PAX';
      $self->{_SCAN}->{PAX} .= $1;
      next LINE;
    }
    # -----------------------------------------    
    # Itinéraire
    if ($line =~ /^(ITINERAIRE-|PAS D\'ITINERAIRE)$/) {
      $section = 'ITINERAIRE';
      next LINE;
    }    
    # -----------------------------------------
    # Places Attribuées
    if ($line =~ /^PLACES ATTRIBUEES -\s*$/) {
      $section = 'PLACES ATTRIBUEES';
      next LINE;
    }
    # -----------------------------------------
    # Titre pré enregistré
    if ($line =~ /^TITRES PRE ENREGISTRES/) {
      $section = 'TITRES PRE ENREGISTRES';
      $self->{TPE} = 1;
      next LINE;
    }
    # -----------------------------------------
    # Téléphone
    if ($line =~ /^TELEPHONE -\s*$/) {
      $section = 'TELEPHONE';
      next LINE;
    }
    # -----------------------------------------
    # Adresse
    if ($line =~ /^ADRESSE -\s*$/) {
      $section = 'ADRESSE';
      next LINE;
    }
    # -----------------------------------------
    # Adresse
    if ($line =~ /^ADRESSE EMAIL -\s*$/) {
      $section = 'ADRESSEMAIL';
      next LINE;
    }
    # -----------------------------------------
    # Particularités
    if ($line =~ /^PARTICULARITES-\s*$/) {
      $section = 'PARTICULARITES';
      next LINE;
    }
    # -----------------------------------------
    # Espace Loisirs / Intermédiaire / Affaire
    if ($line =~ /^ESPACE/) {
      $section = 'ESPACE';
      next LINE;
    }
    # -----------------------------------------
    # Date limite de retrait
    if ($line =~ /^DATE LIMITE DE RETRAIT -\s*$/) {
      $section = 'EMISSION';
      next LINE;
    }
    # -----------------------------------------
    # FCTRX line
    if ($line =~ /^ \s* (?:FRTCX|U6H0|B020|Q0F0|M3S0|Z5O0|C770|E000|E010)\.[A-Z0-9\*]+ \s+ (\d{1,2})(\d\d) \/ (\d+)(\w{3})(\d+) \s+ (\w+) \s*/x ) {
      $section = 'BODY';
      my %d2d  = qw (JAN 01 FEB 02 MAR 03 APR 04 MAY 05 JUN 06 JUL 07 AUG 08 SEP 09 OCT 10 NOV 11 DEC 12);
      $self->{BOOKTIME} = '20'.$5.$d2d{$4}.$3.sprintf("%2.2d", $1).$2;
      $self->{DVId}     = $6;
      next LINE;
    }
    # -----------------------------------------
    # U6H0 or B020 line = FCTRX mais dossier divisé
    if ($line =~ /^ \s* (?:FRTCX|U6H0|B020|Q0F0|M3S0|Z5O0|C770|E000|E010)\.\w+ \*\D{3} \s+ (\d{1,2})(\d\d) \/ (\d+)(\w{3})(\d+) \s+ (\w+) \s*/x ) {
      $section = 'BODY';
      my %d2d  = qw (JAN 01 FEB 02 MAR 03 APR 04 MAY 05 JUN 06 JUL 07 AUG 08 SEP 09 OCT 10 NOV 11 DEC 12);
      $self->{BOOKTIME} = '20'.$5.$d2d{$4}.$3.sprintf("%2.2d", $1).$2;
      $self->{DVId}     = $6;
      next LINE;
    }
    # -----------------------------------------
    # COMPANYCODE line
    if ($line =~ /COMPANYCODE (\d+)\s*$/ ) {
      $section = 'BODY';
      $self->{COMCODE} = $1;
    }
    # -----------------------------------------
    # Update previous line content or analyze lines
    if (defined($section)) {
      if ($section eq 'PAX') {
        $self->{_SCAN}->{PAX} .= $line;
        next LINE;
      }
      # ________________________________________________________________________
      # Projet Ebillet Août 2009
      if ($section eq 'ADRESSEMAIL') {
        if ($line =~ /^\s+\d+\.(.*)$/) {
          $self->{BOOKINGEMAIL} =  $1;
          $self->{BOOKINGEMAIL} =~ s/\s+//ig if (defined $self->{BOOKINGEMAIL});
        }
        next LINE;
      }
#      if ($section eq 'PARTICULARITES') { 
#        if ($line =~ /^\s+\d+\.\s*AMADEUS\s*REF(.*)$/) {
#          $self->{AMADEUSREF}   =  $1;
#          $self->{AMADEUSREF}   =~ s/\s+//ig if (defined $self->{AMADEUSREF});
#        }
#        next LINE;
#      }
      # ________________________________________________________________________
      elsif ($section eq 'ITINERAIRE') {
        if ($line =~ /^\s+(\d)\s(\w{2})(?:\s+)?(\d+|OPEN)(?:\s|\*)(\D{2})(\d{2}\D{3})\s\d\s(\D{5})\s(\D{5})/) {
          push (@{$self->{ITINERAIRE}}, {
                   Line          => $1,
                   Data          => $line,
                   Supplier      => $2,
                   TrainNo       => $3,
                   BookingClass  => $4,
                   DepartureDate => $5,
                   From          => $6,
                   To            => $7 });
        } else {
          debug("ITINERAIRE line doesn't match regexp [...]");
          debug('~ line = '.$line);
        }
        next LINE;
      }
      elsif ($section eq 'EMISSION') {
        if ($line =~ /^\s+\d\.(TL|T-)/) {
          debug("LIGNE D'EMISSION = $line");
          $self->{ISSUED} = 1 if ($1 eq 'T-');
        }
        elsif ($line =~ /^(\w{2})\s+(\d+)\s+(\w{2})\s+(\d+\.\d+EUR)/) {
          my $ticketField = $1; my $ticketNum   = $2;
          my $ticketType  = $3; my $ticketPrice = $4;
          my $nextLine    = shift @lines;
             $nextLine    = shift @lines if ($nextLine =~ /^\s+(\d+\.\d+FRF)\s+$/);
          if ($nextLine =~ /^(\d)\s(\d{8})\s((?:\D{2}\s?){1,2})\s{0,1}(?:$|((?:\d{2}\s?)+)?)/) {
            my $paxNum    = $1; my $TCN         = $2;
            my $supplier  = $3; my $segments    = $4;
            foreach ($supplier, $segments) { $_ =~ s/^\s*|\s*$//g if (defined $_); }
            push (@{$self->{EMISSION}}, {
              TicketField => $ticketField,
              TicketNum   => $ticketNum,
              TicketType  => $ticketType,
              TicketPrice => $ticketPrice,
              PaxNum      => $paxNum,
              TCN         => $TCN,
              Supplier    => $supplier,
              Segments    => $segments, });
          }
        }
        next LINE;
      }
    }
    # -----------------------------------------
  }
  
  # #######################################################
  # Ré-analyse de la ligne _SCAN->PAX pour connaître le
  #   nombre de passagers, leur rang et l'id suivant leur nom
  my $paxLine = $self->{_SCAN}->{PAX};
     $paxLine =~ s/\s*(\d\.\d)/  $1/g;
  $self->{_SCAN}->{PAX} = $paxLine;
  debug('paxLine = '.$paxLine);
  my $paxNum  = 0;
  while ($paxLine =~ s/^\s*(\d+)\.(\d+)([A-Z-\/ ]+)($|[&\?\-\$]\S+|\s{2})(\s*\d+\.\d+|\s*$)?/$5/) {
    debug("Found PAX #$1 = $3 with $2 surname(s).");
    push (@{$self->{PAX}}, { rank => $1.$2, id => $4, Pax => $3 });
    $paxNum += 1;
  }
  debug('PAXNUM = '.$paxNum);
  $self->{PAXNUM} = $paxNum;
  # #######################################################
  # Fin du scan de la DV
  # $$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$

  return 1;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Scan de la tarification W*P9
sub _scanWP9 {
  my $self  = shift;
    
  return 0 if (!$self->{_WP9} || scalar(@{$self->{_WP9}}) == 0);
  return 0 if  ($self->{_WP9}->[0] ne 'R//W*P9');
  
  # ___________________________________________________________________________
  # Scan de la tarification de la DV
  debug('Scan de la tarification de la DV en cours...');
  my $line      = undef;
  my @lines     = @{$self->{_WP9}};
  my $itaNum    = 0;                # Nombre d'image titre active
  my $fareInfo  = '';
  my @elements  = ();
  my $fareReduc = ''; my $paxList = ''; my $segList = ''; my $nbPaxIndicator = '';
  my $advanced  = [];
  LINE: while ($line = shift @lines) {
    next LINE unless ($line =~ /^IMAGE-TITRE ACTIVE :\s*(\w.*\w)?\s*$/);
    $fareInfo  = $1 if (defined $1);
    $itaNum   += 1;
    @elements  = split (/\$/, $fareInfo); # P1PT00AD$S1$N1.1$Q/FN50
    $fareReduc = ''; $paxList = ''; $segList = ''; $nbPaxIndicator = '';
    $advanced  = [];
    foreach my $elt (@elements) {
      if ($elt =~ /^N(.*)/)   { $paxList   = $1; }
      if ($elt =~ /^Q\/(.*)/) { $fareReduc = $1; }
      if ($elt =~ /^S(.*)/)   { $segList   = $1; }
    }
    debug('fareReduc = '.$fareReduc) if ($fareReduc);
    debug('paxList   = '.$paxList)   if ($paxList);
    debug('segList   = '.$segList)   if ($segList);
    $paxList = ''    if ($paxList eq 'I');
    $paxList = '1.1' if (($self->{PAXNUM} == 1) && ($paxList eq ''));
    debug('paxList   = '.$paxList)   if ($paxList);
    # ----------------------------------------------------------------
    # Pour les lignes restantes, on essaye d'attraper le "CODEPRIX:"
    #   ainsi que la destination.
    my $i              = 0;
    my $priceCodeFound = 0;
    my $priceCode      = '';
	my $noseg          = 0 ; 
    LINEBIS: foreach (@lines) {
      if ($_ =~ /^PASSAGER : \w{6}\/(\d)/) {
        $nbPaxIndicator = $1;
        debug('PaxNoIndicator = '.$nbPaxIndicator);
      }
      if (($priceCodeFound == 0) && ($_ =~ /CODEPRIX/)) {
        $priceCode =  substr($lines[$i+1], 48, 16);
        $priceCode =~ s/\s*//ig;
        debug('CODEPRIX: '.$priceCode);
        $priceCodeFound = 1;
      }
      if ($_ =~ /^ (\w{6})\s+(\D{5})\s+(\D{5})/) {
        my $from = $2; debug('From = '.$from);
        my $to   = $3; debug('To   = '.$to);
		
        if ($lines[$i+1] =~ /^NO SEG\.:\s?((?:\d{2} )+)/) {
		  $noseg = 1; 
          my $segmentList =  $1;
             $segmentList =~ s/^\s*|\s*$//g if (defined $segmentList);
          debug('Segments = '.$segmentList);
          my @segmentList = split(' ', $segmentList);
          foreach (@segmentList) { $_ = sprintf("%d", $_); }
          push @{$advanced}, { From => $from, To => $to, SegList => \@segmentList };
        }

		#FOR EHF https://jira/jira/browse/EGE-96922		
		if ($lines[$i+2] =~ /^NO SEG\.:\s?((?:\d{2} )+)/ && $noseg == 0 ) {
          my $segmentList =  $1;
             $segmentList =~ s/^\s*|\s*$//g if (defined $segmentList);
          debug('Segments = '.$segmentList);
          my @segmentList = split(' ', $segmentList);
          foreach (@segmentList) { $_ = sprintf("%d", $_); }
          push @{$advanced}, { From => $from, To => $to, SegList => \@segmentList };
        }
		
      }
      last LINEBIS if ($_ =~ /^IMAGE-TITRE ACTIVE :\s*(\w.*\w)?\s*$/);
      $i++;
    }
    push @{$self->{FAREINFO}}, {
      itaNum         => $itaNum,
      fareInfo       => $fareInfo,
      fareReduc      => $fareReduc,
      priceCode      => $priceCode,
      paxList        => $paxList,
      segList        => $segList,
      advanced       => $advanced,
      nbPaxIndicator => $nbPaxIndicator,
    };
    # ----------------------------------------------------------------
    # Puis on passe à l'IMAGE-TITRE ACTIVE suivante.
  }
  $self->{ITANUM} = $itaNum;
  # ___________________________________________________________________________
  
  return 1;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Scan des informations d'émission de la DV. Utilisé dans TAS SNCF.
sub _scanWP8 {
  my $self  = shift;
  
  # On se replace sur le dossier
  $self->{_GDS}->command(
    Command     => 'R//IG',
    NoIG        => 1,
    NoMD        => 1,
    PostIG      => 0,
    ProfileMode => 0);
  $self->{_GDS}->command(
    Command     => 'R/RT'.$self->{_DV},
    NoIG        => 1,
    NoMD        => 1,
    PostIG      => 0,
    ProfileMode => 0);

  # ___________________________________________________________________________
  # Capture d'écran des informations de l'émission de la DV !!!
  my $lines = $self->{_GDS}->command(
    Command     => 'R//W*P8',
    NoIG        => 1,
    NoMD        => 1,
    PostIG      => 0,
    ProfileMode => 0);

  if (grep(/RECOMMENCER PLUS TARD/,                          @$lines) ||
      grep(/TRAITEMENT IMPOSSIBLE - CONTACTER LE HELP DESK/, @$lines)) {
    notice('Cannot enter Resarail SNCF. Aborting [...]');
    return 0;
  }

  # Try many Move Down
  my $segNums = scalar @{$self->{ITINERAIRE}};
     $segNums = 1 if ($segNums == 0);
  my $nbTries = $self->{PAXNUM} * $segNums;
  TRY: while ($nbTries != 0) {
    my $tmpLines = $self->{_GDS}->command(Command=>'R/MD', NoIG=>1, NoMD=>1, PostIG=>0);
    if (grep(/PLUS RIEN A AFFICHER/, @$tmpLines) || 
        grep(/FIN D\'AFFICHAGE/,     @$tmpLines)) {
      push @$lines, @$tmpLines;
      last TRY;
    } elsif (grep(/RECOMMENCER PLUS TARD/,                          @$tmpLines) ||
             grep(/TRAITEMENT IMPOSSIBLE - CONTACTER LE HELP DESK/, @$tmpLines)) {
      last TRY;
    } else { push @$lines, @$tmpLines; }
    $nbTries--;
  }
    
  $self->{_WP8} = $self->_cleanLines($lines);
  # ___________________________________________________________________________

  debug('_WP8 = '.Dumper($self->{_WP8}));
  
  my $paxSection = 0; 
  my @wp8lines   = @{$self->{_WP8}};
  my $tcnNum     = 0;                # Nombre de blocs TCN
  
  LINE: while (my $wp8Line = shift @wp8lines) {
    if ($wp8Line =~ /TCN\s+CODE TARIF\s+MONTANT/) {
      debug('!!! NOUVEAU BLOC TCN !!!');
      $tcnNum    += 1;
      $paxSection = 0;
      my @paxList = ();
      my @segList = ();
      LINEBIS: foreach (@wp8lines) {
        if ($_ =~ /^NO SEGMENTS:\s+((?:\d{2}(?: |$))+)/) {
          debug('SegLine = '.$_);
          my $segList =  $1;
             $segList =~ s/^\s*|\s*$//g if (defined $segList);
             @segList =  split(' ', $segList);
          foreach (@segList) { $_ = sprintf("%d", $_); }
        }
        if (($paxSection == 1) && ($_ =~ /\s+(\d)\.\d\s+[A-Z]+/)) {
          debug('PaxLine = '.$_);
          push @paxList, $1;
          next LINEBIS;
        }
        if ($_ =~ /PAX: NO\s+NOM\s+TYPE\/NBRE\s+NO FID\./) { $paxSection = 1; next LINEBIS; }
        if ($_ =~ /TCN\s+CODE TARIF\s+MONTANT/)            { last LINEBIS; }
      } # Fin LINEBIS: foreach (@wp8lines)
      push @{$self->{WP8INFO}}, { paxList => \@paxList, segList => \@segList };
    } # Fin if ($wp8Line =~ /TCN\s+CODE TARIF\s+MONTANT/)
  } # Fin LINE: while (my $wp8Line = shift @wp8lines)

  $self->{TCNNUM} = $tcnNum;
  debug('@{$self->{WP8INFO}} = '.Dumper($self->{WP8INFO}));

  return 1;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# R/RTN - Projet Ebillet ~ 01 Décembre 2009
#  Vérification de la présence des dates de naissance et des @ mail
sub _scanRTN {
  my $self  = shift;
  
  # On se replace sur le dossier
  $self->{_GDS}->command(
    Command     => 'R//IG',
    NoIG        => 1,
    NoMD        => 1,
    PostIG      => 0,
    ProfileMode => 0);
  $self->{_GDS}->command(
    Command     => 'R/RT'.$self->{_DV},
    NoIG        => 1,
    NoMD        => 1,
    PostIG      => 0,
    ProfileMode => 0);

  my $lines = $self->{_GDS}->command(
    Command     => 'R/RTN',
    NoIG        => 1,
    NoMD        => 1,
    PostIG      => 0,
    ProfileMode => 0);
             
  # Try many Move Down
  my $nbTries = $self->{PAXNUM};
  TRY: while ($nbTries != 0) {
    my $tmpLines = $self->{_GDS}->command(Command=>'R/MD', NoIG=>1, NoMD=>1, PostIG=>0);
    if (grep(/PLUS RIEN A AFFICHER/, @$tmpLines) || 
        grep(/FIN D\'AFFICHAGE/,     @$tmpLines)) {
      push @$lines, @$tmpLines;
      last TRY;
    } elsif (grep(/RECOMMENCER PLUS TARD/,                          @$tmpLines) ||
             grep(/TRAITEMENT IMPOSSIBLE - CONTACTER LE HELP DESK/, @$tmpLines)) {
      last TRY;
    } else { push @$lines, @$tmpLines; }
    $nbTries--;
  }
  
  $self->{_RTN} = $self->_cleanLines($lines);
  
  debug('_RTN = '.Dumper($self->{_RTN}));
  
  my @rtnLines     = @{$self->{_RTN}};
  $self->{RTNINFO} = [];
  
  LINE: while (my $rtnLine = shift @rtnLines) {
    if ($rtnLine =~ /^\s*(\d+)\.(\d+)([A-Z\/ ]+)($|[&\?\-\$]\S+|\s{2})(\s*\d+\.\d+|\s*$)?/) {
      debug('!!! NOUVEAU BLOC TRAVELLER !!!');
      my $rank       = $1.$2;
      my $birthdate  = undef;
      my $email      = undef;
      LINEBIS: foreach (@rtnLines) {
        if ($_ =~ /\s+DN\s+:\s+(\d{2}\D{3}\d{4})?(\s+(?:MRC|REF)\s+:\s+\d+)?\s*$/) {
          debug('BirthDate Line = '.$_);
          $birthdate = $1;
          $birthdate =~ s/\s+//ig if defined $birthdate;
        }
        if ($_ =~ /\s+MAIL\s+:\s+(.*)$/) {
          debug('Email Line     = '.$_);
          $email     = $1;
          $email     =~ s/\s+//ig if defined $birthdate;
        }
        if ($_ =~ /^\s*(\d+)\.(\d+)([A-Z\/ ]+)($|[&\?\-\$]\S+|\s{2})(\s*\d+\.\d+|\s*$)?/)   { last LINEBIS; }
      } # Fin LINEBIS: foreach (@rtnLines)
      push @{$self->{RTNINFO}}, { rank => $rank, birthdate => $birthdate, email => $email };
    } # Fin if ($rtnLine =~ /^\s*(\d+)\.(\d+)([A-Z\/ ]+)($|[&\?\-\$]\S+|\s{2})(\s*\d+\.\d+|\s*$)?/)
  } # Fin LINE: while (my $rtnLine = shift @rtnLines)
  
  debug('_RTNINFO = '.Dumper($self->{RTNINFO}));
  
  return 1;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Remove Garbage Lines.
#    A ne pas confondre avec celle de Expedia::Databases::Amadeus 
sub _cleanLines {
  my $self  = shift;
  my $lines = shift;

  my @resLines = ();

  foreach (@$lines) {
    next if (/\*\*\s+2C\s+\-\s+RESARAIL\/SNCF\s+\*\*/);
    next if (/^R\/MD$/);
    next if (/FIN D\'AFFICHAGE/);
    next if (/PLUS RIEN A AFFICHER/);
    next if (/ITINERAIRE INVALIDE/);   # Permet de détecter un problème
    next if (/IMPOSSIBLE A TRAITER/);  # Tarification invalide
    next if (/^\s*\$\s*$/);            # Lignes avec rien d'autre qu'un $
    next if (/^\s*$/);                 # Lignes avec que des espacements
    push @resLines, $_;
  }

  return \@resLines;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Permet de connaître la référence d'un PNR Amadeus depuis Socrate
# Si il n'est pas trouvé, la fonction retourne 0 sinon elle retourne le PNR
sub getAmadeusRef {
  my $self = shift;

  # ---------------------------------------------------------
  # Enter in RESARAIL
  my $lines   =  $self->{_GDS}->command(
                   Command     => 'R//IG',
                   NoIG        => 1,
                   NoMD        => 1,
                   PostIG      => 0,
                   ProfileMode => 0);
  unless (grep /\*\*\s+2C\s+\-\s+RESARAIL\/SNCF\s+\*\*/, @$lines) {
    notice('Cannot enter Resarail SNCF. Aborting [...]');
    return undef;
  }
  # Message Socrate =
  # ~ COMMUNICATION ACTUELLEMT NON DISPONIBLE - RECOMMENCER PLUS TARD ~
  # ~ TRAITEMENT IMPOSSIBLE - CONTACTER LE HELP DESK D'AMADEUS ~
  if (grep(/RECOMMENCER PLUS TARD/,                          @$lines) ||
      grep(/TRAITEMENT IMPOSSIBLE - CONTACTER LE HELP DESK/, @$lines)) {
    notice('Cannot enter Resarail SNCF. Aborting [...]');
    return undef;
  }
  # ---------------------------------------------------------
  
  # ---------------------------------------------------------
  # Je me place sur le dossier choisi
  $self->{_GDS}->command(
         Command     => 'R/RT'.$self->{_DV},
         NoIG        => 1,
         NoMD        => 1,
         PostIG      => 0,
         ProfileMode => 0);
  # ---------------------------------------------------------
  
  # ---------------------------------------------------------
  $lines = $self->{_GDS}->command(
         Command     => 'RTY/AN'.$self->{_DV},
         NoIG        => 1,
         NoMD        => 1,
         PostIG      => 0,
         ProfileMode => 0);
  # ---------------------------------------------------------

	debug('lines = '.Dumper($lines));
	
	return undef if (grep(/SANS NOM OU SECURISE/, @$lines));
	
	shift @{$lines} if ($lines->[0] =~ /^\-\-\-\s.*\s\-\-\-$/);

  # PNR identifier should appear on next line
  my $PNR     = undef;
  my $pnrLine = shift @{$lines};
  debug('pnrLine = '.$pnrLine);
  
  $PNR = $7
    if ($pnrLine =~ /^ RP\/(\w+)(\/(\w+))? \s+ (\w+)?\/(\w+)? \s+ (\w+\/\w+) \s+ (\w+) \s* $/x);
  $PNR =~ s/^\s*(\w+.*\w+)\s*$/$1/ if (defined $PNR);
  
  return $PNR;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

1;
