#!/usr/bin/perl -w
#-----------------------------------------------------------------
# Batch fopMarket.pl
#
# $Id: fopGlob.pl 674 2011-04-19 14:00:54Z pbressan $
#
# (c) 2002-2008 Expedia.                   www.expediacorporate.fr
#-----------------------------------------------------------------

use strict;
use File::Slurp;
use Getopt::Long;
use Data::Dumper;
use POSIX qw(strftime);

use lib '../libsperl';

use Expedia::XML::Config;
use Expedia::Tools::GlobalVars qw($cnxMgr);
use Expedia::Tools::Logger qw(&debug &notice &warning &error);

my $config = Expedia::XML::Config->new('config.xml');

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# R�cup�ration de tous les ComCodes pour un march� donn�
notice('########################################################');
notice("___ R�cup�ration des ComCodes � traiter ___");
my $comCodes =  _getMostOlderComCodes();
my $total    = scalar @$comCodes;
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Cr�ation du fichier de RAPPORT d'erreur
my @comCodeList = ();
push @comCodeList, $_->{ComCode} foreach (@$comCodes);
my $reportFile  = './RAPPORTS/GLOB_'.strftime("%Y%m%d",localtime()).'.txt';
my $report      = '';
   $report     .= 'Heure de Lancement = '.strftime("%Y/%m/%d %H:%M:%S",localtime())."\n\n";
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

my $exitCode = -1;
my $commande = '';
my $errors   = 0;
my $count    = 0;

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# R�cup�ration des utilisateurs d'une soci�t� donn�e
foreach (@$comCodes) {

  $count++;

      my $comCode = $_->{ComCode}; 
      $report     .= 'COMCODES � traiter = '.$comCode."\n";
      
      notice('comCode = '.$comCode."($count/$total)");
      
      $commande = 'perl fop.pl --comcode='.$comCode;
      eval { `$commande`; };
      $exitCode = $? / 256;
      if (($exitCode) || ($@)) {
        $report .= " Update Synchro Profils du COMCODE $comCode a �chou�. ErreurCode = $exitCode\n";
        $report .= " ERROR = ".$@.".\n" if ($@);
        $errors++;
      }
      else
      {
       #### PAS D'ERREUR ON METS A JOUR LE PROFIL 
       my $datemaj = strftime("%d/%m/%Y",localtime());
       my $midDB = $cnxMgr->getConnectionByName('mid');
       my $query = "UPDATE AMADEUS_SYNCHRO SET TIME=? WHERE TYPE='COMPANY' AND CODE= ? ";
       my $rows = $midDB->doBind($query, [$datemaj, $comCode]);
       warning('Problem detected !') if ((!defined $rows) || ($rows != 1)); 
      }
  
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

$report .= "\n"                                                       if ($errors  > 0);
$report .= "   < Update FoP s'est achev� sans erreurs. >\n\n"         if ($errors == 0);
$report .= "   < Update FoP s'est achev� avec $errors erreurs. >\n\n" if ($errors  > 0);
$report .= "Heure de Fin       = ".strftime("%Y/%m/%d %H:%M:%S",localtime())."\n\n";

write_file($reportFile, $report);
notice('########################################################');

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# R�cup�ration de tous les ComCodes relatifs � un March� donn�
sub _getMostOlderComCodes {
 
 my $midDB = $cnxMgr->getConnectionByName('mid');
  
        
  
  my $query = "
      SELECT CODE FROM AMADEUS_SYNCHRO 
      WHERE TYPE='COMPANY'
      ORDER BY TIME ASC    
    ";

  my $res = $midDB->saar($query);
  
  my $comcodes = [];

  push (@$comcodes, { ComCode => $_->[0] }) foreach (@$res); 
  
  return $comcodes;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@