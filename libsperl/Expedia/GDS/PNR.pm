package Expedia::GDS::PNR;
#-----------------------------------------------------------------
# Package Expedia::GDS::PNR
#
# $Id: PNR.pm 625 2011-03-01 09:54:23Z pbressan $
#
# (c) 2002-2010 Egencia.                            www.egencia.eu
#-----------------------------------------------------------------

use strict;
use XML::LibXML;
use Data::Dumper;
use MIME::Lite;
use Expedia::Tools::GlobalVars  qw($cnxMgr $sendmailProtocol $sendmailIP $sendmailTimeout);
use Expedia::Tools::Logger qw(&debug &notice &warning &error);
use Expedia::WS::Commun qw(&getPnrAndTstInXml);

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# CONSTRUCTEUR
sub new {
  my ($class, %params) = @_;


  # Les param�es obligatoires sont les suivants :
  #   $params  = { PNR => $PNR, GDS => $GDS }   # EXEMPLE
  my $PNR      = $params{PNR} || undef;
  my $GDS      = $params{GDS} || undef;
  my $NoIG     = $params{NoIG} || undef;
  my $PostIG   = $params{PostIG};
#notice("PNR GDS:".$PNR);
#notice("IG GDS:".$NoIG);
#notice("POST IG GDS:".$PostIG);
  # -------------------------------------------------------------------
  # Gestion des param�es obligatoires
  if ((!$PNR) || (($PNR !~ /^\w{6}$/) && ($PNR !~ /^\/ZZZZZ\S\w{6}$/))) {
    error('A valid PNR parameter must be provided to this constructor. Aborting.');
    return undef;
  }
  if ((!$GDS) || (ref($GDS) ne 'Expedia::Databases::Amadeus')) {
    error('A valid AMADEUS connection must be provided to this constructor. Aborting.');
    return undef;
  }
  unless ($GDS->connected) {
    error('Amadeus needs to be connected. Aborting.');
    return undef;
  }  
  # -------------------------------------------------------------------

  my $self = {};
  bless ($self, $class);

  $self->{_PNR}          = $PNR;  # L'identifiant PNR - Dossier Voyage
  $self->{_GDS}          = $GDS;  # Le handle de connection �MADEUS
  $self->{_SCREEN}       = [];
  
  # Relatif aux Traitements Amadeus XML
  $self->{_XMLPNR}       = undef;
  $self->{_XMLTST}       = undef;
  
  # Relatif au Traitement Automatique des Billets TAS
  $self->{TAS_ERROR}     = undef;
  $self->{EMD_ERROR}     = undef;
  
  # R�cup�r� de l'ancien fonctionnement cod� par Jean-Fran�ois PACCINI
  $self->{Tag}           = undef;
  $self->{RespOfficeId}  = undef;
  $self->{QueueOfficeId} = undef;
  $self->{LastAgent}     = undef;
  $self->{LastTime}      = undef;
  $self->{PNRId}         = '';
  $self->{PAX}           = [];
  $self->{PNRData}       = [];
  $self->{Segments}      = [];
  $self->{Security}      = [];
  
  my $resGet = $self->get({NoIG => $NoIG, PostIG => $PostIG});        # R�p�tion du PNR - Dossier Voyage
  return undef if (!$resGet || $resGet == 0);

  warning('No lines were returned when getting this PNR !')
    if (scalar(@{$self->{_SCREEN}}) == 0);

  warning('Problem detected with PNR Identifier.')
    if (($self->{_PNR} ne $self->{PNRId}) && (($PNR !~ /^\/ZZZZZ\S\w{6}$/)));

  return $self;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
sub get {
  my $self   = shift;
  my $params = shift;

  my $noIG   = 0; # Par d�ut on veut IG avant RT
     $noIG   = 1 if ((defined($params->{NoIG}))   && ($params->{NoIG}   eq '1'));

  my $noMD   = 0; # Par d�faut on veut des move down
     $noMD   = 1 if ((defined($params->{NoMD}))   && ($params->{NoMD}   eq '1'));

  my $postIG = 1; # Par d�faut IG apr�s le RT
     $postIG = 0 if ((defined($params->{PostIG})) && ($params->{PostIG} eq '0')); 

   #  notice("TEST PostIG AMADEUS:".$postIG);
   #  notice("TEST PostIG AMADEUS:".$params->{PostIG});
     
  if ($self->{_PNR} && ($self->{_PNR} ne '')) {
      $self->{_SCREEN} = $self->{_GDS}->RT(PNR => $self->{_PNR}, NoMD => $noMD, PostIG => $postIG, NoIG => $noIG);


    shift @{$self->{_SCREEN}}
      if ($self->{_SCREEN}->[0] =~ /^NOUVELLE\s+VALIDATION.*$/);

	  shift @{$self->{_SCREEN}}
      if ($self->{_SCREEN}->[0] =~ /^\-\-\-\s.*\s\-\-\-$/);

    # PNR Identifier should appear on the first _SCREEN line
		if (($self->{_SCREEN}->[0] !~ /$self->{_PNR}$/) && ($self->{_PNR} !~ /^\/ZZZZZ\S\w{6}$/)) {
			warning("Problem detected during get of PNR '".$self->{_PNR}."'.");
			return 0;
		}
		
		debug('_SCREEN = '.Dumper(\@{$self->{_SCREEN}}));

    my $scan = 0;
       $scan = $self->_scan if (scalar(@{$self->{_SCREEN}}) > 0);
       
    debug('Error detected during PNR _scan !!!') unless ($scan);
    
    return $scan;
    
  } else {
    error('A valid PNR parameter must be provided to this method. Aborting.');
    return 0;
  }

  return 1;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# R�p� la forme XML du PNR et de la TST
sub getXML {
  my $self = shift;
  my $tpid = shift;
  
  my $PNR = $self->{_PNR};
  if (!$PNR || $PNR eq '') {
    error('A valid PNR parameter must be provided to this method. Aborting');
    return 0;
  }
  
  my $replyPNR = undef;
  my $replyTST = undef;
  
  if ($self->{_GDS}->use_cryptic_service == 1) {
    
    my $replyPNRAndTST;
    eval { $replyPNRAndTST = getPnrAndTstInXml($tpid, $PNR); };
    if ($@) { error('Error during getPnrAndTstInXml : '.$@); return 0; }
    if ($replyPNRAndTST =~ /(<PoweredPNR_PNRReply>.*<\/PoweredPNR_PNRReply>).*(<PoweredTicket_DisplayTSTReply>.*<\/PoweredTicket_DisplayTSTReply>)/s) {
      $replyPNR = $1;
      $replyTST = $2;
    }
    
  } else {
    
    my $xmlPNR = "<PoweredPNR_Retrieve><retrievalFacts><retrieve><type>2</type></retrieve><reservationOrProfileIdentifier><reservation><controlNumber>$PNR</controlNumber></reservation></reservationOrProfileIdentifier></retrievalFacts></PoweredPNR_Retrieve>";
    debug($xmlPNR);
    $replyPNR = $self->{_GDS}->commandXML($xmlPNR);
    
    my $xmlTST = "<PoweredTicket_DisplayTST><displayMode><attributeDetails><attributeType>ALL</attributeType></attributeDetails></displayMode></PoweredTicket_DisplayTST>";
    debug($xmlTST);
    $replyTST = $self->{_GDS}->commandXML($xmlTST);
    
  }
  
  my $PNRdoc = undef;
  my $TSTdoc = undef;
  my $parser = XML::LibXML->new();
  
  eval    { $PNRdoc = $parser->parse_string($replyPNR); };
  if ($@) { error('Parser Error !#! '.$@); return 0; }
  $PNRdoc->indexElements();
  debug($PNRdoc->toString(1));
  
  eval    { $TSTdoc = $parser->parse_string($replyTST); };
  if ($@) { error('Parser Error !#! '.$@); return 0; }
  $TSTdoc->indexElements();
  debug($TSTdoc->toString(1));

  $self->{_XMLPNR} = $PNRdoc;
  $self->{_XMLTST} = $TSTdoc;

  return 1;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Rechargement des informations d'un PNR
sub reload {
  my $self = shift;

  if (!$self->{PNRId}) {
    error('Cannot reload PNR because of missing identifier.');
    return 0;
  }
  
  my $travellers = undef;
     $travellers = $self->{Travellers} if (exists $self->{Travellers});
  my $passengers = undef;
     $passengers = $self->{PAX}        if (exists $self->{PAX});

  $self->{PAX}           = [];
  $self->{PNRData}       = [];
  $self->{Segments}      = [];
  $self->{Security}      = [];
  
  $self->get({PostIG => 0}); # On souhaite accomplir les actions dans la foul�
  
  $self->{Travellers} = $travellers if defined $travellers;
  $self->{PAX}        = $passengers if defined $passengers;
  
  return 1;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Mise �our des infos contenues dans un PNR
sub update {
  my $self   = shift;
  my %params = (@_);
  my $RT      = [];

  if (!$self->{PNRId} || !%params) {
    error('Cannot update PNR because of missing update parameters.');
    return 0;
  }

  my @del = (); my @add = (); my @mod = (); my $QE = 0;

  @del = sort {$a <=> $b} (@{$params{del}}) if $params{del};
  @add = @{$params{add}} if $params{add};
  @mod = @{$params{mod}} if $params{mod};

  return 1 if (($#del == -1) && ($#add == -1) && ($#mod == -1) && (!exists $params{rename}));
  debug('I have something to update: '.Dumper(\%params));

  # Ouverture ou R�verture du dossier AMADEUS
  my $GDS = $self->{_GDS};
  $GDS->RT(PNR => $self->{PNRId});

  # -----------------------------------------
  # Modify lines in PNR
  while (my $ref = shift(@mod)) {
    debug('Modifying line : '.$ref);
      $GDS->command(Command => $ref, NoIG => 1, NoMD => 1);

  }
  # -----------------------------------------
  # Delete lines in PNR (from bottom to top)
  while (my $ref = pop(@del)) {           # Delete from Amadeus (from bottom to top)
    foreach my $i (@{$self->{PNRData}}) { # Scan current info & decide updates
      if ($i->{LineNo} == $ref) {         # Found line
        debug('Deleting line n�'.$ref);
          $GDS->command(Command => "XE $ref", NoIG => 1, NoMD => 1);
      }
    }
  }
  # -----------------------------------------
  # Add new infos in PNR
  while (my $ref = shift(@add)) {
    debug('Adding line : '.$ref->{Data});
     #BUG 15475
     #CAS ISOS, ON DOIT FAIRE RF AVANT LA COMMANDE QE
     if($ref->{Data} =~ /^QE/)
     {
         $GDS->command(Command => 'RF'.$GDS->modifsig, NoIG => 1, NoMD => 1); $QE=1;
         $RT = $GDS->command(Command => $ref->{'Data'}, NoIG => 1, NoMD => 1);

       #LORSQU'ON FAIT UNE COMMANDE QEXXXX, ON VA VERIFIER QUE LE MESSAGE EN RETOUR N'EST PAS DU TYPE
       #AVERTISSEMENT/WARNING/AVISO
       #SI C'EST LE CAS ON REFAIT LA COMMANDE POUR LA FORCER
       if (grep(/^(WARNING|AVERTISSEMENT|AVISO|ATTENT)/, @$RT))
       {
          notice('ERROR QUEUING:'.$RT->[0]);
          $RT      = [];
           $RT = $GDS->command(Command => $ref->{'Data'}, NoIG => 1, NoMD => 1);

          notice('RETRY:'.$RT->[0]);
       } 
       elsif(grep(/(PLACE EN FILE|ON QUEUE|EN LA COLA)/, @$RT))
       {
          #ON NE FAIT RIEN C'EST BON
       }
       else
       {
          #AUTRE MESSAGE DE RETOUR, ON ENVOIE UN MAIL POUR ETRE PROACTIF
          notice('ERROR QUEUING UNKNOWN:'.$RT->[0]);
          eval 
      	  {
      	  my $mail_errors='s.dubuc@egencia.fr';
          my $msg_error = MIME::Lite->new(
            From     => 'noreply@egencia.eu',
          	To       => $mail_errors,
          	Subject  => 'TRACKING -- UNKNOWN ERROR',
          	Type     => 'TEXT',
        	  Encoding => 'quoted-printable',
        	  Data    => 'Hello,'.
        	             "\n\nPNR : ".$self->{PNRId}.
        	             "\n\nError Message : ".$RT->[0].
                       "\n\nBatman & Robin :o)\n",  
                    
          );
      	  
          MIME::Lite->send($sendmailProtocol, $sendmailIP, Timeout => $sendmailTimeout);
          $msg_error->send;
      	  } ;
      	  if ($@) {
              notice('Problem during email send process. '.$@);
          }
       }
     }
     else
     {
         $GDS->command(Command => $ref->{'Data'}, NoIG => 1, NoMD => 1);

     }
  }
  # -----------------------------------------

  my $ET      = [];
  my $success = 1;

  if($QE != 1) {
      $GDS->command(Command => 'RF'.$GDS->modifsig, NoIG => 1, NoMD => 1);
      $ET = $GDS->command(Command => 'ET', NoIG => 1, NoMD => 1);

  }
  
  if (grep(/(FIN|END) (DE|OF) (TRANSACTION|TRANSACCION)/, @$ET) || $QE == 1) {
  } else {
      $ET = $GDS->command(Command => 'ET', NoIG => 1, NoMD => 1);

    if (grep(/(FIN|END) (DE|OF) (TRANSACTION|TRANSACCION)/, @$ET)) {
    } else {
      notice('PNR update failure.');
      notice($ET->[0]);
      $success = 0;
    }

  }

  (($params{NoGet}) && ($params{NoGet} ne '')) || $self->get;

  return $success;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Renommage des Passagers dans un dossier - Moulinette TRAIN
sub rename {
  my $self   = shift;
  my $parray = shift; 
  my %params = (@_);

  if (!$self->{PNRId}) {
    error('Cannot update PNR because of missing rename parameters.');
    return 0;
  }

  return [] unless ($parray);
  return [] unless (%params);
  debug('I have something to update...');

  # Ouverture ou R�verture du dossier AMADEUS
  my $GDS = $self->{_GDS};
  $GDS->RT(PNR => $self->{PNRId});

  my $i = 0;
  foreach my $pax (@$parray) {
    $i++;
    my $name = $pax->{name} || $pax->{nfo}->{name};
    debug('Renaming PAX '.$name);
    $GDS->command(Command => 'NU'.$i.'/1'.$name, NoIG => 1, NoMD => 1);
  }

  my $ET      = [];
  my $success = 1;

  $GDS->command(Command => 'RF'.$GDS->modifsig, NoIG => 1, NoMD => 1);
  $ET = $GDS->command(Command => 'ET', NoIG => 1, NoMD => 1);
  
  if (grep(/(FIN|END) (DE|OF) (TRANSACTION|TRANSACCION)/, @$ET)) {
  } else {
    $ET = $GDS->command(Command => 'ET', NoIG => 1, NoMD => 1);
    if (grep(/(FIN|END) (DE|OF) (TRANSACTION|TRANSACCION)/, @$ET)) {
    } else {
      notice('PNR update failure.');
      notice($ET->[1]);
      $success = 0;
    }
  }

  # R�verture du dossier Amadeus pour Analyse des Noms
  my $lines = $GDS->RT(PNR => $self->{PNRId});
  my @lines = @$lines;
         
  my $paxSection = 0;
  my $passengers = {};

  LINE: while (my $line = shift @lines) {
    # Passenger lines
    if ($line =~ /^\s*(\d+\.\w.*)\s{0,16}$/) {
      $paxSection = 1;
      my $pline = $1;
      while ($pline =~ s/^\s*(\d+)\.([^\d\.]+)(\s\d+\.|$)/$3/) {
				debug("Found PAX #$1=$2");
				my $paxnum = $1;
				my $name   = $2;
				$name =~ s/\s{2,}//go;
				$passengers->{$paxnum} = $name;
			}
			next LINE;
		} else {
			last LINE if ($paxSection == 1);
		}
	} # FIN LINE: while (my $line = shift @lines)

  debug('passengers = '.Dumper($passengers));
  
  my $add = [];
  
  foreach my $rp (keys %$passengers) {
    foreach my $p (@$parray) {
      my $name = $p->{name} || $p->{nfo}->{name};
      if ($name =~ /$passengers->{$rp}/) {
        my $percode = $p->{percode} || $p->{nfo}->{percode};
        debug($name.' match '.$passengers->{$rp});
        push (@$add, 'RM *PERCODE '.$percode.'/P'.$rp);
      }
    }
  }
  
  debug('add = '.Dumper($add));
  
  return $add;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Scan le PNR et range les informations contenues dedans...
sub _scan {
  my $self  = shift;

  my $line  = undef;
  my @lines = @{$self->{_SCREEN}};

  return 0 if (!$self->{_SCREEN} || scalar(@{$self->{_SCREEN}}) == 0);

  # ---------------------------------------------------------
  # First line: PNR tag: RLR (regular), AXR, NHP, MSC, HFR,
  # ... *PARENT PNR*, *ASSOCIATE PNR* ...
  # Normalement �rt�ors de l'appel �a commande RT
  # ---------------------------------------------------------
  if ($lines[0] =~ /^\s*---\s+(.*)\s+---\s*$/) {
    $line = shift @lines;
    $self->{Tag} = $1;
  }

  # ---------------------------------------------------------
  # Second line: PNR identification elements
  # RP/PARA121GZ/PARA121JN            JF/SU  13MAY03/1208Z   YYNRCP
  # ---------------------------------------------------------
  $line = shift @lines;
  my ($r, $q, $d, $l) = ($1, $3, $4, $5)
  if ($line =~ /^ RP\/(\w+)(\/(\w+))?.*(\w*\/\w*Z) \s+ (\w+) \s* $/x);
  # if ($line =~ /^ RP\/(\w+)(\/(\w+))? \s+ (\w+)\/\w+ \s+ (\w+\/\w+) \s+ (\w+) \s* $/x);
  # if ($line =~ /^ RP\/(\w+)(\/(\w+))? \s+ (\w+)?\/(\w+)? \s+ (\w+\/\w+) \s+ (\w+) \s* $/x);

# return 0 unless ($1 && $3 && $4 && $6 && $7);
# return 0 unless ($1 && $3 && $6 && $7);
  return 0 unless ($1 && $3 && $4 && $5);

  $self->{RespOfficeId}  = $r;
  $self->{QueueOfficeId} = $q;
  $self->{LastTime}      = $d || '';
  $self->{PNRId}         = $l;
  $self->{PNRId}         =~ s/^\s*(\w+.*\w+)\s*$/$1/; # Suppress leading and trailing spaces
  
  debug("RespOfficeId='".$self->{RespOfficeId}."' QueueOfficeId='".$self->{QueueOfficeId}."' LastTime='".$self->{LastTime}."' PNRId='".$self->{PNRId}."'");

  # ---------------------------------------------------------
  # Remainig lines = PNR content
  # ---------------------------------------------------------
  my $section = undef;
  LINE: while ($line = shift @lines) {
    # -----------------------------------------
    # Passenger lines
    if ($line =~ /^\s*(\d+\.\w.*)\s{0,16}$/) {
      $section = 'PAX';
	  
	  #EGE-97209 , we remove the birthday from the line and keep the same code than previously  
	  $line =~ s/\((ID\/*\w{7})\)//g;
      $line =~ /^\s*(\d+\.\w.*)\s{0,16}$/ ;
      $l = $1;
      while ($l =~ s/^\s*(\d+)\.([^\d\.]+)(\s\d+\.|$)/$3/) {
        debug("Found PAX #$1=$2");
        push (@{$self->{PAX}}, { LineNo => $1, Data => $2 });
      }
      next LINE;
    }
    # -----------------------------------------
    # Regular numbered lines
    if ($line =~ /^ \s* (\d+) [\s\.] (\w.*) \s{0,16} $/x) {
      $section = 'PNRData';
      push (@{$self->{PNRData}}, { LineNo => $1, Data => $2 });
      next LINE;
    }
    # -----------------------------------------
    # Segments
    if ($line =~ /^ \s* (\d+) \s\s (\w.*) \s{0,16} $/x) {
      $section = 'Segments';
      my $segData = $2;
      if ($segData =~ /^ARNK$/) {
        debug ("Ignored line: '$line'");
      } else {
        push (@{$self->{Segments}}, { LineNo=>$1, Data=>$2 });
      }
      next LINE;
    }
    # -----------------------------------------
    # Security elements
    if ($line =~ /^ \s* \* \s ES\/ (\w.*) \s{0,16} $/x) {
      $section = 'Security';
      push (@{$self->{Security}}, { Data => $1 });
      next LINE;
    }
    # -----------------------------------------
    # Continuation lines ~ Update previous line content
    if (defined($section)) {
      if (($section eq 'PNRData') && ($line =~ /^ \s{7} (.*)  \s{0,16} $/x) ) {
        ${$self->{PNRData}}[$#{$self->{PNRData}}]->{Data} .= $1;
        next LINE;
      }
      if (($section eq 'Security') && ($line =~ /^ \s{4} (.*)  \s{0,16} $/x) ) {
        push (@{$self->{Security}}, { Data => $1 });
        next LINE;
      }
    }
    # -----------------------------------------
    debug ("Ignored line: '$line'");
  } # Fin LINE: while ($line = shift @lines)

  # Clean extra spaces in Data lines
  foreach (@{$self->{PNRData}}, @{$self->{Segments}}, @{$self->{PAX}}, @{$self->{Security}}) {
    $_->{Data} =~ s/\s*$// if ((exists $_->{Data}) && (defined $_->{Data}));
  }

  return 1;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

1;

