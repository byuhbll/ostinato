package Ostinato::Policy;

use Ostinato;

our $VERSION="2.0.0";

#Some class-level definitions
use constant POLICY_TYPE  => 0;
use constant POLICY_INDEX => 1;
use constant POLICY_NAME  => 2;
use constant POLICY_DATA_SHADOWED => 2;
use constant LOCATION => "LOCN";
use constant LIBRARY  => "LIBR";
use constant ITEMTYPE => "ITYP";

sub new
{
	my $class = shift;
	my $self  = {};

	#Tie the instantiated class to an existing Ostinato class or create a new one and tie them together
	$self->{env} = shift;
	if(!defined $self->{env}) { $self->{env} = new Ostinato(); }

	bless($self,$class);

	#Create an empty policy map
	$self->{policyIndices} = ();
	$self->{policyData}    = ();

	return $self;
}

sub importPolicies
{
	my $self = shift;

	#Set up array of policy types to search for
	my %policyTypes;
	while(my $type = shift) { $policyTypes{$type} = 1; }
	if(!(%policyTypes))
	{
		#By default, the following item types are supported and will be imported if no type is explicitly requested
		%policyTypes = (
			LOCATION() => 1,
			LIBRARY()  => 1,
			ITEMTYPE() => 1
		);
	}

	#Parse policies file and extract desired types
	open POLICIES, "<", $self->{env}->getPath('policies') or Carp::confess("Unable to open file \"" . $self->{env}->getPath('policies') ."\": $!");	
	while(my $line = <POLICIES>)
	{
		my @fields = split(/\|/, $line);
		if (defined($policyTypes{$fields[POLICY_TYPE]}))
		{
			#Make sure to de-increment each successive index, since splice will remove the previous one
			my $type  = splice(@fields, POLICY_TYPE  -0, 1);
			my $index = splice(@fields, POLICY_INDEX -1, 1);
			my $name  = splice(@fields, POLICY_NAME  -2, 1);
			my $data  = join('|', @fields);

			$self->{policyIndices}->{$type}->{$name} = $index;
			$self->{policyData}->{$type}->{$name} = $data;
		}
	}
	close(POLICIES);
	
	return $self->{policyIndices};
}

#Setters and Getters
sub getPolicyIndex
{
	my $self       = shift;
	my $policyType = shift;
	my $policyName = shift;
	return $self->{policyIndices}->{$policyType}->{uc($policyName)};
}

sub getPolicyData
{
	my $self       = shift;
	my $policyType = shift;
	my $policyName = shift;
	return $self->{policyData}->{$policyType}->{uc($policyName)};
}

sub getPoliciesOfType
{
	my $self = shift;
	my $policyType = shift;
	return $self->{policyIndices}->{$policyType};
}

sub getLibraryIndex { return $_[0]->getPolicyIndex(LIBRARY, $_[1]); }
sub getLocationIndex{ return $_[0]->getPolicyIndex(LOCATION,$_[1]); }
sub getItemtypeIndex{ return $_[0]->getPolicyIndex(ITEMTYPE,$_[1]); }

sub isLocationShadowed
{
	my $self       = shift;
	my $policyName = shift;
	return (split(/\|/, $self->getPolicyData("LOCN",$policyName)))[POLICY_DATA_SHADOWED];
}
#sub getAllShadowedLocations
#{
#	my $self = shift;
#
#	my %locIndex = %{$self->{policyIndices}};
#	my @shadowedLocations;
#	while ( my ($key, $data) = each %{$self->{policyData}->{LOCATION}})
#	{
#		if((split(/\|/, $data))[POLICY_DATA_SHADOWED])
#		{
#			push(@shadowedLocations, $key);
#		}
#	}
#
#}

1;

__END__


=pod


=head1 NAME

Ostinato::Policy - Imports and returns data from the Symphony policies file


=head1 SYNOPSIS

  #Importing the module
  use lib "path/to/ostinato";  #Only required if module is not in the Perl include path already
  use Ostinato::Policy;

  #Create a new instance of the class.  An existing instance of the Ostinato class can be provided, or a new one will be created
  my $policies = new Ostinato::Policy($ostinato_instance);

  #Sample function calls
  $policies->importPolicies();
  $policies->getLibraryIndex("LEE");


=head1 DESCRIPTION

This module imports information from the Symphony policies file.  At its most basic level, it will allow you to recover the index of a given policy (the ID associated with a particular item type, for example), which is required to query the database.  Additional functions are available to get policy-specific data (such as whether or not a location is shadowed).

WARNING: This library has serious potential to damage your system if not used carefully.  Make sure you know what you're doing, and restrict access to trusted users only.

=head1 DEPENDENCIES

This module requires the parent Ostinato module, and inherits its dependencies.


=head1 FUNCTIONS

=head2 I<new($ostinatoInstance)>

=over 4

The B<new> function creates a new instance of the Ostinato::Policy module as a class.  It will import or create a parent Ostinato module and associate itself with it.

=head3 Parameters:

- B<$ostinatoInstance>: [OPTIONAL] An existing instance of the Ostinato class.  If left blank, a new instance of the Ostinato class will be created and associated with this class.

=head3 Returns:

- A reference to the now-instantiated and blessed Ostinato::Policy class

=back


=head2 I<importPolicies($type1,$type2,$type3,...)>

=over 4

The B<importPolicies> function will import all lines associated with one or more policy types from the Symphony policies file.  These lines will be stored in the class as a hash.  If no specific policies types are requested, it will import the LIBR, LOCN, and ITYP policies by default. 

In most cases, this will be the first function called after a new Policy class is set up.

=head3 Parameters:

- B<$type>: [OPTIONAL]  A policy type to import.  Each policy type should be provided as a separate parameter.  If no policy types are provided, the default policies (LIBR, LOCN, ITYP) will be imported

=head3 Returns:

- A hash containing index data for the imported policy lines

=back


=head2 I<getPolicyIndex($type,$name)>

=over 4

The B<getPolicyIndex> function will return the numerical ID/index associated with a provided policy type and name.  This index is how the Symphony database stores references to that policy.  Of note, this function is called by the I<getLibraryIndex>, I<getLocationIndex>, and I<getItemtypeIndex> functions.

=head3 Parameters:

- B<$type>: [REQUIRED] The type of policy to look under

- B<$name>: [REQUIRED] The name of the policy to look for

=head3 Returns:

- The (integer) index associated with the policy

=back


=head2 I<getPolicyData($type,$name)>

=over 4

The B<getPolicyData> function returns the data string associated with a provided policy type and name.  This data contains additional metadata about certain policies that is useful in some scripts.

=head3 Parameters:

- B<$type>: [REQUIRED] The type of policy to look under

- B<$name>: [REQUIRED] The name of the policy to look for

=head3 Returns:

- The pipe-delimited string of data associated with the policy

=back


=head2 I<getLibraryIndex($name)> I<getLocationIndex($name)> I<getItemtypeIndex($name)>

=over 4

The B<getLibraryIndex>, B<getLocationIndex>, and B<getItemtypeIndex> functions will return the index of the policy associated with the given name.  

=head3 Parameters:

- B<$type>: [REQUIRED] The name of the library, location, or item type to get the index for

=head3 Returns:

- The (integer) index associated with the library, location, or item type policy


=head2 I<isLocationShadowed($name)>

=over 4

The B<isLocationShadowed> function will return a boolean value indicating whether a location is shadowed.

=head3 Parameters:

- B<$name>: [REQUIRED] The name of the location to get the shadow flag for

=head3 Returns:

- A boolean representing the shadow state of the location. 1 (TRUE) indicates a location is shadowed; 0 (FALSE) indicates it is not shadowed

=back


=head1 Author/License

(c) Brigham Young University, 2013.

This file is part of the Ostinato Perl Library for SirsiDynix Symphony, developed independently by Brigham Young University.

This work is licensed under the Creative Commons Attribution-ShareAlike 3.0 Unported License. To view a copy of this license, visit http://creativecommons.org/licenses/by-sa/3.0/.
