#!/usr/bin/perl -w

# -----------------------------------------------------------------------
# Ce script met a jour les noms de sociétés dans la table AMADEUS_SYNCHRO
# dans le cas ou celui ci a été changé directement dans AMADEUS
# (Hors Process!). Si le nom n'a pas changé, il ne fait rien.
# -----------------------------------------------------------------------

use strict;

use lib '../libsperl';

use Data::Dumper;

use Expedia::XML::Config;
use Expedia::GDS::Profile;
use Expedia::Tools::Logger qw(&debug &notice &warning &error);
use Expedia::Tools::GlobalVars qw($cnxMgr);

notice("###############################################################");
notice("############        LANCEMENT DE Moulinette        ############");

my $config = Expedia::XML::Config->new('config.xml');

my $mid    = $cnxMgr->getConnectionByName('mid');
my $gdsFR  = $cnxMgr->getConnectionByName('amadeus-FR');
my $gdsDE  = $cnxMgr->getConnectionByName('amadeus-DE');
my $gdsBE  = $cnxMgr->getConnectionByName('amadeus-BE');
my $gdsGB  = $cnxMgr->getConnectionByName('amadeus-GB');
my $gdsIT  = $cnxMgr->getConnectionByName('amadeus-IT');
my $gdsES  = $cnxMgr->getConnectionByName('amadeus-ES');
my $gdsIE  = $cnxMgr->getConnectionByName('amadeus-IE');
my $gdsNL  = $cnxMgr->getConnectionByName('amadeus-NL');
my $gdsCH  = $cnxMgr->getConnectionByName('amadeus-CH');
my $gdsSE  = $cnxMgr->getConnectionByName('amadeus-SE');

# Connexion à Amadeus
$gdsFR->connect;
$gdsDE->connect;
$gdsBE->connect;
$gdsGB->connect;
$gdsIT->connect;
$gdsES->connect;
$gdsIE->connect;
$gdsNL->connect;
$gdsCH->connect;
$gdsSE->connect;

my %tmpHash = (
	'FR' => $gdsFR,
	'GB' => $gdsGB,
	'BE' => $gdsBE,
	'DE' => $gdsDE,
	'IT' => $gdsIT,
	'ES' => $gdsES,
	'IE' => $gdsIE,
	'NL' => $gdsNL,
	'CH' => $gdsCH,
	'SE' => $gdsSE,
	);

my $comQuery  = "SELECT CODE, AMADEUS_ID, MARKET, AMADEUS_NAME FROM AMADEUS_SYNCHRO WHERE TYPE='COMPANY' ORDER BY MARKET ASC, CODE ASC";

my $comRes   = $mid->saar($comQuery);
my $totalCom = scalar(@$comRes);

foreach (@$comRes) {

	my $comCode  = $_->[0];
  my $profile  = $_->[1];
	my $market   = $_->[2];
  my $name1    = $_->[3];
  my $name2    = '';

	my $oProfile = Expedia::GDS::Profile->new((PNR => $profile, GDS => $tmpHash{$market}, TYPE => 'C'));
	
	foreach my $line ( @{$oProfile->{_SCREEN}} ) {
		next unless $line =~ /^\s+\d+\sPCN\/\s(\S+.*\S+)\s*$/;
    $name2 = $1;
		last;
	}

	# Si les noms sont differents, on fait l'update
	if ( $name1 ne $name2 ) {
		notice('RENAMING COMPANY : '.$comCode.' - '.$name2);
		my $req = "UPDATE AMADEUS_SYNCHRO SET AMADEUS_NAME='$name2' WHERE CODE=$comCode AND TYPE='COMPANY'";
		$mid->do($req);
	}
	
}

$gdsFR->disconnect;
$gdsDE->disconnect;
$gdsBE->disconnect;
$gdsGB->disconnect;
$gdsIT->disconnect;
$gdsES->disconnect;
$gdsIE->disconnect;
$gdsNL->disconnect;
$gdsCH->disconnect;
$gdsSE->disconnect;

notice("############           FIN DE Moulinette           ############");
notice("###############################################################");

exit;

