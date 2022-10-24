package Expedia::XML::UserProfile;
#-----------------------------------------------------------------
# Package Expedia::XML::UserProfile
#
# $Id: UserProfile.pm 473 2008-08-25 07:33:15Z pbressan $
#
# (c) 2002-2008 Expedia.                   www.expediacorporate.fr
#-----------------------------------------------------------------

use XML::LibXML;
use XML::Simple;
use Data::Dumper;

use Expedia::Tools::Logger qw(&debug &notice &warning &error);

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# CONSTRUCTEUR
sub new {
	my ($class, $xmlDatas) = @_;

	my $self = {};
  bless ($self, $class);

  $self->{_PARSER} = XML::Simple->new(
    ForceContent => 1,
    ForceArray   => [ContactNumber,ReportingItem,ItemValue,Card,Supplier,IDDocument,PaymentMean,Address,Arranger]
  );
 
  $self->{_XML}  = $xmlDatas;											   
  $self->{_DATA} = $self->{_PARSER}->XMLin($xmlDatas);
	
	# debug "DEBUG [".Dumper($self->{_DATA})."]";
	
	# Attributs propres aux Centre de Coûts
	$self->{CC1}{FLAG}  = undef;
	$self->{CC1}{CODE}  = undef;
	$self->{CC1}{VALUE} = undef;
	
	$self->{CC2}{FLAG}  = undef;
	$self->{CC2}{CODE}  = undef;
	$self->{CC2}{VALUE} = undef;
	
  return $self;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# DESTRUCTEUR
sub DESTROY {
	my $self = shift;
	
	$self->{_DATA}   = undef;
	$self->{_PARSER} = undef; 
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Ecriture du fichier XML dans le fichier de LOG
sub _trace {
  my $self    = shift;

  my $parser  = XML::LibXML->new();
  my $doc     = undef;

  eval { 
    $doc = $parser->parse_string($self->{_XML});
  };
  if ($@) {
    error($@);
    return 0;
  }

  debug('XML = '.$doc->toString(1));

  return 1;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Teste la validité d'un élément avant d'en renvoyer la valeur
#   TODO A placer dans GlobalFuncs.pm 
sub _formatDatas {
  my $datas = shift;
	return $datas if (defined $datas);
	return '';
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Recuperation du percode
sub getUserPerCode {
	my $self = shift;
	return _formatDatas $self->{_DATA}{User}{PerCode};
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Extraction des infos personelles
sub getUserTitle {
	my $self = shift;
	return _formatDatas $self->{_DATA}{User}{PersonalInfo}{Title}{Code};
}

sub getUserFirstName {
	my $self = shift;
	my $userFirstName =  $self->_getItemPersonalInfo('FirstName');
	   $userFirstName =~ s/^\s*|\s*$//g;
	return _formatDatas $userFirstName; 
}

sub getUserLastName {
	my $self = shift;
	my $userLastName =  $self->_getItemPersonalInfo('LastName');
	   $userLastName =~ s/^\s*|\s*$//g;
	return _formatDatas $userLastName;
}

sub getEmail {
	my $self = shift;
	return _formatDatas $self->{_DATA}{User}{PersonalInfo}{Email}{Value}{content}
}

sub getOTFlag {
	my $self = shift;
	return _formatDatas $self->_getItemPersonalInfo('OTFlag');
}

sub getBirthDate {
	my $self = shift;
	return _formatDatas $self->_getItemPersonalInfo('BirthDate');
}

sub getBirthCity {
	my $self = shift;
	return _formatDatas $self->_getItemPersonalInfo('BirthCity');
}

sub getJobTitle {
	my $self = shift;
	return _formatDatas $self->_getItemPersonalInfo('JobTitle');
}

sub getResidenceCountryName {
	my $self = shift;
	return _formatDatas $self->{_DATA}{User}{PersonalInfo}{ResidenceCountry}{Name};
}

sub getResidenceCountryCode {
	my $self = shift;
	return _formatDatas $self->{_DATA}{User}{PersonalInfo}{ResidenceCountry}{Code};
}

sub getIsVIP {
	my $self = shift;
	return $self->_getItemPersonalInfo('IsVIP')
	  if (defined $self->_getItemPersonalInfo('IsVIP'));
  return 'false';
}

sub getHasVIPTreatment {
	my $self = shift;
	return $self->_getItemPersonalInfo('HasVIPTreatment')
	  if (defined $self->_getItemPersonalInfo('HasVIPTreatment'));
  return 'false';
}

sub _getItemPersonalInfo {
	my ($self, $item) = @_;
	return _formatDatas $self->{_DATA}{User}{PersonalInfo}{$item}{content};
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Extraction des données de la partie ReportingData
# (Centres de Coûts 1 et 2)

# Extraction du nombre d'items (de CC à prioris)
sub _getNbReportingItemsInReportingData {
	my $self = shift;
	my $refDatas = $self->{_DATA}{User}{ReportingData}{ReportingItem};
	return (defined $refDatas) ? scalar @{$refDatas} : 0;
}

sub getCC1Flag {
	my $self = shift;
	return 1 if (defined $self->{CC1}{FLAG});
	return 0;
} 

sub getCC2Flag {
	my $self = shift;
	return 1 if (defined $self->{CC2}{FLAG});
	return 0;
}

sub getCC1Code{
	my $self = shift;
	return $self->{CC1}{CODE};
}	

sub getCC2Code{
	my $self = shift;
	return $self->{CC2}{CODE};
}

sub getCC1Value{
	my $self = shift;
	return $self->{CC1}{VALUE};
}	

sub getCC2Value{
	my $self = shift;
	return $self->{CC2}{VALUE};
}

sub extractCCDatas {
	my $self = shift; 

	my $nbElements = $self->_getNbReportingItemsInReportingData();

	for (my $i = 0; $i < $nbElements; $i++) {
		if($self->_getCodeReportingItems($i) eq 'CC1') {
			$self->{CC1}{FLAG}  = 1;
			$self->{CC1}{CODE}  = $self->_getCCDataByName($i, 'Code');
			$self->{CC1}{VALUE} = $self->_getCCDataByName($i, 'Value');
			
		} elsif ($self->_getCodeReportingItems($i) eq 'CC2') {
			$self->{CC2}{FLAG}  = 1;
			$self->{CC2}{CODE}  = $self->_getCCDataByName($i, 'Code');
			$self->{CC2}{VALUE} = $self->_getCCDataByName($i, 'Value');
		}
	}

}

sub _getCCDataByName {
	my ($self, $indice, $dataName) = @_;
	return _formatDatas $self->{_DATA}{User}{ReportingData}{ReportingItem}[$indice]{ItemValues}{ItemValue}[0]{$dataName}{content};
}

sub _getCodeReportingItems {
	my ($self, $indice) = @_;
	return _formatDatas $self->{_DATA}{User}{ReportingData}{ReportingItem}[$indice]{Code};
}

sub getIsMandatoryReportingItems {
	my ($self, $indice) = @_;
	return (defined $self->{_DATA}{User}{ReportingData}{ReportingItem}[$indice]{IsMandatory}{content}) ? 1 : 0;
	
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Extraction de la partie LoyaltySubscriptionCards
sub getNbLoyaltySubscriptionCards {
	my $self = shift;
	my $refDatas = $self->{_DATA}{User}{LoyaltySubscriptionCards}{Card};
	return (defined $refDatas) ? scalar( @{$refDatas}) : 0;
}

sub getCardType {
	my ($self, $indice) = @_;
	return _formatDatas $self->{_DATA}{User}{LoyaltySubscriptionCards}{Card}[$indice]{Type};
}

sub getCardCode {
	my ($self, $indice) = @_;
	return _formatDatas $self->{_DATA}{User}{LoyaltySubscriptionCards}{Card}[$indice]{Code};
}

sub getCardNumber {
	my ($self, $indice) = @_;
	my $cardNumber =  $self->{_DATA}{User}{LoyaltySubscriptionCards}{Card}[$indice]{CardNumber}{content};
	   $cardNumber =~ s/^\s*|\s*$//g;
	return $cardNumber;
}

sub getCardName {
	my ($self, $indice) = @_;
	return _formatDatas $self->{_DATA}{User}{LoyaltySubscriptionCards}{Card}[$indice]{Name}{content};
}

sub getCardValidFrom {
	my ($self, $indice) = @_;
	return _formatDatas $self->{_DATA}{User}{LoyaltySubscriptionCards}{Card}[$indice]{ValidFrom}{content};
}

sub getCardValidTo {
	my ($self, $indice) = @_;
	return _formatDatas $self->{_DATA}{User}{LoyaltySubscriptionCards}{Card}[$indice]{ValidTo}{content};
}

sub getCardClass {
	my ($self, $indice) = @_;
	return _formatDatas $self->{_DATA}{User}{LoyaltySubscriptionCards}{Card}[$indice]{Class}{content};
}

sub getCardItinerary {
	my ($self, $indice) = @_;
	return _formatDatas $self->{_DATA}{User}{LoyaltySubscriptionCards}{Card}[$indice]{Itinerary}{content};
}

sub getCardIsAccreditive {
	my ($self, $indice) = @_;
	return _formatDatas $self->{_DATA}{User}{LoyaltySubscriptionCards}{Card}[$indice]{IsAccreditive}{content};
}

sub getCardNbIssuingSuppliers {
	my ($self, $indice) = @_;
	my $refDatas = $self->{_DATA}{User}{LoyaltySubscriptionCards}{Card}[$indice]{IssuingSuppliers}{Supplier};
	return (defined $refDatas) ? scalar @{$refDatas} : 0;
}

sub getCardISSupplierCode {
	my ($self, $indice1, $indice2) = @_;
	return _formatDatas $self->{_DATA}{User}{LoyaltySubscriptionCards}{Card}[$indice1]{IssuingSuppliers}{Supplier}[$indice2]{Code};
}

sub getCardISSupplierName {
	my ($self, $indice1, $indice2) = @_;
	return _formatDatas $self->{_DATA}{User}{LoyaltySubscriptionCards}{Card}[$indice1]{IssuingSuppliers}{Supplier}[$indice2]{SupplierName}{content};
}

sub getCardISSupplierService {
	my ($self, $indice1, $indice2) = @_;
	return _formatDatas $self->{_DATA}{User}{LoyaltySubscriptionCards}{Card}[$indice1]{IssuingSuppliers}{Supplier}[$indice2]{Service}{content};
}

sub getCardISSupplierIsAlliance {
	my ($self, $indice1, $indice2) = @_;
	return _formatDatas $self->{_DATA}{User}{LoyaltySubscriptionCards}{Card}[$indice1]{IssuingSuppliers}{Supplier}[$indice2]{IsAlliance}{content};
}

sub getCardPTC {
	my ($self, $indice) = @_;
	my $Datas = $self->{_DATA}{User}{LoyaltySubscriptionCards}{Card}[$indice]{DefaultPtc}{content};
	return (defined $Datas) ? $Datas : "";
}

sub getCardNbEligibleSuppliers {
	my ($self, $indice) = @_;
	my $refDatas = $self->{_DATA}{User}{LoyaltySubscriptionCards}{Card}[$indice]{EligibleSuppliers}{Supplier}; 
	return (defined $refDatas) ? scalar @{$refDatas} : 0;
}

sub getCardESSupplierCode {
	my ($self, $indice1, $indice2) = @_;
	return _formatDatas $self->{_DATA}{User}{LoyaltySubscriptionCards}{Card}[$indice1]{EligibleSuppliers}{Supplier}[$indice2]{Code};
}

sub getCardESSupplierName {
	my ($self, $indice1, $indice2) = @_;
	return _formatDatas $self->{_DATA}{User}{LoyaltySubscriptionCards}{Card}[$indice1]{EligibleSuppliers}{Supplier}[$indice2]{SupplierName}{content};
}

sub getCardESSupplierService {
	my ($self, $indice1, $indice2) = @_;
	return _formatDatas $self->{_DATA}{User}{LoyaltySubscriptionCards}{Card}[$indice1]{EligibleSuppliers}{Supplier}[$indice2]{Service}{content};
}

sub getCardESSupplierIsAlliance {
	my ($self, $indice1, $indice2) = @_;
	return _formatDatas $self->{_DATA}{User}{LoyaltySubscriptionCards}{Card}[$indice1]{EligibleSuppliers}{Supplier}[$indice2]{IsAlliance}{content};
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Extraction des datas sur la section IDDocument
sub getNbIDDocuments {
	my $self = shift;
	my $refDatas = $self->{_DATA}{User}{IDDocuments}{IDDocument};
	return ( defined $refDatas ) ? scalar @{$refDatas} : 0;
}

sub getIDDocumentType {
  my ($self, $indice) = @_;
	return _formatDatas $self->{_DATA}{User}{IDDocuments}{IDDocument}[$indice]{DocumentType}{content};
}

sub getIDDocumentNumber {
  my ($self, $indice) = @_;
	return _formatDatas $self->{_DATA}{User}{IDDocuments}{IDDocument}[$indice]{Number}{content};
}

sub getIDDocumentIssueDate {
  my ($self, $indice) = @_;
	return _formatDatas $self->{_DATA}{User}{IDDocuments}{IDDocument}[$indice]{IssueDate}{content};
}

sub getIDDocumentExpiryDate {
	my ($self, $indice) = @_;
	return _formatDatas $self->{_DATA}{User}{IDDocuments}{IDDocument}[$indice]{ExpiryDate}{content};
}

sub getIDDocumentIssuePlaceValue {
	my ($self, $indice) = @_;
	return _formatDatas $self->{_DATA}{User}{IDDocuments}{IDDocument}[$indice]{IssuePlace}{Value}{content};
}

sub getIDDocumentIssuePlaceCode {
	my ($self, $indice) = @_;
	return _formatDatas $self->{_DATA}{User}{IDDocuments}{IDDocument}[$indice]{IssuePlace}{Code}{content};
}

sub getIDDocumentNationalityName {
	my ($self, $indice) = @_;
	return _formatDatas $self->{_DATA}{User}{IDDocuments}{IDDocument}[$indice]{Nationality}{Name};
}

sub getIDDocumentNationalityCode {
	my ($self, $indice) = @_;
	return _formatDatas $self->{_DATA}{User}{IDDocuments}{IDDocument}[$indice]{Nationality}{Code};
}

sub getIDDocumentIssueCountryName {
	my ($self, $indice) = @_;
	return _formatDatas $self->{_DATA}{User}{IDDocuments}{IDDocument}[$indice]{IssueCountry}{Name};
}

sub getIDDocumentIssueCountryCode {
	my ($self, $indice) = @_;
	return _formatDatas $self->{_DATA}{User}{IDDocuments}{IDDocument}[$indice]{IssueCountry}{Code};
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Extraction des datas sur la section PaymentMatrix
sub getNbPaymentMean {
  my $self = shift;
	my $refDatas = $self->{_DATA}{User}{PaymentMatrix}{PaymentMean};
	return (defined $refDatas) ? scalar @{$refDatas} : 0;
}

sub getPaymentService {
	my ($self, $indice) = @_;
	return _formatDatas $self->{_DATA}{User}{PaymentMatrix}{PaymentMean}[$indice]{Service}{content};
}

sub getPaymentCode {
  my ($self, $indice) = @_;
  return _formatDatas $self->{_DATA}{User}{PaymentMatrix}{PaymentMean}[$indice]{Code};
}

sub getPaymentType {
  my ($self, $indice) = @_;
  return _formatDatas $self->{_DATA}{User}{PaymentMatrix}{PaymentMean}[$indice]{PaymentType}{content};
}

sub getPaymentBillingEntityLabel {
  my ($self, $indice) = @_;
  return _formatDatas $self->{_DATA}{User}{PaymentMatrix}{PaymentMean}[$indice]{BillingEntity}{Label}{content};
}

sub getPaymentBillingEntityValue {
  my ($self, $indice) = @_;
  return _formatDatas $self->{_DATA}{User}{PaymentMatrix}{PaymentMean}[$indice]{BillingEntity}{Value}{content};
}

sub getPaymentBillingEntityCode {
  my ($self, $indice) = @_;
  return _formatDatas $self->{_DATA}{User}{PaymentMatrix}{PaymentMean}[$indice]{BillingEntity}{Code}{content};
}

sub getPaymentBillingEntityLanguage {
  my ($self, $indice) = @_;
  return _formatDatas $self->{_DATA}{User}{PaymentMatrix}{PaymentMean}[$indice]{BillingEntity}{Language}{content};
}

sub getPaymentLabel {
  my ($self, $indice) = @_;
  return _formatDatas $self->{_DATA}{User}{PaymentMatrix}{PaymentMean}[$indice]{Label}{content};
}

sub getPaymentLabelCode {
  my ($self, $indice) = @_;
  return _formatDatas $self->{_DATA}{User}{PaymentMatrix}{PaymentMean}[$indice]{Label}{Code}{content};
}

sub getPaymentLabelLanguage {
  my ($self, $indice) = @_;
  return _formatDatas $self->{_DATA}{User}{PaymentMatrix}{PaymentMean}[$indice]{Label}{Language}{content};
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
#	Extraction de la section COMPANY
sub getCompanyComCode {
	my $self = shift;
	return _formatDatas $self->{_DATA}{User}{Company}{ComCode};
}

sub getCompanyName {
	my $self = shift;
	return _formatDatas $self->{_DATA}{User}{Company}{CompanyCoreInfo}{Name}{content};
}

sub getPOSCompanyComCode {
	my $self = shift;
	return _formatDatas $self->{_DATA}{User}{Company}{CompanyCoreInfo}{POS}{Company}{ComCode};
}

sub getPOSCompanyName {
	my $self = shift;
	return _formatDatas $self->{_DATA}{User}{Company}{CompanyCoreInfo}{POS}{Company}{Name}{content};
}

sub getPOSCompanyCountryName {
	my $self = shift;
	return _formatDatas $self->{_DATA}{User}{Company}{CompanyCoreInfo}{POS}{Company}{Country}{Name};
}

sub getPOSCompanyCountryCode {
	my $self = shift;
	return _formatDatas $self->{_DATA}{User}{Company}{CompanyCoreInfo}{POS}{Company}{Country}{Code};
}

sub getPOSName {
	my $self = shift;
	return _formatDatas $self->{_DATA}{User}{Company}{CompanyCoreInfo}{POS}{Name}{content};
}

sub getPOSNameLabel {
	my $self = shift;
	return _formatDatas $self->{_DATA}{User}{Company}{CompanyCoreInfo}{POS}{Name}{Label}{content};
}

sub getPOSNameCode {
	my $self = shift;
	return _formatDatas $self->{_DATA}{User}{Company}{CompanyCoreInfo}{POS}{Name}{Code}{content};
}

sub getPOSNameLanguage {
	my $self = shift;
	return _formatDatas $self->{_DATA}{User}{Company}{CompanyCoreInfo}{POS}{Name}{Language}{content};
}

sub getCountryName {
	my $self = shift;
	return _formatDatas $self->{_DATA}{User}{Company}{CompanyCoreInfo}{Country}{Name};
}

sub getCountryCode {
	my $self = shift;
	return _formatDatas $self->{_DATA}{User}{Company}{CompanyCoreInfo}{Country}{Code};
}

sub getIsDummy {
	my $self = shift;
	
	my $isDumy = $self->{_DATA}{User}{Company}{CompanyCoreInfo}{IsDummy}{content};
	return $isDumy if (defined $isDumy);
	return 'false';
}

sub getCompanyGroupeValue {
	my $self = shift;
	return _formatDatas $self->{_DATA}{User}{Company}{CompanyCoreInfo}{CompanyGroup}{group}{Value}{content};
}

sub getCompanyGroupeCode {
	my $self = shift;
	return _formatDatas $self->{_DATA}{User}{Company}{CompanyCoreInfo}{CompanyGroup}{group}{Code}{content};
}

sub isMeetingCompany {
	my $self = shift;
	
	my $isMeeting = 0;
     $isMeeting = $self->{_DATA}{User}{Company}{CompanyCoreInfo}{IsMeeting}{content};
     $isMeeting = ((defined $isMeeting) && ($isMeeting eq 'true')) ? 1 : 0;
  
  return $isMeeting;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# SECTION ADRESS BOOK
sub getNbAddress {
	my $self = shift;
	my $refDatas = $self->{_DATA}{User}{AddressBook}{Address};
	return (defined $refDatas) ? scalar @{$refDatas} : 0;
}

# Remarque : le première adresse est l'adresse par défaut
sub getDefaultAddressName {
  my $self = shift;
  return _formatDatas $self->{_DATA}{User}{AddressBook}{DefaultDelivery}{Address}[0]{Name}{content};
}

sub getDefaultAddressStreet1 {
  my $self = shift;
  return _formatDatas $self->{_DATA}{User}{AddressBook}{DefaultDelivery}{Address}[0]{Street1}{content};
}

sub getDefaultAddressStreet2 {
  my $self = shift;
	return _formatDatas $self->{_DATA}{User}{AddressBook}{DefaultDelivery}{Address}[0]{Street2}{content};
}

sub getDefaultAddressPostalCode {
  my $self = shift;
	return _formatDatas $self->{_DATA}{User}{AddressBook}{DefaultDelivery}{Address}[0]{PostalCode}{content};
}		

sub getDefaultAddressCity {
  my $self = shift;
	return _formatDatas $self->{_DATA}{User}{AddressBook}{DefaultDelivery}{Address}[0]{City}{content};
}

sub getDefaultAddressCountryName {
  my $self = shift;
	return _formatDatas $self->{_DATA}{User}{AddressBook}{DefaultDelivery}{Address}[0]{Country}{Name};
}

sub getDefaultAddressCountryCode {
  my $self = shift;
  return _formatDatas $self->{_DATA}{User}{AddressBook}{DefaultDelivery}{Address}[0]{Country}{Code};
}

# Extraction de l'adresse en fonction de l'indice dans la liste d'adresses

sub getAddressName {
	my ($self, $indice) = @_;
	return _formatDatas $self->{_DATA}{User}{AddressBook}{Address}[$indice]{Address}[0]{Name}{content};
}

sub getAddressStreet1 {
	my ($self,$indice) = @_;
	return _formatDatas $self->{_DATA}{User}{AddressBook}{Address}[$indice]{Address}[0]{Street1}{content};
}

sub getAddressStreet2 {
	my ($self, $indice) = @_;
	return _formatDatas $self->{_DATA}{User}{AddressBook}{Address}[$indice]{Address}[0]{Street2}{content};
}

sub getAddressPostalCode {
	my ($self, $indice) = @_;
	return _formatDatas $self->{_DATA}{User}{AddressBook}{Address}[$indice]{Address}[0]{PostalCode}{content};
}

sub getAddressCity {
	my ($self, $indice) = @_;
	return _formatDatas $self->{_DATA}{User}{AddressBook}{Address}[$indice]{Address}[0]{City}{content};
}

sub getAddressCountryName {
	my ($self, $indice) = @_;
	return _formatDatas $self->{_DATA}{User}{AddressBook}{Address}[$indice]{Address}[0]{Country}{Name};
}

sub getAddressCountryCode {
	my ($self, $indice) = @_;
	return _formatDatas $self->{_DATA}{User}{AddressBook}{Address}[$indice]{Address}[0]{Country}{Code};
}


sub getAPISResidenCountry {
  my $self = shift;
	return _formatDatas $self->{_DATA}{User}{APIS}{ResidenceCountry};
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# SECTION CONTACT NUMBERS

# Extraction du nb de numéros de tel 
sub _getNbUsersNumbers {
	my $self = shift;
	my $refDatas = $self->{_DATA}{User}{ContactNumbers}{ContactNumber};
	return (defined $refDatas) ? scalar @{$refDatas} : 0;
}

# Extraction d'un numéro (fixe ou mobile)
sub getOnePhoneNumber {
	my ($self) = @_;
	return $self->getUserPhoneNumber()  if ($self->getUserPhoneNumber()  ne '');
	return $self->getUserMobileNumber() if ($self->getUserMobileNumber() ne '');
	return '';
}

# Extraction d'un numéro de fixe
sub getUserPhoneNumber {
	my ($self) = @_;
	return $self->_getUserNumberByType('PHONE');
}

# Extraction d'un numéro de téléphone business
sub getUserPhoneNumberBusiness {
	my ($self) = @_;

	my $nbNum = $self-> _getNbUsersNumbers();
	my $dataToReturn = '';
	
	for (my $indice = 0; $indice < $nbNum; $indice++) {
		my $data = $self->{_DATA}{User}{ContactNumbers}{ContactNumber}[$indice];
		$dataToReturn = _formatDatas $data->{Value}{content}
      if ((defined $data)                           &&
          (defined $data->{Type}{Code}{content})    &&
          ($data->{Type}{Code}{content} eq 'PHONE') &&
          ($data->{Usage}{Code}{content} eq 'BUSINESS'))
	}
	
	return $dataToReturn;  
}

# Extraction d'un numéro de mobile
sub getUserMobileNumber {
	my ($self) = @_;
	return $self->_getUserNumberByType('MOBILE');
}

# Extraction d'un numéro de fax
sub getUserFaxNumber {
	my ($self) = @_;
	return $self->_getUserNumberByType('FAX');
}

# Extraction d'un numéro en fonction de son type
#   On a un seul numéro par type de numéro
sub _getUserNumberByType {
	my ($self, $type) = @_;

	my $nbNum = $self-> _getNbUsersNumbers();
	my $dataToReturn = '';
	
	for (my $indice = 0; $indice < $nbNum; $indice++) {
		my $data = $self->{_DATA}{User}{ContactNumbers}{ContactNumber}[$indice];
		$dataToReturn = _formatDatas $data->{Value}{content}
      if ((defined $data) && (defined $data->{Type}{Code}{content}) && ($data->{Type}{Code}{content} eq $type)) 
	}
	
	return $dataToReturn;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# SECTION ARRANGERS

# Extraction du nombre d'assistants
sub getNbArrangers {
  my $self = shift;
  my $refDatas = $self->{_DATA}{User}{Arrangers}{Arranger};
  return (defined $refDatas) ? scalar @{$refDatas} : 0;
}

# Extraction du prénom de l'assistant
sub getArrangerFirstName {
  my ($self, $indice) = @_;
  return _formatDatas $self->{_DATA}{User}{Arrangers}{Arranger}[$indice]{User}{PersonalInfo}{FirstName}{content};	
}

# Extraction du nom de l'assistant
sub getArrangerLastName {
  my ($self, $indice) = @_;
  return _formatDatas $self->{_DATA}{User}{Arrangers}{Arranger}[$indice]{User}{PersonalInfo}{LastName}{content};
}

# Extraction du mail de l'assistant
sub getArrangerEmail {
	my ($self, $indice) = @_;
	return _formatDatas $self->{_DATA}{User}{Arrangers}{Arranger}[$indice]{User}{PersonalInfo}{Email}{Value}{content};
}

# Extraction du nombre de numéro de tel de l'assistant
sub _getNbArrangerPhoneNumbers {
  my ($self, $indice) = @_;
  my $refDatas = $self->{_DATA}{User}{Arrangers}{Arranger}[$indice]{User}{ContactNumbers}{ContactNumber};
  return (defined $refDatas) ? scalar @{$refDatas} : 0;
}

# Extraction d'un numéro de l'assistant qq soit le type de numéro
sub getArrangerOneNumber {
  my ($self, $indice) = @_;

	return $self->getArrangerPhoneNumber($indice)  if ($self->getArrangerPhoneNumber($indice)  ne '');
	return $self->getArrangerMobileNumber($indice) if ($self->getArrangerMobileNumber($indice) ne '');
  return '';
}

# Extraction du numéro de fixe d'un assistant
sub getArrangerPhoneNumber {
	my ($self, $indice) = @_;
	return $self->_getArrangerNumberByType($indice, 'PHONE');
}

# Extraction du numéro de mobile d'un assistant
sub getArrangerMobileNumber {
	my ($self, $indice) = @_;
	return $self->_getArrangerNumberByType($indice, 'MOBILE');
}

# Extraction d'un numéro en fonction de son type
#   On a un seul numéro par type de numéro
sub _getArrangerNumberByType {
	my ($self, $indiceArranger, $type) = @_;
	
	my $nbNum = $self-> _getNbArrangerPhoneNumbers($indiceArranger);
	my $dataToReturn = '';
	
	for (my $indice = 0; $indice < $nbNum; $indice++) {
		my $data = $self->{_DATA}{User}{Arrangers}{Arranger}[$indiceArranger];
		if ((defined $data) && (defined $data->{User}{ContactNumbers}{ContactNumber}[$indice]{Type}{Value}{content}) 
												&& ($data->{User}{ContactNumbers}{ContactNumber}[$indice]{Type}{Value}{content} eq $type)) {
			$dataToReturn = _formatDatas $data->{User}{ContactNumbers}{ContactNumber}[$indice]{Value}{content};
		} 
	}
	
	return $dataToReturn;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# SECTION ADDITIONNAL INFOS
sub getUserMiscComment {
	my $self = shift;
	return _formatDatas $self->{_DATA}{User}{AdditionalInfo}{MiscellaneousComment}{content};
}

sub getUserOSIYY {
	my $self = shift;
	return _formatDatas $self->{_DATA}{User}{AdditionalInfo}{OSIYY}{content};
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# SECTION PREFERENCES
sub getUserAirPrefMeal {
	my $self = shift;
	return _formatDatas $self->{_DATA}{User}{TravelPreferences}{AirPreferences}{Meal}{Code}{content};
}

sub getUserAirPrefSeat { # TODO à refaire en prenant la VALUE. 3 valeurs possibles !
	my $self = shift;
	
	my $seatPref = _formatDatas $self->{_DATA}{User}{TravelPreferences}{AirPreferences}{Seat}{Code}{content};
	   $seatPref = ''  if ($seatPref eq 'A');
	   $seatPref = 'A' if ($seatPref eq 'C');
	   $seatPref = 'W' if ($seatPref eq 'W');
		
	return $seatPref;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

1;
