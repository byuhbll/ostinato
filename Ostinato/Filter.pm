package Ostinato::Filter;

use Ostinato::Policy;

our $VERSION="2.1.0";

#Some class-level definitions
use constant KEYS => "KEYS";

sub new
{
	my $class = shift;
	my $self  = {};

	#Tie the instantiated class to an existing Ostinato class or create a new one and tie them together
	$self->{env} = shift;
	if(!defined $self->{env}) { $self->{env} = new Ostinato(); }
	if(!defined $self->{env}->{class}->{policy}) { $self->{env}->{class}->{policy} = new Ostinato::Policy($self->{env}); }

	#Create an empty filter map
	$self->{filter} = ();

	#Bless and return class
	bless($self,$class);
	return $self;
}

sub getFilter
{
	my $self = shift;
	my $key = shift;
	return $self->{filter}->{$key};
}
sub setFilter
{
	my $self = shift;
	my $key = shift;
	my $value = shift;

	$self->{filter}->{$key} = $value;
	return $value;
}

sub autofilter_excludeShadowedLocations
{
	my $self = shift;
	
	my $policies = $self->{env}->{class}->{policy}->getPoliciesOfType(Ostinato::Policy::LOCATION);
	my $filterString = "~";
	while( my ($key,$value) = each %{$policies})
	{
		if($self->{env}->{class}->{policy}->isLocationShadowed($key))
		{
			$filterString .= "$key,";
		}
	}

	$filterString = substr($filterString, 0, -1);
	if(length($filterString) > 1 || 1)
	{
		$self->setFilter(Ostinato::Policy::LOCATION, $filterString);
		return $filterString;
	}
	else
	{
		return 0;
	}
}


__END__


=pod


=head1 NAME

Ostinato::Filter - Manages filters to include/exclude specifc Symphony libraries, locations, or items in further considerations.


=head1 SYNOPSIS

  #Importing the module
  use lib "path/to/ostinato";  #Only required if module is not in the Perl include path already
  use Ostinato::Filter;

  #Create a new instance of the class.  An existing instance of the Ostinato class can be provided, or a new one will be created
  my $filter = new Ostinato::Filter($ostinato_instance);

  #Sample function calls
  $filter->autofilter_excludeShadowLocations();
  $filter->setfilter(Ostinato::Policy::LIBRARY, "LEE");


=head1 DESCRIPTION

This module establishes and maintains a list of "filters".  Each filter corresponds to some inclusion or exclusion that can be applied to API calls and database queries.  The behavioral change effected by each filter is specific to each API or database call, so some familiarization with the Ostinato code is recommended when using them.

WARNING: This library has serious potential to damage your system if not used carefully.  Make sure you know what you're doing, and restrict access to trusted users only.

=head1 DEPENDENCIES

This module requires the Ostinato::Policies module, and inherits its dependencies.


=head1 FUNCTIONS

=head2 I<new($ostinatoInstance)>

=over 4

The B<new> function creates a new instance of the Ostinato::Filter module as a class.  It will import or create a parent Ostinato module and associate itself with it.  If an Ostinato::Policy instance is not associated with the parent Ostinato module, one will be created, since that class is required for proper functioning of the Filter class.

=head3 Parameters:

- B<$ostinatoInstance>: [OPTIONAL] An existing instance of the Ostinato class.  If left blank, a new instance of the Ostinato class will be created and associated with this class.

=head3 Returns:

- A reference to the now-instantiated and blessed Ostinato::Filter class

=back


=head2 I<getFilter($filter_name)>

=over 4

The B<getFilter> function will return the value of the filter associated with the provided $filter_name.

=head3 Parameters:

- B<$filter_name>: [REQUIRED] The key/name of the filter to return.

=head3 Returns:

The value of the filter.

=back


=head2 I<setFilter($filter_name,$filter_value)>

=over 4

The B<setFilter> function will create or overwrite the filter associated with the provided $filter_name.  Of note, this function is called by the I<autofilter_excludeShadowedLocations> function.

=head3 Parameters:

- B<$filter_name>: [REQUIRED] The key/name of the filter to create or update.

- B<$filter_value>: [REQUIRED] A string representing the value of the filter.  Filters consist of a comma-separated list of values.  They can either be inclusive or exclusive (exclusive filters are identified by the first character, which should be a tilde symbol "~").  A good rule of thumb is to see what kind of list is required if you were to filter an API call directly and replicate that list of values here.

=head3 Returns:

- The value of the newly-written filter, identical to the provided $filter_value.

=back


=head2 I<autofilter_excludeShadowedLocations>

=over 4

The B<autofilter_excludeShadowedLocations> creates a predefined filter, which excludes all shadowed locations as defined in the Symphony policies file.  The name/key of the resulting filter can be referenced by using the Ostinato::Policy::LOCATION constant.

=head3 Parameters:

- [none]

=head3 Returns:

- The value of the newly-written filter.

=back


=head1 Author/License

This file is part of the Ostinato Perl Library for SirsiDynix Symphony, developed independently by Brigham Young University.

License information is available in the Ostinato LICENSE.md document.
