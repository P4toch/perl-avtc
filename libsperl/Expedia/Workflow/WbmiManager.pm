package Expedia::Workflow::WbmiManager;
#-----------------------------------------------------------------
# Package Expedia::Workflow::WbmiManager
#
# $Id: WbmiManager.pm 602 2010-08-10 13:26:27Z pbressan $
#
# (c) 2002-2007 Expedia.                   www.expediacorporate.fr
#-----------------------------------------------------------------

use strict;
use Data::Dumper;
use POSIX qw(strftime);
use Time::HiRes qw(nanosleep);

use Expedia::Tools::Logger qw(&debug &notice &warning &error);
use Expedia::XML::MsgGenerator;
use Expedia::Databases::WbmiQueries qw(&getWbmiMessage);
use Expedia::Databases::WorkflowManager qw(&insertWbmiMsg);

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# CONSTRUCTEUR
sub new {
  my ($class, $options) = @_;
  
  my $batchName = $options->{batchName};
  my $mdCode    = $options->{mdCode};
  
  if ((!$batchName) || ($batchName !~ /^(BTC_AIR|BTC_TRAIN)$/)) {
    error("A valid '$batchName' is required. Aborting.");
    return undef;
  }
  
  if ((!$mdCode) || ($mdCode !~ /^\d+$/)) {
    error("A valid '$mdCode' is required. Aborting.");
    return undef;
  }
  
  my $currentPhase = 1;
  my $totalPhase   = 1;
     $totalPhase   = 3   if ($batchName eq 'BTC_TRAIN');

	my $self = {};
	bless ($self, $class);
	
	$self->{_BATCH}        = $batchName;
	$self->{_STATUS}       = 'SUCCESS';
	$self->{_MDCODE}       = $mdCode;
	$self->{_CURRENTPHASE} = $currentPhase;
	$self->{_TOTALPHASE}   = $totalPhase;
	$self->{_REPORTS}      = [];
	$self->{_REPORTSENDED} = 0; # Rapport WBMI déjà notifié
	$self->{_SENDALL}      = 0;

  return $self;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
sub status {
	my ($self, $status) = @_;

  $self->{_STATUS} = $status if (defined $status);
  return $self->{_STATUS};
}

sub currentPhase {
  my ($self, $phase)  = @_;
  
  $self->{_CURRENTPHASE} = $phase if (defined $phase);
  return $self->{_CURRENTPHASE};
}

sub reportSended {
  my ($self, $sended)  = @_;
  
  $self->{_REPORTSENDED} = $sended if (defined $sended);
  return $self->{_REPORTSENDED};
}

sub sendAll {
  my ($self, $sendall)  = @_;
  
  $self->{_SENDALL} = $sendall if (defined $sendall);
  return $self->{_SENDALL};
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
sub addReport {
  my ($self, $report) = @_;
  
  my $code = $report->{Code};
  
  if ((!defined $code) || ($code !~ /^\d+$/)) {
    notice('addReport: A valid code is needed.');
    return undef;
  }
  
  if ($self->_searchIfReportExists($report)) {
    debug('addReport: This report already exists. Will not add it [...]');
    return $self->{_REPORTS};
  }
  
  my $wbmiMesg = getWbmiMessage($code);
  
  if (!defined $wbmiMesg) {
    notice("addReport: Cannot add this report because Code '$code' is not mapped.");
    return undef;
  }
  
  $report->{WbmiMesg}  = $wbmiMesg;
  $report->{WbmiMesg} .= $report->{AddWbmiMesg} if (exists $report->{AddWbmiMesg});
  # 30 Juin 2008 - A la demande de Lionel car la colonne SQL est trop *short*
  $report->{WbmiMesg}  = substr($report->{WbmiMesg}, 0, 254);

  $report->{Date}      = _getTimeForXml();
  
  push @{$self->{_REPORTS}}, $report;
  
  return $self->{_REPORTS};
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Utilisé pour la génération d'une date au format XML / XSD
sub _getTimeForXml {
  return strftime "%Y-%m-%dT%H:%M:%S.000Z", localtime;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
sub sendXmlReport {
  my $self = shift;
  
  return 1 if ($self->{_REPORTSENDED} == 1); # On ne fait rien si XML déjà envoyé.
  
  my $oMsg = Expedia::XML::MsgGenerator->new({
    Batch          => $self->{_BATCH},
    Status         => $self->{_STATUS},
    MdCode         => $self->{_MDCODE},
    CurrentPhase   => $self->{_CURRENTPHASE},
    TotalPhase     => $self->{_TOTALPHASE},
    Reports        => $self->{_REPORTS},
  }, 'NotifyBTCProcessed.tmpl');
  
  my $msg =  $oMsg->getMessage; debug('WBMI Report = '.$msg);
     $msg =~ s/>\s*</></ig; # Préparation pour envoi en base.

  notice('Notifying WBMI Report [...]');
  
  &insertWbmiMsg({XML => $msg, CODE => $self->{_MDCODE}});
  
  # ____________________________________________________________________
  # Suite à la réunion WBMI et relecture de la Spec, je dois faire
  #  le HACK suivant : Si c'est du TRAIN et que j'ai une FAILURE
  #  et que je ne suis pas en phase (3/3) alors je dois envoyer
  #   les étapes manquantes pour aller au (3/3).
  # 19 Février 2010 ~ RavelGold : Ou qu'il faut tout envoyer
  if ((($self->{_BATCH}  eq 'BTC_TRAIN') &&
       ($self->{_STATUS} eq 'FAILURE')   && 
       ($self->{_CURRENTPHASE} < 3)) || ($self->{_SENDALL})) {
    my $nbFakeMsg = 3 - $self->{_CURRENTPHASE};
    notice('Need to send '.$nbFakeMsg.' fake WBMI messages.');
    for (my $phase = ($self->{_CURRENTPHASE} + 1); $phase <= $self->{_TOTALPHASE}; $phase++) {
      nanosleep(200000000);
      my $oFake = Expedia::XML::MsgGenerator->new({
        Batch          => $self->{_BATCH},
        Status         => $self->{_STATUS},
        MdCode         => $self->{_MDCODE},
        CurrentPhase   => $phase,
        TotalPhase     => $self->{_TOTALPHASE},
        Reports        => [],
      }, 'NotifyBTCProcessed.tmpl');
      my $fake =  $oFake->getMessage; debug('WBMI Report = '.$fake);
         $fake =~ s/>\s*</></ig; # Préparation pour envoi en base.
      &insertWbmiMsg({XML => $fake, CODE => $self->{_MDCODE}});
    }
  }
  # ____________________________________________________________________
  
  $self->{_REPORTSENDED} = 1;
  
  return 1;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Va voir si ce rapport existe dejà dans la base des rapports
#  => Pour éviter de l'envoyer plusieurs fois dans le XML ;)
sub _searchIfReportExists {
  my ($self, $report) = @_;

  my $exists = 0;

  my $allReports = $self->{_REPORTS};

  REPORT: foreach my $r (@$allReports) {
    last REPORT if ($exists);
    foreach my $key (keys %{$report}) {
      next if ($key =~ /^(Date|WbmiMesg)$/);
      next REPORT if ($r->{$key} ne $report->{$key});
    }
    # Si je suis là c'est que j'ai déjà un rapport exactement similaire
    $exists = 1;
  }

  return $exists;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

1;
