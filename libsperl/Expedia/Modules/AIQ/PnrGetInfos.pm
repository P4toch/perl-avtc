package Expedia::Modules::AIQ::PnrGetInfos;
#-----------------------------------------------------------------
# Package Expedia::Modules::AIQ::PnrGetInfos
#
# $Id: PnrGetInfos.pm 609 2011-01-06 11:33:36Z pbressan $
#
# (c) 2002-2010 Egencia.                            www.egencia.eu
#-----------------------------------------------------------------

use Data::Dumper;

use Expedia::Tools::Logger      qw(&debug &notice &warning &error);
use Expedia::Tools::GlobalFuncs qw(&stringGdsPaxName);
use Expedia::Tools::GlobalVars  qw($sendmailProtocol $sendmailIP $sendmailTimeout);
use Expedia::Tools::GlobalVars  qw($cnxMgr);
use Expedia::WS::Front          qw(&aqh_ticketingdeadline &aqh_unidentified &aqh_serviceconfirmation &aqh_schedulechange &aqh_waitlistfeedback &aqh_flightcancellation &aqh_UnidentifiedAmadeusCarMessage);
use Expedia::Tools::AqhFuncs  qw(&getMailForAqh);
use Expedia::Databases::MidSchemaFuncs qw(&isInMsgKnowledge &insertIntoMsgKnowledge &updateMsgKnowledge);

use Spreadsheet::WriteExcel;
use MIME::Lite;
use POSIX qw(strftime);

#no warnings 'closure'; #POUR SUPPRIMER LES WARNING (Variable "$GDS" will not stay shared at ../libsperl/Expedia/Modules/AIQ/PnrGetInfos.pm line 143)

sub run {
  my $self   = shift;
  my $params = shift;
  
  my $globalParams = $params->{GlobalParams};
  my $moduleParams = $params->{ModuleParams};
  my $changes      = $params->{Changes};
  my $item         = $params->{Item};
  $GDS             = $params->{GDS};
  
    
  #ON RECUPERE L'OFFICE-ID DEFINI DANS LE TASKNAME
  $OID          = substr($params->{TaskName},10);
  
  #DECLARATION DES PARAMETRES
  my ($r, $q, $a, $d, $l) = undef;
  my $valide = 0;
  my $count=0;
  my @lines_sauv = undef;
  $soapOut = undef;   
  my $nb_pnr_in_queue=undef;  #VALEUR POUR LES TESTS
  my $mytime_gen = undef;
  my $flag_qd_crash = 0 ;
  
  #CONNECTION A NAVISION POUR TROUVER LA LISTE DES OFFICES ID A NE PAS PRENDRE EN COMPTE
  my $dbh = $cnxMgr->getConnectionByName('navision');
  $query = "
  SELECT 
  OFFICE_ID AS OFFICE_ID
  FROM AQH_BLACKLIST";
  $blacklist_oid = $dbh->sahr($query, 'OFFICE_ID');   

  $my_queue        =$item->{QUEUE};
  $my_type         =$item->{TYPE};
  $my_wbmi_rules   =$item->{WBMI_RULES};
  $my_pos          =$item->{POS};
  
  my $command             = 'QS/'.$OID.'/'.$my_queue;
  $sauv_QS_line           = 'Q[U|A]/QE/'.$OID.'/'.$my_queue;
  $sauv_QS_line_EUROSTAR  = 'Q[U|A]/Q[E|R]/\w{3}EC.*?\w{4}/'.$my_queue;
  $sauv_QS_line_sans_oid  = 'Q[U|A]/QE'.$my_queue;
  $sauv_QR_line           = 'QR'.$my_queue;
  $sauv_QN_line           = 'QN/'.$my_queue;
  
  debug("command:".$command);
  debug("QS_line:".$sauv_QS_line);
  debug("QR_line:".$sauv_QR_line);
  debug("QN_line:".$sauv_QN_line);
        
  #our use to transfert the variable to the others package
  our $log_id= '';
                                
  #######ATTETION TODO : CAS OU LA MISE EN QUEUE EST AU FORMAT "1C6"
  #SI QUEUE = XXXD1 ALORS ON RECHERCHE XXX
  if($my_queue =~ /D1/) {$sauv_QS_line_D1 = substr($sauv_QS_line,0,length($sauv_QS_line)-2).'$';}else{$sauv_QS_line_D1=$my_queue;}
  if($my_queue eq "0C0") {$sauv_QS_line_OCO = 'Q[U|A]/QE/'.$OID.'/0\s*$';}else{$sauv_QS_line_OCO=$my_queue;}
  if($my_queue eq "1C0D1") {$sauv_QS_line_1C0D1 = 'Q[U|A]/QE/'.$OID.'/1\s*$';}else{$sauv_QS_line_1C0D1=$my_queue;}  
  if($my_queue eq "0C0") {$sauv_QS_line_OCO_2 = 'Q[U|A]/QE/'.$OID.'/0-';}else{$sauv_QS_line_OCO_2=$my_queue;}
  if($my_queue eq "1C0D1") {$sauv_QS_line_1C0D1_2 = 'Q[U|A]/QE/'.$OID.'/1-';}else{$sauv_QS_line_1C0D1_2=$my_queue;}
                
  #RECUPERATION DES PARAMETRES EN CAS DE TEST 
  #SI LES PARAMETRES SONT DEFINIS ALORS ON NE FAIT LE PROGRAMME CLASSIQUE, MAIS UN MODE DEBUG
  #SI PNR PASSE EN LIGNE DE COMMANDE ON NE FAIT LE PROGRAMME QUE POUR UN PNR 

  if(defined($globalParams->{_PNR}))
  {
     if($globalParams->{_PNR} =~/(.*),(.*)/)
     {
       $PNRId=$1;
       $command="RT".$PNRId;
       $lines    = $GDS->command(Command => $command, NoIG => 1, NoMD => 0); 
       notice ("##############################################################################");
       notice ("#       CAS DE TEST SUR UN PNR :".$command." AVEC OID:".$OID."               #");
       notice ("##############################################################################"); 
       #notice("LINES:".Dumper($lines));
	     updateAQHProceed({PNR => $PNRId,MARKET => $my_pos});
       &AQH_Moteur($GDS);
          
       $PNRId=$2;
       $command="RT".$PNRId;
       $lines    = $GDS->command(Command => $command, NoIG => 1, NoMD => 0); 
       notice ("##############################################################################");
       notice ("#       CAS DE TEST SUR UN PNR :".$command." AVEC OID:".$OID."               #");
       notice ("##############################################################################"); 
       #notice("LINES:".Dumper($lines));
	     updateAQHProceed({PNR => $PNRId,MARKET => $my_pos});
       &AQH_Moteur($GDS);
     
     }
     else
     {
       $PNRId=$globalParams->{_PNR};
       $command="RT".$globalParams->{_PNR};
       $lines    = $GDS->command(Command => $command, NoIG => 1, NoMD => 0); 
       notice ("##############################################################################");
       notice ("#       CAS DE TEST SUR UN PNR :".$command." AVEC OID:".$OID."               #");
       notice ("##############################################################################"); 
       #notice("LINES:".Dumper($lines));
	     updateAQHProceed({PNR => $PNRId,MARKET => $my_pos});
       &AQH_Moteur($GDS);
     }
  }
  else
  {
    $lines    = $GDS->command(Command => $command, NoIG => 1, NoMD => 0); 
    notice("LINES:".Dumper($lines));
 
    my $match = 0;
	my $count_opw = 0;
	
	if($lines->[0] =~ /OPW TROUVES/ || $lines->[0] =~ /SORTI DE LA FILE/ || $lines->[0] =~ /OPW FOUND/ || $lines->[0] =~ /OPW EXISTED/ || $lines->[0] =~ /PURGED PNRS/ )
	{
		$match = 1;
	}
    # CAS OU LE RETOUR EST "50 PNR SANS OPC/OPW TROUVES - RECOMMENCER LA SAISIE
    while($match == 1)
	{
        $lines    = $GDS->command(Command => $command, NoIG => 1, NoMD => 0); 
        notice ("opw trouves:".$lines->[0]);
		if($lines->[0] =~ /OPW TROUVES/ || $lines->[0] =~ /SORTI DE LA FILE/ || $lines->[0] =~ /OPW FOUND/ || $lines->[0] =~ /OPW EXISTED/ || $lines->[0] =~ /PURGED PNRS/)
		{
			$match = 1;
		}
		else
		{
			$match = 0;
		}
		$count_opw ++;
		if($count_opw == 50)
		{
			last;
		}
    }

	if($lines->[0] !~ /QUEUE CYCLE COMPLETE/ && $flag_qd_crash == 1 )
	{
		#move to next queue
		$command  = 'QI';
        $lines    = $GDS->command(Command => $command, NoIG => 1, NoMD => 0); 
	}
      
    if($lines->[0] =~ /IGNORE AND RE-ENTER/ || $lines->[0] =~ /IGNORER\/ENTRER DE NOUVEAU/ || $lines->[0] =~ /IGNORE Y VUELVA A INTRODUCIR/ || $lines->[0] =~ /TERMINER OU IGNORER/ || $lines->[0] =~/FINALICE O IGNORE/ || $lines->[0] =~/FINISH OR IGNORE/)
    {
      $GDS->disconnect;
      notice("DECONNECTION");
      $tmp_amadeus='amadeus-'.$OID;
      $GDS      = $cnxMgr->getConnectionByName($tmp_amadeus);
      $GDS->connect;
      notice("CONNECTE A NOUVEAU");
      $lines       = $GDS->command(Command => $command, NoIG => 1, NoMD => 0); 
    }
    
    #COMMANDE POUR DETERMINER SI L'APPEL A LA QUEUE RENVOIE UN DOSSIER OU UN MESSAGE 
    #POUR DIRE QUE LA QUEUE EST VIDE
    #SI C'EST VIDE, ALORS ON SORT DE LA QUEUE, ET ON PASSE A LA SUIVANTE
    while($lines->[0] !~ /VIDE/ && $lines->[0] !~ /QUEUE.*EMPTY/ && $lines->[0] !~ /NOT ASSIGNED/ && $lines->[0] !~ /NON ATTRIBUEE/
    && $lines->[0] !~ /PERIODO EN BLANCO/ && $lines->[0] !~ /COLA VACIA/ )
    {
      $PNRId=undef;
      $mytime_gen= strftime("%Y-%m-%dT00:00:00",localtime());

      # ON CONTROLE LE NOMBRE DE LIGNES EN ERREUR DANS LA TABLE 
      # SI PLUS DE 50 ERREURS ALORS ON SORT
      $arret_prog = &count_error($mytime_gen);
      if($arret_prog > 50)
      {
  	    eval 
    	  {
    	  my $mail_errors='s.dubuc@egencia.fr;c.perdriau@egencia.fr';
        my $msg_error = MIME::Lite->new(
          From     => 'noreply@egencia.eu',
        	To       => $mail_errors,
        	Subject  => 'AQH -- MORE THAN 50 ERRORS -- PROCESS IS NOT RUNNING ANYMORE',
        	Type     => 'TEXT',
      	  Encoding => 'quoted-printable',
      	  Data    => 'Hello,'.
                     "\n\nMulder & Scully :o)\n",  
                  
        );
    	  
        MIME::Lite->send($sendmailProtocol, $sendmailIP, Timeout => $sendmailTimeout);
        $msg_error->send;
    	  };
    	  if ($@) {
            notice('Problem during email send process. '.$@);
        }
        notice("!!!!!!!ATTENTION PLUS DE 50 ERREURS DANS LA TABLE DES ERREURS -- FIN DU PROGRAMME!!!!!!");
        exit 1; 
      }
      my %h_QS=();
          
      #LA QUEUE N'EST PAS VIDE
      #PREMIERE ETAPE TROUVER LE PNR  POUR  RECUPERER LE PERCODE  
      foreach my $line (@$lines) 
      {
              #POUR TROUVER LE NOMBRE DE LIGNE DANS LA QUEUE
              if ($line =~ /.*Q\d.\w\d.*\((\d+)\)/ )
              {
                notice($1." DOSSIERS DANS LA QUEUE ".$my_queue);
                $nb_pnr_in_queue=$1 unless (defined($nb_pnr_in_queue));
              }
              
              #if ($line =~ /^ RP\/(\w+)(\/(\w+))? \s+ (\w+)?\/(\w+)? \s+ (\w+\/\w+) \s+ (\w+) \s* $/x)
              if ($line =~ /^ RP\/(\w+)(\/(\w+)).*\s+(\w+)\s* $/x)
              {
                        ($r, $q, $a) = ($1, $3, $4);
                        $PNRId = $a;
                        $log_id=$PNRId;
                        notice("PNRID:".$PNRId);
                                  notice ("##############################################################################");
                                  notice ("#                        DEBUT DE TRAITEMENT DU PNR:".$PNRId." AVEC OID:".$OID."               #");
                                  notice ("##############################################################################"); 
                        last;
              } 
      }
      
    if(!defined($PNRId) || $PNRId eq '')
    {
        eval 
    	  {
          $my_to   = &getMailForAqh($my_pos,'AQH_ERROR_TO');
    	  #my $mail_errors='s.dubuc@egencia.fr;c.perdriau@egencia.fr;backoffice@egencia.fr';
        my $msg_error = MIME::Lite->new(
          From     => 'noreply@egencia.eu',
          To       => $my_to,
          Subject  => 'Processing error on PNR � Please handle it manually',
          Type     => 'TEXT',
      	  Encoding => 'quoted-printable',
      	  Data    => 'Hello,'.
      	           "\n\nPOS : ".$my_pos.
      	           "\n\nOID: '".$OID."'".
                   "\n\nQueue : ".$my_queue.
                   "\n\nLine : ".$lines->[0],
                  
        );
    	  
        MIME::Lite->send($sendmailProtocol, $sendmailIP, Timeout => $sendmailTimeout);
        $msg_error->send;
    	  };
    	  if ($@) {
            notice('Problem during email send process. '.$@);
        }
        #exit 1; #EGE-82253
    } else {
    	updateAQHProceed({PNR => $PNRId,MARKET => $my_pos}); 
    	&AQH_Moteur($GDS);
    }
    

    notice ("##############################################################################");
    notice ("#                        FIN DE TRAITEMENT DU PNR:".$PNRId."                 #");
    notice ("##############################################################################"); 
    #QN - SUPPRIME -- PROD
	my $command_Q  = 'QN';
    #QD - POUR TEST 
    #my $command_Q  = 'QD';
    
    if(!defined($PNRId) || $PNRId eq '')
    {
       notice("Unable to identify the PNR, move to next message queue (QD)");
       $command_Q  = 'QD';
	   $flag_qd_crash = 1; 
    }
	     
    ###########PROD and TEST #############     
    $lines    = $GDS->command(Command => $command_Q, NoIG => 1, NoMD => 0); 
    notice ("Q:".$lines->[0]);
    ##########EN PROD#############
	
    # CAS OU LE RETOUR EST "50 PNR SANS OPC/OPW TROUVES - RECOMMENCER LA SAISIE
    if($lines->[0] =~ /OPW TROUVES/ || $lines->[0] =~ /SORTI DE LA FILE/ || $lines->[0] =~ /OPW FOUND/ || $lines->[0] =~ /OPW EXISTED/  || $lines->[0] =~ /OFF QUEUE/ || $lines->[0] =~ /FUERA DE LA COLA/)
    {
        my $command  = 'QS/'.$OID.'/'.$my_queue;
        $lines    = $GDS->command(Command => $command, NoIG => 1, NoMD => 0); 
        notice ("QS FOR OPW:".$lines->[0]);
    }

    if($lines->[0] =~ /IGNORE AND RE-ENTER/ || $lines->[0] =~ /IGNORER\/ENTRER DE NOUVEAU/ || $lines->[0] =~ /IGNORE Y VUELVA A INTRODUCIR/ || $lines->[0] =~ /TERMINER OU IGNORER/ || $lines->[0] =~/FINALICE O IGNORE/ || $lines->[0] =~/FINISH OR IGNORE/)
    {
		$command="RFAQH";
		$lines       = $GDS->command(Command => $command, NoIG => 1, NoMD => 0); 

		$command="ER";
		$lines       = $GDS->command(Command => $command, NoIG => 1, NoMD => 0); 
		  
		if($lines->[0] =~/WARNING/ || $lines->[0] =~/AVERTISSEMENT/ || $lines->[0] =~/ATTENT/ )
		{
		  $lines       = $GDS->command(Command => $command, NoIG => 1, NoMD => 0); 
		}

		$lines       = $GDS->command(Command => $command_Q, NoIG => 1, NoMD => 0); 
    }
    	
    ###########POUR TEST#############
    #if($count == $nb_pnr_in_queue)
    #{
    #   notice("FIN:".$count); 
    #   $command  = 'QI';
    #   $lines    = $GDS->command(Command => $command, NoIG => 1, NoMD => 0); 
    #   notice ("QI:".$lines->[0]);
    #   last; 
    #}
    ###########POUR TEST#############
        
    $count++;   
    
    } #FIN WHILE ON EST DANS UNE QUEUE NON VIDE 
  } #FIN ELSE MODE NORMAL 


sub AQH_Moteur
{
		$GDS		=	shift;

	  #LISTE DES VARIABLES A REMETTRE A ZERO
    $handleUM=0;
		$handleTK=0;
		$handleSC=0;
		$handleFC=0;
		$handleWF=0;
		$handleSCF1=0;
		$handleSCF2=0;
		$handleSCF3=0;
    $PERCODE  =undef;
    $code_retour_ws = undef;
    $no_action=0;
    my $tabnumero='';
    
    #ON RECHERCHE LE PERCODE
      $command_RH  = 'RTR/PERCODE';
      $lines_percode    = $GDS->command(Command => $command_RH, NoIG => 1, NoMD => 0); 
      
      foreach $line_percode (@$lines_percode)
      {  
        if($line_percode =~ /(.*)PERCODE\s*(\d*)/ ) 
        {
          $PERCODE.= $2.";";
        } 
      }
      $PERCODE=substr($PERCODE,0,length($PERCODE)-1);
      notice("-----> PERCODE:".$PERCODE." <----- ");
      
    #LECTURE HISTORIQUE
    #TOUT LES CAS DE LECTURE HISTORIQUE SONT EN DEPENDS ON USE CAS, DONC ON PARCOURS L'HISTO 
    #POUR DETERMINER LE TYPE DE WEBSERVICE A APPELLER.
    if($my_type == 1)
    {

      notice("-----> TYPE HISTORIQUE:".$my_type." <----- ");
      #ON AFFICHE L'HISTORIQUE
      $command_RH  = 'RH/ALL';
      $lines    = $GDS->RHALL($command_RH); 
      debug ("##############################################################################");
      debug ("#                 AFFICHAGE DE L'HISTORIQUE ORIGINAL                         #");
      debug ("##############################################################################");        
      debug("HISTO:".Dumper($lines));
            
      my $debut=0;
      my $sauv_numero_ligne='';
      @line_jointe= ();
      %h_QS = ();
      %h_UK = ();
      %h_BL = ();
      %h_eurostar = ();
      @tab_QS = ();
      @WS_TK  = ();
      $nb_tk = 0 ; 
      
      debug("HISTO QS_line:".$sauv_QS_line);
      debug("QR_line:".$sauv_QR_line);
      debug("QN_line:".$sauv_QN_line);
      
      #CONCATENATION DES LIGNES 
      #EX:  001 XXXX
      #         YYYY
      #         ZZZZ
      #     002 AAAA
      #RES: 001 XXXX YYYY ZZZZ
      #     002 AAAA
      foreach my $line (@$lines) 
      { 
				$line =~ s/-RT$// if ($line =~ /-RT$/);
				$numero_ligne=substr($line,4,3);
				
				push @tab_clean, $numero_ligne;
				#PERMET DE NE PAS PRENDRE EN COMPTE LES PREMIERES LIGNES QUI SONT DES CARACTERES
  				if( ( $line =~ /^[0-9]/ ) || ( $line =~ /^\s\s\s/ ) )
  				{
    				if($numero_ligne =~ /^[0-9]/)
    				{
    					  $tabnumero='tab'.$numero_ligne;
    					  $line =~ s/\s+$/ /g;
    						push @$tabnumero, $line;
    						push @line_jointe, $line;
    				}
    				else
    				{;
    						$line_sauv = pop(@$tabnumero);
    						$line_jointe = pop(@line_jointe);
							  $line_sauv =~ s/\s+$/ /g;
    						$line_sauv = $line_sauv.substr($line,8); #SUBSTR POUR VIRER LES ESPACES A LA PLACE DE (001/001) 
    						push @$tabnumero, $line_sauv;
    						push @line_jointe, $line_sauv;
    				}
				  }  #FIN PREMIERE LIGNE A NE PAS PRENDRE EN COMPTE 
      }

=begin	
##### PENSE A AJOUTER UN EXIT A LA FIN DE AQH_RULES  
@line_jointe=(
'    000 ON/LASTNAMETRAVELTHREE/TRAVELTHREE MISS',
'    000 OS/AF1180 V 28OCT 2 CDGLHR LK1 1900 1915/NN *1A/E*',
'    000 OR/SSR FPMLAFNO1/AF1180 V 28OCT CDGLHR/LASTNAMETRAVELTHREE/TRAVELTHREE MISS',
'    000 OR/SSR FQTVAFHK1 AF664321B/AF1180 V 28OCT CDGLHR/LASTNAMETRAVELTHREE/TRAVELTHREE MISS',
'    000 OK/SK TLPW AF CORPORATE',
'    000 OQ/OPW-01AUG:1200/1C7/AF REQUIRES TICKET ON OR BEFORE 02AUG:1200/AF1180 V 28OCT CDGLHR',
'    000 OQ/OPC-02AUG:1200/1C8/AF CANCELLATION DUE TO NO TICKET/AF1180 V 28OCT CDGLHR',
'    000 RF-674249-MCG-EXPEDI/WSECTECW CR-PAREC38DD 20263051 SU 9999WS/RO-9CBAF185 PARW33ECT 00000000 30JUL0902Z',
'    001 QA/QE1C6D4',
'    001 RF-SYSTEM PLACED CR-PAREC38DD 20263051 SU 9999WS 30JUL0903Z',
'    002 RF-1AINV RM AF 300903 CR-1AINV RM AF    0000   30JUL0903Z',
'000/003 XO/OPW-01AUG:1200/1C7/AF REQUIRES TICKET ON OR BEFORE 02AUG:1200/AF1180 V 28OCT CDGLHR',
'000/003 XO/OPC-02AUG:1200/1C8/AF CANCELLATION DUE TO NO TICKET/AF1180 V 28OCT CDGLHR',
'000/003 XF/FV AF',
'    003 AO/OPW-01AUG:1200/1C7/AF REQUIRES TICKET ON OR BEFORE 02AUG:1200/AF1180 V 28OCT CDGLHR',
'    003 AO/OPC-02AUG:1200/1C8/AF CANCELLATION DUE TO NO TICKET/AF1180 V 28OCT CDGLHR',
'    003 AF/FE NONREF / NO CHANGE/AF1180 V 28OCT CDGLHR/LASTNAMETRAVELTHREE/TRAVELTHREE MISS',
'    003 AF/FT *F*/TM0000/AF1180 V 28OCT CDGLHR/LASTNAMETRAVELTHREE/TRAVELTHREE MISS',
'    003 AF/FV *F*AF/AF1180 V 28OCT CDGLHR/LASTNAMETRAVELTHREE/TRAVELTHREE MISS',
'    003 RF-674249-MCG-EXPEDI/WSECTECW CR-PAREC38DD 20263051 SU 9999WS/RO-9CBAF185 PARW33ECT 00000000 30JUL0903Z',
'    004 AR/RM @@ BTC-AIR PROCEED @@',
'    004 AR/RM* METADOSSIER 168456404',
'    004 RF-BTCAIR CR-PAREC38DD 20263051 SU 0001AA/DS-9C431956 30JUL0909Z',
'000/005 XF/FP CCVIXXXXXXXXXXXX1111D1020*CV',
'    005 AF/FP EC/LASTNAMETRAVELTHREE/TRAVELTHREE MISS',
'    005 RF-BTCAIR CR-PAREC38DD 20263051 SU 0001AA/DS-9C431956 30JUL0909Z',
'    006 SA/SSR DOCSAFHK1 P/FRA//FRA/30SEP52/F//LASTNAMETRAVELTHREE/TRAVELTHREE/LASTNAMETRAVELTHREE/TRAVELTHREE MISS',
'    006 RF-BTCAIR CR-PAREC38DD 20263051 SU 0001AA/DS-9C431956 30JUL0909Z',
);
=cut

      notice ("##############################################################################");
      notice ("#                 AFFICHAGE DE L'HISTORIQUE CONCATENE                        #");
      notice ("##############################################################################"); 

			foreach $yop (@line_jointe)
			{
			   notice ($yop);
			   if ( $yop =~ /$sauv_QS_line/ ) {notice ("ADD IN QUEUE0-------->");}
			   if ( $yop =~ /$sauv_QS_line_D1/ && $my_queue =~ /D1/)  {notice ("ADD IN QUEUE1-------->");}
			   if ( $yop =~ /$sauv_QS_line_OCO/ && $my_queue eq "0C0") {notice ("ADD IN QUEUE2-------->");} 
			   if ( $yop =~ /$sauv_QS_line_1C0D1/ && $my_queue eq "1C0D1") {notice ("ADD IN QUEUE3-------->");}
			   if ( $yop =~ /$sauv_QS_line_OCO_2/ && $my_queue eq "0C0") {notice ("ADD IN QUEUE4-------->");}
			   if ( $yop =~ /$sauv_QS_line_1C0D1_2/ && $my_queue eq "1C0D1") {notice ("ADD IN QUEUE5-------->");} 
			   if ( $yop =~ /$sauv_QS_line_sans_oid/ ) {notice ("ADD IN QUEUE6-------->");}
			   #if ( $yop =~ /$sauv_QS_line_1C0/ && ( $my_queue eq "1C0D1" || $my_queue eq "1C0D2" || $my_queue eq "1C0D3" || $my_queue eq "1C0D4"))
			   #   {notice ("ADD IN QUEUE6-------->");}
			   #if ( $yop =~ /$sauv_QS_line_1C1/ && ( $my_queue eq "1C1D1" || $my_queue eq "1C1D2" || $my_queue eq "1C1D3" || $my_queue eq "1C1D4"))
			   #   {notice ("ADD IN QUEUE7-------->");}
			   #if ( $yop =~ /$sauv_QS_line_1C11/ && ( $my_queue eq "1C11D1" || $my_queue eq "1C11D2" || $my_queue eq "1C11D3" || $my_queue eq "1C11D4"))
			   #   {notice ("ADD IN QUEUE8-------->");}			      
         if ($yop =~ /$sauv_QR_line/ || $yop =~ /$sauv_QN_line/ ){notice ("DEL IN QUEUE-------->");}
			}

      debug ("##############################################################################");
      debug ("#                        NETTOYAGE DES LIGNES                                #");
      debug ("##############################################################################");     
      #MOTEUR DE RECUPERATION DES LIGNES A CONSERVER POUR ANALYSE
      #APRES AVOIR TROUVE LA LIGNE QA/QE/PAREC3100/Q1C1D1
      #ON RECUPERE LE NUMERO DE LIGNE CORRESPONDANT 
      #007 QA/QE/PAREC38DD/1C6D1',

      #notice("QUEUE:".$my_queue);
      #notice("sauv_QS_line:".$sauv_QS_line);
      #notice("sauv_QS_line_OCO:".$sauv_QS_line_OCO);
      #notice("sauv_QS_line_D1:".$sauv_QS_line_D1);
      
      my $q=0;
      my $QA_temp=0;
      
			foreach my $line (@line_jointe)
  		{
  			  
  				#PERMET D'AFFECTER LE TABLEAU CORRESPONDANT EN FONCTION DE LA LIGNE OU L'ON SE TROUVE
   				#EXEMPLE: ON EST SUR LA LIGNE 003, alors on va retrouver l'�l�ment dans le tableau : tab003
    		  $numero_ligne=substr($line,4,3); 			
          $numero_precedent=sprintf("%03d",$numero_ligne) -1 ;
          $rf=0;

         #ON INITIALISE LA VALEUR, SI LA STEP N'EST PAS DEFINI ET QUE LA STEP N'EST PAS A 1 ALORS ON METS 0 
         if(!exists($h_UK{$numero_ligne}) )
         {
          $h_UK{$numero_ligne}=0;
         }

         if($line =~ /Q[U|A]\/Q[E|R]/)
         {
            $h_UK{$numero_ligne}=1;
         }

         #SI ON A UNE LIGNE QA/QE
         #ALORS ON CHERCHE LA LIGNE SUIVANTE EST DU TYPE CR-OID
         #ON VERIFIE QUE LA LIGNE NE DOIT PAS ETRE BLACKLISTE
         if($h_UK{$numero_ligne} eq 1 && $line =~ /CR-(\w{9})\s.*/)
         {
           if($1 =~ /\w{3}EC.*?\w{4}/ || $blacklist_oid->{$1})
           {
             $h_UK{$numero_ligne}=0;
           }
         }
         
				##### DEV SPECIAL EUROSTART JIRA 41222 JIRA EGE-35
                ##### If the one step before is a queuing line starting with Qx/Qy where x = U or A and where y = E or R then take into account the one step above this one.
                if ($line =~ /$sauv_QS_line_EUROSTAR/ )
                {
                	notice("EURO: dans premiere boucle");
                    if(!exists($h_eurostar{sprintf("%03d",$numero_ligne)}))
                    {
                        $h_eurostar{sprintf("%03d",$numero_ligne)}=1;
                        notice("EURO: ajout de la ligne comme etant une ligne eurostar:".$numero_ligne);
                    }
               }

		                          
         #notice("MA LIGNE:".$line);
         #ON RECHERCHE LA LIGNE QUI CONTIENT LE NUMERO DE LA QUEUE
         #ON AJOUTE AU TABLEAU FINAL DE RESULTAT, LE NUMERO DU TABLEAU DE LA LIGNE PRECEDENTE
         if ($line =~ /$sauv_QS_line/ || ( $line =~ /$sauv_QS_line_D1/ && $my_queue =~ /D1/) 
         || ( $line =~ /$sauv_QS_line_OCO/ && $my_queue eq "0C0") || ( $line =~ /$sauv_QS_line_1C0D1/ && $my_queue eq "1C0D1")
         || ( $line =~ /$sauv_QS_line_OCO_2/ && $my_queue eq "0C0") || ( $line =~ /$sauv_QS_line_1C0D1_2/ && $my_queue eq "1C0D1")
         ||   $line =~ /$sauv_QS_line_sans_oid/        
         )
         {

			           #ON A TROUVE LA QUEUE, EST-cE QUE LA LIGNE d'AVANT EST UNE MISE EN QUEUE POUR EUROSTAR ?
			           my $num_temp1=sprintf("%03d",$numero_precedent)-1;
			           if(exists($h_eurostar{sprintf("%03d",$num_temp1)})) # deja ligne-1
			           {
			           		 notice("EURO: j'ai trouv� une ligne eurostar juste avant".$numero_precedent);
			           		 notice("EURO: num_temp1:".$num_temp1);
			                 #alors on ajoute la step encore au dessus � traiter
			                 if(!exists($h_QS{sprintf("%03d",$num_temp1)}))
			                 {
			                 	 notice("EURO: derniere boucle, j'ajoute la ligne precedente:".$num_temp1);
                                 $h_QS{sprintf("%03d",$num_temp1)}=1;
                                 notice("AJOUT LIGNE EUROSTART:".$num_temp1);
			                }
			            }

		         		
                if($line =~ /$sauv_QS_line_sans_oid/)
                {
                    #ON EST DANS LE BUG 15632
                    #UNE QUEUE SANS OID
                    #ON TEMPORISE LA VALIDATION DE LA QUEUE, TANT QU'ON A PAS VERIFIER LA LIGNE SUIVANTE CR-OID
                    $QA_temp=1;
                }
                else
                {
                    #SI LA LIGNE N'A PAS ETE AJOUTE, ALORS ON AJOUTE LA STEP PRECEDENTE
                    #ON VERIFIE QUE LA LIGNE N'EST PAS BLACKLISTE & ET QUE CE N'EST PAS UNE LIGNE QA/ (PROBLEME UK) 
                    if($h_UK{sprintf("%03d",$numero_precedent)} eq 1)
                    {
                      $numero_precedent=$numero_precedent-1;
                    }
                    
                    #ON DOIT RECHERCHER SI LA LIGNE PRECEDENTE N'EST PAS BLACKLISTE
                    if(!exists($h_BL{sprintf("%03d",$numero_precedent)}))
                    {
                      if(!exists($h_QS{sprintf("%03d",$numero_precedent)}))
                      {
        							  $h_QS{sprintf("%03d",$numero_precedent)}=1;
        							  notice("AJOUT LIGNE PRECEDENTE:".$numero_precedent);
        							}
                    }
                    else
                    {
                      notice("STEP BLACKLISTE (RF1):".$numero_precedent);
                    }
      							$numero_zap=$numero_ligne;
      							$q=1; #ON A TROUVE UNE LIGNE QA
                }
  			}
  			#ON RECHERCHE LES LIGNES A ELIMINER
        #LES LIGNES QN OU QR .. SI ON TROUVE UNE LIGNE COMME CA, ON SUPPRIME LA LIGNE PRECEDENTE
  			elsif($line =~ /$sauv_QR_line/ || $line =~ /$sauv_QN_line/  ) 
  			{     
 							if($line !~ /007XXX/  )#004 #### BULL
 							{
    							notice("SUPRESSION DE LA QUEUE(QN): ".$line);
    							%h_QS = ();
    							$numero_zap=$numero_ligne;
    							$rf=1; #PERMET DE NE PAS SUPPRIMER DEUX FOIS LA MEME LIGNE 
    							$q=0; #ON A SUPPRIME L'INFORMATION DE LA QUEUE -> NE PLUS RIEN FAIRE  
              }
  							#SI ON TROUVE UNE LIGNE QR OU QN ET QUE LA SIGNATURE EST A SUPPRIMER, ON NE SUPPRIME QU'UNE FOIS
  			}
        elsif( $line =~ /CR-(\w{9})\s.*/   ) # && defined($tab_QA_Avant)
  			#ON VIRE LES LIGNES QUI SONT SIGNE PAR DES OFFICES ID EGENCIA + LISTE AQH_BLACKLIST_OID
  			{			   
  			  #ON REGARDE EN PREMIER SI C'EST UNE LIGNE QUI EST FLAGE QA_TEMP 
  			  if($QA_temp == 1 && $1 eq $OID)
  			  {
  			        ####DOUBLON DU CODE MAIS QUE FAIRE D'AUTRE??? 

                #SI LA LIGNE N'A PAS ETE AJOUTE, ALORS ON AJOUTE LA STEP PRECEDENTE
                #ON VERIFIE QUE LA LIGNE N'EST PAS BLACKLISTE & ET QUE CE N'EST PAS UNE LIGNE QA/ (PROBLEME UK) 
                if($h_UK{sprintf("%03d",$numero_precedent)} eq 1)
                {
                  $numero_precedent=sprintf("%03d",$numero_precedent)-1;
                }
                
                #ON DOIT RECHERCHER SI LA LIGNE PRECEDENTE N'EST PAS BLACKLISTE
                if(!exists($h_BL{sprintf("%03d",$numero_precedent)}))
                {
                  if(!exists($h_QS{sprintf("%03d",$numero_precedent)}))
                  {
    							  $h_QS{sprintf("%03d",$numero_precedent)}=1;
    							  notice("STEP A TRAITER -:".$numero_precedent);
    							}
                }
                else
                {
                  notice("STEP BLACKLISTE (RF2):".sprintf("%03d",$numero_precedent));
                }
  							$numero_zap=$numero_ligne;
  							$q=1; #ON A TROUVE UNE LIGNE QA	
  			  }
  			  else
  			  {  			  
  			         #ON REMET LA VARIABLE A ZERO DANS LE CAS OU ON NE PRENDS CETTE ETAPE COMME REFERENCE   
  			         $QA_temp=0;
  			  }
  			  
  			  if( $q == 1 && $rf == 0 && ($1 =~ /\w{3}EC3.*?\w{3}/ || $blacklist_oid->{$1})) 
  			  {
  			        #### ON EST LE CAS OU LA LIGNE QA A DEJA ETE TROUVES, ON SUPPRIME AUTOMATIQUE LES LIGNES SUIVANTES
  			        notice("STEP BLACKLISTE (RF3):".sprintf("%03d",$numero_ligne));
  			        delete( $h_QS{sprintf("%03d",$numero_ligne)});
  					$numero_zap=$numero_ligne;
					$h_BL{$numero_ligne}=1;
  			  }
  			  elsif($q == 0 && $1 =~ /\w{3}EC3.*?\w{3}/ || $blacklist_oid->{$1}) 
  			  {
  			        #### LA LIGNE QA N'A PAS ENCORE ETE TROUVE, ON FLAG LES STEP DONT LA SIGNATURE EST BLACKLISTE
  			        if(!exists($h_BL{sprintf("%03d",$numero_ligne)}))
                {
  							  $h_BL{$numero_ligne}=1;
  							}
  			  }
  			  else{} #c'est moche !! 
  			}
  			else
  		  {
  							#ON AJOUTE LES LIGNES AU TABLEAU APRES
  							#SEULEMENT SI LE TABLEAU EST DEFINI 
  							#POUR ELIMINER LES PREMIERES LIGNES DE LA QUEUE AVANT QA
  							if($q == 1 && ($numero_zap ne $numero_ligne))
  							{
  							   if(!exists($h_QS{$numero_ligne}))
  							   {
  							     $h_QS{$numero_ligne}=1; 
  							   }
				        }
  			}      
    }

     
     notice ("##############################################################################");
     notice ("#                           LECTURE DU HASH                                  #");
     notice ("##############################################################################");

      #UTILISE POUR GENERER UN WS UNIDENTIFIED DANS LE CAS OU AUCUNE LIGNE AUTRE QUE RF/QA/QU EST TROUVE  
      $find_line=0;
      #UTILISER POUR GENERER UNE LIGNE DE REPORTING DANS LE CAS OU TOUT LES WS SONT EN NO_ACTION
      $nb_ws=0;
           
      #PASSAGE DU HASH DANS UN TABLEAU ET TRI
      foreach $zefzef (keys(%h_QS))    { 
        if(defined($zefzef) && $zefzef ne ''){  #CAS BIZARRE D'UNE LIGNE A VIDE  
          push @tab_QS, sprintf("%03d",$zefzef);   
          #notice("STEP A TRAITER:".$zefzef);
       }
      }
      @tab_QS = sort @tab_QS;
      foreach $tmp (@tab_QS){notice("STEP A TRAITER:".$tmp);}
      
      debug("NOMBRE LIGNE TABLEAU:".scalar(@tab_QS));
      if(scalar(@tab_QS) == 0 || !defined(@tab_QS)) 
      {
        $find_line=1;
        $nb_ws=1;
        $action="handleUnidentifiedAirlineMessage";      
        $nom_ws="handleUnidentifiedAirlineMessage";
        $service='';
        $unidentified=$my_queue;  
        $soapOut = aqh_unidentified('AirlineQueueWS', { percode => $PERCODE, pnr => $PNRId, pos => $my_pos, unidentified => $unidentified} );
        $param_ws = 'unidentifiedmessage|'.$PERCODE."|".$PNRId."|".$my_pos."|".$unidentified."|RULE:NO REGEX RAN. CASE WHEN NO HISTORY LINES SELECTED";
        notice(" WS UNIDENTIFIED (TAB VIDE):".$param_ws);
        notice("RESSSSSSSSSSSSSs:".Dumper($soapOut->{status}));
        $code_retour_ws =$soapOut->{status}->[0];
        $team           =$soapOut->{team};
                      
        if (defined($code_retour_ws)) {notice("RETOUR DU WS:".$code_retour_ws);}
        else{notice("RETOUR DU WS: -1");}
  
        if (!defined($code_retour_ws) || $code_retour_ws lt 0)
        {
            if(!defined($codeservice)){$codeservice='';}
            &add_ws_error($code_retour_ws,$team,$nom_ws,$service,$PNRId,$my_pos,$codeservice,$dt1,$heure,$unidentified,$OID,$param_ws, $ligne_courante);
        }
        
        $ligne_courante='';              
        &add_report();
                      
      }
            
      #ON CHERCHE MAINTENANT DANS LA BIBLIOTHQUE A QUOI CORRESPONDS LE MESSAGE
      foreach $step (@tab_QS)
      {
          $tabnumero='tab'.$step;
          $compteur_ligne_step=0; ###0 PREMIER LIGNE DU TABLEAU
           	
        	foreach $ligne_courante (@$tabnumero)
        	{     
        	     $ligne_pas_encore_trouve = undef;
        	     $chaine_to_return= undef;
        	     #ON EXCLUT LES LIGNES QUI N'ONT PAS DE SENS (PAS UTILE A TRAITER) 
        	     #ET ON DECOUPE EN 4 VARIABLES CELLE QUI RESTE
        	     if( ($ligne_courante !~ /RF-/) && ($ligne_courante !~ /^QA\//) && ($ligne_courante !~ /^QU\//)  && ($ligne_courante =~ /\w{3}\s(.*?)\/(.*?)\s(.{4})(.*)/ ))
        	     {
        	          notice("-------------------------------------------------------------------------------");
        	          $find_line=1;
        	          $PRETYPE=$1;
        	          $TYPE=$2;
        	          $FORLC=$3;
        	          $FREETEXT=$4;
        	          $FREETEXT =~ s/\s+$//g;

        	          notice("($step) P1:".$PRETYPE." P2:".$TYPE." P3:".$FORLC." P4:".$FREETEXT."|");
        	          
        	          #DANS UN CAS HISTORIQUE OU PNR ON VA LIRE DANS UNE TABLE DE PARAMETRES
                    #LA LECTURE EST FAITE AU DEBUT DU PROGRAMME, PUIS MISE EN MEMOIRE
                    $results = request_trois_params();
                    $taille = @$results;

                     #SI TAILLE SUPERIEUR A 0, ALORS ON A TROUVE QUELQUE CHOSE 
                     #ON BOUCLE SUR LA LISTE DE RESULTAT POUR TROUVER LE FREETEXT QUI CORRESPONDS
                     #notice("taille trois param:".$taille);
                     if($taille > 0 )
                     {
                        #ON APPELLE LE MOTEUR POUR CALCULER CE QUI DOIT ETRE FAIT
                        $nb_param=3;
                        &AQH_Rules();
                        #notice("FIN TROIS PARAMS");
                     }#FIN TAILLE > 0 
                    #if(defined($ligne_pas_encore_trouve)){notice("lpet:".$ligne_pas_encore_trouve);}
                   # else{notice("PAS ENCORE TROUVE DE CORRESPONDANCE");}
                    if(!defined($ligne_pas_encore_trouve) )
                    {
                        $results = request_deux_params();
                        $taille = @$results;  
                        #notice("taille deux param:".$taille);  
                        if($taille > 0 )
                        {
                            $nb_param=2;
                            &AQH_Rules();
                            #notice("FIN DEUX PARAMS");
                        }#FIN TAILLE > 0 
                    }
                    # if(defined($ligne_pas_encore_trouve)){notice("lpet:".$ligne_pas_encore_trouve);}
                    # else{notice("PAS ENCORE TROUVE DE CORRESPONDANCE");}
                    if(!defined($ligne_pas_encore_trouve))
                    {
                        $results = request_un_param();
                        $taille = @$results;
                        #notice("taille param:".$taille);
                        if($taille > 0 )
                        {
                           $nb_param=1;
                           &AQH_Rules();
                           #notice("FIN UN PARAMS");
                        }#FIN TAILLE > 0 
                    }
                    
                    #ON A RECHERCHE DANS LES TROIS CAS 
                    #PAS DE CORRESPONDANCE, ON METS LA LIGNE DANS UNIDENTIFIED 
                    if(!defined($ligne_pas_encore_trouve) && $handleUM == 0 )
                    { 
                      $nb_ws=1;
                      notice("AUCUNE CORRESPONDANCE DANS LES TROIS REQUETES");
                      $action="handleUnidentifiedAirlineMessage";
                      $nom_ws="handleUnidentifiedAirlineMessage";
											$handleUM=1;
                      $service='';
                      $dt1='';
                      $unidentified=$my_queue."|".$ligne_courante;  
                      $soapOut = aqh_unidentified('AirlineQueueWS', { percode => $PERCODE, pnr => $PNRId, pos => $my_pos, unidentified => $unidentified} );
                      $param_ws = 'unidentifiedmessage|'.$PERCODE."|".$PNRId."|".$my_pos."|".$unidentified."|RULE:NO MATCHING REGEX RULE ON THE LINE";
                      notice(" WS UNIDENTIFIED (PAS DANS RULES):".$param_ws);

                      $code_retour_ws =$soapOut->{status}->[0];
                      $team           =$soapOut->{team};
                      
                      if (defined($code_retour_ws)) {notice("RETOUR DU WS:".$code_retour_ws);}
                      else{notice("RETOUR DU WS: -1");}
          
                      if (!defined($code_retour_ws) || $code_retour_ws lt 0)
                      {
                        if(!defined($codeservice)){$codeservice='';}
                        &add_ws_error($code_retour_ws,$team,$nom_ws,$service,$PNRId,$my_pos,$codeservice,$dt1,$heure,$unidentified,$OID,$param_ws, $ligne_courante);
                      }
                      
                      $action=$nom_ws;
                      &add_report();
                
                      #last; 
                    } #ON EST A LA FIN DE LA RECHERCHE EN BASE, SI ON A PAS TROUVE LA LIGNE ALORS ON PASSE A LA SUIVANTE
                    #TODO DEFINIR EN UNIDENTIFIED
                           	       
        	     }#FIN IF DECOUPAGE DES VARIABLES, LES LIGNES QUI NE CORRESPONDENT PAS SONT EXCLUT
        	     else
        	     {
        	         $compteur_ligne_step++;
        	         push @tab_non_use, $ligne_courante;
        	         #$action="NOT USE";
        	         #$param_ws="";
        	         #$soapOut="";
                   #&add_report(); 
        	     }
        	  } # FIN BOUCLE foreach $ligne_courante (@$tabnumero)
      } # FIN BOUCLE foreach $step (@tab_QS)
                  
      ########### ENVOI DU WS TICKETING DEADLINE EN DIFFERE POUR GERER LA DATE LA PLUS PROCHE
      ########### UN SEUL WS ENVOYE
      if($nb_tk != 0)
      {
	    my $SAUV_TK = 0;
        notice ("##############################################################################");
        notice ("#                        ENVOI WS TICKETING DEADLINE".$nb_tk."                         #");
        notice ("##############################################################################");
        for ($TK_COMPTEUR=1; $TK_COMPTEUR <= $nb_tk; $TK_COMPTEUR++)
        {
            if($SAUV_TK == 0  && defined($WS_TK[3][$TK_COMPTEUR]) && $WS_TK[3][$TK_COMPTEUR] ne '')
            {
              notice("DATE LA PLUS RECEnte:".$WS_TK[3][$TK_COMPTEUR]);
              $SAUV_TK=$TK_COMPTEUR;
            }
            else
            {
               if(defined($WS_TK[3][$TK_COMPTEUR]) && $WS_TK[3][$TK_COMPTEUR] ne '')
              {
                        $my_annee_1 = substr($WS_TK[3][$SAUV_TK],0,4);
                        $my_mois_1  = substr($WS_TK[3][$SAUV_TK],5,2);
                        $my_jour_1  = substr($WS_TK[3][$SAUV_TK],8,2);

                        $my_annee_2 = substr($WS_TK[3][$TK_COMPTEUR],0,4);
                        $my_mois_2  = substr($WS_TK[3][$TK_COMPTEUR],5,2);
                        $my_jour_2  = substr($WS_TK[3][$TK_COMPTEUR],8,2);

                        $dt1        = DateTime->new(year=> $my_annee_1, month=> $my_mois_1, day=> $my_jour_1);
                        $dt2        = DateTime->new(year=> $my_annee_2, month=> $my_mois_2, day=> $my_jour_2);

                        my $cmp2 = DateTime->compare($dt1, $dt2);
                        if($cmp2 == 1)
                        {
                                notice("DATE LA PLUS RECENTE:".$WS_TK[3][$TK_COMPTEUR]);
                                $SAUV_TK = $TK_COMPTEUR;
                        }
                 }
              }
        }

		if($SAUV_TK == 0) #IF thIS case append, that means we have only ONE TK with an empty date, the loop before will not work
		{
			$SAUV_TK = 1;
		}
        $nb_ws=1;
        $action="handleTicketingDeadline";
        $nom_ws=$action;
        $service='';
        $unidentified='';    
        $PERCODE=$WS_TK[0][$SAUV_TK];
        $PNRId=$WS_TK[1][$SAUV_TK];
        $my_pos=$WS_TK[2][$SAUV_TK];
        $dt1=$WS_TK[3][$SAUV_TK];
        $HEURE=$WS_TK[4][$SAUV_TK];
        $ligne_courante=$WS_TK[5][$SAUV_TK];
              
        notice("WS TICKETING DEADLINE");
        $soapOut = aqh_ticketingdeadline('AirlineQueueWS', { percode => $PERCODE, pnr => $PNRId, pos => $my_pos, date => $dt1, heure => $HEURE});
        $param_ws = 'TicketingDealdline|'.$PERCODE."|".$PNRId."|".$my_pos."|".$dt1."|".$HEURE."|RULE:Pretype = ".$PRETYPE."Type = ".$TYPE."Forlc = ".$FORLC."Airline = ".$AIRLINE."Freetext1 = ".$FREETEXT1;
        notice(" WS TICKETING DEADLINE:".$param_ws);   
                            
        $code_retour_ws   =$soapOut->{status}->[0];
        $code_retour_ws_1 =$soapOut->{status}->[1];
        $code_retour_ws_2 =$soapOut->{status}->[2];
        $team             =$soapOut->{team};

        $code_retour_ws_glob=$code_retour_ws;
              
        if (defined($code_retour_ws)) {
             if (defined($code_retour_ws_1)) {$code_retour_ws_glob.="|".$code_retour_ws_1;}
             if (defined($code_retour_ws_2)) {$code_retour_ws_glob.="|".$code_retour_ws_2;}
        }
        else{$code_retour_ws_glob=-1; $code_retour_ws=-1; notice("RETOUR DU WS: -1");}
      
        #ON CONSIDERE QUE LE CODE RETOUR -2 EST TOUJOURS LE PREMIER CODE ERREUR RETOURNE
        #PAS BESOIN D'ANALYSER LES AUTRES CODE RETOUR
        if (!defined($code_retour_ws) || $code_retour_ws lt 0)
        {
           if(!defined($codeservice)){$codeservice='';}
           &add_ws_error($code_retour_ws,$team,$nom_ws,$service,$PNRId,$my_pos,$codeservice,$dt1,$heure,$unidentified,$OID,$param_ws, $ligne_courante);
        }
        
        if (defined($code_retour_ws_1) && $code_retour_ws_1 lt 0)
        {
           if(!defined($codeservice)){$codeservice='';}
           &add_ws_error($code_retour_ws_1,$team,$nom_ws,$service,$PNRId,$my_pos,$codeservice,$dt1,$heure,$unidentified,$OID,$param_ws, $ligne_courante);
        }
        
        if (defined($code_retour_ws_2) &&  $code_retour_ws_2 lt 0)
        {
           if(!defined($codeservice)){$codeservice='';}
           &add_ws_error($code_retour_ws_2,$team,$nom_ws,$service,$PNRId,$my_pos,$codeservice,$dt1,$heure,$unidentified,$OID,$param_ws, $ligne_courante);
        }
 
        $code_retour_ws=$code_retour_ws_glob;
        notice("RETOUR DU WS:".$code_retour_ws);
        $action=$nom_ws;
        &add_report();      
      } #FIN IF NB_TK != 0
              
      if($find_line == 0)
      {     
            notice("AUCUNE LIGNE A TRAITER AUTRE QUE RF/QU/QA");
            $nb_ws=1;
            $nom_ws="handleUnidentifiedAirlineMessage";
						$handleUM=1;
            $service='';
            $dt1='';
            $unidentified=$my_queue;  
            $soapOut = aqh_unidentified('AirlineQueueWS', { percode => $PERCODE, pnr => $PNRId, pos => $my_pos, unidentified => $unidentified} );
            $param_ws = 'unidentifiedmessage|'.$PERCODE."|".$PNRId."|".$my_pos."|".$unidentified."|RULE:UNIDENTIFIED (RF/QU/QA)";
            notice(" WS UNIDENTIFIED (RF/QU/QA):".$param_ws);
            $code_retour_ws =$soapOut->{status}->[0];
            $team           =$soapOut->{team};
            
            if (defined($code_retour_ws)) {notice("RETOUR DU WS:".$code_retour_ws);}
            else{notice("RETOUR DU WS: -1");}

            if (!defined($code_retour_ws) || $code_retour_ws lt 0)
            {
              if(!defined($codeservice)){$codeservice='';}
              &add_ws_error($code_retour_ws,$team,$nom_ws,$service,$PNRId,$my_pos,$codeservice,$dt1,$heure,$unidentified,$OID,$param_ws, $ligne_courante);
            }
            
            $ligne_courante='';
            $action=$nom_ws;
            &add_report();
      }
      
      #### SI ON A TROUVE DES LIGNES MAIS QU'IL N'Y A PAS EU DE WS, ALORS ON AJOUTE UNE LIGNE AU REPORTING POUR DIRE "NO ACTION"
      if($nb_ws == 0)
      {
        $action="NO ACTION";
        $code_retour_ws="-99"; #CODE RETOUR NO_ACTION MO
        $team="";
        $param_ws="|RULE:LINE FOUND BUT NO WS";
        $ligne_courante="";
        &add_report();
      }
      
      #### VIDAGE DES TABLEAUX DE STOCKAGE##########     
      foreach $step (@tab_clean)
      {
          $tabnumero='tab'.$step;
          @$tabnumero=();
      }
      
           
    }
    #LECTURE PNR
    elsif ($my_type == 2)
    { 
      notice("----> TYPE LECTURE PNR CONTENT:".$my_type);
      
      $code_retour_ctk = &controle_tk();
      
      if($code_retour_ctk !=  3) ####CAS 1 & CAS 2 
      {
        # CAS 1 
        #ON RECHERCHE LA LIGNE OPW POUR TROUVER LA DATE  
        if($code_retour_ctk == 1)
        {
            notice("PAS DE LIGNES FA -- APPEL WS AVEC DATE");
            $command_RH  = 'RTO';
            $lines_rto    = $GDS->command(Command => $command_RH, NoIG => 1, NoMD => 1); 
          
            foreach $line_rto (@$lines_rto)
            {  
              if($line_rto =~ /.*OPC-(\d{2}\w{3}).*CANCELLATION DUE TO NO TICKET/ ) 
              {
                    notice("LIGNE OPW:".$line_rto);
				    eval {
					    &init_date_tk($1,$my_pos,$PNRId,$line_rto); 
						

				    };
				    if ($@){
					    warning('Problem detected during in init_date_tk'.$@);
					    sendErrMail($1,$my_pos,$PNRId,$line_rto);
					}       	     
              } 
            }
            $ligne_courante=$line_rto;
            #$dt1=$dt1.".000Z";
        }
        else
        {
          #CAS 2
          notice("TOUT LES SEGMENTS/PASSAGERS N'ONT PAS ETE TROUVES -- APPEL WS SANS DATE");
          $dt1='';
          $ligne_courante=''; 
        }
        $action="handleTicketingDeadline";
        $nom_ws=$action;
    	  $heure=1;
    	  $service='';
    	  $unidentified='';
    	  $soapOut = aqh_ticketingdeadline('AirlineQueueWS', { percode => $PERCODE, pnr => $PNRId, pos => $my_pos, date => $dt1, heure => $heure});
        $param_ws = 'TicketingDealdline|'.$PERCODE."|".$PNRId."|".$my_pos."|".$dt1."|".$heure."|RULE:QUEUE PLACEMENT RULE FOR LTD";
        notice(" WS TICKETING DEADLINE:".$param_ws); 
     
        $code_retour_ws   =$soapOut->{status}->[0];
        $code_retour_ws_1 =$soapOut->{status}->[1];
        $code_retour_ws_2 =$soapOut->{status}->[2];
        $team             =$soapOut->{team};
        
        $code_retour_ws_glob=$code_retour_ws;
        
        if (defined($code_retour_ws)) {
            
            if (defined($code_retour_ws_1)) {$code_retour_ws_glob.="|".$code_retour_ws_1;}
            if (defined($code_retour_ws_2)) {$code_retour_ws_glob.="|".$code_retour_ws_2;}
        }
        else{$code_retour_ws_glob=-1; $code_retour_ws=-1; notice("RETOUR DU WS: -1");}

        #ON CONSIDERE QUE LE CODE RETOUR -2 EST TOUJOURS LE PREMIER CODE ERREUR RETOURNE
        #PAS BESOIN D'ANALYSER LES AUTRES CODE RETOUR
        if (!defined($code_retour_ws) || $code_retour_ws lt 0)
        {
           if(!defined($codeservice)){$codeservice='';}
           &add_ws_error($code_retour_ws,$team,$nom_ws,$service,$PNRId,$my_pos,$codeservice,$dt1,$heure,$unidentified,$OID,$param_ws, $ligne_courante);
        }
        
        if (defined($code_retour_ws_1) && $code_retour_ws_1 lt 0)
        {
           if(!defined($codeservice)){$codeservice='';}
           &add_ws_error($code_retour_ws_1,$team,$nom_ws,$service,$PNRId,$my_pos,$codeservice,$dt1,$heure,$unidentified,$OID,$param_ws, $ligne_courante);
        }
        
         if (defined($code_retour_ws_2) && $code_retour_ws_2 lt 0)
        {
           if(!defined($codeservice)){$codeservice='';}
           &add_ws_error($code_retour_ws_2,$team,$nom_ws,$service,$PNRId,$my_pos,$codeservice,$dt1,$heure,$unidentified,$OID,$param_ws, $ligne_courante);
        }
        
        $code_retour_ws=$code_retour_ws_glob;
        notice("RETOUR DU WS:".$code_retour_ws);
        &add_report(); 
      }
      else
      {
        # CAS 3 
        notice("Tout les segments trouv�s pour les passagers --> Pas de ticketing deadline"); 
      } 
        
    
      
    }
    else
    {
      #SI ON EST DANS LE CAS 3, ON ENVOIE DIRECTEMENT AU WS
      # 3 = FLIGHT CANCELLATION
      # 4 = WAITLIST
      # 5 = UNIDENTIFIED 
      # 6 = SCHEDULE CHANGE
      # 7 = SPECIAL CHANGE
      if($my_wbmi_rules == 3 ) 
      {
         $nom_ws='handleFlightCancellation';
         $service='';
         $soapOut = aqh_flightcancellation('AirlineQueueWS', {percode => $PERCODE, pnr => $PNRId, pos => $my_pos});
         $param_ws = 'FlightCancellation|'.$PERCODE."|".$PNRId."|".$my_pos."|RULE:QUEUE PLACEMENT RULE";
         notice(" WS FLIGHT CANCELLATION:".$param_ws);
      }
      elsif($my_wbmi_rules == 4 ) 
      {
          $nom_ws='handleWaitListFeedback';
          $service='WaitListFeedBack';        
          $soapOut = aqh_waitlistfeedback('AirlineQueueWS', { percode => $PERCODE, pnr => $PNRId, pos => $my_pos});
          $param_ws = 'WaitListFeedBack|'.$PERCODE."|".$PNRId."|".$my_pos."|RULE:QUEUE PLACEMENT RULE";
          notice(" WS WAITLIST FEEDBACK:".$param_ws);
      }
      elsif($my_wbmi_rules ==  5) 
      {
          $nom_ws='handleUnidentifiedAirlineMessage';
          $service='';
          $unidentified=$my_queue;                 
          $soapOut = aqh_unidentified('AirlineQueueWS', { percode => $PERCODE, pnr => $PNRId, pos => $my_pos, unidentified => $unidentified } );
          $param_ws = 'unidentifiedmessage|'.$PERCODE."|".$PNRId."|".$my_pos."|".$unidentified."|RULE:QUEUE PLACEMENT RULE";
          notice(" WS UNIDENTIFIED(normal):".$param_ws);
      }
      elsif($my_wbmi_rules == 6 )
      {
        $nom_ws='handleScheduleChange';
        $service='';
        $soapOut = aqh_schedulechange('AirlineQueueWS', {percode => $PERCODE, pnr => $PNRId, pos => $my_pos});
        $param_ws = 'ScheduleChange|'.$PERCODE."|".$PNRId."|".$my_pos."|RULE:QUEUE PLACEMENT RULE";
        notice(" WS SCHEDULE CHANGE:".$param_ws);
      }
       elsif($my_wbmi_rules == 7 ) 
      {
        $nom_ws='handleServiceConfirmation';
        $service=$WS_OPTION;
        if($WS_OPTION eq "servicex"){$codeservice=$ligne_courante;}else{$codeservice='';}        
        $soapOut = aqh_serviceconfirmation('AirlineQueueWS', {service => $WS_OPTION, percode => $PERCODE, pnr => $PNRId, codeservice => $codeservice, pos => $my_pos});
        $param_ws = $WS_OPTION.'|'.$PERCODE."|".$PNRId."|".$codeservice."|".$my_pos."|RULE:QUEUE PLACEMENT RULE";
        notice(" WS SERVICE CONFIRMATION:".$param_ws);
      }
      elsif($my_wbmi_rules == 8 ) 
      {
        $nom_ws='handleUnidentifiedAmadeusCarMessage';
        my $carMessage="Unidentified Car Message";      
        $soapOut = aqh_UnidentifiedAmadeusCarMessage('AirlineQueueWS', { percode => $PERCODE, pnr => $PNRId, pos => $my_pos, message => $carMessage});
        $param_ws = $PERCODE."|".$PNRId."|".$my_pos."|".$carMessage."|RULE:QUEUE PLACEMENT RULE";
        notice(" WS UNIDENTIFIED AMADEUS CAR MESSSAGE:".$param_ws);
      }      
      else
      {
       #CAS NORMALEMENT IMPOSSIBLE, SAUF SI ERREUR DANS LA CONFIGURATION EN BASE
       #A METTRE DANS LE REPORTING 
       notice("ATTENTION DANS LE ELSE");
      }
  
      $code_retour_ws =$soapOut->{status}->[0];
      $team           =$soapOut->{team};
      
      ###### REPORTING ###### 
      $action=$nom_ws;
      if(!defined($unidentified)){$unidentified='';}
      if(!defined($codeservice)){$codeservice='';}
      &add_report();
             
      if (defined($code_retour_ws)) {notice("RETOUR DU WS:".$code_retour_ws);}
      else{notice("RETOUR DU WS: -1");}

      if (!defined($code_retour_ws) || $code_retour_ws lt 0)
      {
          if(!defined($codeservice)){$codeservice='';}
          &add_ws_error($code_retour_ws,$team,$nom_ws,$service,$PNRId,$my_pos,$codeservice,$dt1,$heure,$unidentified,$OID,$param_ws, $ligne_courante);
      }
      

    }
    

    notice ("##############################################################################");
    notice ("#                          LIGNE EXCLUSE                                     #");
    notice ("##############################################################################"); 
    foreach $nonuse (@tab_non_use)
    {
      notice("NOT USE".$nonuse);  
    }
    
    @tab_non_use=();
}################ FIN AQH_MOTEUR

sub AQH_Rules
{
      #ON RECHERCHE DANS CETTE FONCTION SI LA LIGNE CORRESPONDS AVEC UNE DONNE EN BDD
      #SI CE N'EST PAS LE CAS ALORS ON SORT ET ON PASSE A LA RECHERCHE SUIVANTE
      #SI TOUT LES CAS ON ETE TESTE SANS SUCCES ALORS ON ENREGISTRE LA LIGNE COMME UNIDENTIFIED
      foreach $tab (@$results)
      {
          $ACTIF              =$tab->[0];
          $PRETYPE            =$tab->[1];
          $TYPE               =$tab->[2]; 
          $FORLC              =$tab->[3];
          $AIRLINE            =$tab->[4];
          $FREETEXT1          =$tab->[5];
          $OFFSET             =$tab->[6];
          $FREETEXT_OFFSET    =$tab->[7];
          $WEBSERVICE         =$tab->[8];
          $WS_OPTION          =$tab->[9];
          $TRIM               =$tab->[10];
          $SEARCH_START       =$tab->[11];
          $SEARCH_LENGHT      =$tab->[12];
          $OPERATOR           =$tab->[13];
          $COMPARE_TO         =$tab->[14];   
          $RESULTAT           =$tab->[15];
          $OFFSET_RES         =$tab->[16];
          $PARAM1_START       =$tab->[17];
          $PARAM1_LENGHT      =$tab->[18];
          $PARAM2_START       =$tab->[19];
          $PARAM2_LENGHT      =$tab->[20];
          $HEURE              =$tab->[21];
          $CONVERSION         =$tab->[22];
          $COMMENT            =$tab->[23];
          
         # notice("!!!".$FREETEXT1."!!!"); 
          ################CONTROLE 1#########################
          #SI LE FREETEXT CORRESPONDS A LA CHAINE EN BASE, ON RECUPERE LES INFORMATIONS 
          #AVANT POURSUIVRE, ON METS FIN A LA BOUCLE 

          if(!defined($FREETEXT1) )
          { $FREETEXT1=''; }
      
           if($FREETEXT =~/$FREETEXT1/ || ( $FREETEXT1 eq '' ) ) #( $FREETEXT1 eq '' && $nb_param < 3) )
           { 
              notice("LIGNE EN BDD TROUVE:".$FREETEXT1);
              #notice("LIGNE EN BDD TROUVE:".$FREETEXT."|");
              $text_res="FREETEXT:'".$FREETEXT1."'";
              #SI OFFSET = -1 ALORS IL FAUT ALLER COMPARER PAR RAPPORT A LA LIGNE APRES OU AVANT  
              if(defined($OFFSET) && $OFFSET ne '')
              {
                                 notice("balla:".$ligne_courante);
                                  notice("LIGNE:".$tabnumero->[1]);
                 if( $OFFSET eq "-1")
                 {
                   $compteur_ligne_step_decale=$compteur_ligne_step-1;
                 }
                 else
                 {
                   $compteur_ligne_step_decale=$compteur_ligne_step+1;
                 }
                  
                 # notice("DANS OFFEST:".$compteur_ligne_step." ".$compteur_ligne_step_decale);
                                   
                 #TODO VERIFIER QUE CA MARCHE DEPUIS QUE J'AI SUPPRIME @$tabnumero 
                 notice("TEST:".$tabnumero->[$compteur_ligne_step_decale]); 
                 notice("LIGNE:".$compteur_ligne_step_decale);               
                 $chaine_offeset=$tabnumero->[$compteur_ligne_step_decale];
                 $chaine_offeset =~ /\w{3}\s(.*?)\/(.*?)\s(\w{4})(.*)/;
                 $FREETEXT_OFFSET_LIGNE=$4;
                 $FREETEXT_OFFSET_LIGNE =~ s/\s+$//g;
                 
                 if($FREETEXT_OFFSET_LIGNE =~ /$FREETEXT_OFFSET/)
                 {
                    $text_res.=" OFFSET ".$OFFSET." OFFSET OK";
                 }
                 else
                 {
                   $text_res.=" OFFSET ".$OFFSET." OFFSET NOK";
                   #LA CHAINE RECHERCHE N'EST PAS LA MEME, ALORS ON SORT ET ON PASSE A LA SUIVANTE
                   $ligne_pas_encore_trouve=1; #TODO A VERIFIER #POUR SORTIR SANS GENERER UN UNIDENTIFIED
                   last;                                     
                 }
                                                    
                
                 #notice("OFFSET OUI"); 
              }
              ################CONTROLE 2#########################
              #SI COMPARE_TO N'EST PAS VIDE, ALORS COMPARER LA RECHERCHE AVEC LE CHAMP
              if(defined($COMPARE_TO) && $COMPARE_TO ne '')
              {
                $chaine_to_compare=substr($FREETEXT,$SEARCH_START,$SEARCH_LENGHT);
                if($OPERATOR eq 'differ')
                {
                  if($COMPARE_TO !~/$chaine_to_compare/)
                  {
                     notice($chaine_to_compare." est diff�rente de :".$COMPARE_TO);
                  }
                  else
                  {
                     notice($chaine_to_compare." n'est pas diff�rente de :".$COMPARE_TO);
                     notice("(NO ACTION) FIN DE TRAITEMENT POUR LA LIGNE");
                     $text_res.=" -- COMPARE TO FAUX";
                     $ligne_pas_encore_trouve=1;
                     last; #LA COMPARAISON FAUSSE, ON SORT DE LA BOUCLE 
                  }
                }
                else
                {
                  if($COMPARE_TO =~/$chaine_to_compare/)
                  {
                     notice($chaine_to_compare."  est dans la chaine:".$COMPARE_TO);                
                  }
                  else
                  {
                     notice($chaine_to_compare." n'est pas dans la chaine:".$COMPARE_TO);
                     notice("(NO ACTION) FIN DE TRAITEMENT POUR LA LIGNE");
                     $text_res.=" -- COMPARE TO FAUX";
                     $ligne_pas_encore_trouve=1;
                     last; #LA COMPARAISON FAUSSE, ON SORT DE LA BOUCLE 
                  }                 
                }

                $text_res.=" -- COMPARE TO OK";
              }
              else{$text_res.=" -- NO COMPARE TO";}
              
              ################CONTROLE 3#########################
              #EST-CE QU'IL Y A UNE ACTION A FAIRE ? 

              if( $RESULTAT eq 'ACTION')
              {
                  $action=$WEBSERVICE;
                  $no_action=0;
                  
                 #BUG15735 

                  if( ($WEBSERVICE eq 'handleFlightCancellation' && $handleFC == 0) ||  ($WEBSERVICE eq 'handleWaitListFeedback' && $handleWF == 0)
                  || ($WEBSERVICE eq 'handleScheduleChange' && $handleSC == 0)
                   || ($WEBSERVICE eq 'handleServiceConfirmation' && $handleSCF1 == 0 && $WS_OPTION eq 'service1'
                  && ( $my_pos ne 'GB' && $my_pos ne 'DE' && $my_pos ne 'BE' && $my_pos ne 'ES' && $my_pos ne 'AU' && $my_pos ne 'SE' && $my_pos ne 'NL' && $my_pos ne 'CH' && $my_pos ne 'IE' && $my_pos ne 'NO' && $my_pos ne 'DK' && $my_pos ne 'FI'))
                  || ($WEBSERVICE eq 'handleServiceConfirmation' && $handleSCF2 == 0  && $WS_OPTION eq 'service2' ) || ($WEBSERVICE eq 'handleServiceConfirmation' && $handleSCF3 == 0  && $WS_OPTION eq 'servicex')
                  || ($WEBSERVICE eq 'handleTicketingDeadline' && $handleTK == 0) || ($WEBSERVICE eq 'handleUnidentifiedAirlineMessage' && $handleUM == 0 ) )
  							  {
                      #EST-CE QU'IL Y A UN PARAMETRE A RETOURNER ? 
                      if(defined($PARAM1_START)) 
                      {
      									######TODO AJOUTER L'OFFSET DE RETOUR
                        $chaine_to_return=substr($FREETEXT,$PARAM1_START,$PARAM1_LENGHT);
                        notice("VARIABLE DE RETOUR:".$chaine_to_return);
                        $text_res.=" -- VALEUR DE RETOUR:".$chaine_to_return;
                        $noparam=0; 
                      }
                      else
                      {
                        $noparam=1; 
                      }
                  
                      #IL Y A QUELQUE CHOSE A FAIRE.... 
                      #METTRE L'ACTION DANS UNE TABLE POUR DEBOUBLONNAGE
                      #push @action_to_do,  
                     
                      # 3 = FLIGHT CANCELLATION
                      # 4 = WAITLIST
                      # 5 = UNIDENTIFIED 
                      # 6 = SCHEDULE CHANGE
                      # 7 = SERVICE CONFIRMATION
                      if($WEBSERVICE eq "handleFlightCancellation" ) 
                      {
                        $nom_ws='handleFlightCancellation';
              	        $service='';
                        $soapOut = aqh_flightcancellation('AirlineQueueWS', { percode => $PERCODE, pnr => $PNRId, pos => $my_pos});
                        $param_ws = 'FlightCancellation|'.$PERCODE."|".$PNRId."|".$my_pos."|RULE:Pretype = ".$PRETYPE."Type = ".$TYPE."Forlc = ".$FORLC."Airline = ".$AIRLINE."Freetext1 = ".$FREETEXT1;
                        notice(" WS FLIGHT CANCELLATION:".$param_ws);
                      }
                      elsif($WEBSERVICE eq "handleWaitListFeedback" )
                      {
                        $nom_ws='handleWaitListFeedback';
              	        $service='';
                        $soapOut = aqh_waitlistfeedback('AirlineQueueWS', {percode => $PERCODE, pnr => $PNRId, pos => $my_pos});
                        $param_ws = 'WaitListFeedBack|'.$PERCODE."|".$PNRId."|".$my_pos."|RULE:Pretype = ".$PRETYPE."Type = ".$TYPE."Forlc = ".$FORLC."Airline = ".$AIRLINE."Freetext1 = ".$FREETEXT1;
                        notice(" WS WAITLIST FEEDBACK:".$param_ws);
                      }
                      elsif($WEBSERVICE eq "handleScheduleChange" )
                      {
                        $nom_ws='handleScheduleChange';
              	        $service='';
                        $soapOut = aqh_schedulechange('AirlineQueueWS', { percode => $PERCODE, pnr => $PNRId, pos => $my_pos});
                        $param_ws = 'ScheduleChange|'.$PERCODE."|".$PNRId."|".$my_pos."|RULE:Pretype = ".$PRETYPE."Type = ".$TYPE."Forlc = ".$FORLC."Airline = ".$AIRLINE."Freetext1 = ".$FREETEXT1;
                        notice(" WS SCHEDULE CHANGE:".$param_ws);
                      }
                      elsif($WEBSERVICE eq "handleServiceConfirmation" )
                      {
                        $nom_ws='handleServiceConfirmation';
              	        $service=$WS_OPTION;
              	        if($WS_OPTION eq "servicex"){$codeservice=$ligne_courante;}else{$codeservice='';}     
                        $soapOut = aqh_serviceconfirmation('AirlineQueueWS', {service => $WS_OPTION, percode => $PERCODE, pnr => $PNRId, codeservice => $codeservice, pos => $my_pos});
                        $param_ws = $WS_OPTION.'|'.$PERCODE."|".$PNRId."|".$codeservice."|".$my_pos."|RULE:Pretype = ".$PRETYPE."Type = ".$TYPE."Forlc = ".$FORLC."Airline = ".$AIRLINE."Freetext1 = ".$FREETEXT1;
                        notice(" WS SERVICE CONFIRMATION:".$param_ws);
                      }
                      elsif($WEBSERVICE eq "handleTicketingDeadline" )
                      {
                        
                        $code_retour_ctk = &controle_tk();
    
                        if($code_retour_ctk !=  3) ####CAS 1 & CAS 2 
                        {
                          # CAS 1 
                          #ON PRENDS LA DATE TROUVE DANS LA QUEUE 
                          if($code_retour_ctk == 1)
                          {
                              notice("PAS DE LIGNES FA -- APPEL WS AVEC DATE");
							  eval {
                                 &init_date_tk($chaine_to_return,$my_pos,$PNRId,$ligne_courante); 
							  };
							   if ($@){
							      warning('Problem detected during in init_date_tk'.$@);
								  sendErrMail($chaine_to_return,$my_pos,$PNRId,$ligne_courante);
							  }
                          }
                          else
                          {
                            #CAS 2
                            notice("TOUT LES SEGMENTS/PASSAGERS N'ONT PAS ETE TROUVES -- APPEL WS SANS DATE");
                            $dt1='';
                            $ligne_courante=''; 
                          }

                      	  if(!defined($HEURE)){$HEURE=0;}
                      	  
                      	  if(defined($dt1)){  
                      	    notice("DT1:".$dt1);  
                      	    notice("WS TICKETING DEADLINE DIFFERE");                  	  
                      	  $nb_tk=$nb_tk+1;
                      	  $WS_TK[0][$nb_tk] = ($PERCODE);
                      	  $WS_TK[1][$nb_tk] = ($PNRId);
                      	  $WS_TK[2][$nb_tk] = ($my_pos);
                      	  $WS_TK[3][$nb_tk] = ($dt1);
                      	  $WS_TK[4][$nb_tk] = ($HEURE);
                      	  $WS_TK[5][$nb_tk] = ($ligne_courante);
                      	  }
                     
                      	  
                      	  ### POUR SHUNTER LE CODE DE RETOUR DES WS ET L'ENREGISTREMENT DU REPORTING
                      	  $no_action=1;
     
                        }
                        else
                        {
                          # CAS 3 
                          $no_action=1;
                          notice("Tout les segments trouv�s pour les passagers --> Pas de ticketing deadline"); 
                        }           
                      }
                      else
                      {
                        $nom_ws='handleUnidentifiedAirlineMessage';
              	        $service='';
              	        $unidentified=$my_queue."|".$ligne_courante;   
                        $soapOut = aqh_unidentified('AirlineQueueWS', {percode => $PERCODE, pnr => $PNRId, pos => $my_pos, unidentified => $unidentified } );
                        $param_ws = 'unidentifiedmessage|'.$PERCODE."|".$PNRId."|".$my_pos."|".$unidentified."|RULE:Pretype = ".$PRETYPE."Type = ".$TYPE."Forlc = ".$FORLC."Airline = ".$AIRLINE."Freetext1 = ".$FREETEXT1;
                        notice(" WS UNIDENTIFIED(normal2):".$param_ws);
                      }
                    }
                    else
                    {
                       $no_action=1; 
                      if($handleSCF1 == 0 && $WS_OPTION eq 'service1')
                      {
                        notice("(NO ACTION) ".$WEBSERVICE." EXCEPTION FOR THIS POS"); #15735
                      }
                      else
                      {
                        notice("(NO ACTION) IL Y A DEJA EU UN WS DU TYPE:".$WEBSERVICE." ".$WS_OPTION);
                        #notice($handleUM."|".$handleTK."|".$handleSC."|".$handleFC."|".$handleWF."|".$handleSCF1."|".$handleSCF2."|".$handleSCF3);
                      }
                    }

                    if($no_action == 0)
                    {
                      $nb_ws=1;
                      notice("RESSSSSSSSSSSSSs:".Dumper($soapOut->{status}));
                      $code_retour_ws =$soapOut->{status}->[0];
                      $team           =$soapOut->{team};
                      
                      if (defined($code_retour_ws)) {notice("RETOUR DU WS:".$code_retour_ws);}
                      else{notice("RETOUR DU WS: -1");}
                
                      if (!defined($code_retour_ws) || $code_retour_ws lt 0)
                      {
                          if(!defined($codeservice)){$codeservice='';}
                          &add_ws_error($code_retour_ws,$team,$nom_ws,$service,$PNRId,$my_pos,$codeservice,$dt1,$heure,$unidentified,$OID,$param_ws, $ligne_courante);
                      }
                      
                      if(!defined($unidentified)){$unidentified='';}
                      $action=$nom_ws;
                      &add_report();
                    }
                    else
                    { 
                      $no_action=0;
                    }
              }
              else
              {
                 notice("(NO ACTION DANS AQH_RULES) ".$text_res);
                 #ON EST DANS LE CAS OU UNE CHAINE DEFINIE NE DOIT RIEN GENERER
                 #ON NE FAIT RIEN #NADA #QUEDALLE #MAIS ON AJOUTE LE FAIT QU'ON A PAS TROUVE LA LIGNE DANS LA BILBIOTHEQUE DANS LE REPORTING
                 #$action="NO_ACTION";
                 #&add_report();
              }
              #BUG15735 
              
								if($WEBSERVICE eq 'handleFlightCancellation' && $handleFC == 0){$handleFC=1;}
								if($WEBSERVICE eq 'handleWaitListFeedback' && $handleWF == 0){$handleWF=1;}
								if($WEBSERVICE eq 'handleScheduleChange' && $handleSC == 0){$handleSC=1;}
								if($WEBSERVICE eq 'handleServiceConfirmation' && $handleSCF1 == 0 && $WS_OPTION eq 'service1' 
								&& ( $my_pos ne 'GB' && $my_pos ne 'DE' && $my_pos ne 'BE' && $my_pos ne 'ES' && $my_pos ne 'AU' && $my_pos ne 'SE' && $my_pos ne 'NL' && $my_pos ne 'CH' && $my_pos ne 'IE'  && $my_pos ne 'NO' && $my_pos ne 'DK' && $my_pos ne 'FI' )){$handleSCF1=1;}
								if($WEBSERVICE eq 'handleServiceConfirmation' && $handleSCF2 == 0 && $WS_OPTION eq 'service2'){$handleSCF2=1;}
								if($WEBSERVICE eq 'handleServiceConfirmation' && $handleSCF3 == 0 && $WS_OPTION eq 'servicex'){$handleSCF3=1;}
								#if($WEBSERVICE eq 'handleTicketingDeadline' && $handleTK == 0){$handleTK=1;}
								if($WEBSERVICE eq 'handleUnidentifiedAirlineMessage' && $handleUM == 0 ){$handleUM=1;}
                 			  					
              $compteur_ligne_step++;
              $ligne_pas_encore_trouve=1;
            last; #SI ON A TROUVE UNE CORRESPONDANCE ON SORT DE LA BOUCLE
           }#FIN IF FREETEXT
      }#FIN FOREACH RESULTS 
}################ FIN AQH_RULES

sub request_trois_params
{
                      my $dbh = $cnxMgr->getConnectionByName('navision');
                      
                     # $PRETYPE_R  ="('".$PRETYPE."')";
                     # $TYPE_R     ="('".$TYPE."')";
                     # $FORLC_R    ="('".$FORLC."')";
                      $PRETYPE_R  ="'%".$PRETYPE."%'";
                      $TYPE_R     ="'%".$TYPE."%'";
                      $FORLC_R    ="'%".$FORLC."%'";
					  
                      if($FORLC =~/\d{4}/)
					  { 
						notice("forlc:".$FORLC);
                        $FORLC_R.=" OR FOURLC='[0-9][0-9][0-9][0-9]'";   
					  }                   
                      #notice("PARAM:".$PRETYPE."|".$TYPE."|".$FORLC);
                      my $query = "
                      SELECT 
                        ACTIF,
                        PRETYPE,
                        TYPE,
                        FOURLC,
                        AIRLINE,
                        FREETEXT1,
                        OFFSET,
                        FREETEXT_OFFSET,
                        WEBSERVICE,
                        WS_OPTION,
                        TRIM,
                        SEARCH_START, --10
                        SEARCH_LENGHT,
                        OPERATOR,
                        COMPARE_TO,   
                        UPPER(RESULTAT),
                        OFFSET_RES,
                        PARAM1_START,
                        PARAM1_LENGHT,
                        PARAM2_START,
                        PARAM2_LENGHT,
                        HEURE,
                        CONVERSION,
                        COMMENT   FROM AQH_RULES 
                        WHERE ACTIF = 1
                        AND PRETYPE like $PRETYPE_R 
                        AND TYPE like  $TYPE_R
                        AND FOURLC like $FORLC_R
                        AND PRETYPE is not null
                        AND TYPE is not null
                        AND FOURLC is not null
                        ORDER BY FREETEXT1 DESC";
                    my $results = $dbh->saar($query);
                    #notice("RES TROIS PARAM:".Dumper($results));
                    return $results;
}

sub request_deux_params
{
                      my $dbh = $cnxMgr->getConnectionByName('navision');
                      my $query = "
                      SELECT 
                        ACTIF,
                        PRETYPE,
                        TYPE,
                        FOURLC,
                        AIRLINE,
                        FREETEXT1,
                        OFFSET,
                        FREETEXT_OFFSET,
                        WEBSERVICE,
                        WS_OPTION,
                        TRIM,
                        SEARCH_START, --10
                        SEARCH_LENGHT,
                        OPERATOR,
                        COMPARE_TO,   
                        UPPER(RESULTAT),
                        OFFSET_RES,
                        PARAM1_START,
                        PARAM1_LENGHT,
                        PARAM2_START,
                        PARAM2_LENGHT,
                        HEURE,
                        CONVERSION,
                        COMMENT   FROM AQH_RULES 
                        WHERE ACTIF = 1
                        AND PRETYPE like $PRETYPE_R 
                        AND TYPE like  $TYPE_R
                        AND PRETYPE is not null
                        AND TYPE is not null
                        AND FOURLC is null
                        ORDER BY FREETEXT1 DESC";
                    #my $results = $dbh->saarBind($query, [ $PRETYPE, $TYPE, $FORLC ] );
                    my $results = $dbh->saar($query);
                    #notice("QUERY 2:".Dumper($query));
                    return $results;
}

sub request_un_param
{
                      my $dbh = $cnxMgr->getConnectionByName('navision');
                      my $query = "
                      SELECT 
                        ACTIF,
                        PRETYPE,
                        TYPE,
                        FOURLC,
                        AIRLINE,
                        FREETEXT1,
                        OFFSET,
                        FREETEXT_OFFSET,
                        WEBSERVICE,
                        WS_OPTION,
                        TRIM,
                        SEARCH_START, --10
                        SEARCH_LENGHT,
                        OPERATOR,
                        COMPARE_TO,   
                        UPPER(RESULTAT),
                        OFFSET_RES,
                        PARAM1_START,
                        PARAM1_LENGHT,
                        PARAM2_START,
                        PARAM2_LENGHT,
                        HEURE,
                        CONVERSION,
                        COMMENT   FROM AQH_RULES 
                        WHERE ACTIF = 1
                        AND PRETYPE like $PRETYPE_R 
                        AND PRETYPE is not null
                        AND TYPE is null
                        AND FOURLC is null 
                        ORDER BY FREETEXT1 DESC";
                    my $results = $dbh->saar($query);
                    # notice("QUERY 1:".Dumper($query));
                    return $results;
}

sub request_blacklist
{
                      my $dbh = $cnxMgr->getConnectionByName('navision');
                      my $query = "
                      SELECT 
                        OFFICE_ID
                      FROM AQH_BLACKLIST";
                    my $results = $dbh->saar($query);
                    return $results;
}


sub add_report
{
  my $dbh = $cnxMgr->getConnectionByName('navision');
  $query="INSERT INTO AQH_REPORT VALUES (?,?,?,?,?,?,?,?,?,getdate())";
  $dbh->doBind($query, [$my_pos, $OID, $my_queue, $PNRId, $action, $code_retour_ws, $team, $param_ws, $ligne_courante ]);  
}

sub add_ws_error
{
  $code_retour_ws = shift;
  $team           = shift;
  $nom_ws         = shift;
  $service        = shift;
  $PNRId          = shift;
  $my_pos         = shift;
  $codeservice    = shift;
  $dt1            = shift;
  $heure          = shift;
  $unidentified   = shift;
  $OID            = shift;
  $param_ws       = shift;
  $ligne_courante = shift;
  
  if(!defined($code_retour_ws)){$code_retour_ws=-1;}
  if ( ($code_retour_ws eq -1) || ($code_retour_ws eq -3) || ($code_retour_ws eq -6) || ($code_retour_ws eq -9)  ||
  ($code_retour_ws eq -5) || ($code_retour_ws eq -21) || ($code_retour_ws eq -23) || ($code_retour_ws eq -13) || ($code_retour_ws eq -2) )
  {
    my $dbh = $cnxMgr->getConnectionByName('navision');
    $query="INSERT INTO AQH_WS_ERROR VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,getdate())";
    $dbh->doBind($query, ['0',$code_retour_ws, $team, $nom_ws, $service , $PERCODE, $PNRId, $my_pos, $codeservice, $dt1, $heure, $unidentified, $OID, $param_ws, $ligne_courante ]);
  }  
}

sub init_date_tk
{
       my $date_param 		= shift;
	   my $country    		= shift;
	   my $PNRId			= shift;
	   my $ligne_courante	= shift;
      
#5	DDMMM
#6	DDMMYY
#7	DDMMMYY
#9	DDMMMYYYY

			 if( (defined($date_param)) && ( ($date_param =~/^\d{2}\D{3}/) || ($date_param =~/^\d{6}/) || ($date_param =~/^\d{2}\D{3}\d{2}/) || ($date_param =~/^\d{2}\D{3}\d{4}/) ))
			 {
			 
			 
       notice("DATE TROUVE:".$date_param);
       $madate2= strftime("%Y-%m-%d", localtime());
       $add_annee=substr($madate2,0,2);
       $annee2=substr($madate2,0,4);
       $mois2=substr($madate2,5,2);
       $jour2=substr($madate2,8,2);
       
    
       if(length($date_param) == 5)
       {
         $jour=substr($date_param,0,2);
         $mois=substr($date_param,2,3);
         my %d2d  = qw (JAN 01 FEB 02 MAR 03 APR 04 MAY 05 JUN 06 JUL 07 AUG 08 SEP 09 OCT 10 NOV 11 DEC 12);
         #BUG 16196 (certaines comapgnies enregistrent les mois en orthographe Allemande donc OKTOBER, DEZEMBER et MAI) 
         #BUG 16417 (bug MARZ en MRZ au lieu de MAR) 
         if($mois eq 'MRZ'){$mois='MAR';}
         if($mois eq 'MAI'){$mois='MAY';}
         if($mois eq 'OKT'){$mois='OCT';}
         if($mois eq 'DEZ'){$mois='DEC';}
         $mois = $d2d{$mois};
         #LE PRINCIPE....AJOUTER L'ANNEE COURANTE  A LA DATE
         #COMPARER AVEC LA DATE COURANTE... SI LA DATETROUVE < DATECOURANTE ALORS ON METS LA DATETROUVE AVEC L'ANNEE SUIVANTE
         $dt1 = DateTime->new( year => $annee2 , month => $mois, day => $jour);
         $dt2 = DateTime->new( year => $annee2 , month => $mois2, day => $jour2);
         notice("DATE TROUVE   :".$dt1);
         notice("DATE COURANTE :".$dt2);
         my $cmp = DateTime->compare($dt1, $dt2);
         debug("DATE TROUVE < DATE_COURANTE ? (-1 < ; 0 == ; 1 > ) --->".$cmp);
         if($cmp lt 0) #SI CMP == -1
         {
           $annee2++;
           $dt1 = DateTime->new( year => $annee2 , month => $mois, day => $jour);
           $dt2->add(days=>350);
           notice("DATE TROUVE   ( +1AN) :".$dt1);
           notice("DATE COURANTE (+350J) :".$dt2);
           my $cmp = DateTime->compare($dt2, $dt1);
           debug("DATE_COURANTE <  DATE TROUVE ? (-1 < ; 0 == ; 1 > ) --->".$cmp);
           if($cmp lt 0) #SI CMP == -1
           {
            $dt1="";
            notice("DATE TROUVE MIS A VIDE");
           }
         } 
       }
       elsif(length($date_param) == 6)
       {
         $jour=substr($date_param,0,2);
         $mois=substr($date_param,2,2);
         $annee=$add_annee.substr($date_param,4,2);
         $dt1 = DateTime->new( year => $annee , month => $mois, day => $jour);
       }
       elsif(length($date_param) == 7)
       {
         $jour=substr($date_param,0,2);
         $mois=substr($date_param,2,3);
         #BUG 16196 (certaines comapgnies enregistrent les mois en orthographe Allemande donc OKTOBER, DEZEMBER et MAI) 
         #BUG 16417 (bug MARZ en MRZ au lieu de MAR) 
         if($mois eq 'MRZ'){$mois='MAR';}
         if($mois eq 'MAI'){$mois='MAY';}
         if($mois eq 'OKT'){$mois='OCT';}
         if($mois eq 'DEZ'){$mois='DEC';}
         $annee=$add_annee.substr($date_param,5,2);
         my %d2d  = qw (JAN 01 FEB 02 MAR 03 APR 04 MAY 05 JUN 06 JUL 07 AUG 08 SEP 09 OCT 10 NOV 11 DEC 12);
         $mois = $d2d{$mois};
         $dt1 = DateTime->new( year => $annee , month => $mois, day => $jour);
       }
       elsif(length($date_param) == 9)
       {
         $jour=substr($date_param,0,2);
         $mois=substr($date_param,2,3);
         #BUG 16196 (certaines comapgnies enregistrent les mois en orthographe Allemande donc OKTOBER, DEZEMBER et MAI)
         #BUG 16417 (bug MARZ en MRZ au lieu de MAR) 
         if($mois eq 'MRZ'){$mois='MAR';} 
         if($mois eq 'MAI'){$mois='MAY';}
         if($mois eq 'OKT'){$mois='OCT';}
         if($mois eq 'DEZ'){$mois='DEC';}
         $annee=substr($date_param,5,4);
         my %d2d  = qw (JAN 01 FEB 02 MAR 03 APR 04 MAY 05 JUN 06 JUL 07 AUG 08 SEP 09 OCT 10 NOV 11 DEC 12);
         $mois = $d2d{$mois};
         $dt1 = DateTime->new( year => $annee , month => $mois, day => $jour);
       }
       else
       {
         notice("ATTENTION PROBLEME DE DATE");
				 $dt1='';
       }
		}
	  else
	  {
	      notice("ATTENTION PROBLEME DE DATE");
				$dt1='';
	  }

    #my $duree Datetime::Duration->new(year=>1);
    
    #my $date_fin = Datetime->now() + $duree;
    #notice("DATE A NE PAS DEPASSER:".$date_fin);
    
   
    if($dt1 eq '')
    {
 	    # _______________________________________________________________________
	    # ENVOI D'UN MAIL DE RAPPORT D'ERREUR
	    # -----------------------------------------------------------------------
  	  # Les adresses mails qui vont �tre utilis�es pour l'envoi des messages 12
  	  if(!defined($date_param)){$date_param='';}
      sendErrMail($date_param,$country,$PNRId,$ligne_courante);  	  
    }
       
}

sub controle_tk
{
    #CONTROLE POUR SAVOIR SI ON APPEL LE WS
    # 1 = ON APPEL AVEC DATE QU'ON TROUVE
    # 2 = ON APPEL SANS DATE
    # 3 = ON APPEL PAS  
    $code_retour_ctk=3;
    @line_jointe_tmp_rtf=();
    debug ("##############################################################################");
    debug ("#                        DEBUT CONTROLE TICKETING DEADLINE                   #");
    debug ("##############################################################################"); 
    $command_RTF  = 'RTF';
    $lines_rtf    = $GDS->command(Command => $command_RTF, NoIG => 1, NoMD => 0); 
    
    notice("RTF:".Dumper($lines_rtf));
    
    foreach my $line_temp_rtf (@$lines_rtf) 
    { 
    	$numero_ligne_tmp_rtf=substr($line_temp_rtf,1,2);
    	push @tab_clean_tk, $numero_ligne_tmp_rtf;
    	#PERMET DE NE PAS PRENDRE EN COMPTE LES PREMIERES LIGNES QUI SONT DES CARACTERES
    		if( ( $line_temp_rtf =~ /^\s/ ) )
    		{
    			if($numero_ligne_tmp_rtf   =~ /^\d+/)
    			{
    				  $tabnumero_tmp_rtf='tab'.$numero_ligne_tmp_rtf;
    				  #$line_temp_rtf =~ s/\s+$/ /g;
    					push @$tabnumero_tmp_rtf, $line_temp_rtf;
    					push @line_jointe_tmp_rtf, $line_temp_rtf;
    			}
    			else
    			{
    					$line_sauv_tmp_rtf = pop(@$tabnumero_tmp_rtf);
    					$line_jointe_tmp_rtf = pop(@line_jointe_tmp_rtf);
    				  #$line_sauv_tmp_rtf =~ s/\s+$/ /g;
    					$line_sauv_tmp_rtf = $line_sauv_tmp_rtf.substr($line_temp_rtf,8); #SUBSTR POUR VIRER LES ESPACES A LA PLACE DE (001/001) 
    					push @$tabnumero_tmp_rtf, $line_sauv_tmp_rtf;
    					push @line_jointe_tmp_rtf, $line_sauv_tmp_rtf;
    			}
    	  }  #FIN PREMIERE LIGNE A NE PAS PRENDRE EN COMPTE 
    }
    
  #	foreach $yop (@line_jointe_tmp_rtf)
	#	{
	#	   notice ($yop);
	#	}
			  
    #####ON RECHERCHE LES LIGNES FHM & FHE      
    foreach $line_rtf (@line_jointe_tmp_rtf)
    {  
      if($line_rtf =~ / FHM/ || $line_rtf =~ / FHE/) 
      {
        notice("IL Y A UNE LIGNE FHM OU FHE");
        $code_retour_ctk=2;
        last;
      }
    }
   
    ######SI LE CODE_RETOUR_CTK != 2 ALORS ON CONTINUE ET ON CHERCHE LES LIGNES FA 
    if($code_retour_ctk != 2)
    {
      
      #######RTF POUR RECUPERER LES LIGNES FA 
      foreach $line_rtf (@line_jointe_tmp_rtf)
      {    
        if($line_rtf =~ /^.+\d{2}.FA.(.*)(\/.*)(\/.*)/ )
        {
          #notice("LIGNE FA: ".$line_rtf);
          $code_retour_ctk=1;
          $var1 = substr($2,1,length($2)-1);
          $var2 = substr($3,1,length($3)-1);
          # FA ...../XXX/S3,4/P1 
          # FA ...../XXX/S3,4/
          # FA ...../XXX/
          
          #INVERSION DES VARIABLES DANS LES CAS OU ON A XXXX/P1/S3,4
          if(($var1 =~/P(\d{1})/) && ($var2 =~/S.*/) ) 
          {
            $var2 = substr($2,1,length($2)-1);
            $var1 = substr($3,1,length($3)-1);
            #notice("CAS INVERSION DES VARIABLES");
          }
          
          #notice("VAR1:".$var1);
          #notice("VAR2:".$var2);
          
          #EST-CE QU'IL Y A PLUSIEURS PASSAGERS
          if($var2 =~/P(\d{1})/)
          {
            #notice("11111111111111:".$1);
            $pax=$1;
            if(!exists($h_FA_PAX{$pax})){$h_FA_PAX{$pax}=$pax.'-';}
            #notice("ADD PAX ".$pax);
            
            #3-6 means 3, 4 , 5 , 6
            #3,4 means 3 and 4
            if($var1 =~/(\d+)([-|,])(\d+)/)
            {
                $var_recup=$h_FA_PAX{$pax};
                if($2 eq "-")
                {
                  $seg=",";
                  for ($x = $1; $x <= $3; $x++)
                  {
                     $seg=$seg.$x.",";
                  }
                  $h_FA_PAX{$pax}=$var_recup.$seg;
                  #notice("h_FA_PAX de ".$pax." = ".$h_FA_PAX{$pax});
                }
                else
                {
                  #notice("ADD SEGMENT ".$1);
                  #notice("ADD SEGMENT ".$3); 
                  $h_FA_PAX{$pax}=$var_recup.$1.",".$3;
                  #notice("h_FA_PAX de ".$1." = ".$h_FA_PAX{$pax});
                } 
            }
             else
            {
              $var_recup=$h_FA_PAX{$pax};
              $h_FA_PAX{$pax}=$var_recup.substr($var2,1,1).",";
              #notice("CAS S TOUT COURT:".$pax." - ".$h_FA_PAX{$pax});
            }
            
          }
          else
          {
            if(!exists($h_FA_PAX{1})){$h_FA_PAX{1}="1-"; }
            #notice("(ONLY ONE ADD PAX )".$var2);
            #3-6 means 3, 4 , 5 , 6
            #3,4 means 3 and 4
            if($var2 =~/(\d+)([-|,])(\d+)/)
            {
                $var_recup=$h_FA_PAX{1};
                if($2 eq "-")
                {
                  #notice("X:".$1." -  ".$3);
                  $seg=",";
                  for ($x = $1; $x <= $3; $x++)
                  {
                    $seg=$seg.$x.",";
                    #notice("DANS BOUCLE SEG:".$seg);
                  }
                  #notice("VARRECUP:".$var_recup);
                  #notice("SEG:".$seg);
                  $h_FA_PAX{1}=$var_recup.$seg;
                 # notice("h_FA_PAX de 1 = ".$h_FA_PAX{1});
                }
                else
                {
                  #notice("ADD SEGMENT ".$1);
                  #notice("ADD SEGMENT ".$3); 
                  $h_FA_PAX{1}=$var_recup.$1.",".$3;
                  #notice("h_FA_PAX de 1 = ".$h_FA_PAX{1});
                } 
            }
            else
            {

              $var_recup=$h_FA_PAX{1};
              $h_FA_PAX{1}=$var_recup.substr($var2,1,1).",";
              #notice("CAS S TOUT COURT:1- ".$h_FA_PAX{1});
            }
            
          }
        }
      }   
      
      ##### CODE_RETOUR_CTK = 1 , ALORS ON CONTINU LE PROGRAMME 
      if($code_retour_ctk == 1)
      {
        #### ON FAIT LE RTN
        $command_RTN  = 'RTN';
        $lines_rtn    = $GDS->command(Command => $command_RTN, NoIG => 1, NoMD => 0); 
        
        notice("LIGNES RTN:".Dumper($lines_rtn));
                  
        foreach $lines_rtn (@$lines_rtn)
        {  
          if($lines_rtn =~ /.*(\d{1}).*/ ) 
          {
            $nb_passager=$1;
          }
        }
        notice("NOMBRE DE PASSAGER =".$nb_passager);
        
        #SI ON TROUVE TOUT LES PASSAGERS, ALORS ON PASSE A L'ETAPE SUIVANTE
        #SINON ON SORT AVEC CODE_RETOUR_CTK=2
        for ($y=1 ; $y <= $nb_passager; $y ++)
        {
          if(exists($h_FA_PAX{$y}))
          {
            $code_retour_ctk=3;
            notice("PASSAGER: ".$y." TROUVE DANS RTF");
          } 
          else
          {
            $code_retour_ctk=2;
            notice("PASSAGER: ".$y." INCONNU DANS RTF");  
            last; 
          }
        }
        
        if($code_retour_ctk == 3)
        {
          #### ON FAIT LE RTA
          $command_RTA  = 'RTA';
          $lines_rta    = $GDS->command(Command => $command_RTA, NoIG => 1, NoMD => 0); 
          notice("LIGNES RTA:".Dumper($lines_rta));
          
          foreach $lines_rta (@$lines_rta)
          {  
            if($lines_rta =~ /\s{1,}(\d{1,})\s{1,}\w{2}.*/ && $code_retour_ctk != 2) 
            {
              $segment=$1;
              for ($x=1 ; $x <= $nb_passager; $x ++)
              {
                notice("Est-ce que h_FA_PAX du passager ".$x."(".$h_FA_PAX{$x}.") contient le segment :".$segment);
                if($h_FA_PAX{$x} =~ /$segment,/)
                {
                  notice("SEGMENT: ".$segment." TROUVE DANS RTF POUR LE PASSAGER ".$x);
                }
                else
                {
                  notice("SEGMENT: ".$segment." PAS TROUVE DANS RTF POUR LE PASSAGER ".$x);
                  $code_retour_ctk=2;
                  last;
                }
              }
            }
          }
        }
      }
      ##### CODE_RETOUR_CTK != 1 ALORS ON N'A P�S TROUVE DE LIGNE FA, ON SORT ET ON ENVOYE LE WS AVEC DATE
      else
      {
        $code_retour_ctk=1;
        notice("PAS DE LIGNE FA");
      }
    }
    
    debug ("##############################################################################");
    debug ("#                        FIN CONTROLE TICKETING DEADLINE                     #");
    debug ("##############################################################################"); 
    
    #VIDER LES TABLES POUR LE PNR SUIVANT
    if(defined($nb_passager))
    {
    for ($z=1; $z <= $nb_passager; $z++)
    {
      $h_FA_PAX{$z}='';
    }
    }
    
    #### VIDAGE DES TABLEAUX DE STOCKAGE##########     
#    foreach $cleaner (@tab_clean_tk)
#    {
#        $tabnumero_clean='tab_clean'.$cleaner;
#        @$tabnumero_clean=();
#     }     
            
    return  $code_retour_ctk;

}

sub count_error
{
  my $mytime_gen= shift;
  my $dbh = $cnxMgr->getConnectionByName('navision');
  $request="SELECT count(*) FROM AQH_WS_ERROR WHERE TRY <= 3";
  $results = $dbh->saar($request);
  
  return $dbh->saar($request)->[0][0];
}

sub sendErrMail 
{      
  eval {
       my $date_param 		= shift;
	   my $country    		= shift;
	   my $PNRId			= shift;
	   my $ligne_courante	= shift;
       my $mail_errors='s.dubuc@egencia.fr;c.perdriau@egencia.fr;a.dossantos@egencia.fr';
        my $msg_error = MIME::Lite->new(
        From     => 'noreply@egencia.eu', 
      	To       => $mail_errors,
      	Subject  => 'Airline queue format error on TicketingDeadline Date',
      	Type     => 'TEXT',
    	  Encoding => 'quoted-printable',
    	  Data    => 'Hello,'.
                   "\n\nDate format error on ".$PNRId.
                   "\n\nValue : ".$date_param.
				   "\n\nCountry: ".$country.
                   "\n\nLine : ".$ligne_courante,  
                
      );
  	  
      MIME::Lite->send($sendmailProtocol, $sendmailIP, Timeout => $sendmailTimeout);
      $msg_error->send;
};
if ($@) {
   notice('Problem during email send process. '.$@);
}
}

return 1;
}

#@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Update AQH_PROCEED or insert record in MSG_KNOWLEDGE for all bookings treated by AQH
#@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
sub updateAQHProceed {
    my $params  = shift;
    my $pnr     = $params->{PNR}  || undef;
    my $market  = $params->{MARKET}  || undef;
    my $type    =  'AIR';

    my $aqh_stat = 1;

    if (!defined $pnr && !defined $market) {
        error('Missing or wrong parameter for this method.');
        return undef;
    }
    my $midDB = $cnxMgr->getConnectionByName('mid');
    my $mkItem = &isInMsgKnowledge({ PNR => $pnr });
    
    
    if ((!defined $mkItem) || (scalar(@$mkItem) == 0)) {
      &insertIntoMsgKnowledge({ PNR => $pnr, TYPE => $type, MARKET => $market, AQHProceed => $aqh_stat });
    }
    
    if(scalar(@$mkItem) == 1) {
      my $row = &updateMsgKnowledge({PNR => $pnr, TYPE => $type, MARKET => $market, AQHProceed => $aqh_stat });
    } 
    
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

1;
