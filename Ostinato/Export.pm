package Ostinato::Export;

use Ostinato::Filter;
use Data::Dumper;

our $VERSION="2.1.0";

#Some class-level definitions
use constant MAX_QUERY_LENGTH => 10000;
use constant KEYS_PER_QUERY   => 500;
use constant FORMAT_MARC => "marc";
use constant FORMAT_FLAT => "flat";
use constant FORMAT_XML  => "marcxml";
use constant FORMAT_RAW  => "raw";
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

	my $destination = defined($destination)  ?  $destination  :  $self->{env}->getPath("temp") . "/" . $self->{env}->getEnvId() . ".ostinato.export.appendVisibilityFlag.results";

	$keys = $self->calculateVisibility($keys_ref);
	keys %$keys;

	open DESTFILE, ">", $destination;
	while(my($key, $visibility) = each %$keys)
	{
		print DESTFILE "$key|$visibility|\n";
	}
	close(DESTFILE);
	return $destination;
}

sub calculateVisibility 
{
	my $self = shift;
	my $keys_ref = shift;

	my %keys = map { $_ => 0 } @{$keys_ref};
	my $results = $self->{env}->getPath("temp") . "/" . $self->{env}->getEnvId() . ".ostinato.export.calculateVisibility.results";

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
	my $numKeys = keys %keys;
	my $keyString = "";
	my $localCount  = 0;
	my $globalCount = 0;

	while(($catkey, $visibility) = each %keys)
	{
		#Remove empty elements from the hash
		if (not length($catkey)) {
			delete $keys{$catkey};
			$numKeys--;
			next;
		}

		$keyString .= "$catkey,";
		if($localCount > KEYS_PER_QUERY || $globalCount >= ($numKeys - 1))
		{
			chop($keyString);
			my $query = "select cat.CATALOG_KEY as catkey, $shadowFilter $libraryFilter $currentLocationFilter $homeLocationFilter $itemtypeFilter as visibility " . 
			"from SIRSI.CATALOG cat left join SIRSI.CALLNUM cnm " .
			"on cat.CATALOG_KEY = cnm.CATALOG_KEY left join SIRSI.ITEM itm on cnm.CATALOG_KEY = itm.CATALOG_KEY and cnm.CALL_SEQUENCE = itm.CALL_SEQUENCE " . 
			"where cat.CATALOG_KEY in ($keyString) " . 
			"group by cat.CATALOG_KEY";

			if(length $query > MAX_QUERY_LENGTH)
			{
				Carp::confess("Due to limitations in the the sirsisql API, queries must be limited to " . MAX_QUERY_LENGTH . " characters or less.  Please reduce the number of keys being queried at any given time:\nQuery:\n" . $query);
			}

			my $queryfile = $self->{env}->getPath("temp") . "/" . $self->{env}->getEnvId() . ".ostinato.export.calculateVisibility.query";
			open QUERYFILE, ">", $queryfile;
			print QUERYFILE $query;
			close(QUERYFILE);

			my $cmd = "cat $queryfile | sirsisql >>$results 2>>" . $self->{env}->getPath("log");
			system($cmd);

			$localCount = -1;
			$keyString = "";
		}
		$localCount++;
		$globalCount++;
	}

	open RESULTFILE, '<', $results;
	while($line = <RESULTFILE>)
	{
		chomp($line);
		if(length($line))
		{
			@fields = split(/\|/, $line);
			$keys{$fields[0]} = $fields[1];
		}
	}
	close RESULTFILE;
	return \%keys;
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

	my $visibilityMap = $self->calculateVisibility(\@keys);
	my $destinationPrefix = (defined $args->{destination})  ?  $args->{destination}  :  $self->{env}->getPath("temp") . "/" . $self->{env}->getEnvId() . ".ostinato.export.splitByVisibility.results";
	my @destination = ($destinationPrefix . ".visible", 
	                   $destinationPrefix . ".hidden");

	#Iterate through the appended file and split based on the second column
	open DEST_VISIBLE,    ">", $destination[0] or Carp::confess("Unable to open file: " . $destination[0]);
	open DEST_HIDDEN,     ">", $destination[1] or Carp::confess("Unable to open file: " . $destination[1]);
	while (($key, $visibility) = each %$visibilityMap)
	{
		if($visibility) { print DEST_VISIBLE "$key|\n"; }
		else            { print DEST_HIDDEN  "$key|\n";  }
	}
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
		Carp::confess("Source file not provided or not found.");
	}
	my $destination = (defined $args->{destination})  ?  $args->{destination}  :  $self->{env}->getPath("temp") . "/" . $self->{env}->getEnvId() . ".ostinato.export.catalogdump.results";

	#Set the format based on the parameters
	$format = (defined $args->{format})  ?  $args->{format}  :  FORMAT_MARC;
	my $formatHandler = ($format eq FORMAT_MARC)  ?  "-om"  :
	                    ($format eq FORMAT_XML)   ?  "-om | " . $self->{env}->getPath("yaz") . " -f utf8 -o marcxml " . Ostinato::STDIN_PATH  :
						"-of";

	#Include MARC Holdings if requested
	my $includeHoldings = (defined $args->{holdings} && $args->{holdings} == Ostinato::TRUE)  ?  "-lALL_MARCS"  :  "";

	my $libraryFilter = $self->{env}->{class}->{filter}->getFilter(Ostinato::Policy::LIBRARY);
	$libraryFilter = (defined $libraryFilter)  ?  "-y $libraryFilter"  :  "";

	$catkeyPrefix = $self->{env}->getMarc("catkeyPrefix");
	if($catkeyPrefix != 'a' && $catkeyPrefix != 'u') {
		$catkeyPrefix = 'c';
	}
	my $cmd = "cat " . $args->{source} . " | sort -u | catalogdump -h -i -kf -k$catkeyPrefix" . $self->{env}->getMarc("catkey") . " $libraryFilter $includeHoldings 2>>" . $self->{env}->getPath("log") . " $formatHandler >$destination"; 
	system($cmd);

	return $destination;
}

sub createEmptyRecord 
{
	my $self = shift;
	my $args = shift;

	#Sort out the pathing based on the parameters
	if(!(defined $args->{source} && -s $args->{source}))
	{
		Carp::confess("Source file not provided or not found.");
	}
	my $destination = (defined $args->{destination})  ?  $args->{destination}  :  $self->{env}->getPath("temp") . "/" . $self->{env}->getEnvId() . ".ostinato.export.createEmptyRecord.results";

	#Set the format based on the parameters
	$format = (defined $args->{format})  ?  $args->{format}  :  FORMAT_MARC;
	if($format eq FORMAT_FLAT) {
		$self->_convertKeysToFlat($args->{source}, $destination);
	}
	elsif($format eq FORMAT_XML)
	{
		$self->_convertKeysToMarcXML($args->{source}, $destination);
	}
	elsif($format eq FORMAT_RAW)
	{
		my $cmd = "cp \"" . $args->{source} . "\" \"$destination\"";
		system($cmd);
	}
	else
	{
		$marcXmlFile = $self->{env}->getPath("temp") . "/" . $self->{env}->getEnvId() . ".ostinato.export.createEmptyRecord.marcxml";

		$self->_convertKeysToMarcXML($args->{source}, $marcXmlFile);
		$self->_convertMarcXMLToMarc($marcXmlFile, $destination);
	}

	return $destination;
}

#This function is designed for internal use only and wraps up catalog keys in a FLAT strcture.
#The tag and prefix of the key is pulled from the Ostinato configuration.
sub _convertKeysToFlat {
	my $self = shift;
	my $source = shift;
	my $destination = shift;
		
	open DESTFILE, '>', $destination or Carp::confess("Unable to open destination file for writing: $destination");
	open SRCFILE, '<', $source;

	while (<SRCFILE>)
	{
		my $recordKey = substr $_, 0, -2;

		print DESTFILE "*** DOCUMENT BOUNDARY ***" .
			"\nFORM=MARC" . 
			"\n" . $self->{env}->getMarc("catkey") . ". |a" . $self->{env}->getMarc("catkeyPrefix") . "$recordKey" .
			"\n";
	}

	close (SRCFILE);
	close (DESTFILE);
}

#This function is designed for internal use only and wraps up catalog keys in a MARCXML strcture.
#The tag and prefix of the key is pulled from the Ostinato configuration.
sub _convertKeysToMarcXML 
{
	my $self = shift;
	my $source = shift;
	my $destination = shift;
		
	open DESTFILE, '>', $destination or Carp::confess("Unable to open destination file for writing: $destination");
	print DESTFILE "<collection xmlns=\"http://www.loc.gov/MARC21/slim\">";
	open SRCFILE, '<', $source;

	while (<SRCFILE>)
	{
		my $recordKey = substr $_, 0, -2;

		print DESTFILE "\n<record>" .
			"\n\t<controlfield tag=\"" . $self->{env}->getMarc("catkey") . "\">" . $self->{env}->getMarc("catkeyPrefix") . "$recordKey</controlfield>" . 
			"\n\t<status>deleted</status>" . 
			"\n</record>";
	}

	print DESTFILE "\n</collection>";
	close (SRCFILE);
	close (DESTFILE);
}

#This function is designed for internal use only and converts MARCXML to MARC using the yaz-marcdump utility
sub _convertMarcXMLToMarc
{
	my $self = shift;
	my $source = shift;
	my $destination = shift;

	$cmd = "cat $source | " . $self->{env}->getPath("yaz") . " -i marcxml -f utf8 -o marc -t utf8 " . Ostinato::STDIN_PATH . " >$destination";
	system($cmd);
}


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

The B<appendVisibilityFlag> function uses the I<calculateVisibility> logic to determine if a record should be "visibile" to patrons.  It saves the results of the I<calculateVisibility> to a file and is maintained for backwards compatibility with previous versions of Ostinatohistorical reasons.

=head3 Parameters:

- B<$keys_ref>: [REQUIRED] A reference to an array containing the catalog keys of the records to determine visibility for.

- B<$destination>: [OPTIONAL] The path to the desired destination, if the default destination in the temp directory is not satisfactory.

=head3 Returns:

- The path to the pipe-delimited file returned by the database, containing the keys with their visibility flag.  A true/1 flag indicates an item should be visible to the public; a false/0 flag indicates the opposite.

=back

=head2 I<calculateVisibility($keys_ref)>

=over 4

The B<calculateVisibility> function will figure out whether a catalog record should be "visible" in an export meant to be seen by patrons (such as an export to a discovery layer).  The Symphony database will be queried using the I<sirsisql> API.  Shadow flags at the Title/Catalog, Callnum, and Item levels will be checked.  Additionally at the item level, only items matching the currently set filters for libraries, locations, and item types will calculate as visible.  In order to be "visible", a record must have at least one item (or at least one call number with no items underneath it - such as boundwiths) that is visible.  Of note, this function is called by the I<splitByVisibility> function.

=head3 Parameters:

- B<$keys_ref>: [REQUIRED] A reference to an array containing the catalog keys of the records to determine visibility for.

=head3 Returns:

A hash map with the following structure:  {B<catalog_key> => B<visibility_boolean>}

=back


=head2 I<splitByVisibility($args)>

=over 4

The B<splitByVisibility> function takes a set of keys and writes them to two files, depending on their visibility (as calculated by the I<calculateVisibility> function logic).

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

- B<format>: [OPTIONAL] The format to export the records in.  Valid options include are defined by the following class constants: FORMAT_MARC, FORMAT_XML, FORMAT_FLAT.  If this argument is not provided, the records will export by default in the MARC (transmission) format.

=head2 I<createEmptyRecord($args)>

=over 4

The B<createEmptyRecord> function will export a set of single-field bibliographic records by wrapping catalog keys in MARC, FLAT, or MARCXML format.

=head3 Parameters:

B<Note: Parameters for this function should be provided in hash form>

- B<source>: [REQUIRED] The path to the file containing the keys to be exported.

- B<destination>: [OPTIONAL] The path to the desired destination, if the default destination in the temp directory is not satisfactory.

- B<format>: [OPTIONAL] The format to export the records in.  Valid options include are defined by the following class constants: FORMAT_MARC, FORMAT_XML, FORMAT_FLAT.  If this argument is not provided, the records will export by default in the MARC (transmission) format.


=head1 Author/License

This file is part of the Ostinato Perl Library for SirsiDynix Symphony, developed independently by Brigham Young University.  

License information is available in the Ostinato LICENSE.md document.
