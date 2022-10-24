package Expedia::Modules::TJQ::Reconciliation;
#-----------------------------------------------------------------
# Package Expedia::Modules::TJQ::Reconciliation
#
# $Id: Queue.pm 589 2010-07-21 08:53:20Z sdubuc $
#
# (c) 2002-2008 Expedia.                   www.expediacorporate.fr
#-----------------------------------------------------------------

use strict;

use Net::FTP;
use File::Slurp;
use Data::Dumper;
use POSIX qw(strftime);

use lib '../libsperl';

use Expedia::XML::Config;
use Expedia::Tools::Logger qw(&debug &notice &warning &error);
use Expedia::Tools::GlobalVars qw($cnxMgr $h_AmaMonths $ftp_dir_In $ftp_dir_TJQ);

sub run {

  my $self   = shift;
  my $params = shift;

  my $globalParams = $params->{GlobalParams};
  my $moduleParams = $params->{ModuleParams};

  my $GDS    = $params->{GlobalParams}->{gds};
  my $OID    = substr($params->{GlobalParams}->{name},4);
  my $market = $params->{GlobalParams}->{market};

  notice("NAMe:".$OID);

  my $filDate = strftime("%Y%m%d", localtime());
  my $tjqDate = uc(strftime("%d%m", localtime(time - 86400))); # Jour N-1
     $tjqDate = substr($tjqDate, 0, 2).$h_AmaMonths->{substr($tjqDate, 2, 2)};

  # ________________________________________________________________
  # REMARQUE : Comment forcer une date ?
  # > Attention : $tjqDate = $filDate - 1
  # $filDate = '20080530';
  # $tjqDate = '29MAY';
  # ________________________________________________________________

  my $bakDir  = $ftp_dir_TJQ.'/Backup/'.substr($filDate, 0, 4).'/'.substr($filDate, 4, 2).'/'.substr($filDate, 6, 2).'/';

  notice('fileDate = '.$filDate);
  notice(' tjqDate = '.$tjqDate);
  # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
  # Génération des rapports quotidiens de TJQ
  my $TJQ       = 'TJQ/SOF/D-'.$tjqDate;
  my $TJQ_VIA_CA = 'TJQ/SOF/D-'.$tjqDate.'/QFP-CA';
  my $TJQ_VIA_CC = 'TJQ/SOF/D-'.$tjqDate.'/QFP-CC';
  my $TJQ_VIA_NR = 'TJQ/SOF/D-'.$tjqDate.'/QFP-NR';
  
  if($market =~/DK|NO|SE/)
  {
  	my $lines   = $GDS->TJQ($TJQ_VIA_CA); _writeFile('./RAPPORTS/'.$filDate.'_'.$market.'_'.$OID.'_TJQ.CA', $lines);
  	   $lines   = $GDS->TJQ($TJQ_VIA_CC); _writeFile('./RAPPORTS/'.$filDate.'_'.$market.'_'.$OID.'_TJQ.CC', $lines);
  	   $lines   = $GDS->TJQ($TJQ_VIA_NR); _writeFile('./RAPPORTS/'.$filDate.'_'.$market.'_'.$OID.'_TJQ.NR', $lines);
  }
  else
  {
  	my $lines   = $GDS->TJQ($TJQ); _writeFile('./RAPPORTS/'.$filDate.'_'.$market.'_'.$OID.'_TJQ.txt', $lines);
  }
  # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

  $GDS->disconnect;

    foreach ('./RAPPORTS/'.$filDate.'_'.$market.'_'.$OID.'_TJQ.txt') {
		 if(-e $_)
		 {
		 my @lines = read_file($_);
		 if ( ( grep(/AUCUNE DONNEE TROUVEE/, @lines) ) || ( grep(/NO DATA FOUND/, @lines) ) ) {
					system "mkdir -p $bakDir";
					system "cp", $_ ,$bakDir;
		 }
		 else {
					system "cp", $_ ,$ftp_dir_In;
		 }
		 }
	}

    foreach ('./RAPPORTS/'.$filDate.'_'.$market.'_'.$OID.'_TJQ.CA') {
		 if(-e $_)
		 {
		 my @lines = read_file($_);
		 if ( ( grep(/AUCUNE DONNEE TROUVEE/, @lines) ) || ( grep(/NO DATA FOUND/, @lines) ) ) {
					system "mkdir -p $bakDir";
					system "cp", $_ ,$bakDir;
		 }
		 else {
					system "cp", $_ ,$ftp_dir_In;
		 }
		 }
	}

    foreach ('./RAPPORTS/'.$filDate.'_'.$market.'_'.$OID.'_TJQ.CC') {
		 if(-e $_)
		 {
		 my @lines = read_file($_);
		 if ( ( grep(/AUCUNE DONNEE TROUVEE/, @lines) ) || ( grep(/NO DATA FOUND/, @lines) ) ) {
					system "mkdir -p $bakDir";
					system "cp", $_ ,$bakDir;
		 }
		 else {
					system "cp", $_ ,$ftp_dir_In;
		 }
		 }
	}
  
    foreach ('./RAPPORTS/'.$filDate.'_'.$market.'_'.$OID.'_TJQ.NR') {
		 if(-e $_)
		 {
		 my @lines = read_file($_);
		 if ( ( grep(/AUCUNE DONNEE TROUVEE/, @lines) ) || ( grep(/NO DATA FOUND/, @lines) ) ) {
					system "mkdir -p $bakDir";
					system "cp", $_ ,$bakDir;
		 }
		 else {
					system "cp", $_ ,$ftp_dir_In;
		 }
		 }
	}

  
=begin
  # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
  # Copie des rapports via FTP

  my $ftp = Net::FTP->new($ftpServer, Debug => 0);
     $ftp->login($ftpLogin, $ftpPaswd);
      $ftp->ascii();


  foreach ('./RAPPORTS/'.$filDate.'_'.$market.'_'.$OID.'_TJQ.txt') {
     if(-e $_)
     {
     $ftp->cwd();
     my @lines = read_file($_);
     if ( ( grep(/AUCUNE DONNEE TROUVEE/, @lines) ) || ( grep(/NO DATA FOUND/, @lines) ) ) {
       $ftp->mkdir($bakDir, 'RECURSE');
       $ftp->cwd($bakDir);
       $ftp->put($_);
     }
     else {
       $ftp->cwd('In');
       $ftp->put($_);
     }
     }
  }

  foreach ('./RAPPORTS/'.$filDate.'_'.$market.'_'.$OID.'_TJQ.CA') {
     $ftp->cwd();
     my @lines = read_file($_);
     if ( ( grep(/AUCUNE DONNEE TROUVEE/, @lines) ) || ( grep(/NO DATA FOUND/, @lines) ) ) {
       $ftp->mkdir($bakDir, 'RECURSE');
       $ftp->cwd($bakDir);
       $ftp->put($_);
     }
     else {
       $ftp->cwd('In');
       $ftp->put($_);
     }
  }

  foreach ('./RAPPORTS/'.$filDate.'_'.$market.'_'.$OID.'_TJQ.CC') {
     $ftp->cwd();
     my @lines = read_file($_);
     if ( ( grep(/AUCUNE DONNEE TROUVEE/, @lines) ) || ( grep(/NO DATA FOUND/, @lines) ) ) {
       $ftp->mkdir($bakDir, 'RECURSE');
       $ftp->cwd($bakDir);
       $ftp->put($_);
     }
     else {
       $ftp->cwd('In');
       $ftp->put($_);
     }
  }

    foreach ('./RAPPORTS/'.$filDate.'_'.$market.'_'.$OID.'_TJQ.NR') {
     $ftp->cwd();
     my @lines = read_file($_);
     if ( ( grep(/AUCUNE DONNEE TROUVEE/, @lines) ) || ( grep(/NO DATA FOUND/, @lines) ) ) {
       $ftp->mkdir($bakDir, 'RECURSE');
       $ftp->cwd($bakDir);
       $ftp->put($_);
     }
     else {
       $ftp->cwd('In');
       $ftp->put($_);
     }
  }
  
  $ftp->quit;
  # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
=cut

  return 1;
}

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Méthode privée d'écriture du fichier de rapport TJI ou TJQ
sub _writeFile {
        my $fileName = shift;
        my $resLines = shift;

  my $result   = '';

        foreach my $resLine (@$resLines) {
                $result .= $resLine."\n";
        }
        write_file($fileName, $result);

  return 1;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@



1;
