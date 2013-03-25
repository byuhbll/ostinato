package Ostinato::Export;

use Ostinato::Filter;

our $VERSION="2.0.0";

#Some class-level definitions
use constant MAX_QUERY_LENGTH => 10000;
use constant KEYS_PER_QUERY   => 500;
use constant FORMAT_MARC => 0;
use constant FORMAT_FLAT => 1;
use constant FORMAT_XML  => 2;
use constant WHERE  => 0;
use constant SELECT => 1;


sub new
{
	my $class = shift;
	my $self  = {};
	bless($self,$class);

#Tie the instantiated class to an existing Ostinato class or create a new one and tie them together
	$self->{env} = shift;
	if(!defined $self->{env}) { $self->{env} = new Ostinato(); }
	if(!defined $self->{env}->{class}->{filter}) { $self->{env}->{class}->{filter} = new Ostinato::Filter($self->{env}); }

	return $self;
}


sub createSQLFilter
{
	my $self = shift;
	my $args = shift;

	my $sqlStatement = "";
	my $filterId   = (defined $args->{filter})  ?  $args->{filter}  :  undef;
	my $filterType = (defined $args->{type})    ?  $args->{type}    :  WHERE;

	my $logicalOperator;
	my $compareOperator;
	my $filter = $self->{env}->{class}->{filter}->getFilter($filterId);
	if (defined $args->{table} && defined $args->{column})
	{
		if(defined $filter)
		{
			#Exclusion statement
			if($filter =~ s/\A~|!//)
			{
				$logicalOperator = "and";
				$compareOperator = "!=";
			}
			#Inclusion statement
			else
			{
				$logicalOperator = "or";
				$compareOperator = "=";
			}

			#Construct the SQL statement for each element
			my @filterElements = split(/,/, $filter);
			foreach my $element (@filterElements)
			{
				my $elementIndex = $self->{env}->{class}->{policy}->getPolicyIndex($filterId, $element);
				$element = (defined $elementIndex)  ?  $elementIndex  :  $element;
				$sqlStatement .= " " . $args->{table} . "." . $args->{column} . " $compareOperator '$element' $logicalOperator ";
			}

			#Knock off the last "and"/"or" and wrap the constructed SQL in a single evaluation 
			if($filterType == SELECT)
			{
				return " * MAX(case when(" . substr($sqlStatement, 0, (length($logicalOperator) + 1) * -1) . ") then 1 else 0 end) ";
			}
			else
			{
				return " AND (" . substr($sqlStatement, 0, (length($logicalOperator) + 1) * -1) . ") ";
			}
		}
		else
	   	{
			return "";
		}
	}
	else
	{ 
		Carp::confess("Error creating SQL statement for filter.  Required arguments were either not provided or a corresponding filter has not been created:\nfilter:$filterId\ntable:" . $args->{table} . "\ncolumn:" . $args->{column} . "\n"); 
	}
}


sub appendVisibilityFlag
{
	my $self = shift;
	my $keys_ref = shift;
	my $destination = shift;

	my @keys = @{$keys_ref};
	my $destination = (defined $destination)  ?  $destination  :  $self->{env}->getPath("temp") . "/" . $self->{env}->getEnvId() . ".ostinato.export.determineVisibility.results";

	#Generate needed filters
	my $libraryFilter = $self->createSQLFilter({
		table  => "cnm",
		column => "LIBRARY",
		filter => Ostinato::Policy::LIBRARY,
		type   => SELECT,
	});
	my $currentLocationFilter = $self->createSQLFilter({
		table  => "itm",
		column => "CURRENT_LOCATION",
		filter => Ostinato::Policy::LOCATION,
		type   => SELECT,
	});
	my $homeLocationFilter = $self->createSQLFilter({
		table  => "itm",
		column => "HOME_LOCATION",
		filter => Ostinato::Policy::LOCATION,
		type   => SELECT,
	});
	my $itemtypeFilter = $self->createSQLFilter({
		table  => "itm",
		column => "TYPE",
		filter => Ostinato::Policy::ITEMTYPE,
		type   => SELECT,
	});
	my $shadowFilter = "(1 - MIN(cat.SHADOW + case when cnm.SHADOW is null then 1 else cnm.SHADOW end + case when itm.SHADOW is null then 0 else itm.SHADOW end))";

	#Split the keys into smaller chunks if required
	my $numberOfSplitsRequired = int((scalar(@keys) - 1) / (KEYS_PER_QUERY));
	my $splitIndex = 0;
	while($splitIndex <= $numberOfSplitsRequired)
	{
		my $indexStart = $splitIndex * KEYS_PER_QUERY;
		my $indexEnd   = ($splitIndex == $numberOfSplitsRequired)  ?  scalar(@keys) - 1  :  ($splitIndex + 1) * KEYS_PER_QUERY - 1;
		my $keyString = (join ',', @keys[$indexStart .. $indexEnd]);

		#Construct and run query
		my $query = "select cat.CATALOG_KEY as catkey, $shadowFilter $libraryFilter $currentLocationFilter $homeLocationFilter $itemtypeFilter as visibility " . 
		"from SIRSI.CATALOG cat left join SIRSI.CALLNUM cnm " .
		"on cat.CATALOG_KEY = cnm.CATALOG_KEY left join SIRSI.ITEM itm on cnm.CATALOG_KEY = itm.CATALOG_KEY and cnm.CALL_SEQUENCE = itm.CALL_SEQUENCE " . 
		"where cat.CATALOG_KEY in ($keyString) " . 
		"group by cat.CATALOG_KEY";

		if(length $query > MAX_QUERY_LENGTH)
		{
			Carp::confess("Due to limitations in the the sirsisql API, queries must be limited to " . MAX_QUERY_LENGTH . " characters or less.  Please reduce the number of keys being queried at any given time:\nQuery:\n" . $query);
		}

		my $queryfile = $self->{env}->getPath("temp") . "/" . $self->{env}->getEnvId() . ".ostinato.export.determineVisibility.query";
		open QUERYFILE, ">", $queryfile;
		print QUERYFILE $query;
		close(QUERYFILE);

		my $cmd = "cat $queryfile | sirsisql >>$destination 2>>" . $self->{env}->getPath("log");
		system($cmd);

		$splitIndex++;
	}

	return $destination;
}


sub splitByVisibility
{
	my $self = shift;
	my $args = shift;

	#Create the keys array from the parameters
	my @keys = (defined $args->{keys})  ?  @{$args->{keys}}  :  ();
	if(!@keys)
	{
		my $source = (defined $args->{source})  ?  $args->{source}  :  undef;
		if(defined $source)
		{
			open SOURCE,       "<", $source or Carp::confess("Unable to open file: $source");
			@keys = <SOURCE>;
			close(SOURCE);
			chomp(@keys);
			if(substr($keys[0], -1, 1) eq '|')
			{
				chop(@keys);
			}
		}
	}
	
	#Die if there are no keys to consider
	if(!@keys)
	{
		Carp::confess("Required arguments not provided or no keys were found");
	}

	my $visibilityFile = $self->appendVisibilityFlag(\@keys);
	my $destinationPrefix = (defined $args->{destination})  ?  $args->{destination}  :  $self->{env}->getPath("temp") . "/" . $self->{env}->getEnvId() . ".ostinato.export.splitByVisibility.results";
	my @destination = ($destinationPrefix . ".visible", 
	                   $destinationPrefix . ".hidden");

	#Iterate through the appended file and split based on the second column
	open VISIBILITYFLAGS, "<", $visibilityFile or Carp::confess("Unable to open file: $visibilityFile");
	open DEST_VISIBLE,    ">", $destination[0] or Carp::confess("Unable to open file: " . $destination[0]);
	open DEST_HIDDEN,     ">", $destination[1] or Carp::confess("Unable to open file: " . $destination[1]);
	while (my $line = <VISIBILITYFLAGS>)
	{
		if($line =~ /\A.*?\|1\|/)  {  print DEST_VISIBLE $line;  } 
		else                       {  print DEST_HIDDEN  $line;  }
	}
	close(VISIBILITYFLAGS);
	close(DEST_VISIBLE);
	close(DEST_HIDDEN);

	return @destination;
}


sub catalogdump
{
	my $self = shift;
	my $args = shift;

	#Sort out the pathing based on the parameters
	if(!(defined $args->{source} && -s $args->{source}))
	{
		Carp::confess("Source file not provided or not found: $source");
	}
	my $destination = (defined $args->{destination})  ?  $args->{destination}  :  $self->{env}->getPath("temp") . "/" . $self->{env}->getEnvId() . ".ostinato.export.catalogdump.results";
	print "DESTINATION: $destination\n";

	#Set the format based on the parameters
	$format = (defined $args->{format})  ?  $args->{format}  :  FORMAT_MARC;
	my $formatHandler = ($format == FORMAT_MARC)  ?  "-om"  :
	                    ($format == FORMAT_XML)   ?  "-om | " . $self->{env}->getPath("yaz") . " -f utf8 -o marcxml " . Ostinato::STDIN_PATH  :
						"-of";

	my $libraryFilter = $self->{env}->{class}->{filter}->getFilter(Ostinato::Policy::LIBRARY);
	$libraryFilter = (defined $libraryFilter)  ?  "-y $libraryFilter"  :  "";

	my $cmd = "cat " . $args->{source} . " | sort -u | catalogdump -h -i -kf -ku002 $libraryFilter 2>>" . $self->{env}->getPath("log") . " $formatHandler >$destination"; 
	system($cmd);

	return $destination;
}


#This code will be moved to the new Exporter (Chromatic).  There is no general solution to the boundwith problem.  It is dependent on an XML export so far...
#sub identifyBoundwiths
#{
#	my $self     = shift;
#	my $keys_ref = shift;
#
#	my $destination = $self->{env}->getPath("temp") . "/" . $self->{env}->getEnvId() . ".ostinato.export.identifyBoundwiths.results";
#
#	my @keys = @{$keys_ref};
#	my $libraryFilter = $self->createSQLFilter({
#		table  => "bnd",
#		column => "LIBRARY",
#		filter => Ostinato::Policy::LIBRARY,
#		type   => WHERE,
#	});
#
#	#Split the keys into smaller chunks if required
#	my $numberOfSplitsRequired = int((scalar(@keys) - 1) / (KEYS_PER_QUERY));
#	my $splitIndex = 0;
#	while($splitIndex <= $numberOfSplitsRequired)
#	{
#		my $indexStart = $splitIndex * KEYS_PER_QUERY;
#		my $indexEnd   = ($splitIndex == $numberOfSplitsRequired)  ?  scalar(@keys) - 1  :  ($splitIndex + 1) * KEYS_PER_QUERY - 1;
#		my $keyString = (join ',', @keys[$indexStart .. $indexEnd]);
#
#		#Construct and run query
#		my $query = "select PARENT_CATALOG_KEY, PARENT_CALL_SEQUENCE, CHILD_CATALOG_KEY, CHILD_CALL_SEQUENCE " .
#		            "from SIRSI.BOUND bnd " . 
#		            "where bnd.CHILD_CATALOG_KEY in ($keyString) or bnd.PARENT_CATALOG_KEY in ($keyString) $libraryFilter";
#
#		if(length $query > MAX_QUERY_LENGTH)
#		{
#			Carp::confess("Due to limitations in the the sirsisql API, queries must be limited to " . MAX_QUERY_LENGTH . " characters or less.  Please reduce the number of keys being queried at any given time:\nQuery:\n" . $query);
#		}
#
#		my $queryfile = $self->{env}->getPath("temp") . "/" . $self->{env}->getEnvId() . ".ostinato.export.identifyBoundwiths.query";
#		open QUERYFILE, ">", $queryfile;
#		print QUERYFILE $query;
#		close(QUERYFILE);
#
#		my $cmd = "cat $queryfile | sirsisql >>$destination 2>>" . $self->{env}->getPath("log");
#		system($cmd);
#
#		$splitIndex++;
#	}
#}


__END__


=pod


=head1 NAME

Ostinato::Export - Provides additional options related to exporting data


=head1 SYNOPSIS

  #Importing the module
  use lib "path/to/ostinato";  #Only required if module is not in the Perl include path already
  use Ostinato::Export;

  #Create a new instance of the class.  An existing instance of the Ostinato class can be provided, or a new one will be created
  my $exporter = new Ostinato::Export($ostinato_instance);

  #Sample function calls
  my ($visibleKeysFile, $hiddenKeysFile) = $exporter->splitByVisibility({
      source      => "data.in",
	  destination => "data.out",
  })
  my $catalogDumpFile = $exporter->catalogdump({
      source => $visibleKeysFile,
	  format => Ostinato::Export::FORMAT_XML,
  });


=head1 DESCRIPTION

This module processes and exports data from Symphony.  It contains functions designed to establish visibility/shadowing, boundwith links, and other data not included in Symphony's built-in catalogdump API.  It was written specifically for exporting to BYU's Lime Importer for Primo, but may have relevancy elsewhere too.

WARNING: This library has serious potential to damage your system if not used carefully.  Make sure you know what you're doing, and restrict access to trusted users only.

=head1 DEPENDENCIES

This module requires the Ostinato::Filter module, and inherits its dependencies.


=head1 FUNCTIONS

=head2 I<new($ostinatoInstance)>

=over 4

The B<new> function creates a new instance of the Ostinato::Export module as a class.  It will import or create a parent Ostinato module and associate itself with it.  If an Ostinato::Filter instance is not associated with the parent Ostinato module, one will be created, since that class is required for proper functioning of the Export class.

=head3 Parameters:

- B<$ostinatoInstance>: [OPTIONAL] An existing instance of the Ostinato class.  If left blank, a new instance of the Ostinato class will be created and associated with this class.

=head3 Returns:

- A reference to the now-instantiated and blessed Ostinato::Export class

=back


=head2 I<createSQLFilter($args)>

=over 4

The B<createSQLFilter> function will create a filter in the select statement based off an existing Ostinato Filter.

=head3 Parameters:

B<Note: Parameters for this function should be provided in hash form>

- B<table>: [REQUIRED] The name of the table to search for the filter in.

- B<column>: [REQUIRED] The column of the table that the filter is associated with.

- B<filter>:  [REQUIRED] The identifier of the Ostinato Filter to check against.

=head3 Returns:

- The string containing the SQL Statement associated with the filter.

=back


=head2 I<appendVisibilityFlag($keys_ref)>

=over 4

The B<appendVisibilityFlag> function will figure out whether a catalog record should be "visible" in an export meant to be seen by patrons (such as an export to a discovery layer).  The Symphony database will be queried using the I<sirsisql> API.  Shadow flags at the Title/Catalog, Callnum, and Item levels will be checked.  Additionally at the item level, only items matching the currently set filters for libraries, locations, and item types will calculate as visible.  In order to be "visible", a record must have at least one item (or at least one call number with no items underneath it - such as boundwiths) that is visible.  Of note, this function is called by the I<splitByVisibility> function.

=head3 Parameters:

- B<$keys_ref>: [REQUIRED] A reference to an array containing the catalog keys of the records to determine visibility for.

- B<$destination>: [OPTIONAL] The path to the desired destination, if the default destination in the temp directory is not satisfactory.

=head3 Returns:

- The path to the pipe-delimited file returned by the database, containing the keys with their visibility flag.  A true/1 flag indicates an item should be visible to the public; a false/0 flag indicates the opposite.  If a catalog key does not exist in the database, it will be omitted from the file.

=back


=head2 I<splitByVisibility($args)>

=over 4

The B<splitByVisibility> function takes a set of keys and writes them to two files, depending on their visibility (as calculated by the I<appendVisibilityFlag> function logic).

=head3 Parameters:

B<Note: Parameters for this function should be provided in hash form>

B<Note: Either (but not both) of the following two parameters are required.>

- B<keys>: [REQUIRED/OPTIONAL] An array reference containing keys to be split.  If this argument is not provided, then the B<source> argument is required.

- B<source>: [REQUIRED/OPTIONAL] The path to a file containing keys to be split.  This argument will only be considered if the B<keys> argument is not provided.

- B<destination>: [OPTIONAL] The path to the desired destination, if the default destination in the temp directory is not satisfactory.  If set, The actual resulting files will be named $path.visible and $path.hidden, respectively.

=head3 Returns:

An array containing two filepaths.  Element [0] contains the path to the file containing visible keys, and element [1] points to the hidden keys filepath.

=back


=head2 I<catalogdump($args)>

=over 4

The B<catalogdump> function will export a set of full bibliographic records using the catalogdump API (with prepopulated settings).

=head3 Parameters:

B<Note: Parameters for this function should be provided in hash form>

- B<source>: [REQUIRED] The path to the file containing the keys to be exported.

- B<destination>: [OPTIONAL] The path to the desired destination, if the default destination in the temp directory is not satisfactory.

- B<format>: [OPTIONAL] The format to export the records in.  Valid options include are defined by the following class constants: FORMAT_MARC, FORMAT_XML, FORMAT_FLAT.  If this argument is not provided, the records will export by default in the FLAT format.


=head1 Author/License

(c) Brigham Young University, 2013.

This file is part of the Ostinato Perl Library for SirsiDynix Symphony, developed independently by Brigham Young University.

This work is licensed under the Creative Commons Attribution-ShareAlike 3.0 Unported License. To view a copy of this license, visit http://creativecommons.org/licenses/by-sa/3.0/.
