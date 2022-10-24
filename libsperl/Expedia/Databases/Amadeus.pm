package Expedia::Databases::Amadeus;
#-----------------------------------------------------------------
# Package Expedia::Databases::Amadeus
#
# $Id: Amadeus.pm 588 2010-07-20 15:07:58Z pbressan $
#
# (c) 2002-2010 Expedia.                   www.expediacorporate.fr
#-----------------------------------------------------------------

use base qw(Expedia::Databases::Connection);

use APIV2XS;
use Data::Dumper;

use Expedia::Tools::Logger qw(&debug &notice &warning &error);
use Expedia::Databases::Cryptic qw(&getConversationID &executeCrypticCommand &closeConnection);

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# CONSTRUCTEUR
sub new {
  my ($class) = @_;

  my $self = new Expedia::Databases::Connection();
  bless ($self, $class);
  
  $self->{_TYPE}                = 'Amadeus';
  $self->{_SIGNIN}              = undef;
  $self->{_MODIFSIG}            = undef;
  $self->{_TCP}                 = undef;
  $self->{_PORT}                = undef;
  $self->{_CORPOID}             = undef;
  $self->{_LOGIN}               = undef;
  $self->{_PASSWORD}            = undef;
  $self->{_OFFICEID}            = undef;
  $self->{_LANGUAGE}            = undef;
  $self->{_USE_CRYPTIC_SERVICE} = undef;
  $self->{_DISCONNECTABLE}      = 1;
  $self->{_SAIPEM}              = 0; # Sp�cificit� SAIPEM 24 Juin 2010
  $self->{_PSA1}                = 0; # Sp�cificit� PSA 19 Janvier 2012
  $self->{_MRSEC3100}           = 0; # Sp�cificit� BUG 11411
   
  $self->{_SCREEN}              = [];

  return $self;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
sub type {
	my ($self, $type) = @_;

  $self->{_TYPE} = $type if (defined $type);
  return $self->{_TYPE};
}

sub signin {
  my ($self, $signin) = @_;

  $self->{_SIGNIN} = $signin if (defined $signin);
  return $self->{_SIGNIN};
}

sub modifsig {
  my ($self, $modifsig) = @_;

  $self->{_MODIFSIG} = $modifsig if (defined $modifsig);
  return $self->{_MODIFSIG};
}

sub tcp {
  my ($self, $tcp) = @_;

  $self->{_TCP} = $tcp if (defined $tcp);
  return $self->{_TCP};
}

sub port {
  my ($self, $port) = @_;

  $self->{_PORT} = $port if (defined $port);
  return $self->{_PORT};
}

sub corpoid {
  my ($self, $corpoid) = @_;

  $self->{_CORPOID} = $corpoid if (defined $corpoid);
  return $self->{_CORPOID};
}

sub login {
  my ($self, $login) = @_;

  $self->{_LOGIN} = $login if (defined $login);
  return $self->{_LOGIN};
}

sub password {
  my ($self, $password) = @_;

  $self->{_PASSWORD} = $password if (defined $password);
  return $self->{_PASSWORD};
}

sub officeid {
  my ($self, $officeid) = @_;

  $self->{_OFFICEID} = $officeid if (defined $officeid);
  return $self->{_OFFICEID};
}

sub language {
  my ($self, $language) = @_;

  $self->{_LANGUAGE} = $language if (defined $language);
  return $self->{_LANGUAGE};
}

sub use_cryptic_service {
  my ($self, $use_cryptic_service) = @_;

  $self->{_USE_CRYPTIC_SERVICE} = $use_cryptic_service if (defined $use_cryptic_service);
  return $self->{_USE_CRYPTIC_SERVICE};
}

sub disconnectable {
	my $self = shift;

  return $self->{_DISCONNECTABLE};
}

sub saipem {
  my ($self, $saipem) = @_;

  $self->{_SAIPEM} = $saipem if (defined $saipem);
  return $self->{_SAIPEM};
}

sub psa1 {
  my ($self, $psa1) = @_;

  $self->{_PSA1} = $psa1 if (defined $psa1);
  return $self->{_PSA1};
}

sub MRSEC3100 {
  my ($self, $MRSEC3100) = @_;

  $self->{_MRSEC3100} = $MRSEC3100 if (defined $MRSEC3100);
  return $self->{_MRSEC3100};
}

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
sub connect {
  my ($self) = @_;

  foreach(qw(_NAME _SIGNIN _MODIFSIG _TCP _PORT _CORPOID _LOGIN _PASSWORD _LANGUAGE _USE_CRYPTIC_SERVICE)) {
    if (!defined($self->{$_})) {
      error("Missing parameter '$_'.");
      return 0
    }
  }

  if ($self->use_cryptic_service == 1) {
  
    debug('Connecting to Amadeus through cryptic service...');
    $self->handler(
      {'conversationID' => getConversationID($self->officeid)}
    );
    debug("Connection handler =\n".Dumper($self->handler));
    
    # Gestion Erreur lors de la Connection a Amadeus
    if (!defined $self->handler->{'conversationID'}) {
      error('Problem detected during Amadeus connect through cryptic service !');
      return 0;
    }
  
  } else {
  
    my $agtSign     = '0001';
    my $agtInitials = 'AA';
    my $dutyCode    = 'SU';

    if ((length($self->signin) != 9) || ($self->signin !~ /(\d{4})(\D{2})\/(\D{2})/)) {
      warning("Signin parameter not exact. Robot will use 0001AA/SU.");
    } else {
      ($agtSign, $agtInitials, $dutyCode) = ($1, $2, $3);
      debug("agtSign     = $agtSign");
      debug("agtInitials = $agtInitials");
      debug("dutyCode    = $dutyCode");
      debug("tcp    = ".$self->tcp);
      debug("port    = ".$self->port);
      debug("corpoid    = ".$self->corpoid);
      debug("login ".$self->login);
      debug("password    = ".$self->password);
      debug("oid    = ".$self->officeid);
      debug("language    = ".$self->language);
    }

    debug('Connecting to Amadeus through APIV2XS...');
    $self->handler(
      APIV2XS::get_connexion_signed(
        $self->tcp,
        $self->port,
        $self->corpoid,
        $self->login,
        $self->password,
        $self->officeid,
        $self->language,
        $agtSign,
        $agtInitials,
        $dutyCode
      )
    );
    debug("Connection handler =\n".Dumper($self->handler));

    # Gestion Erreur lors de la Connection a Amadeus
    if (($self->handler->{'conv'} == 0) && ($self->handler->{'fact'} == 0)) {
      error('Problem detected during Amadeus connect !');
      $self->disconnect();
      return 0;
    }
  
  }

  if (defined $self->handler) {
    debug("Connected to AMADEUS database : '".$self->name."'");
    $self->connected(1);
    return 1;
  } else {
    error("Cannot connect to '".$self->name);
  }

  return 0;
}

sub disconnect {
  my ($self) = @_;

  $self->{ProfileMode} = 0;
  $self->connected(0);
  $self->saipem(0);
  $self->psa1(0);

  if ($self->use_cryptic_service == 1) {
    closeConnection($self->handler->{'conversationID'});
  } else {
    APIV2XS::gds_disconnect($self->handler);
  }
  debug("Disconnected from AMADEUS database : '".$self->name."'");

  return 1;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
sub command {
  my $self = shift;

  my ($command, $noIG, $noMD, $postIG, $profMode);

  if ($#_ == 0) {
    $command = shift;
  } else {
    my %params = @_;
    $command   = $params{Command};
    $noMD      = $params{NoMD};
    $noIG      = $params{NoIG};
    $postIG    = $params{PostIG};
    $profMode  = $params{ProfileMode};
  }


  $self->_command('IG') unless ($noIG || $profMode);

  # ------------------------------------------------------
  # Is profile mode needed ?
  if ($profMode) {
    $self->_command('PM') unless $self->{ProfileMode};
    $self->{ProfileMode} = 1;
  } else {
    $self->_command('PIE') if $self->{ProfileMode};
    $self->{ProfileMode} = 0;
  }
  # ------------------------------------------------------

  # ------------------------------------------------------
  # Envoi de la commande AMADEUS
  $self->_clearScreen;
  $self->_command($command);
  $self->_cleanScreen;
  my $lines = $self->_getScreen;
  # ------------------------------------------------------

  # Check continuation sign ")" & Remove last line.
  pop @$lines if (grep (/^\)\s*$/, ${$lines}[$#$lines]));

  my $done     = 0;
  my $tmpLines = [];
  unless ($noMD) {
    my $loops = 50;  # Limit to number of MD tries
    LOOP: while ($loops-- > 0) {
      # Next page handling in profile mode is painful.
      # MDR is not supported, so we scroll 22 lines
      # and will have to handle duplicated lines on last screen.
      if ($self->{ProfileMode}) { $self->_command('MD22'); } else { $self->_command('MDR'); }
      $tmpLines = $self->_getAndClearScreen;
      $self->_cleanLines($tmpLines);
      # If we are in profile mode and did an MD22, we may
      # have in the last screen lines that where in the previous
      # screen. We try to get rid of duplicates.
      if ($self->{ProfileMode}) {
        shift @{$tmpLines} while (grep { ${$tmpLines}[0] eq $_ } @$lines);
      }
      # Check end of display
      $done = 0;
      while( (${$tmpLines}[$#$tmpLines] =~ /END\s+OF\s+DISPLAY/)                    	||
             (${$tmpLines}[$#$tmpLines] =~ /END\s+OF\s+BLOCK/)                      	||
		         (${$tmpLines}[$#$tmpLines] =~ /ADVICE\s+02859/)                        ||
		         (${$tmpLines}[$#$tmpLines] =~ /CHECK\s+DEACTIVATED\s+PROFILES\s+LIST/) ||
		         (${$tmpLines}[$#$tmpLines] =~ /^>\s*$/)                                ||
		         (${$tmpLines}[$#$tmpLines] =~ /^IMPOSSIBLE DE FAIRE DEFILER/)          ||
		         (${$tmpLines}[$#$tmpLines] =~ /\*PROFILE\s+MODE\*/)					||
                 (${$tmpLines}[$#$tmpLines] =~ /REQUESTED\s+DISPLAY\s+NOT\s+SCROLLABLE/)
                ) {
		    pop @$tmpLines; # Remove the last line
		    $done = 1;
		    last if (scalar(@$tmpLines) == 0);
		  }
      if ($done) {
		    push (@$lines, @{$tmpLines});
		    last LOOP;
		  }
      pop @{$tmpLines} if (grep (/^\)\s*$/, ${$tmpLines}[$#$tmpLines]));
      last LOOP if (${$lines}[$#$lines] eq ${$tmpLines}[$#$tmpLines]);
      push (@$lines, @{$tmpLines});
    } # Fin LOOP: while ($loops-- > 0)
  } # Fin unless ($noMD)

  # notice('lines    = '.Dumper($lines));
  # notice('$#$lines = '.$#$lines);

  while( (grep(/END\s+OF\s+DISPLAY/,           ${$lines}[$#$lines])) ||
         (grep(/^IMPOSSIBLE DE FAIRE DEFILER/, ${$lines}[$#$lines])) ||
         (grep(/END\s+OF\s+BLOCK/,             ${$lines}[$#$lines])) ||
         (grep(/ADVICE\s+02859/,               ${$lines}[$#$lines])) ||
         (grep(/\*PROFILE\s+MODE\*/,           ${$lines}[$#$lines])) ||
         (grep(/^>\s*$/,                       ${$lines}[$#$lines])) ) {
    pop @$lines; # Remove the last line
    last if (scalar(@$lines) == 0);
  }

#notice("POSTIG:".$postIG);

  $self->_command('IG') if ($postIG && !$profMode);

  return $lines;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
sub commandXML {
  my $self = shift;
  my $xml  = shift;

  return APIV2XS::send_string_NATIVE($xml, $self->handler);
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Juste faire un IG = IGNORE
sub IG {
  my $self  = shift;
  
  my $lines = $self->_command('IG');
  
  return $lines;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Retrieve PNR method
# Si le seul param�tre PNR est pass�, les param�tres qui seront appliqu�s les suivants :
#   * Pas de IG avant la commande   (NoIG   = 1)
#   * Le PNR est d�roul� en entier  (NoMD   = 0)
#   * Pas de IG apr�s la commande   (PostIG = 0)
sub RT {
  my $self   = shift;
  my %params = @_;

  if ((!exists($params{PNR})) || (($params{PNR} !~ /^\w{6}$/) && ($params{PNR} !~ /^\/ZZZZZ\S\w{6}$/))) {
    error('A valid PNR param must be passed to this method.');
    return [];
  }

  my $noIG    = 0; # Par d�faut IG avant de commencer
     $noIG    = 1 if ((exists($params{NoIG}))   && ($params{NoIG}   eq '1'));

  my $noMD    = 1; # Par d�faut on ne veut pas de move down
     $noMD    = 0 if ((exists($params{NoMD}))   && ($params{NoMD}   eq '0'));

  my $postIG  = 0; # Par d�faut pas de IG apr�s le RT
     $postIG  = 1 if ((exists($params{PostIG})) && ($params{PostIG} eq '1'));

  my $command = 'RT'.$params{PNR};

  return $self->command(Command => $command, NoIG => $noIG, NoMD => $noMD, PostIG => $postIG, ProfileMode => 0);
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Retrieve History method
# Si le seul param�tre PNR est pass�, les param�tres qui seront appliqu�s les suivants :
#   * Pas de IG avant la commande   (NoIG   = 1)
#   * Le PNR est d�roul� en entier  (NoMD   = 0)
#   * Pas de IG apr�s la commande   (PostIG = 0)
sub RH {
  my $self   = shift;
  my %params = @_;

  if ((!exists($params{PNR})) || (($params{PNR} !~ /^\w{6}$/) && ($params{PNR} !~ /^\/ZZZZZ\S\w{6}$/))) {
    error('A valid PNR param must be passed to this method.');
    return [];
  }

  my $noIG    = 0; # Par d�faut IG avant de commencer
     $noIG    = 1 if ((exists($params{NoIG}))   && ($params{NoIG}   eq '1'));

  my $noMD    = 1; # Par d�faut on ne veut pas de move down
     $noMD    = 0 if ((exists($params{NoMD}))   && ($params{NoMD}   eq '0'));

  my $postIG  = 0; # Par d�faut pas de IG apr�s le RT
     $postIG  = 1 if ((exists($params{PostIG})) && ($params{PostIG} eq '1'));

notice("TEST IG AMADEUS:".$postIG);
notice("TEST IG AMADEUS:".$params{PostIG});

  my $command = 'RH/ALL';

  return $self->command(Command => $command, NoIG => $noIG, NoMD => $noMD, PostIG => $postIG, ProfileMode => 0);
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@


# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Retrieve Traveler Profile method
# Si le seul param�tre PNR est pass�, les param�tres qui seront appliqu�s les suivants :
#   * Pas de IG avant la commande   (NoIG   = 1) ~ IG ne s'applique pas en mode Profil
#   * Le PNR est d�roul� en entier  (NoMD   = 0)
#   * Pas de IG apr�s la commande   (PostIG = 0) ~ IG ne s'applique pas en mode Profil
sub PDRT {
  my $self   = shift;
  my %params = @_;

  if ((!exists($params{PNR})) || ($params{PNR} !~ /^\w{6}$/)) {
    error('A valid PNR param must be passed to this method.');
    return [];
  }

  my $noMD  = 0; # Par d�faut on veut des move down
     $noMD  = 1 if ((exists($params{NoMD})) && ($params{NoMD} eq '1'));

  my $command = 'PDRT/'.$params{PNR}; 
  
  return $self->command(Command => $command, NoIG => 1, NoMD => $noMD, PostIG => 0, ProfileMode => 1);
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Retrieve Company Profile method
# Si le seul param�tre PNR est pass�, les param�tres qui seront appliqu�s les suivants :
#   * Pas de IG avant la commande   (NoIG   = 1) ~ IG ne s'applique pas en mode Profil
#   * Le PNR est d�roul� en entier  (NoMD   = 0)
#   * Pas de IG apr�s la commande   (PostIG = 0) ~ IG ne s'applique pas en mode Profil
sub PDRC {
  my $self   = shift;
  my %params = @_;

  if ((!exists($params{PNR})) || ($params{PNR} !~ /^\w{6}$/)) {
    error('A valid PNR param must be passed to this method.');
    return [];
  }
  
  my $noMD  = 0; # Par d�faut on veut des move down
     $noMD  = 1 if ((exists($params{NoMD})) && ($params{NoMD} eq '1'));
     
  my $command = 'PDRC/'.$params{PNR};
  
  return $self->command(Command => $command, NoIG => 1, NoMD => $noMD, PostIG => 0, ProfileMode => 1);
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Delete a User Profile in Amadeus
sub PXRT {
  my $self   = shift;
  my %params = @_;
  
  if ((!exists($params{PNR})) || ($params{PNR} !~ /^\w{6}$/)) {
    error('A valid PNR param must be passed to this method.');
    return 0;
  }

  my $command = 'PXRT/'.$params{PNR};
  
  my $lines = 
       $self->command(Command => $command, NoIG => 1, NoMD => 1, PostIG => 0, ProfileMode => 1);

  $lines = $self->command(Command => 'PE', NoIG => 1, NoMD => 1, PostIG => 0, ProfileMode => 1)
	  if (grep(/TYPE\s+PE\s+TO\s+CONFIRM\s+OR\s+PI\s+TO\s+IGNORE/, @$lines));

  debug('LINES = '.Dumper($lines));

  return 1;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Delete a Company Profile in Amadeus
sub PXRC {
  my $self   = shift;
  my %params = @_;
  
  if ((!exists($params{PNR})) || ($params{PNR} !~ /^\w{6}$/)) {
    error('A valid PNR param must be passed to this method.');
    return 0;
  }

  my $command = 'PXRC/'.$params{PNR};
  
  my $lines = 
       $self->command(Command => $command, NoIG => 1, NoMD => 1, PostIG => 0, ProfileMode => 1);

  $lines = $self->command(Command => 'PE', NoIG => 1, NoMD => 1, PostIG => 0, ProfileMode => 1)
	  if (grep(/TYPE\s+PE\s+TO\s+CONFIRM\s+OR\s+PI\s+TO\s+IGNORE/, @$lines));

  debug('LINES = '.Dumper($lines));

  return 1;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Commande TJQ / R�conciliation
sub TJQ {
  my $self    = shift;
  my $command = shift;

  if (!defined $command) {
    error('A valid TJQ command must be passed to this method.');
    return [];
  }

  my $lines    = [];
  my $tmpLines = [];

  $lines = $self->command(Command=>$command, NoIG=>1, NoMD=>1, PostIG=>0);
  
  while (1) {
    $tmpLines = $self->command(Command=>'MDR', NoIG=>1, NoMD=>1, PostIG=>0);
    last if (scalar @$tmpLines == 0);
    if (scalar @$tmpLines == 1) { push @$lines, @$tmpLines; last; }
    last if (grep(/REQUESTED DISPLAY NOT SCROLLABLE/, @$tmpLines));
    last if ((${$lines}[$#$lines]     eq ${$tmpLines}[$#$tmpLines]) &&
             (${$lines}[$#$lines - 1] eq ${$tmpLines}[$#$tmpLines - 1]));
    push @$lines, @$tmpLines;
  }
  
  return $lines;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Commande TJI / R�conciliation
sub TJI {
  my $self    = shift;
  my $command = shift;

  if (!defined $command) {
    error('A valid TJI command must be passed to this method.');
    return [];
  }

  my $lines    = [];
  my $tmpLines = [];

  $lines = $self->command(Command=>$command, NoIG=>1, NoMD=>1, PostIG=>0);

  while (1) {
    $tmpLines = $self->command(Command=>'MDR', NoIG=>1, NoMD=>1, PostIG=>0);
    last if (scalar @$tmpLines == 0);
    if (scalar @$tmpLines == 1) { push @$lines, @$tmpLines; last; }
    last if (grep(/REQUESTED DISPLAY NOT SCROLLABLE/, @$tmpLines));
    last if ((${$lines}[$#$lines]     eq ${$tmpLines}[$#$tmpLines]) &&
             (${$lines}[$#$lines - 1] eq ${$tmpLines}[$#$tmpLines - 1]));
    push @$lines, @$tmpLines;
  }
  
  return $lines;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Retrieve PNR method by Name and TripDateStart
#  Utilis� dans le cadre de RavelGold pour le Train FR
# La m�thode renvoie le PNR � utiliser ou bien UVWXYZ si elle ne trouve pas.
sub getPnrByTrvName {
  my $self   = shift;
  my %params = @_;
  
  my $PNR    = 'UVWXYZ';

  if ((!exists($params{Name}))     ||
      (!exists($params{OfficeID})) ||
      (!exists($params{DV}))       || ($params{DV}   !~ /^\w{6}$/) ||
      (!exists($params{Date}))     || ($params{Date} !~ /^\d{2}\D{3}$/)) {
    error('Please check function parameters.');
    return $PNR;
  }
  
  my $DV      = uc($params{DV});
  
  my $noIG    = 0; # Par d�faut pas de IG avant de commencer
     $noIG    = 1 if ((exists($params{NoIG}))   && ($params{NoIG}   eq '1'));

  my $noMD    = 1; # Par d�faut on ne veut pas de move down
     $noMD    = 0 if ((exists($params{NoMD}))   && ($params{NoMD}   eq '0'));

  my $postIG  = 0; # Par d�faut pas de IG apr�s le RT
     $postIG  = 1 if ((exists($params{PostIG})) && ($params{PostIG} eq '1'));

  # EXEMPLE : RT/PAREC38DD/26JAN-MARTIN/AURORE MRS*A
  #   *A : Pour n'avoir que les trajets actifs.
  # my $command = 'RT/'.$params{OfficeID}.'/'.$params{Date}.'-'.uc($params{Name}).'*A';
  my $command = 'RT/'.$params{OfficeID}.'-'.uc($params{Name}).'*A';
  
  my $lines    = [];
  my $tmpLines = [];
  
  $lines = $self->command(Command => $command, NoIG => $noIG, NoMD => $noMD, PostIG => $postIG, ProfileMode => 0);
  # notice('LINES = '.Dumper($lines));
   
  # Dans le cas d'un affichage multiple, nous effectuons des MOVE DOWN
  if ($lines->[0] =~ /^RT\//) {
    while (1) {
      $tmpLines = $self->command(Command=>'MDR', NoIG=>1, NoMD=>1, PostIG=>0);
      last if (scalar @$tmpLines == 0);
      if (scalar @$tmpLines == 1) { push @$lines, @$tmpLines; last; }
      last if (grep(/IMPOSSIBLE DE FAIRE DEFILER/, @$tmpLines));
      last if ((${$lines}[$#$lines]     eq ${$tmpLines}[$#$tmpLines]) &&
               (${$lines}[$#$lines - 1] eq ${$tmpLines}[$#$tmpLines - 1]));
      push @$lines, @$tmpLines;
    } 
  }
  
  # ====================================================================
  # Trois possibilit�s dans la r�ponse Amadeus:
  #
  # ____________________________________________________________________
  # ### SANS NOM OU SECURISE
  # ____________________________________________________________________
  #    L'OfficeID fourni ne permet pas d'acc�der � ce PNR.
  #    Le nom et la date utilis�e ne donne aucun r�sultat.
  if (grep(/SANS NOM OU SECURISE/, @$lines)) { return $PNR; }
  #
  # ____________________________________________________________________
  # ### OUVERTURE DU PNR
  # ____________________________________________________________________
  #    La commande RT fournie ne nous ram�ne qu'� un seul PNR
  #    Nous v�rifions via la commande RL que celui ci se rapporte bien
  #      au PNR Socrate fourni (DV).
  if ($lines->[0] =~ /^\s*---\s+(.*)\s+---\s*$/) { # La premi�re ligne est --- RLR ---
    my $line = $lines->[1];
    my ($r, $q, $a, $d, $l) = ($1, $3, $4, $6, $7)
      if ($line =~ /^ RP\/(\w+)(\/(\w+))? \s+ (\w+)?\/(\w+)? \s+ (\w+\/\w+) \s+ (\w+) \s* $/x);
    return $PNR unless ($1 && $3 && $6 && $7); # Sous-entendu 'UVWXYZ'
    $PNR =  $l; $PNR =~ s/^\s*(\w+.*\w+)\s*$/$1/;
    # Nous v�rifions ensuite que la r�f�rence trouv�e correspond bien � la DV fournie
    my $tmpLines = $self->command(Command => 'RL', NoIG => 1, NoMD => 1);
    if (grep(/2C\/$DV/, @$tmpLines)) { return $PNR } else { $PNR = 'UVWXYZ'; }
  }
  #
  # ____________________________________________________________________
  # ### PROPOSITION DE RESULTATS
  # ____________________________________________________________________
  #    'RT/PAREC38DD/26JAN-MARTIN*A                                       ',
  #    '  1 MARTIN/AUROREMRS      TRN 2C      26JAN           1 5EDOSV  ',
  #    '  2 MARTIN/PHILIPPEMR     TP  441  O  26JAN  ORYLIS   2 YQVOS2  '
  #
  #    Etant donn� que cette fonctionnalit� ne concerne que le TRAIN FR,
  #      nous allons filtrer que les entr�es qui concernent la compagnie 2C "SNCF"
  #    # TODO Eurostar et Thalys ?
  #    
  #    Nous parcourons la liste des r�sultats en nou v�rifions via la commande RL
  #      qu'elle se rapporte bien au PNR Socrate fourni.
  #
  # ====================================================================
  
  if ($lines->[0] =~ /^RT\//) {
    my $tmpLines = [];
    # notice(Dumper($lines));
    foreach my $line (@$lines)    { push @$tmpLines, $line if ($line =~ /TRN 2C/); }
    # notice(Dumper($tmpLines));
    foreach (@$tmpLines) {
      my $tmpPNR   =  $_;
         $tmpPNR   =~ s/^.*?\d\s(\w{6})\s*$/$1/;
      # notice('tmpPNR = '.$tmpPNR.'.');
      $self->RT(PNR => $tmpPNR, NoMD => 1, NoPostIG => 1, NoIG => 1, NoPostIG => 1);
      my $rlLines = $self->command(Command => 'RL', NoIG => 1, NoMD => 1, NoPostIG => 1);
      if (grep(/2C\/$DV/, @$rlLines)) { return $tmpPNR; }
    }
  }
  
  return $PNR;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
#             ~~~ M�thodes priv�es ~~~ Privates methods ~~~             
# ----------------------------------------------------------------------
sub _command {
  my $self    = shift;
  my $command = shift;

  $command =~ s/\"/\\\"/g; # " have to be escaped !
  my $isFpQuery = 0; 

  # _____________________________________________________________
  # Norme PCI DSS - Masquage partiel du numero de carte de cr�dit
  #  G�n�rique � BTC-AIR, BTC-TRAIN (MEETINGS) et SYNCRO-PROFILS
  if (($command =~ /(FP\s+CC\w{2},?)(\d+)\/(\d+)?(.*)?$/) ||
      ($command =~ /(FP-CC\w{2},?)(\d+)\/(\d+)?(.*)?$/) ||
	  ($command =~ /(FP\s+PAX\s+CC\w{2},?)(\d+)\/(\d+)?(.*)?$/) ||
      ($command =~ /(FPO\/\w+\+\/CC\w{2},?)(\d+)\/(\d+)?(.*)?$/) ||
      ($command =~ /(RC\s+CC\s+HOTEL\s+ONLY\s+\w{2})(\d+)\/(\d+)?(.*)?$/) ||
      ($command =~ /(RC\s+PMEAN\s+FP\s+CC\w{2})(\d+)\/(\d+)?(.*)?$/)) {
    my $begin  = $1;
    my $nums   = $2;
    my $exp    = $3 || '';
    my $next   = $4 || '';
    my $length = length($nums);
    my $substr = substr($nums, $length -4, 4);
    my $tmp    = '*'x($length -4);
    notice('Commande Amadeus = '.$begin.$tmp.$substr.'/'.$exp.$next);
  } else {
    notice('Commande Amadeus = '.$command);
  }

  my $reply = undef;
  if ($self->use_cryptic_service == 1) {
      $reply = executeCrypticCommand($self->officeid, $command, $self->handler->{'conversationID'});
  } else {
      $reply = APIV2XS::send_string($command, $self->handler);
  }

  if (!$reply) {
    debug('No Output !');
    $self->_clearScreen;
	} else {
	  my @lines = split("\n", $reply);
	  # _____________________________________________________________
    # Norme PCI DSS - Masquage partiel du numero de carte de cr�dit
    #  G�n�rique � BTC-AIR, BTC-TRAIN (MEETINGS) et SYNCRO-PROFILS
      my @tmpLines = @lines;
      foreach my $line (@tmpLines) {
        if (($line =~ /^(.*?)(FP\s+CC\w{2},?)(\d+)\/(\d+)?(.*)$/) ||
		    ($line =~ /^(.*?)(FP-CC\w{2},?)(\d+)\/(\d+)?(.*)$/) ||
			($line =~ /^(.*?)(FP\s+PAX\s+CC\w{2},?)(\d+)\/(\d+)?(.*)$/) ||
            ($line =~ /^(.*?)(FP\s+O\/\w+\+\/CC\w{2},?)(\d+)\/(\d+)?(.*)$/) ||
            ($line =~ /^(.*?)(RC\s+CC\s+HOTEL\s+ONLY\s+\w{2})(\d+)\/(\d+)?(.*)?$/) ||
			($line =~ /^(.*?)(RC\s+PMEAN\s+FP\s+CC\w{2})(\d+)\/(\d+)?(.*)?$/)) {
          my $start  = $1;
          my $begin  = $2;
          my $nums   = $3;
          my $exp    = $4 || '';
          my $end    = $5 || '';
          my $length = length($nums);
          my $substr = substr($nums, $length -4, 4);
          my $tmp    = '*'x($length -4);
          $line = $start.$begin.$tmp.$substr.'/'.$exp.$end;
        }
      }
      debug("Reponse Amadeus = \n".Dumper(\@tmpLines));
      $self->{_SCREEN} = \@lines;
	}

  return $self->_getScreen;
}
# ----------------------------------------------------------------------

# ----------------------------------------------------------------------
# R�cup�rer le contenu de la derni�re commande AMADEUS
sub _getScreen {
  my $self = shift;

  return $self->{_SCREEN};
}
# ----------------------------------------------------------------------

# ----------------------------------------------------------------------
# Nettoyer le contenu de l'appel � la derni�re commande AMADEUS
sub _clearScreen {
  my $self = shift;

  $self->{_SCREEN} = [];

  return $self->{_SCREEN};
}
# ----------------------------------------------------------------------

# ----------------------------------------------------------------------
# R�cup�rer le contenu de la derni�re commande AMADEUS et le vide
sub _getAndClearScreen {
  my $self = shift;

  my $lines = $self->_getScreen;
  $self->_clearScreen;

  return $lines;
}
# ----------------------------------------------------------------------

# ----------------------------------------------------------------------
# Remove extras empty lines in a _SCREEN
sub _cleanScreen {
  my $self = shift;

  my $lines = $self->_getScreen;

  return [] if (scalar(@$lines) == 0);

  # Scan downwards & upwards
  shift @$lines while (grep(/^\s*$/, ${$lines}[0]));
  pop   @$lines while (grep(/^\s*$/, ${$lines}[$#$lines]));

  $self->{_SCREEN} = $lines;

  return $self->{_SCREEN};
}
# ----------------------------------------------------------------------

# ----------------------------------------------------------------------
# Remove extras empty lines in an arrayRef
sub _cleanLines {
  my $self  = shift;
  my $lines = shift;
  
  # Scan downwards & upwards
  shift @$lines while (grep(/^\s*$/, ${$lines}[0]));
  pop   @$lines while (grep(/^\s*$/, ${$lines}[$#$lines]));
}
# ----------------------------------------------------------------------
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Commande TJQ / R�conciliation
sub RHALL {
  my $self    = shift;
  my $command = shift;

  if (!defined $command) {
    error('A valid command must be passed to this method.');
    return [];
  }

  my $lines    = [];
  my $tmpLines = [];

  $lines = $self->command(Command=>$command, NoIG=>1, NoMD=>1, PostIG=>0);
  
  while (1) {
    $tmpLines = $self->command(Command=>'MDR', NoIG=>1, NoMD=>1, PostIG=>0);
    last if (scalar @$tmpLines == 0);
    if (scalar @$tmpLines == 1) { push @$lines, @$tmpLines; last; }
    last if (grep(/REQUESTED DISPLAY NOT SCROLLABLE/, @$tmpLines));
    last if ((${$lines}[$#$lines]     eq ${$tmpLines}[$#$tmpLines]) &&
             (${$lines}[$#$lines - 1] eq ${$tmpLines}[$#$tmpLines - 1]) &&
             (${$lines}[$#$lines - 2] eq ${$tmpLines}[$#$tmpLines - 2]));
    push @$lines, @$tmpLines;
  }
  
  return $lines;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

1;
