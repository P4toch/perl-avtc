package Expedia::Modules::TAS::PreQuality;
#-----------------------------------------------------------------
# Package Expedia::Modules::TAS::PreQuality
#
# $Id: PreQuality.pm 623 2011-03-01 09:23:01Z pbressan $
#
# (c) 2002-2007 Expedia.                   www.expediacorporate.fr
#-----------------------------------------------------------------

use strict;
use Data::Dumper;

use Expedia::Tools::Logger qw(&debug &notice &warning &error);

sub run {
  my $self   = shift;
  my $params = shift;

  my $globalParams = $params->{GlobalParams};
  my $moduleParams = $params->{ModuleParams};
  my $changes      = $params->{Changes};
  my $item         = $params->{Item};
  my $pnr          = $params->{PNR};

	  my $doc		 = $pnr->{_XMLPNR};
	  my $tstdoc = $pnr->{_XMLTST};
	  
	  my $pnr_seg_hash;
	  my @seg_node_list;
	  my @seg_total_node_list;
	  my @node_collection_hash;
	  
    ##########################################################
    # Ajout d'une détection d'un problème relatif à la TST XML  
    # if ($tstdoc->toString() =~ /applicationError/) {
    #   debug('_XMLTST = '.$tstdoc->toString(1));
    #   notice('Problem detected in _XMLTST. Aborting.');
    #   return 0;
  	# }
    ##########################################################
  
    ##########################################################
    # 2.7 de la spec TAS
    if ($tstdoc->toString() =~ /(TST NECESSAIRES|NEED TST|SE REQUIERE UN TST|EXISTE PAS D\'ENREGISTREMENT DE TST|NO TST RECORD EXISTS|NO HAY REGISTRO DE TST)/) {
      # Regardons s'il y a présence de Segments confirmés. HK et pas RU
      # Car la réponse XML n'est pas suffisamment précise.
      my $segmentHKfound   = 0;
      my @originDestinationDetailsNodes = $doc->getElementsByTagName('originDestinationDetails');
      foreach my $oNode (@originDestinationDetailsNodes) {
        my @itinaryInfoNodes = $oNode->getElementsByTagName('itineraryInfo');
        foreach my $iNode (@itinaryInfoNodes) {
  	      next unless ($iNode->find('travelProduct/offpointDetail/cityCode')->to_literal->value());
  	      next unless ($iNode->find('relatedProduct/status')->to_literal->value() eq 'HK');
  	      $segmentHKfound = 1;
  	      last;
        }
      }
      if ($segmentHKfound == 0) {
    	  $pnr->{TAS_ERROR} = 33;
        debug('### TAS MSG TREATMENT 33 ###');
        return 1;
      } else {
        $pnr->{TAS_ERROR} = 3;
        debug('### TAS MSG TREATMENT 3 ###');
        return 1;
      }
    }
    ##########################################################
  
    ##########################################################
    # 2.6 de la spec TAS
  	my $infantIndicator = $doc->find('//travellerInformation/passenger/infantIndicator')->to_literal->value();
  	debug("infantIndicator : $infantIndicator");
  	if ($infantIndicator) {
      $pnr->{TAS_ERROR} = 30;
      debug('### TAS MSG TREATMENT 30 ###');
      return 1;
  	}
  
  	my @pnr_node_list2 = $doc->find('//travellerInformation/passenger/type');
  # my @tst_node_list = $tstdoc->getElementsByTagName('tstFlag');
  	debug('pnr_node_list2 '.Dumper(\@pnr_node_list2));
  	if (scalar(@pnr_node_list2)) {
  		foreach my $node (@pnr_node_list2) {
  	  # my $content = $node->textContent();
  			my $content = $node->to_literal->value();
  			debug("CONTENT $content");
  			if ($content !~ /^(ADT|YTH|YCD)+$/ and $content ne '') {
  			  $pnr->{TAS_ERROR} = 30;
  			  debug('### TAS MSG TREATMENT 30 ###');
  			  return 1;
  			}
  		}
  	}
    ##########################################################
	  
	  ##########################################################
    # 2.2.1 de la SPEC TAS
  	my @tst_node_list = $tstdoc->getElementsByTagName('fareList');
  	my @nodelist      = $doc->getElementsByTagName('travellerInfo');
  
    my @travelersNumbers = ();
    my $jaitrouve = 0;
    foreach my $node (@nodelist) {
      push (@travelersNumbers, $node->find('elementManagementPassenger/reference/number')->to_literal->value());
    }
    debug('travelersNumbers = '.Dumper(\@travelersNumbers));
  
    if (scalar(@travelersNumbers) > 1) {
      debug('scalar nodelist : '.scalar(@nodelist));
  
      foreach my $i (sort triCroissant (@travelersNumbers)) {
        $jaitrouve = 0;
        foreach my $node (@tst_node_list) {
          my @refDetailsNode = $node->findnodes('paxSegReference/refDetails');
          foreach (@refDetailsNode) {
            if ($i eq $_->find('refNumber')->to_literal->value()) {
              $jaitrouve = 1;
            }
          }
        }
        last if ($jaitrouve == 0);
      }
  
      if ($jaitrouve == 0) {
  	    $pnr->{TAS_ERROR} = 23;
  		  debug('### TAS MSG TREATMENT 23 ###');
  		  return 1;
      }
    }
  	##########################################################
  	
  	# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
  	QUALITY_CONTROL: 
    {
    	my @tst_node_list = $tstdoc->getElementsByTagName('fareList');
      debug('TST NODE LIST :'.Dumper(\@tst_node_list));
      
      my @originDestinationDetailsNodes = $doc->getElementsByTagName('originDestinationDetails');
      my @pnr_node_list = ();
      my @tmp_node_list = ();
      foreach my $oNode (@originDestinationDetailsNodes) {
        @tmp_node_list = $oNode->getElementsByTagName('itineraryInfo');
        push @pnr_node_list, $_ foreach (@tmp_node_list);
      }
      debug('PNR NODE LIST :'.Dumper(\@pnr_node_list));
    	
    	foreach my $node_seg (@pnr_node_list) {
        my $node_ref  = $node_seg->find('elementManagementItinerary/reference/number'); 
        my $node_type = $node_seg->find('elementManagementItinerary/segmentName')->to_literal->value();
    		debug("NODE TYPE : $node_type");	
    		next unless ($node_type eq 'AIR');
        my $ref     = $node_ref->to_literal->value();
    		$pnr_seg_hash->{$ref} = {'node'=>$node_seg,'ref'=>$ref};
    	}
      debug("PNR SEG HASH : \n".Dumper($pnr_seg_hash));
      
      # Construction des TST nodes par pax
    	my $pax_number = scalar(@{$pnr->{'PAX'}});
    	debug('PNR PAX = '.Dumper($pnr->{'PAX'}));
    	debug("PAX NUMBER (PNR) = $pax_number");
    	
    	# -------------------------------------------------------------------
    	# PBRESSAN Correction de bug
    	# Les travelers ne sont pas forcément dans l'ordre 1 ... 2 ... 3
    	my @pax_ref_list = ();
    	my @travellerInfoNodes = $doc->getElementsByTagName('travellerInfo');
    	foreach my $tNode (@travellerInfoNodes) {
        my @elementManagementPassengerNodes = $tNode->getElementsByTagName('elementManagementPassenger');
        foreach my $eNode (@elementManagementPassengerNodes) {
          my @referenceNode = $eNode->findnodes('reference');
          foreach my $rNode (@referenceNode) {
            push (@pax_ref_list, $rNode->find('number')->to_literal->value());
          }
        }
      }
      debug('PAX NUMBER (XML) = '.scalar(@pax_ref_list));
      debug('pax_ref_list: '.Dumper(\@pax_ref_list));
      warning('The number of PAXs found (PNR/XML) is not equal !!!')
        if (scalar(@pax_ref_list) != $pax_number); 
      # -------------------------------------------------------------------
    	
    	my $pax_fare_list = {};
    	foreach my $i (sort triCroissant (@pax_ref_list)) {
    	# for (my $i = 1; $i <= $pax_number; $i++) { # ^ Correction de BuG PBRESSAN !
    	  debug("i = $i");
    		foreach my $node (@tst_node_list) {
    
          # -------------------------------------------------------------------
          # PBRESSAN Correction Bug MultiPax / MultiTST
    		  my @refDetailsNode = $node->findnodes('paxSegReference/refDetails');
    		  foreach(@refDetailsNode) {
    			  if ($i eq $_->find('refNumber')->to_literal->value()) {
    				  $pax_fare_list->{$i}->{'pax_ref'} = $i;
    				  debug("On push le node :\n".Dumper($node));
    				  push @{$pax_fare_list->{$i}->{'node_list'}}, $node;
    			  }
    		  }
    			# -------------------------------------------------------------------
    
    		}
    		unless (exists ($pax_fare_list->{$i}->{'pax_ref'})) {
    		  # Si je suis la ca sent le gros Pb...
    			$pax_fare_list->{$i}->{'pax_ref'}   = $i;
    			$pax_fare_list->{$i}->{'node_list'} = [];
    		}
    		debug("le node list du pax :\n".Dumper($pax_fare_list->{$i}->{'node_list'}));
    	}
    
      # Each serial of test must be run on each pax
      debug("pax_fare_list :\n".Dumper($pax_fare_list));
    	foreach my $pax (values %$pax_fare_list) {
    	  
        debug("un pax :\n".Dumper($pax));
        my @node_list = @{$pax->{'node_list'}};
        debug("node_list :\n".Dumper(\@node_list));
        my $do_last = 0;

    		TEST1: if (scalar(@node_list) >= 2) {{
    			foreach my $node (@node_list) {
    				@seg_node_list = ();
    				@seg_node_list = $node->findnodes('segmentInformation');
    				debug(Dumper(\@seg_node_list));
    				# last TEST1 if (scalar(@seg_node_list)>1);
    				# ($do_last =1 ) && last if (scalar(@seg_node_list)>1);
    				if (scalar(@seg_node_list)>1) { $do_last = 1; last; } # PBRESSAN
    				debug('after step do_last 1');
    				push @seg_total_node_list, @seg_node_list;
    			}
    			last if ($do_last);
    			
    			debug('after step do_last 2');
    			foreach my $node_seg (@seg_total_node_list) {
    			  # Attention potentiellement Buggé à cet endroit.
    				my $node_ref = $node_seg->find('segmentReference/refDetails/refNumber');	
    				my $ref      = $node_ref->to_literal->value();
    				push @node_collection_hash,{'seg_node'=>$node_seg,'ref'=>$ref};
    			}
    			
    			foreach my $tst_seg_hash (@node_collection_hash) {
    				my $ref          = $tst_seg_hash->{'ref'};
    				my $pnr_seg_node = $pnr_seg_hash->{$ref}->{'node'};	
    			  my $cie    = $pnr_seg_node->find('travelProduct/companyDetail/identification');
    			  my $deploc = $pnr_seg_node->find('travelProduct/boardpointDetail/cityCode');
    				my $offloc = $pnr_seg_node->find('travelProduct/offpointDetail/cityCode');
    				# RU
    				next unless $offloc;
    				$tst_seg_hash->{'cie'}    = $cie->to_literal->value();
    				$tst_seg_hash->{'deploc'} = $deploc->to_literal->value();
    				$tst_seg_hash->{'offloc'} = $offloc->to_literal->value();
    			}	
    			
    			while (my $tst_seg = pop @node_collection_hash) {
    				last unless scalar(@node_collection_hash);
    				my @iti1 = ($tst_seg->{'deploc'},$tst_seg->{'offloc'});
    				
    				foreach my $tst_seg_hash (@node_collection_hash) {
    					next if ($tst_seg->{'ref'} == $tst_seg_hash->{'ref'});
    					my @iti2 = ($tst_seg_hash->{'deploc'},$tst_seg_hash->{'offloc'});
    					if ($tst_seg->{'cie'} eq $tst_seg_hash->{'cie'}) {
    					  debug('cas  1');
    						debug('iti1 : '.Dumper(\@iti1));
    						debug('iti2 : '.Dumper(\@iti2));
    						
    						unless (join("",@iti1) eq join("",@iti2)) {
                  # or	join("",@iti1) eq join("",reverse @iti2)) {
    				      # debug('### TAS MSG TREATMENT 1 ###');
    							# $pnr->{TAS_ERROR} = 1;
    							# return 1;
       	  	 			# last QUALITY_CONTROL;
    						}					
    					} else {
    						debug('cas  2');
    						debug('iti1 : '.Dumper(\@iti1));
    						debug('iti2 : '.Dumper(\@iti2));
    					 	# unless (join("",@iti1) eq join("",reverse @iti2)) {
    					 	if (join("",@iti1) eq join("",reverse @iti2)) {
    							# OPPOSITES ITINERARIES
                  # debug('### TAS MSG TREATMENT 1 ###');
    							# $pnr->{TAS_ERROR} = 1;
    							# return 1; 
                  # last QUALITY_CONTROL;
    						}	
    					}	
    				}
    			}
    				
    		}} # if (scalar(@node_list) >= 2) 
    
        # TEST2
        debug("tst_node_list :\n".Dumper(\@tst_node_list));
        debug("node_list     :\n".Dumper(\@node_list));
    		
    		# -------------------------------------------------------------------------
    		# 2.2.3 de la Spec TAS
    		foreach my $node (@node_list) {
    
          my $h_result         = {};
          my @segDetails       = ();
          my @segmentReference = ();
          my @segmentInformation = $node->findnodes('segmentInformation');
    
          foreach my $segInfoNode (@segmentInformation) {
    
            @segDetails         = $segInfoNode->findnodes('segDetails');
            @segmentReference   = $segInfoNode->findnodes('segmentReference');
            my $refSegNumber    = $segInfoNode->find('segmentReference/refDetails/refNumber')->to_literal->value();
            my $ticketingStatus = $segInfoNode->find('segDetails/ticketingStatus')->to_literal->value();
            # On saute les segmentInformation Fantômes ;-?
            next if ((!$refSegNumber) || ($refSegNumber =~ /^\s*$/));
            debug('refSegNumber    = '.$refSegNumber);
            debug('ticketingStatus = '.$ticketingStatus);
    
            $h_result->{$refSegNumber}->{ticketingStatus} = $ticketingStatus;
            
            warning("segDetails contient plus d'une node ... Bug possible !")       if (scalar(@segDetails) > 1);
            warning("segmentReference contient plus d'une node ... Bug possible !") if (scalar(@segmentReference) > 1);
          }
    
          foreach my $itineraryInfoNode (@pnr_node_list) {
             my $segmentReference = $itineraryInfoNode->find('elementManagementItinerary/reference/number')->to_literal->value();
             my $status = $itineraryInfoNode->find('relatedProduct/status')->to_literal->value();
             debug('segmentReference = '.$segmentReference);
             debug('status           = '.$status);
    				 foreach (keys %$h_result) {
               if ($_ == $segmentReference) {
                 $h_result->{$_}->{status} = $status;
                 last;
               }
    				 }
          }
    
          debug('h_result = '.Dumper($h_result));
    
          foreach (keys %$h_result) {
            if (($h_result->{$_}->{status} ne 'HK') ||
                ($h_result->{$_}->{ticketingStatus}) ne 'OK') {
              debug('### TAS MSG TREATMENT 2 ###');
              $pnr->{TAS_ERROR} = 2;
              return 1;
            	last QUALITY_CONTROL;
            }
          }
    		} # foreach my $node (@node_list)
    		# ------------------------------------------------------------------------- 
    
        # TEST3
        debug("NODE LIST :\n".Dumper(\@node_list));
    
        my $hash_seg_ref   = {};
        my $hash_segs      = {};
        my $pricedSegments = {};
        
        foreach my $deg (@pnr_node_list) {
    	    # RU
    	    next unless ($deg->find('travelProduct/offpointDetail/cityCode')->to_literal->value());
    	    # NOT HK
    	    next unless ($deg->find('relatedProduct/status')->to_literal->value() eq 'HK');
    	    
    	    my $pair = $deg->find('travelProduct/boardpointDetail/cityCode')->to_literal->value().
    	               $deg->find('travelProduct/offpointDetail/cityCode')->to_literal->value();
    	    
    	    my $segRef = $deg->find('elementManagementItinerary/reference/number')->to_literal->value();
    	    $pricedSegments->{$segRef}->{priced}   = 0;
          $pricedSegments->{$segRef}->{cityPair} = $pair;
    
    	    if (exists $hash_segs->{$pair}) {
    		    $hash_segs->{$pair} += 1;
    	    } else {
    		    $hash_segs->{$pair}  = 1 ;
    	    }
        }
    	
        debug('hash_segs    => '.Dumper($hash_segs));
        debug('pnr_seg_hash => '.Dumper($pnr_seg_hash));

    		PNRSEG: foreach my $pnr_seg (values %$pnr_seg_hash) {
    			my $seg_node = $pnr_seg->{'node'};
    			next unless ($seg_node->find('relatedProduct/status')->to_literal->value() eq 'HK');
    			my $seg_ref = $pnr_seg->{'ref'};
    			debug("SEG REF : $seg_ref");
    			
    			foreach my $node (@node_list) {
    		    my @fare_sref = $node->findnodes('segmentInformation/segmentReference/refDetails');
    			  debug(Dumper(\@fare_sref));	
    				
    				foreach my $n (@fare_sref) {
    					my $ref = $n->find('refNumber')->to_literal->value();
    					debug("REF : $ref");
    					# next PNRSEG if ($fare_seg_ref == $ref);
    					if ($seg_ref == $ref) {
    					  debug("The AIR segment REF = $seg_ref is priced.");
    					  $pricedSegments->{$seg_ref}->{priced} = 1;
    						$hash_seg_ref->{$seg_ref} = $ref;
    						next PNRSEG; 
    					}
    				}
    				if ($pricedSegments->{$seg_ref}->{priced} == 0) {
    				  debug("The AIR segment REF = $seg_ref is NOT priced.");
    				}
    			}
    			
    			###################################################
    			# 2.2.4 de la spec TAS
    			my $pricedSegmentForSameCityPair = 0;
          foreach my $segRef1 (keys %$pricedSegments) {
            if ($pricedSegments->{$segRef1}->{priced} == 0) {
              debug("One NOT priced Segment with HK found for segRef = $segRef1");
              $pricedSegmentForSameCityPair = 0;
              foreach my $segRef2 (keys %$pricedSegments) {
                next if ($segRef1 == $segRef2);
                if (($pricedSegments->{$segRef1}->{cityPair} eq $pricedSegments->{$segRef2}->{cityPair}) &&
                    ($pricedSegments->{$segRef2}->{priced} = 1)) {
                  debug('Another Priced Segment with same cityPair was found');
                  $pricedSegmentForSameCityPair = 1;
                }
              }
              if ($pricedSegmentForSameCityPair == 0) {
                debug('### TAS MSG TREATMENT 3 ###');
                $pnr->{TAS_ERROR} = 3;
                return 1;
            		last QUALITY_CONTROL;
              }
            }
          }
          ###################################################
    
    		} # FIN PNRSEG: foreach my $pnr_seg (values %$pnr_seg_hash)
    
        # TEST4
    		my @city_pairs;
    		foreach my $node (@node_list) {
    			my @segments = $node->findnodes('segmentInformation');
    			debug('SEGMENTS : '.Dumper(\@segments));
    			
    			foreach my $seg (@segments) {
    				# next if ($seg->find('segDetails/ticketingStatus')->to_literal ne 'HK');
    				next if ($seg->find('segDetails/ticketingStatus')->to_literal->value() ne 'OK');
    				push @city_pairs, get_city_pair_4one_seg($pnr_seg_hash, $seg);				
    			}
    		}
    		my $pairs_hash = {};
    		debug('CITY PAIRS :'.Dumper(\@city_pairs));
    		foreach (@city_pairs) { $pairs_hash->{$_}=$_; }
    		debug('CITY PAIRS :'.Dumper(\@city_pairs));
    		debug('CITY_PAIRS HASH '.Dumper($pairs_hash));
    		debug($#city_pairs .' et '.scalar(keys %$pairs_hash));
    		if (scalar(@city_pairs) != scalar(keys %$pairs_hash)) {
          debug('### TAS MSG TREATMENT 6 ###');
          $pnr->{TAS_ERROR} = 6;
          return 1;
          last QUALITY_CONTROL;
    		}
    	
    	} # foreach my $pax (values %$pax_fare_list)
    
    } # Fin : QUALITY_CONTROL
   	# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

  return 1;  
}

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Methodes privées
sub get_city_pair_4one_seg {
	my $pnr_seg_hash = shift;
	my $seg_node 		 = shift;

	my $ref = $seg_node->find('segmentReference/refDetails/refNumber')->to_literal->value();
	my $seg = $pnr_seg_hash->{$ref}->{'node'};
  my $dep = $seg->find('travelProduct/boardpointDetail/cityCode')->to_literal->value();
  my $off = $seg->find('travelProduct/offpointDetail/cityCode')->to_literal->value();

	return $dep.$off;	
}

sub triCroissant { $a <=> $b }
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

1;
