package Expedia::Tools::GlobalFuncs;
#-----------------------------------------------------------------
# Package Expedia::Tools::GlobalFuncs
#
# $Id: GlobalFuncs.pm 586 2010-04-07 09:26:34Z pbressan $
#
# (c) 2002-2008 Expedia.                   www.expediacorporate.fr
#-----------------------------------------------------------------

use Data::Dumper;
use Exporter 'import';
use MIME::Lite;
use POSIX qw(strftime);

use Expedia::Tools::Logger     qw(&debug &notice &warning &error);
use Expedia::Tools::GlobalVars qw($h_processors $cnxMgr $soapRetry $soapProblems $hashNavisionLogin);

@EXPORT_OK = qw(&fielddate2amaddate &fielddate2srdocdate &xmldatetosearchdate
                &stringGdsPaxName &stringGdsCompanyName &stringGdsOthers
                &cleanXML &dateXML &dateTimeXML
                &aqh_reporting &getNavisionConnForAllCountry &setNavisionConnection
                &_getcompanynamefromcomcode &getRTUMarkup &check_TQN_markup);

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Converts a "fields" date (2003-04-15) into an Amadeus Date (15MAR2003)
sub fielddate2amaddate {
  my $date = shift;

  return '' if ($date eq '');
  $date =~ /^(\d{4})-(\d{2})-(\d{2})/;

  my $res  = $3 ;
     $res .= qw(JAN FEB MAR APR MAY JUN JUL AUG SEP OCT NOV DEC)[$2 -1];
     $res .= $1;

  return $res;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Converts a "fields" date (2003-04-15) into an "SR DOCS" Date (15MAR03)
sub fielddate2srdocdate {
  my $date = shift;

  return '' if ($date eq '');
  $date =~ /^(\d{4})-(\d{2})-(\d{2})/;

  my $res  = $3 ;
     $res .= qw(JAN FEB MAR APR MAY JUN JUL AUG SEP OCT NOV DEC)[$2 -1];
     $res .= substr($1, 2, 2);

  return $res;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Convert a date (2009-12-13T21:05:00.000Z) to date (13DEC)
sub xmldatetosearchdate {
  my $date = shift;

  return '' if ($date eq '');
  $date =~ /^(\d{4})-(\d{2})-(\d{2})/;

  my $res  = $3 ;
     $res .= qw(JAN FEB MAR APR MAY JUN JUL AUG SEP OCT NOV DEC)[$2 -1];

  return $res; 
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Formater une chaine de caractères pour Amadeus de type PaxName
#  => Le & est converti en ' '. Les chiffres ne sont pas tolérés !
sub stringGdsPaxName {
  my $string  = shift;
  my $country = shift; 
  
  return undef if !defined $string;

  $string= `/var/egencia/libsperl/Expedia/Tools/Conversion.pl --option=PAX --string="$string"`;
  
  return $string;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Formater une chaine de caractères pour Amadeus de type CompanyName
#  => Le & est converti en ' '.
#  => Les chiffres sont tolérés.
sub stringGdsCompanyName {
  my $string = shift;
  
  return undef if !defined $string;

  $string= `/var/egencia/libsperl/Expedia/Tools/Conversion.pl --option=COMP --string="$string"`;

  return $string;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Formater une chaine de caractères pour Amadeus : Autre (que PaxName !)
#  => Chiffres tolérés.
#  => Le & est converti en '&amp;'.
#  => Les caractères - @ sont tolérés.
sub stringGdsOthers {
  my $string = shift;
  
  return undef if !defined $string;

  $string= `/var/egencia/libsperl/Expedia/Tools/Conversion.pl --string="$string"`;

  return $string;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Nettoyage d'un document XML
sub cleanXML {
  my $XML = shift;

  $XML =~ s/\n//g;
  $XML =~ s/\s+/ /g;
  $XML =~ s/> </></g;

  return $XML;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Conversion d'un élément XML 'date' ou 'datetime'
sub dateXML {
  my $date = shift;
  
  return '' if ((!defined $date) || ($date =~ /^\s*$/));
  
  my $tmp =  substr($date, 0, 10);
     $tmp =~ s/\-/\//ig;
     
  return $tmp;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Conversion d'un élément XML 'date' ou 'datetime'
sub dateTimeXML {
  my $dateTime = shift;
  
  return '' if ((!defined $dateTime) || ($dateTime =~ /^\s*$/));
  
  my $tmp =  substr($dateTime, 0, 10).' '.substr($dateTime, 11, 8);
     $tmp =~ s/\-/\//ig;
  
  return $tmp;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

sub getNavisionConnForAllCountry {

  my $dbh_nav = $cnxMgr->getConnectionByName('navision');
  my $query = "SELECT  pays
                        ,LOWER(NameServer)
                        ,NameDatabase
                        ,NameLogin
						,NamePort
                 FROM
                        liste_pays_serveur";
  my $res = $dbh_nav->saarBind($query, []);


  my %ret=();
  foreach (@$res) {
                $ret{$_->[0]} = {
                                  server          => $_->[1],
                                  database        => $_->[2],
                                  login           => $_->[3],
								  port            => $_->[4],
                            };
  }

  #notice("Navision Connection Results:".Dumper(%ret));
  return \%ret;
}

sub setNavisionConnection {
  my $Country = shift;
  my $nav_conn = shift;
  my $task   = shift;

  my $server      = $nav_conn->{$Country}->{server};
  my $database    = $nav_conn->{$Country}->{database};
  my $login       = $nav_conn->{$Country}->{login};
  my $port        = $nav_conn->{$Country}->{port};
  my $password = $hashNavisionLogin->{$login};
  my $autoconnect;

  my $dbstring = "dbi:Sybase:host=".$server.";port=".$port.":database=".$database.";sendStringParametersAsUnicode=false";
  notice("new navision database:".$dbstring);
  $autoconnect = 1 unless ($autoconnect);

  if (!$server || !$database || !$login || !$password) {
    error("Missing parameter for Navision connection.");
  } else {
         my $XMLFile = "/tmp/$Country.xml";
         my $NL=0;
         my $NL2=0;
         my $NL3=0;
         my $chaine2= undef ;

    open (OF, "<", "/var/egencia/libsperl/Expedia/Tools/config_DDB.xml") or error ("Cant open XML file");
    open (FH, ">" ,$XMLFile) or error("Cant Open XML File");
    while (<OF>)
    {
        if($_ =~/navision/)
        {
                print FH $_;
                $NL=1;
                next;
        }

        if($NL == 0)
        {
          print FH $_;
        }
        elsif($NL == 1)
        {
                $chaine2= $_;
                my $chaine="<database>".$dbstring."<\/database>";
                $chaine2=~s/.*/$chaine/;
                print FH $chaine2;
                $NL=2;
        }
        elsif($NL == 2)
        {
                $chaine2= $_;
                my $chaine="<login>".$login."</login>";
                $chaine2=~s/.*/$chaine/;
                print FH $chaine2;
                $NL=3;
        }
        elsif($NL == 3)
        {
                $chaine2= $_;
                my $chaine="<password>".$password."</password>";
                $chaine2=~s/.*/$chaine/;
                print FH $chaine2;
                $NL=0;
        }
    }
	close OF;
	close FH;
	
	my $config        = Expedia::XML::Config->new($XMLFile,$task);
	unlink $XMLFile or error ("Could not delete $XMLFile");
	
  }
}

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Get the company name with the comcode
sub _getcompanynamefromcomcode {
  my $code = shift;

  my $midDB = $cnxMgr->getConnectionByName('mid');

  my $query = "
    SELECT AMADEUS_NAME
      FROM AMADEUS_SYNCHRO
     WHERE CODE = ?
       AND TYPE = 'COMPANY' ";

  return $midDB->saarBind($query, [$code])->[0][0];
}


# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Get the RTU Markup
sub getRTUMarkup {
  my $market = shift;
  
  my $midDB = $cnxMgr->getConnectionByName('mid');
  
  my $query = "
    SELECT RTU_MARKUP
      FROM MO_CFG_DIVERS
     WHERE COUNTRY = ? ";

  return $midDB->saarBind($query, [$market])->[0][0];
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@


# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Get the currency
sub getCurrency {
  my $market   = shift;
  
  my $midDB = $cnxMgr->getConnectionByName('mid');
  
  my $query = "
    SELECT CURRENCY
    FROM MO_CFG_DIVERS
    WHERE COUNTRY = ? ";

  return $midDB->saarBind($query, [$market])->[0][0];
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@


#####   EGE-103770
sub check_TQN_markup {

	my $tqn_return = shift;
	my $pnr        = shift;
	my $market     = shift;
    my $flag=0;
    my $fare_i=undef;
    my $fare_n=undef;
    my $lwdHasMarkup;


    #check if the RM is available, if not doing the GAP process 
   
	### Same function as getPnrOnlinePricing
	 my $checkToNP = '';
  
    foreach (@{$pnr->{PNRData}}) {
		if ($_->{Data} =~ /^RM \*ONLINE PRICING LINE FOR TAS: (.*)/) {
		  $checkToNP = $1;
		  last;
		}
	}
    #####
  
	my $currency = getCurrency($market);
  
	notice('tqn valeur'.Dumper($tqn_return));
	foreach  (@$tqn_return) {

		
	   if ( ( $_ =~ m/^FX[PBAUT].*(R,U131173|R,U.*VIA|R,U008885|R,U.*EGENCIA)/ )  || ( $_ =~ m/FXA|FXP/ && $checkToNP =~ m/R,U131173|R,U.*VIA|R,U008885|R,U.*EGENCIA/  )   || $flag == 1  )
	   {
			if ($_ =~ m/\s\s[I|U]\s$currency\s*(\d*\.*\d*)/){
					debug('Valeur de FARE I :'.$1);
					$fare_i=$1;
			}


			if ($_ =~ m/N\s$currency\s*(\d*\.*\d*)/){
					debug('Valeur de FARE N :'.$1);
					$fare_n=$1;
			}
			
			$flag=1;
			
	   }
	   
	}
	
   if (defined($fare_i) && defined($fare_n) && ($fare_i > $fare_n)){
            debug ('THIS IS A MARKUP FILE');
            $lwdHasMarkup='true';
	}
	else {
           $lwdHasMarkup='false';
    }
		

   return $lwdHasMarkup;


}

1;
