package Expedia::Modules::LCH::Launcher;
#-----------------------------------------------------------------
# Package Expedia::Modules::LCH::Launcher
#
# $Id: Tracking.pm 410 2008-02-11 09:20:59Z pbressan $
#
# (c) 2002-2008 Expedia.                   www.expediacorporate.fr
#-----------------------------------------------------------------

use Data::Dumper;

use Expedia::Tools::Logger      qw(&debug &notice &warning &error);
use Expedia::Tools::GlobalFuncs qw(&stringGdsPaxName);
use Expedia::Tools::GlobalVars  qw($sendmailProtocol $sendmailIP $sendmailTimeout);
use Expedia::Tools::GlobalVars  qw($cnxMgr);
use Spreadsheet::WriteExcel;
use MIME::Lite;
use POSIX qw(strftime);
use DateTime;

sub run {
  my $self   = shift;
  my $params = shift;

  my $globalParams   = $params->{GlobalParams};
  my $item         = $params->{Item};
  my $server        =$globalParams->{_SERVER};
  
  my $dbh = $cnxMgr->getConnectionByName('mid');
  
  #SELECT P.ID, P.SHORT_DESC, P.COMMAND, L.HEURE_DEB, L.HEURE_FIN, L.RECURENCE, L.DATE_DERNIERE_EXEC
  
  $ID                       =$item->{ID};
  $COMMAND                  =$item->{COMMAND};
  $HEURE_DEB                =$item->{HEURE_DEB};
  $HEURE_FIN                =$item->{HEURE_FIN};
  $RECURENCE                =$item->{REC};
  $DATE_DERNIERE_EXEC       =$item->{DATE_DERNIERE_EXEC};
    
  my @myDateTime = split(/ /, $DATE_DERNIERE_EXEC);
  my @myDate = split(/-/, $myDateTime[0]);
  my @myTime = split(/:/, $myDateTime[1]);
                 
  my $dt = DateTime->new(
     year   => $myDate[0],
     month  => $myDate[1],
     day    => $myDate[2],
     hour   => $myTime[0],
     minute => $myTime[1],
     second => $myTime[2],
     time_zone => 'Europe/Paris',
     );  
      
 my $dt_courante = DateTime->now();
    $dt_courante ->set_time_zone('Europe/Paris');
 
  notice("DATE_COURANTE:".$dt_courante);
        
  if($HEURE_DEB eq '*' && $HEURE_FIN eq '*')
  {
      #ON AJOUTE LE TEMPS DE RECURENCE A LA DATE DE DERNIERE EXECUTION
      $dt->add(minutes => $RECURENCE);
      notice("DATE DDE (".$DATE_DERNIERE_EXEC.") + RECURENCE (".$RECURENCE.") :".$dt); 

      #SI DATE_COURANTE > DATE_DERNIERE_EXECUTION + RECCURENCE
      #ALORS ON CONSIDERE QU'ON DOIT EXECUTER LE PROGRAMME
      #VAUT UNIQUEMENT POUR LES CAS * * (excution 24/24) 
      if(DateTime->compare($dt_courante,$dt) == 1)
      {
        #$COMMAND = "cd ; /home/mid/workflow/workflow.sh --task=synchro &";
        notice("COMMANDE:".$COMMAND);
        #exec($COMMAND);

        &update_status($ID,$dt_courante);
      }
      else
      {
        notice("DATE COURANTE:".$dt_courante." --- DDE + REC:".$dt); 
        notice("PAS ENCORE L'HEURE");
      }
  }
  else
  {
    if($HEURE_DEB <= $dt_courante->hour() && $HEURE_FIN > $dt_courante->hour())
    {
      if($RECURENCE =~ /,/)
      {
         my @minutes = split(",", $RECURENCE);
         notice("Dumper:".Dumper(@minutes));
         notice("MINUTE COURANTE:".$dt_courante->minute);
         foreach $minutes_rec (@minutes)
         {
            notice("minutes_rec:".$minutes_rec);
          if($dt_courante->minute eq $minutes_rec)
          {
             notice("COMMANDE:".$COMMAND);
          } 
         }
      }
      else
      {
        notice("REC:".$RECURENCE);
        #ON AJOUTE LE TEMPS DE RECURENCE A LA DATE DE DERNIERE EXECUTION
      $dt->add(minutes => $RECURENCE);
      notice("DATE DDE (".$DATE_DERNIERE_EXEC.") + RECURENCE (".$RECURENCE.") :".$dt); 

      #SI DATE_COURANTE > DATE_DERNIERE_EXECUTION + RECCURENCE
      #ALORS ON CONSIDERE QU'ON DOIT EXECUTER LE PROGRAMME
      #VAUT UNIQUEMENT POUR LES CAS * * (excution 24/24) 
      if(DateTime->compare($dt_courante,$dt) == 1)
      {
        #$COMMAND = "cd ; /home/mid/workflow/workflow.sh --task=synchro &";
        notice("COMMANDE:".$COMMAND);
        #exec($COMMAND);

        &update_status($ID,$dt_courante);
      }
      else
      {
        notice("DATE COURANTE:".$dt_courante." --- DDE + REC:".$dt); 
        notice("PAS ENCORE L'HEURE");
      }
      
      }      
    }
    else
    {
     notice("EN DEHORS DE LA PLAGE HORAIRE (".$HEURE_DEB." - ".$HEURE_FIN.")");
    }
  }  

  
  foreach $test (@liste_horaire)
  {
   notice("LISTE_H:".$test); 
  }

  return 1;
}

      #for($x=$HEURE_DEB ; $x <= $HEURE_FIN ; $x++)
      #{
      #  if($x == $HEURE_FIN){notice("TRAITEMENT A PARTIR DE LA DATE DE FIN");}
      #  else{
      #    notice("X:".$x);
      #    $dt_tmp=$dt_courante->clone();
      #    $dt_tmp->set( hour => $x);
          #for ($y = 0; $y >= $RECURENCE ; $y+$RECURENCE)
          #{
          #  $dt_tmp=$dt_tmp->clone();
          #  $dt_tmp->set( minute => $RECURENCE);
          #  push @liste_horaire, $dt_tmp;
          #}
       # }
      
      #}
      
sub update_status
{
  my		$ID		=	shift;
  my  	$DDE	=	shift;
   
  my $dbh     = $cnxMgr->getConnectionByName('mid');
  my $query   = "
    UPDATE MO_LAUNCHER
       SET date_derniere_exec   = '$DDE'
     WHERE ID = $ID ";
  
  my $rows    = $dbh->do($query);
}

1;
