package Expedia::XML::MsgGenerator;
#-----------------------------------------------------------------
# Package Expedia::XML::MsgGenerator
#
# $Id: MsgGenerator.pm 410 2008-02-11 09:20:59Z pbressan $
#
# (c) 2002-2007 Expedia.                   www.expediacorporate.fr
#-----------------------------------------------------------------

use Template;

use Expedia::Tools::Logger qw(&debug &notice &warning &error);
use Expedia::Tools::GlobalVars qw($templatesPath);

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# CONSTRUCTEUR
sub new {
	my ($class, @Params) = @_;

	my $self = {};
  bless ($self, ref($class) || $class);

	$self->{_ERRMSG} = '';
		
	$self->_init(@Params);

  return $self;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
sub _init {
	my ($self, @Params) = @_;
	
	# Initialisation du moteur de template 
	my $oTT = undef;

	if (!($oTT = Template->new({
        		INCLUDE_PATH 	=> $templatesPath,
        		INTERPOLATE  	=> 1,
						OUTPUT				=> \$self->{_XMLString}
    	                       }))) { 
			error($Template::ERROR);
			$self->{_ERRMSG} = $Template::ERROR;
	} else {
 	 	$self->{_TEMPLATE_ENGINE} = $oTT; 

		# Construction du message
		$self->_buildMsg(@Params);

		# TODO Implementer le contrôle vis a vis du XSD
		# $self->_validate();
	}
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# _buildMsg: Methode privée construisant le message XML
sub _buildMsg {
	my ($self, $rhDatasToProcess, $template) = @_; 
	
	if (!$self->{_TEMPLATE_ENGINE}->process($template, $rhDatasToProcess)) {
		error($self->{_TEMPLATE_ENGINE}->error());
		$self->{_ERRMSG} = $self->{_TEMPLATE_ENGINE}->error();
	}
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# _validate: Méthode privée vérifiant la validité du XML fabriqué
sub _validate {
	my $self = shift;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
sub getMessage {
  my $self = shift;
  
	return $self->{_XMLString} if ($self->{_ERRMSG} eq '');
  return undef;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# DESTRUCTEUR
sub DESTROY {
  my $self = shift;

	$self->{_TEMPLATE_ENGINE} = undef;
	$self->{_ERRMSG}          = undef;
	$self->{_XMLString}       = undef;
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

1;
