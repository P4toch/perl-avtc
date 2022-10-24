#!/usr/bin/perl -w
#-----------------------------------------------------------------
# Batch fopMarket.pl
#
# $Id: fopMarket.pl 533 2009-06-16 15:45:33Z pbressan $
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

my $opt_mrkt;
my $opt_help;

GetOptions(
  'market=s', \$opt_mrkt,
  'help',     \$opt_help,
);

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# La notion de march� est obligatoire
if (!$opt_mrkt || $opt_mrkt !~ /^(FR|GB|IT|DE|BE|ES|IE|NL|CH|SE)$/) {
  $opt_help = 1;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Affichage de l'aide
if ($opt_help) {
  print STDERR ("\nUsage: $0 --market=[FR|GB|IT|DE|BE|ES|IE|NL|CH|SE] --help\n\n");
  exit(0);
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

my $config = Expedia::XML::Config->new('config.xml');

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# R�cup�ration de tous les comCodes pour un march� donn�
notice('########################################################');
notice("___ R�cup�ration des ComCodes des Soci�t�s � traiter ___");
my $comCodes =  _getComCodesFromMarket($opt_mrkt);
my $total    = scalar @$comCodes;
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Cr�ation du fichier de RAPPORT d'erreur
my @comCodeList = ();
push @comCodeList, $_->{ComCode} foreach (@$comCodes);
my $reportFile  = './RAPPORTS/'.strftime("%Y%m%d",localtime()).'_'.$opt_mrkt.'.txt';
my $report      = '';
   $report     .= 'Heure de Lancement = '.strftime("%Y/%m/%d %H:%M:%S",localtime())."\n\n";
   $report     .= 'March�             = '.$opt_mrkt."\n\n";
   $report     .= 'COMCODES � traiter = '.join(', ', @comCodeList)."\n\n";
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
  my $comName = $_->{ComName};

  notice('comCode = '.$comCode.' - comName = '.$comName." ($count/$total)");
  
  $commande = 'perl fop.pl --comcode='.$comCode;
  eval { `$commande`; };
  $exitCode = $? / 256;
  if (($exitCode) || ($@)) {
    $report .= " Update Synchro Profils de COMCODE $comCode a �chou�. ErreurCode = $exitCode\n";
    $report .= " ERROR = ".$@.".\n" if ($@);
    $errors++;
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
sub _getComCodesFromMarket {
  my $market = shift || undef;
  
  if (!defined $market) {
    error('Missing or wrong parameter for this method.');
    return 0;
  }
  
  my $midDB = $cnxMgr->getConnectionByName('mid');
  
  my $query = '
    SELECT C.CODE, C.NAME
      FROM COMP_COMPANY C, OPST_POS O
     WHERE C.IS_ACTIVE = 1
       AND C.IS_TEST_USE = 0
       AND C.IS_COMMERCIAL_USE = 1
       AND C.OPST_POS_ID = O.ID
       AND O.CODE = ?
  ORDER BY C.CODE ASC ';

  my $res = $midDB->saarBind($query, [$market]);
  
  my $comcodes = [];

  push (@$comcodes, { ComCode => $_->[0], ComName => $_->[1] }) foreach (@$res); 
  
  return $comcodes;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@