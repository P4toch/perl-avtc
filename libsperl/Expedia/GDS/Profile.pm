package Expedia::GDS::Profile;
#-----------------------------------------------------------------
# Package Expedia::GDS::Profile
#
# $Id: Profile.pm 661 2011-04-12 12:52:21Z pbressan $
#
# (c) 2002-2008 Expedia.                   www.expediacorporate.fr
#-----------------------------------------------------------------

use Data::Dumper;
use Exporter 'import';

use Expedia::Tools::Logger qw(&debug &notice &warning &error);
use Expedia::Tools::GlobalVars qw($cnxMgr);

@EXPORT_OK = qw(&profCreate);

use strict;

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# CONSTRUCTEUR
sub new {
  my ($class, %params) = @_;

  # Les paramètres obligatoires sont les suivants :
  #   $params  = { PNR => $PNR, GDS => $GDS, TYPE => 'T' }   # EXEMPLE
  my $PNR  = $params{PNR}  || undef;
  my $GDS  = $params{GDS}  || undef;
  my $TYPE = $params{TYPE} || undef;

  # -------------------------------------------------------------------
  # Gestion des paramètres obligatoires
  if ((!$PNR) || ($PNR !~ /^\w{6}$/)) {
    error('A valid PNR parameter must be provided to this constructor. Aborting');
    return undef;
  }
  if ((!$GDS) || (ref($GDS) ne 'Expedia::Databases::Amadeus')) {
    error('A valid AMADEUS connection must be provided to this constructor. Aborting.');
    return undef;
  }
  if ((!$TYPE) || ($TYPE !~ /^(T|C)$/)) {
    error("TYPE parameter is mandatory and should match 'T' or 'C'. Aborting.");
    return undef;
  }
  # -------------------------------------------------------------------

  my $self = {};
  bless ($self, $class);

  $self->{_PNR}          = $PNR;  # L'identifiant PNR de Traveller ou de Company
  $self->{_GDS}          = $GDS;  # Le handle de connection à AMADEUS
  $self->{_TYPE}         = $TYPE; # T ou C pour Traveller ou Company
  $self->{_SCREEN}       = [];

  $self->{_TRDATA}       = undef; # ------- PNR TRANSFERABLE DATA
  $self->{_PRIORITY}     = undef; # ------- PRIORITY
  $self->{_INFORMATION}  = undef; # ------- GENERAL INFORMATION
  $self->{_DOCUMENTS}    = undef; # ------- DOCUMENTS
  $self->{_POLICIES}     = undef; # ------- POLICIES
  $self->{_PSENTRIES}    = undef; # ------- PRE-STORED ENTRIES
  $self->{_FOLLOWUP}     = undef; # ------- FOLLOW UP 
  $self->{_PROFILENOTES} = undef; # ------- PROFILE NOTES
  $self->{_INACTIVEFFNS} = undef; # ------- INACTIVE/DELETED FREQUENT FLYER NUMBERS

  # Récupéré de l'ancien fonctionnement codé par Jean-François PACCINI
  $self->{Type}          = undef; # T ou C pour Traveller ou Company
  $self->{Name}          = undef; # NOM/PRENOM TITRE du Profil si Type = T
  $self->{ComName}       = undef; # COMPANY si Type = C ou T selon les cas
  $self->{ProfId}        = undef; # Est égal à "$self->{_PNR}" Normalement
  $self->{PnrTrData}     = undef;
                
  my $resGet = $self->get;        # Récupération du Profil
  return undef if (!$resGet || $resGet == 0);

  warning('No lines were returned when getting this Profile !')
    if (scalar(@{$self->{_SCREEN}}) == 0);

  warning('Problem detected with Profile Type.')
    unless (defined($self->{Type})   && ($self->{_TYPE} eq $self->{Type}));

  warning('Problem detected with PNR Identifier.')
    unless (defined($self->{ProfId}) && ($self->{_PNR}  eq $self->{ProfId}));

  return $self;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
sub get {
  my $self = shift;

  if ($self->{_PNR} && ($self->{_PNR} ne '')) {

    $self->{_SCREEN} = $self->{_GDS}->PDRC(PNR => $self->{_PNR})
      if ($self->{_TYPE} && ($self->{_TYPE} eq 'C'));

		$self->{_SCREEN} = $self->{_GDS}->PDRT(PNR => $self->{_PNR})
      if ($self->{_TYPE} && ($self->{_TYPE} eq 'T'));

    # PNR Identifier should appear on the first _SCREEN line
		if ($self->{_SCREEN}->[0] !~ /$self->{_PNR}$/) {
      warning("Problem detected during get of PNR '".$self->{_PNR}."'.");
      return 0;
    }

		$self->_scan if (scalar(@{$self->{_SCREEN}}) > 0);
  } else {
    error('A valid PNR parameter must be provided to this method. Aborting');
    return 0;
  }

  return 1;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Scan le PNR et range les informations contenues dedans...
sub _scan {
  my $self  = shift;

  my @lines = @{$self->{_SCREEN}};

  return 0 if (!$self->{_SCREEN} || scalar(@{$self->{_SCREEN}}) == 0);

  my ($t, $n, $c, $cn, $p);

  debug('Profile = '.Dumper(\@lines));

  shift @lines if ($lines[0] =~ /\*+\s+DEACTIVATED\s\*+/);

  my $line = shift @lines;

  ($t, $n, $p) = ($line =~ /^
        \s*\*(.)\*               # *T* or *C*
	      \s+
	      (.*)
	      \s
	      (\w+)                    # Last word is profile ID or *MRG* in merge mode
	      \s*$/x);

  if ($t eq 'T') {
    ($t, $n, $c, $cn, $p) =
      ($line =~ /^
       \s*
       \*(.)\*                   # *T* or *C*
       \s+
       (.......................) # 23 chars for name, hugh
       (.)                       # C for company name
       \s+
       (.*)                      # Company name, any size up to last word
       \s
       (\w+)                     # Last word is profile ID or *MRG* in merge mode
       \s*$/x);
  }

  debug(' t = ^'.$t .'$');
  debug(' n = ^'.$n .'$');
  debug(' c = ^'.$c .'$') if (defined $c);
  debug('cn = ^'.$cn.'$') if (defined $cn);
  debug(' p = ^'.$p .'$');
  
  $self->{Type} = $t;

  # Traveler Profile
  if ($self->{Type} && ($self->{Type} eq 'T')) {
    $self->{Name} = $n;
    $self->{Name} =~ s/^\s*(\w+.*\w+)\s*$/$1/;

    # Traveler is attached to a Company 
    if ((defined $c) && ($c eq 'C')) {
      $self->{ComName} = $cn;
      $self->{ComName} =~ s/^\s*(\w+.*\w+)\s*$/$1/;
    }
  }
  # Company Profile
  elsif ($self->{Type} && ($self->{Type} eq 'C')) {
    $self->{ComName} = $n;
    $self->{ComName} =~ s/^\s*(\w+.*\w+)\s*$/$1/;
  }
  else {
    error("Unknown ~Type~ detected in Profile ".$self->{_PNR}.'.');
    # $self->{Type} = undef;
    return 0;
  }

  # Common to Traveler & Company
  notice("Unsupported 'MERGE' mode detected !") if ($p =~ /\*MRG\*/);
  if ($p && ($p !~ /\*MRG\*/) && ($p =~ /\w/)) {
    $self->{ProfId} = $p;
    $self->{ProfId} =~ s/^\s*(\w+.*\w+)\s*$/$1/;
  }

  debug('   Name = ^'.$self->{Name}.'$')    if ($self->{Name});
  debug('ComName = ^'.$self->{ComName}.'$') if ($self->{ComName});
  debug(' ProfId = ^'.$self->{ProfId}.'$')  if ($self->{ProfId});

  ########################################
  # ~ Remaining Lines: Profile Content ~ #
  ########################################
  my $section   = undef;
	my $lastToken = '';
  LINE: while ($line = shift @lines) {
    # --------------------------------------------------
    # DETECTION DE SECTION
    if ($line =~ /^ [-]+ \s+ (\w.{30})/x) {
      $section = $1;
      debug('Section is now '.$section.'.');
      next LINE;
    }
    # TODO Sections non supportées !
    # -----------------------------------------
    # PRIORITY SECTION
    if ($section =~ /^PRIORITY/) {
      if ($line =~ /^ \s* (\d+) (\sPPR\/)? \s+ (\w.*) \s* $/x) {
        push (@{$self->{PnrTrData}}, { LineNo => $1, Data => 'PPR/ '.$3});
        push (@{$self->{_PRIORITY}}, { LineNo => $1, Data => 'PPR/ '.$3});
	      next LINE;
      }
    }
    # -----------------------------------------
    # DOCUMENTS SECTION
    if ($section =~ /^DOCUMENTS/) {
      if ($line =~ /^ \s* (\d+) \s* (\w\w\w\/)? \s* (.*) \s* $/x) {
        $lastToken = $2 if ($2 && ($2 !~ /^\s*$/));
        push (@{$self->{PnrTrData}},  { LineNo => $1, Data => $lastToken.$3 });
        push (@{$self->{_DOCUMENTS}}, { LineNo => $1, Data => $lastToken.$3 });
	      next LINE;
      }
    }
    # -----------------------------------------
    # PNR TRANSFERABLE DATA SECTION
    if ($section =~ /^PNR TRANSFERABLE DATA/) {
      if ($line =~ /^ \s* (?:[a-zA-Z]{1}){0,1}\s*(\d+) \s+ (.)(\w) \s+ (\w.*) \s* $/x) {
        push (@{$self->{PnrTrData}}, { LineNo => $1, TrIndicator => $3, Data => $4 });
        push (@{$self->{_TRDATA}},   { LineNo => $1, TrIndicator => $3, Data => $4 });
      } elsif ($line =~ /^ \s{17} (.*)  \s* $/x) {
        ${$self->{PnrTrData}}[$#{$self->{PnrTrData}}]->{Data} .= $1;
        ${$self->{_TRDATA}}[$#{$self->{_TRDATA}}]->{Data}     .= $1;
      } else {
        warning('Ignored line: '.$line);
      }
    }
    # -----------------------------------------
    # GENERAL INFORMATION SECTION
    if ($section =~ /^GENERAL INFORMATION/) {
      if ($line =~ /^ \s* (\d+) \s* (\w\w\w\/)? \s* (.*) \s* $/x) {
        $lastToken = $2 if ($2 && ($2 !~ /^\s*$/));
        push (@{$self->{PnrTrData}},    { LineNo => $1, Data => $lastToken.$3 });
        push (@{$self->{_INFORMATION}}, { LineNo => $1, Data => $lastToken.$3 });
	      next LINE;
      } elsif ($line =~ /^ \s* C? \s* (\d+\s+)? PCN\/ \s*(\w.*) $/x) {
        # TODO Vérifier si le nom de société est le même que $self->{ComName}
      }
    }
    # -----------------------------------------
    # INACTIVE/DELETED FREQUENT FLYER NUMBERS
    # -----------------------------------------
    if ($section =~ /^INACTIVE\/DELETED FREQUENT/) {
      if ($line =~ /^ \s* (\d+) \s* (\w\w\w\/)? \s* (.*) \s* $/x) {
        push (@{$self->{PnrTrData}},     { LineNo => $1, Data => $3 });
        push (@{$self->{_INACTIVEFFNS}}, { LineNo => $1, Data => $3 });
	      next LINE;
      }
    }
    # -----------------------------------------
    # TRAVEL POLICIES - HOTEL SECTION
    if ($section =~ /^TRAVEL POLICIES - HOTEL/) {
      if ($line =~ /^ \s* (\d+) \s+ (PHI\/)? \s+ (\w.*) \s* $/x) {
	      push (@{$self->{PnrTrData}}, { LineNo => $1, Data => 'PHI/ '.$3 });
	      push (@{$self->{_POLICIES}}, { LineNo => $1, Data => 'PHI/ '.$3 });
	      next LINE;
      }
    }
    # -----------------------------------------
    # TRAVEL POLICIES - CAR SECTION
    if ($section =~ /^TRAVEL POLICIES - CAR/) {
      if ($line =~ /^ \s* (\d+) \s+ (PCI\/)? \s+ (\w.*) \s* $/x) {
	      push (@{$self->{PnrTrData}}, { LineNo => $1, Data => 'PSI/ '.$3 });
	      push (@{$self->{_POLICIES}}, { LineNo => $1, Data => 'PSI/ '.$3 });
	      next LINE;
      }
    }
    # -----------------------------------------
    # PRE-STORED SECTION
    if ($section =~ /^PRE-STORED ENTRIES/) {
      if ($line =~ /^ \s* (\d+) \s* (PPS\/)? \s+ (\w.*) \s* $/x) {
	      push (@{$self->{PnrTrData}},  { LineNo => $1, Data => 'PPS/ '.$3 });
	      push (@{$self->{_PSENTRIES}}, { LineNo => $1, Data => 'PSI/ '.$3 });
	      next LINE;
      }
    }
    # -----------------------------------------
    # FOLLOW UP SECTION
    if ($section =~ /^FOLLOW UP/) {
      if ($line =~ /^ \s* (\d+) \s* (\w\w\w\/)? \s* (.*) \s* $/x) {
        $lastToken = $2 if ($2 && ($2 !~ /^\s*$/));
	      push (@{$self->{PnrTrData}}, { LineNo => $1, Data => $lastToken.$3 });
	      push (@{$self->{_FOLLOWUP}}, { LineNo => $1, Data => $lastToken.$3 });
	      next LINE;
      }
    }
    # -----------------------------------------
    # PROFILE NOTES
    if ($section =~ /^PROFILE NOTES/) {
      if ($line =~ /^ ([\w\s]) \s (.{56}) \s* $/x) {
 	    # push (@{$self->{PnrTrData}},     { LineNo => undef, Data => 'PROFILENOTES '.$1.' '.$2 });
 	      push (@{$self->{_PROFILENOTES}}, { LineNo => undef, Data => 'PROFILENOTES '.$1.' '.$2 });
	      next LINE;
      }
    }
  } # FIN LINE: while ($line = shift @lines)

  # Clean extra spaces in data lines
  foreach my $i (@{$self->{PnrTrData}},
                 @{$self->{_PRIORITY}},     @{$self->{_DOCUMENTS}}, @{$self->{_TRDATA}},
                 @{$self->{_INFORMATION}},  @{$self->{_POLICIES}},  @{$self->{_PSENTRIES}},
                 @{$self->{_PROFILENOTES}}, @{$self->{_FOLLOWUP}}) {
    $i->{Data} =~ s/\s*$//; }

  return 1;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# "Minimal Scan" regarde si le ProfileId peut-être atteint dans AMADEUS
#   Renvoie 1 pour vrai ou 0 pour faux.
sub _mscan {
  my (%params) = @_;
  
  my $GDS  = $params{GDS}   || undef;
  my $PNR  = $params{PNR}   || undef; # PROFILE ID
  my $TYPE = $params{TYPE}  || undef; # TYPE 'T' ou 'C'
  
  # -------------------------------------------------------------------
  # Gestion des paramètres obligatoires
  if ((!$GDS) || (ref($GDS) ne 'Expedia::Databases::Amadeus')) {
    error('A valid AMADEUS connection must be provided to this constructor. Aborting.');
    return 0;
  }
  if ((!$PNR) || ($PNR !~ /^\w{6}$/)) {
    error('A valid PNR parameter must be provided to this constructor. Aborting');
    return 0;
  }
  if ((!$TYPE) || ($TYPE !~ /^(T|C)$/)) {
    error("TYPE parameter is mandatory and should match 'T' or 'C'. Aborting.");
    return 0;
  }
  # -------------------------------------------------------------------
  
  my $screen = [];
     $screen = $GDS->PDRC(PNR => $PNR, NoMD => 1) if ($TYPE eq 'C');
		 $screen = $GDS->PDRT(PNR => $PNR, NoMD => 1) if ($TYPE eq 'T');
		 
  my @lines = @{$screen};

  return 0 if (!$screen || scalar(@{$screen}) == 0);

  debug('Profile = '.Dumper(\@lines));

  shift @lines if ($lines[0] =~ /\*+\s+DEACTIVATED\s\*+/);

  my $line = shift @lines;

  my ($t, $n, $p) = ($line =~ /^
        \s*\*(.)\*               # *T* or *C*
	      \s+
	      (.*)
	      \s
	      (\w+)                    # Last word is profile ID or *MRG* in merge mode
	      \s*$/x);
	
	debug('p = '.$p) if (defined $p);
	
  return 0 if ((defined $p) && ($p ne $PNR));
  return 1;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Trouver les lignes de doublons dans un Profil
sub _getDuplicates {
  my $self = shift;

  my @checkedLines  = ();
  my @linesToRemove = ();

  foreach my $line (@{$self->{PnrTrData}}) {
    debug('line: '.$line->{LineNo}.' '.$line->{Data});
    CL: foreach my $cL (@checkedLines) {
      if ($line->{Data} eq $cL) {
        push (@linesToRemove, $line->{LineNo});
        last CL;
      }
    }
    push (@checkedLines, $line->{Data});
  }

  debug('linesToRemove = '.Dumper(\@linesToRemove));

  return \@linesToRemove;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Création d'un nouveau Profil dans Amadeus
sub profCreate {
  my (%params) = @_;
  
  my $GDS   = $params{GDS}   || undef;
  my $tName = $params{TNAME} || undef; # TRAVELLER NAME
  my $cName = $params{CNAME} || undef; # COMPANY   NAME
  
  my $lines = [];

  # -------------------------------------------------------------------
  # Gestion des paramètres obligatoires
  if ((!$GDS) || (ref($GDS) ne 'Expedia::Databases::Amadeus')) {
    error('A valid AMADEUS connection must be provided to this constructor. Aborting.');
    return undef;
  }
  if (((!defined $tName) && (!defined $cName))   ||
      ((!defined $tName) && ($cName =~ /^\s*$/)) ||
      ((!defined $cName) && ($tName =~ /^\s*$/))) {
    error('Missing parameters for this method');
    return undef;
  }
  # -------------------------------------------------------------------
  
  # Enter in profile mode if necessary
  unless ($GDS->{ProfileMode}) {
    $GDS->_command('PM');
    $GDS->{ProfileMode} = 1;
  }
  
  # Traveller profile creation
  if (defined $tName) {
    $lines = $GDS->command(Command => 'NM1'.$tName, NoIG=> 1, NoMD => 1, PostIG => 0, ProfileMode => 1);
    # Need confirmation ?
    if (grep (/TRAVELLER\s+PROFILE\s+EXISTS\s+-\s+TYPE\s+Y\s+TO\s+PROCEED/, @$lines) || 
		    grep (/OR\s+N\s+TO\s+DISPLAY\s+PROFILE/, @$lines)) {
	    $GDS->command(Command => 'Y', NoIG=> 1, NoMD => 1, PostIG => 0, ProfileMode => 1);
    }
    # Problème détecté lors de la création ?
    if (grep (/INVALID\/NOT\s+ENTERED/, @$lines)) {
      error("Cannot create Profile for ".$tName.".\nLast screen : ".join("//",@$lines));
      return 0;
    }
    $GDS->command(Command => '1/1'.$tName, NoIG=> 1, NoMD => 1, PostIG => 0, ProfileMode => 1);    
  }
  # Company profile creation or traveller attachement to company
  if (defined $cName) {
    # TODO Attention ici à bien prendre le COMPANY_NAME
    #      depuis la table AMADEUS_SYNCHRO
    $lines = $GDS->command(Command => 'PCN/'.$cName, NoIG=> 1, NoMD => 1, PostIG => 0, ProfileMode => 1);
    if (grep (/DUPLICATE/, @$lines)) {
		 $GDS->command(Command => 'PDN/'.$cName, NoIG=> 1, NoMD => 1, PostIG => 0, ProfileMode => 1);
		}    
  }
  
  # --------------------------------------------------------------------
  # Save and redisplay to scan profile ID
  $lines = $GDS->command(Command => 'PER', NoIG=> 1, NoMD => 1, PostIG => 0, ProfileMode => 1);
  my $line = shift @$lines;
  my ($t, $n, $p) = ($line =~ /^
        \s*\*(.)\*               # *T* or *C*
	      \s+
	      (.*)
	      \s
	      (\w+)                    # Last word is profile ID or *MRG* in merge mode
	      \s*$/x);
	$lines = $GDS->command(Command => 'PE', NoIG=> 1, NoMD => 1, PostIG => 0, ProfileMode => 1);
  # --------------------------------------------------------------------
  
  if ((defined $p) && ($p =~ /^\w{6}$/)) {
    debug("AMADEUS_PROFILE CREATED = '$p'");
    return $p;
  }
  
  return undef;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Mise à jour des infos contenues dans un Profil
sub update {
  my $self   = shift;
  my %params = (@_);

  if (!$self->{ProfId} || !%params) {
    error('Cannot update Profile because of missing update parameters.');
    return 0;
  }

  my @del = (); my @add = ();

  @del = sort {$a <=> $b} (@{$params{del}}) if $params{del};
  @add = @{$params{add}} if $params{add};

  return 1 if (($#del == -1) && ($#add == -1) && (!exists $params{rename}));
  debug('I have something to update: '.Dumper(\%params));
  
	$self->{_GDS}->PDRT(PNR => $self->{ProfId}, NoMD => 1) if ($self->{Type} eq 'T');
	$self->{_GDS}->PDRC(PNR => $self->{ProfId}, NoMD => 1) if ($self->{Type} eq 'C');

  # -------------------------------------------------------------
  # Delete in AMADEUS (from bottom to top)
  
  while (my $ref = pop(@del)) {             # Delete from Amadeus (from bottom to top)
    foreach my $i (@{$self->{PnrTrData}}) { # Scan current info & decide updates
      if ($i->{LineNo} == $ref) {           # Found line
	      $self->{_GDS}->command(Command => "XE $ref", NoIG => 1, NoMD => 1, ProfileMode => 1);
      }
    }
  }
  # -------------------------------------------------------------

  # -------------------------------------------------------------
  # Add new infos in AMADEUS
  my $lines   = [];
  my $comName = '';
  
  while (my $ref = shift(@add)) {
    debug('Adding new line: '.Dumper($ref));
	  $ref->{Data} =~ s/&AMP;/&amp;/g;
    if ($ref->{TrIndicator} && ($ref->{TrIndicator} ne '')) {
      error('Bad value for TrIndicator.') unless ($ref->{TrIndicator} =~ /^[ASM]$/);
			$lines = $self->{_GDS}->command(
                 Command     => $ref->{Data}.'*'.$ref->{TrIndicator},
				         NoIG        => 1,
				         NoMD        => 1,
				         ProfileMode => 1);
    } else {
      $lines = $self->{_GDS}->command(
                 Command     => $ref->{Data},
					       NoIG        => 1,
					       NoMD        => 1,
					       ProfileMode => 1);
    }

    $comName = $self->{ComName} if defined $self->{ComName};

    unless (grep(/PNR TRANSFERABLE DATA/, @$lines)) {
      error('Problem adding: '.Dumper($ref));
      error("Problem during update of Profile '".$self->{ProfId}.
	          "' (traveller=".$self->{Name}.', company='.$comName.') - Last Screen: '.join("//",@$lines));
    }
  }
  # -------------------------------------------------------------

  # -------------------------------------------------------------
  # Renommage
  if ($params{rename} && ($params{rename} ne '')) {
    $self->{_GDS}->command(Command => '1/1'.$params{rename}, NoIG => 1, NoMD => 1, ProfileMode => 1);
    unless (grep(/PNR TRANSFERABLE DATA/, @$lines)) {
      error("Problem during update of Profile '".$self->{ProfId}.
	          "' (traveller=".$self->{Name}.', company='.$comName.') - Last Screen: '.join("//",@$lines));
    }
  }
  # -------------------------------------------------------------

  # -------------------------------------------------------------
  if ($params{ComName} && $params{ComName} ne '') {
    $self->{_GDS}->command(Command => 'PCN/'.$params{ComName}, NoIG => 1, NoMD => 1, ProfileMode => 1);
    unless (grep(/PNR TRANSFERABLE DATA/, @$lines)) {
      error("Problem during update of Profile '".$self->{ProfId}.
	          "' (traveller=".$self->{Name}.', company='.$comName.') - Last Screen: '.join("//",@$lines));
    }
  }
  # -------------------------------------------------------------

  $lines = $self->{_GDS}->command(Command => 'PEE', NoIG => 1, NoMD => 1, ProfileMode => 1);
  
  unless (grep(/END OF TRANSACTION COMPLETE/, @$lines)) {
    $self->{_GDS}->command(Command => 'PIE', NoIG => 1, NoMD => 1, ProfileMode => 1);
    $self->{_GDS}->{ProfileMode} = 0;
    return 0;
  }
  
  $self->{_GDS}->{ProfileMode} = 0;

  (($params{NoGet}) && ($params{NoGet} ne '')) || $self->get;

  return 1;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

1;
