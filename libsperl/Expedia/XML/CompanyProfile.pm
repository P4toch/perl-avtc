package Expedia::XML::CompanyProfile;
#-----------------------------------------------------------------
# Package Expedia::XML::CompanyProfile
#
# $Id: CompanyProfile.pm 473 2008-08-25 07:33:15Z pbressan $
#
# (c) 2002-2008 Expedia.                   www.expediacorporate.fr
#-----------------------------------------------------------------

use XML::Simple;

use Expedia::Tools::Logger qw(&debug &notice &warning &error);

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# CONSTRUCTEUR
sub new {
	my ($class, $xmlDatas) = @_;

	my $self = {};
  bless ($self, $class);

  $self->{_PARSER} = XML::Simple->new(ForceContent => 1,
  																		ForceArray   => [] );

  $self->{_DATA}   = $self->{_PARSER}->XMLin($xmlDatas);

  return $self;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# DESTRUCTEUR
sub DESTROY {
  my $self = shift;
	
	$self->{_DATA} 				= undef;
	$self->{_PARSER} 			= undef; 
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
# Récuperation du Nom de Société
sub getCompanyName {
	my $self = shift;
	return _formatDatas $self->{_DATA}{Company}{CompanyCoreInfo}{Name}{content};
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Récupération du Marché
sub getPOSCompanyComCode {
	my $self = shift;
	return _formatDatas $self->{_DATA}{Company}{CompanyCoreInfo}{POS}{Company}{ComCode};
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Récupération du ComCode
sub getCompanyComCode {
	my $self = shift;
	return _formatDatas $self->{_DATA}{Company}{ComCode};
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# S'agit-il d'une Company Meeting ? 
sub isMeetingCompany {
	my $self = shift;
	
  my $isMeeting = 0;
     $isMeeting = $self->{_DATA}{Company}{CompanyCoreInfo}{IsMeeting}{content};
     $isMeeting = ((defined $isMeeting) && ($isMeeting eq 'true')) ? 1 : 0;
  
  return $isMeeting;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

1;
