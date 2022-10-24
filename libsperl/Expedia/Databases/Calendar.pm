package Expedia::Databases::Calendar;
# ----------------------------------------------------------------
# package Expedia::DB::Calendar
#
# $Id: Calendar.pm 712 2011-07-04 15:43:55Z pbressan $
#
# (c) 2002-2008 Expedia.                   www.expediacorporate.fr
# ----------------------------------------------------------------

use Exporter 'import';

@EXPORT_OK = qw(&getCalId &getMonthCalId &getCalIdwithtz);

use strict;
use Data::Dumper;
use POSIX qw(strftime);

use Expedia::Tools::Logger qw(&debug &notice &warning &error);
use Expedia::Tools::GlobalVars qw($cnxMgr);

    # EXTRAIRE LA WEEKNUM DEPUIS ORACLE
    #   SELECT TO_CHAR(TO_DATE('12/05/2007', 'DD/MM/YYYY'), 'WW') FROM DUAL;
    #   SELECT TO_CHAR(TO_DATE('12/05/2007', 'DD/MM/YYYY'), 'IW') FROM DUAL;

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# ~ Récupération d'un identifiant de calendrier. Si aucun paramètre
#   n'est fourni, c'est le calId de la date du jour qui est renvoyé.
# ~ Si le calId n'est pas trouvé les données de l'année manquante
#   sont insérées.
sub getCalId {
  my $date = shift;
     $date = strftime("%d/%m/%Y", localtime())
       if ((!defined $date) || ($date !~ /\d{2}\/\d{2}\/\d{4}/));
  debug('date = '.$date);
  
  my $dbh   = $cnxMgr->getConnectionByName('mid');
  my $query = "SELECT ID FROM CALENDAR WHERE CONVERT(CHAR(10),DAY,103) = CONVERT(CHAR(10),?, 103)";
  my $calId = undef;
  
  RETRY: {{
    $calId = $dbh->saarBind($query, [$date])->[0][0];
    debug('calId = '.$calId) if (defined $calId);
    
    if (!defined $calId) {
      my $year = $1 if ($date =~ /\d{2}\/\d{2}\/(\d{4})/);
      return 0 if (($year < 2007) || ($year > 2049));
      debug("INSERTION DES DONNÉES DE CALENDAR - YEAR = $year");
      _initYear($year);
      goto RETRY;
    }
  }};
  
  return $calId;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# ~ Récupération d'un identifiant de calendrier. Si aucun paramètre
#   n'est fourni, c'est le calId de la date du jour qui est renvoyé.
# ~ Si le calId n'est pas trouvé les données de l'année manquante
#   sont insérées.
sub getCalIdwithtz {
  my $zone =  shift;

  my $mytime= strftime("%d/%m/%Y %H:%M:%S",localtime());
  my @myDateTime = split(/ /, $mytime);
  my @myDate = split(/\//, $myDateTime[0]);
  my @myTime = split(/:/, $myDateTime[1]);
            
  my $dt = DateTime->new(
     year   => $myDate[2],
     month   => $myDate[1],
     day    => $myDate[0],
     hour   => $myTime[0],
     minute => $myTime[1],
     time_zone => 'Europe/Paris',
     );  

     $dt ->set_time_zone($zone);
     
  my $date = sprintf("%02d",$dt->day()).'/'.sprintf("%02d",$dt->month()).'/'.$dt->year();
  
  my $dbh   = $cnxMgr->getConnectionByName('mid');
  my $query = "SELECT ID FROM CALENDAR WHERE CONVERT(CHAR(10),DAY,103) = CONVERT(CHAR(10),?, 103)";
  my $calId = undef;
  
  RETRY: {{
    $calId = $dbh->saarBind($query, [$date])->[0][0];
    debug('calId = '.$calId) if (defined $calId);
    
    if (!defined $calId) {
      my $year = $1 if ($date =~ /\d{2}\/\d{2}\/(\d{4})/);
      return 0 if (($year < 2007) || ($year > 2049));
      debug("INSERTION DES DONNÉES DE CALENDAR - YEAR = $year");
      _initYear($year);
      goto RETRY;
    }
  }};
  
  return $calId;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# ~ Récupération des identifiants de calendrier pour un mois
sub getMonthCalId {
  my $month =  shift;
  my $year  =  shift;
  
  my $dbh   =  $cnxMgr->getConnectionByName('mid');
  my $query = "
    SELECT ID, CONVERT(CHAR(10),DAY,103) + '/' + datename(dw, day) 
      FROM CALENDAR
     WHERE MONTH(DAY) = ?
       AND YEAR(DAY) = ?
  ORDER BY ID ASC ";
  
  return $dbh->saarBind($query, [$month, $year]);
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Fonction servant à initialiser une année dans le table
#  CALENDAR si elle n'est pas disponible.
sub _initYear {
  my $year  = shift;

#  my @week  = (
#    'Monday'   ,
#    'Tuesday'  ,
#    'Wednesday',
#    'Thursday' ,
#    'Friday'   ,
#    'Saturday' ,
#    'Sunday'  );
#  
#  my @month = (
#    'January'  ,
#    'February' ,
#    'March'    ,
#    'April'    ,
#    'May'      ,
#    'June'     ,
#    'July'     ,
#    'August'   ,
#    'September',
#    'October'  ,
#    'November' ,
#    'December' );
  
  my $dbh   = $cnxMgr->getConnectionByName('mid');
  my $query = "INSERT INTO CALENDAR (DAY) VALUES (CONVERT(datetime,?,103))";

  # ________________________________________________________________
  my $i = my $j = my $k = my $l = 0;
  my $tmp; my $inc; my $day; my $week; my $date; my $calId;
                
  for ($i = 1; $i <= 12; $i++) {
    
    my $cal = `cal $i $year`;
    my @cal = split /\n/, $cal;
    my $mon = sprintf("%02d", $i);
    
    foreach (@cal) {

      if ($j > 1 && $j < 8) {
        $inc = 0;
        $l = 0;
        for ($k = 0; $k < 7; $k++) {
          if (length($_) >= ($inc + 2)) {
            $tmp = substr($_, $inc, 2);
            $inc += 3;
            if    ($tmp =~ (/^\s{2}$/))     { }
            elsif ($tmp =~ (/^\s(\d{1})$/) || $tmp =~ (/^(\d{2})$/))   {
              $day  = sprintf("%02d", $1);
              $date = "$day/$mon/$year";
              debug("Insertion de la DATE = $date dans la table CALENDAR");
              #$calId = _getCalendarSeqNextVal();
              $dbh->doBind($query, [$date]);
            }
            $l++;
          } # Fin if (length($_) >= ($inc + 2))
        } # Fin for ($k = 0; $k < 7; $k++)
      } # Fin if ($j > 1 && $j < 8)
      
      $j++;
    } # Fin foreach (@cal)
    
    $j = 0;
  } # Fin for ($i = 1; $i <= 12; $i++)
  # ________________________________________________________________
  
  return 1;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

1;
