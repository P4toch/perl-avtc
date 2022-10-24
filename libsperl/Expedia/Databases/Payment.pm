package Expedia::Databases::Payment;
#-----------------------------------------------------------------
# Package Expedia::Databases::Payment
#
# $Id: Payment.pm 410 2008-02-11 09:20:59Z pbressan $
#
# (c) 2002-2007 Expedia.                   www.expediacorporate.fr
#-----------------------------------------------------------------

use Data::Dumper;
use Exporter 'import';

use Expedia::Tools::Logger qw(&debug &notice &warning &error);
use Expedia::Tools::GlobalVars qw($cnxMgr);

@EXPORT_OK = qw(&getCreditCardData);

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Appel à la procédure stockée de récupération des numéros de carte de crédit.
sub getCreditCardData {
  my $CcCode = shift;
  
  if ((!defined $CcCode) || ($CcCode !~ /\d+/)) {
    notice('Wrong parameter used for this method.');
    return undef;
  }
  
  my $midDB = $cnxMgr->getConnectionByName('mid')->handler;
    
  my ($result, $csr);

  eval {
	  $csr = $midDB->prepare("
      BEGIN
        enig_pkg_credit_card.get_credit_card_data (
          '$CcCode',
          :code,
          :card_number,
          :start_date,
          :expiry_date,
          :card_type,
          :cvv2,
          :holder_name,
          :service,
          :werr,
          :wmes
        );
      END; ");
    };
		if ($@) { warning('Erreur Oracle prepare: '.$@); }
		
		my ($code, $cardNumber, $startDate, $expiryDate, $cardType,
		    $cvv2, $holderName, $service,   $werr,       $wmes);
		
		$csr->bind_param_inout(":code",        \$code,       30);
		$csr->bind_param_inout(":card_number", \$cardNumber, 32);
		$csr->bind_param_inout(":start_date",  \$startDate,  10);
		$csr->bind_param_inout(":expiry_date", \$expiryDate, 12);
		$csr->bind_param_inout(":card_type",   \$cardType,   8);
		$csr->bind_param_inout(":cvv2",        \$cvv2,       32);
		$csr->bind_param_inout(":holder_name", \$holderName, 60);
		$csr->bind_param_inout(":service",     \$service,    8);
		$csr->bind_param_inout(":werr",        \$werr,       3);
		$csr->bind_param_inout(":wmes",        \$wmes,       500);

		eval { $csr->execute; };
		if ($@) { warning('Erreur Oracle execute: '.$@); return undef; }
		
		$_ =~ s/^\s*|\s*$//g foreach ($cardNumber, $cardType);

    return { CardNumber => $cardNumber,
             CardExpiry => _dateConvert($expiryDate),
             CardType   => $cardType,
             Service    => $service,
           } if ($werr == 0);

    return undef;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Conversion de la date récupérée depuis l'appel à la procédure stockée
sub _dateConvert {
  my $date = shift;
  
  my $month = substr($date, 3, 2);
  my $year  = substr($date, 6, 2);
  
  return $month.$year;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

1;
