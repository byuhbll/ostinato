package Ostinato::Transaction;

use Ostinato;
use POSIX qw(strftime);
use Date::Parse;
use File::Copy;

our $VERSION="2.0.1";

#Some class-level definitions
use constant ONE_DAY  => 86400;
use constant DUPLICATE_IGNORE => 0;
use constant DUPLICATE_COUNT  => 1;
use constant DUPLICATE_REMOVE => 2;

sub new
{
	my $class = shift;
	my $self  = {};
	bless($self,$class);

#Tie the instantiated class to an existing Ostinato class or create a new one and tie them together
	$self->{env} = shift;
	if(!defined $self->{env}) { $self->{env} = new Ostinato(); }

	#Init some required variables
	$self->{source} = $self->{env}->getPath("temp") . "/" . $self->{env}->getEnvId() . ".ostinato.transaction.source";
	$self->setDates(0, time());
	$self->{updateBarcodes} = "php " . $self->{env}->getPath("barcodeReplacer");

	return $self;
}

sub setDates
{
	my $self = shift;
	my $dateStart = shift;
	my $dateEnd = shift;

	if(defined $dateStart && $dateStart =~ /\A[0-9]+\z/)
	{
		$self->{dateStart} = $dateStart;
		$self->{dateStart_formatted} = POSIX::strftime "%Y%m%d", localtime($dateStart);
	}
	else
	{
		Carp::confess("dateStart was not provided or is not a valid unix timestamp (integer)");
	}
	
	if(defined $dateEnd && $dateEnd =~ /\A[0-9]+\z/ && $dateEnd > $dateStart)
	{
		$self->{dateEnd} = $dateEnd;
		$self->{dateEnd_formatted} = POSIX::strftime "%Y%m%d", localtime($dateEnd);
	}
	else
	{
		Carp::confess("dateEnd was not provided, is not a valid unix timestamp (integer), or occurs before dateStart");
	}

	$self->{env}->printToLog("Transaction dates updated.\n\tStart: " . $self->{dateStart_formatted} . "\n\tEnd: " . $self->{dateEnd_formatted});
	return $dateEnd-$dateStart;
}

sub setSource
{
	my $self = shift;
	my $source = shift;

	if(-s $source)
	{
		$self->{source} = $source;
	}
	else
	{
		Carp::confess("Unable to change data source.  File does not exist or is empty: \"$source\"");
	}

	return $source;
}

sub identifyRelevantLogs
{
	my $self      = shift;

	$self->{env}->printToLog("Retrieving a list of history files between " . $self->{dateStart_formatted} . " and " . $self->{dateEnd_formatted});
	my $dirHist = `getpathname hist`;
	chomp $dirHist;

	my $dateCurrent = POSIX::strftime "%Y%m%d", localtime;
	my $dateIter = $self->{dateStart};
	my %filenames = ();
	my @filesArray = ();
	while($dateIter <= $self->{dateEnd})
	{
		my $dateFormatted  = POSIX::strftime "%Y%m%d", localtime($dateIter);
		if($dateFormatted >= $dateCurrent)
		{
			$filenames{$dateFormatted} = "$dateFormatted.hist";
		}
		else
		{
			my $monthFormatted = POSIX::strftime "%Y%m", localtime($dateIter);
			$filenames{$monthFormatted} = "$monthFormatted.hist.Z";	
		}
		$dateIter += ONE_DAY;
	}

	foreach(values %filenames)
	{
		if(-s "$dirHist/$_")
		{
			push(@filesArray, "$dirHist/$_");
		}
	}
	return \@filesArray;
}

sub autoprepare
{
	my $self      = shift;
	my $dateStart = shift;
	my $dateEnd   = shift;

	if(defined $dateStart && defined $dateEnd) { $self->setDates($dateStart,$dateEnd); }

	my $logfile = $self->{env}->getPath("log");
	$self->{env}->printToLog("Extracting all history files between " . $self->{dateStart_formatted} . " and " . $self->{dateEnd_formatted} . " to temp directory");

	my @filenames = @{$self->identifyRelevantLogs($self->{dateStart}, $self->{dateEnd})};
	foreach my $oldFilepath (@filenames)
	{
		my $filename = (File::Basename::fileparse($oldFilepath))[0];

		#If the file is in the compressed format
		if(substr $oldFilepath, -2, 2)
		{
			my $cmd = "cat $oldFilepath 2>>$logfile | squeeze -d >>" . $self->{source} . " 2>>$logfile";
			system($cmd);
		}
		#if the file is uncompressed
		else
		{
			open INFILE,  '<', $oldFilepath;
			open OUTFILE, '>>', $oldFilepath;
			while(<INFILE>) { print OUTFILE $_; }
			close(INFILE);
			close(OUTFILE);
		}
	}

	return $self->{source};
}

sub extractdata
{
	my $self = shift;
	my $args = shift;

	#Import/define pathing information
	my $destination = (defined $args->{destination})  ?  $args->{destination}  :  $self->{env}->getPath("temp") . "/" . $self->{env}->getEnvId() . ".ostinato.transaction.extractdata.data";
	my $logfile     = $self->{env}->getPath("log");

	#Import data parameters
	my $cmdcode     = (defined $args->{cmdcode  })  ?  "-c \"" . $args->{cmdcode  } . "\""  :  "";
	my $datacode    = (defined $args->{datacode })  ?  "-d \"" . $args->{datacode } . "\""  :  "";
	my $cmdsuffix   = (defined $args->{command  })  ?  "| "   . $args->{command  }         :  "";
	
	#Construct the output codes
	my $outcode;
	my $parseDate = "";
	if (defined $args->{timestamp} && $args->{timestamp})
	{
		$outcode   = (defined $args->{outcode  })  ?  "-o\"" . $args->{outcode} . ",K\""  :  "";
		#This sed command will strip out the transaction output by the -oK output flag in seltrans, leaving only the date
		$parseDate = '| sed -r \'s/E([0-9]{14})....R \\^.*/\\1/\'';
	}
	else

	{
		$outcode     = (defined $args->{outcode  })  ?  "-o\"" . $args->{outcode} . "\""  :  "";
	}

	#If duplicate counting is requested
	my $duplicateAction   = (defined $args->{duplicates})  ? $args->{duplicates} : DUPLICATES_IGNORE;
	my $duplicateHandler = ($duplicateAction == DUPLICATE_COUNT)   ?  "| uniq -c | sed 's/\\s*\\([0-9]\\+\\)\\s*/\\1\\|/' | sort -gr"  :
	                       ($duplicateAction == DUPLICATE_REMOVE)  ?  "| uniq"  :
	                       "";

	#Construct the command using the provided parameters
	$self->{env}->printToLog("Extracting data from transaction logs:\n\tcmdcode:$cmdcode\n\tdatacode:$datacode\n\toutcode:$outcode\n\tcmdsuffix:$cmdsuffix");

	my $cmd = "cat \"" . $self->{source} . "\" | seltrans -s" . $self->{dateStart_formatted} . " -e" . $self->{dateEnd_formatted} . " $cmdcode $datacode $outcode 2>>\"$logfile\" $parseDate $cmdsuffix $duplicateHandler >>\"$destination\";";
	$self->{env}->printToLog("Command to be run:\n\t" . $cmd);
	system($cmd);

	return $destination;
}

sub extractBarcodeChangeMap
{
	my $self = shift;
	my $args = shift;

	my $destination = (defined $args->{destination})  ?  $args->{destination}  :  $self->{env}->getPath("temp") . "/" . $self->{env}->getEnvId() . ".ostinato.transaction.extractBarcodeChangeMap";
	my $logfile = $self->{env}->getPath("log");

	my $outfile = $self->extractdata({
		destination => $destination,
		cmdcode     => "IV",
		datacode    => "NR~AUTO",
		outcode     => "NQ,NR",
		timestamp   => $args->{timestamp}
	});
	return $outfile;
}

sub extractKeysOfAllAvailabilityChanges
{
	my $self    = shift;
	my $args    = shift;

	my $destination = (defined $args->{destination})  ?  $args->{destination}  :  $self->{env}->getPath("temp") . "/" . $self->{env}->getEnvId() . ".ostinato.transaction.extractAvailabilityChanges";
	my $outcode    = (defined($args->{includepatron} && $args->{includepatron}))  ?  "NQ,UO"  :  "NQ";
	my $logfile = $self->{env}->getPath("log");

	my $outfile = $self->extractdata({
		destination => $destination,
		cmdcode     => "CV,RV,CX,RX,EV",
		outcode     => $outcode,
		duplicates  => $args->{duplicates},
		command     => $self->{updateBarcodes} . " 2>>$logfile | selitem -iB -oC 2>>$logfile",
	});
	return $outfile;
}

sub extractKeysOfChargedRecords
{
	my $self    = shift;
	my $args    = shift;
	
	my $destination = (defined $args->{destination})  ?  $args->{destination}  :  $self->{env}->getPath("temp") . "/" . $self->{env}->getEnvId() . ".ostinato.transaction.extractKeysOfChargedRecords";
	my $outcode    = (defined($args->{includepatron} && $args->{includepatron}))   ?  "NQ,UO"  :  "NQ";
	my $logfile = $self->{env}->getPath("log");

	my $outfile = $self->extractdata({
		destination => $destination,
		cmdcode     => "CV",
		outcode     => $outcode,
		duplicates  => $args->{duplicates},
		command     => $self->{updateBarcodes} . " 2>>$logfile | selitem -iB -oC 2>>$logfile",
	});
	return $outfile;
}

sub extractKeysOfDischargedRecords
{
	my $self    = shift;
	my $args    = shift;
	
	my $destination = (defined $args->{destination})  ?  $args->{destination}  :  $self->{env}->getPath("temp") . "/" . $self->{env}->getEnvId() . ".ostinato.transaction.extractKeysOfDischargedRecords";
	my $logfile = $self->{env}->getPath("log");

	my $outfile = $self->extractdata({
		destination => $destination,
		cmdcode     => "EV",
		outcode     => "NQ",
		duplicates  => $args->{duplicates},
		command     => $self->{updateBarcodes} . " 2>>$logfile | selitem -iB -oC 2>>$logfile",
	});
	return $outfile;
}


1;

__END__


=pod


=head1 NAME

Ostinato::Transaction - Parses data from the Symphony history transaction logs


=head1 SYNOPSIS

  #Importing the module
  use lib "path/to/ostinato";  #Only required if module is not in the Perl include path already
  use Ostinato::Transaction;

  #Create a new instance of the class.  An existing instance of the Ostinato class can be provided, or a new one will be created
  my $history = new Ostinato::Transaction($ostinato_instance);

  #Sample function calls
  $history->autoprepare(1293861601, 1296539999);
  $history->extractKeysOfChargedRecords({
      duplicates     => Ostinato::Transaction::DUPLICATE_REMOVE,
      includepatrons => Ostinato::TRUE,
      timestamp      => Ostinato::TRUE,
  });


=head1 DESCRIPTION

This module parses data from the Symphony transaction logs.  Its use is split into 2 distinct phases: Preparation and Extraction.  The preparation phase prepares the source transaction files for extraction.  Calling the I<autoprepare> function with starting and ending timestamps will expedite the entire preparation phase into a single call, using the relevant Symphony logs as the source.  Alternatively, manually calling the I<setDates> and I<setSource> functions will allow the user to manually define a source.  Once prepared, data can be extracted from the source.  The I<extractdata> function will allow complete customization of the data extraction.  Additional functions are available with predefined, common extraction settings.

WARNING: This library has serious potential to damage your system if not used carefully.  Make sure you know what you're doing, and restrict access to trusted users only.

=head1 DEPENDENCIES

This module requires the parent Ostinato module, and inherits its dependencies.

Additionally, this module requires the following Perl/CPAN modules:

- POSIX

- Date::Parse

- File::Copy

- Switch


=head1 FUNCTIONS

=head2 I<new($ostinatoInstance)>

=over 4

The B<new> function creates a new instance of the Ostinato::Transaction module as a class.  It will import or create a parent Ostinato module and associate itself with it.

=head3 Parameters:

- B<$ostinatoInstance>: [OPTIONAL] An existing instance of the Ostinato class.  If left blank, a new instance of the Ostinato class will be created and associated with this class.

=head3 Returns:

- A reference to the now-instantiated and blessed Ostinato::Transaction class

=back

B<PREPARATION FUNCTIONS:>

=head2 I<setDates($dateStart, $dateEnd)>

=over 4

The B<setDates> function will set the starting and ending dates for this class instance.  Of note, this function is called by the I<new> and the I<autoprepare> (if params provided) functions.

=head3 Parameters:

- B<$dateStart>: [REQUIRED] The starting date/time to be considered, provided as a Unix timestamp

- B<$dateEnd>: [REQUIRED] The ending date/time to be considered, provided as a Unix timestamp

=head3 Returns:

- The number of seconds between the provided start and end dates

=back


=head2 I<setSource($pathToFile)>

=over 4

The B<setDataSource> function will instruct this class instance to only consider transactions written in the file located at the provided path.

=head3 Parameters:

- B<$pathToFile>: [REQUIRED] The path of the file containing the transactions to be considered.

=head3 Returns:

- The provided $pathToFile.

=back


=head2 I<identifyRelevantLogs()>

=over 4

The B<identifyRelevantLogs> function will calculate which Symphony transaction logs correspond with the starting and end date.  I<setDates> should be called before this function, or else all logs will be returned.  Of note, this function is called by the I<autoprepare> function.

=head3 Parameters:

- [none]

=head3 Returns:

- A reference to an array containing the list of relevant logs

=back


=head2 I<autoprepare($dateStart, $dateEnd)>

=over 4

The B<autoprepare> function will identify and decompress the appropriate Symphony and transaction logs into a single file, which is then set as the data source.  If starting and ending dates are provided as parameters (RECOMMENDED), they will automatically be set as the class start and end dates.  Otherwise, the I<setDates> function will need to be called prior to this function, or all logs will be considered.

=head3 Parameters:

- B<$dateStart>: [OPTIONAL] The starting date/time to be considered, provided as a Unix timestamp

- B<$dateEnd>: [OPTIONAL] The ending date/time to be considered, provided as a Unix timestamp

=head3 Returns:

- The source file generated from the relevant transaction logs

=back

B<EXTRACTION FUNCTIONS:>

=head2 I<extractdata($args)>

=over 4

The B<extractdata> function will parse through the source file, returning parsed data for transactions matching the provided arguments.  Before running this function, dates and a source must be set, either by running I<autoprepare> or the combination of I<setDates> and I<setSource>.  Of note, this function is called by the other extraction functions.

=head3 Parameters:

B<Note: Parameters for this function should be provided in hash form>

- B<destination>: [OPTIONAL] The filepath to where the output of this function should be written.  If not set, the output will be written to a temporary file.

- B<cmdcode>: [OPTIONAL]  If set, only data from transactions having the provided command code(s) will be returned.  See the F<seltrans> documentation (esp. the "-c" flag section) for more information and formatting instructions.

- B<datacode>: [OPTIONAL]  If set, only date from transactions having the provided datacode(s) will be returned.  See the F<seltrans> documentation (esp. the "-d" flag section) for more information and formatting instructions.

- B<timestamp>: [OPTIONAL] If set to 1 (TRUE), the timestamp of the transaction will be appended to the end of the other data returned.

- B<duplicates>: [OPTIONAL] Defines how duplicate entries should be handled.  Options are enumerated constants as follows:

=over 4

- DUPLICATES_IGNORE: does nothing to the duplicates - this is the default if this argument is not provided

- DUPLICATES_REMOVE: deletes duplicate lines

- DUPLICATE_COUNT: deletes duplicate lines, but counts the number of duplicates and prepends the count to the rest of the returned data - of note, unique lines will still have a count of 1 prepended

=back

- B<command>: [OPTIONAL]  If set, the transaction data returned will be piped into the provided shell command(s) before being written to the destination file.  This option provides the ability to manipulate and customize the data that gets written to the results.

=head3 Returns:

- The path to the destination file

=back


=head2 I<extractBarcodeChangeMap()>

=over 4

The B<extractBarcodeChangeMap> function will make a predefined call to the I<extractdata> function that will return a mapping of all barcode changes within the defined daterange.  Specifically, transactions with the following command codes will be returned IV.  Further, only transactions with an NR (new barcode) datacode will be returned..

The old and new barcodes of these transactions will be written to the destination file in that order.

=head3 Parameters:

B<Note: Parameters for this function should be provided in hash form>

- B<destination>: [OPTIONAL] The path to the desired destination, if the default destination in the temp directory is not satisfactory.

=head3 Returns:

- The path to the destination file

=back


=head2 I<extractKeysOfAllAvailabilityChanges($args)>

=over 4

The B<extractKeysOfAllAvailabilityChanges> function will make a predefined call to the I<extractdata> function that will return the keys of all records whose availability status changed within the defined daterange.  Specifically, transcactions with the following command codes will be returned: CV (charge), RV (reserve charge), CX (renewal), RX (reserve renewal), EV (discharge).

The barcodes of these transactions will be checked against the barcode replacement database and sent to selitem to recover the catkeys.  Patron IDs can be optionally included.

=head3 Parameters:

B<Note: Parameters for this function should be provided in hash form>

- B<duplicates>: [OPTIONAL] If set, this argument will be passed to I<extractdata> as its I<duplicates> parameter.  Valid options are listed in that function's documentation.

- B<includepatron>: [OPTIONAL] If set to true, patron UserIds will be included in the results.

- B<destination>: [OPTIONAL] The path to the desired destination, if the default destination in the temp directory is not satisfactory.

=head3 Returns:

- The path to the destination file

=back


=head2 I<extractKeysOfChargedRecords($args)>

=over 4

- The B<extractKeysOfChargedRecords> function will make a predefined call to the I<extractdata> function that will return the keys of all records charged (checked out) within the defined daterange.  Specifically, transactions with the following command codes will be returned: CV (charge).

The barcodes of these transactions will be checked against the barcode replacement database and sent to selitem to recover the catkeys.  Patron IDs can be optionally included.

=head3 Parameters:

B<Note: Parameters for this function should be provided in hash form>

- B<duplicates>: [OPTIONAL] If set, this argument will be passed to I<extractdata> as its I<duplicates> parameter.  Valid options are listed in that function's documentation.

- B<includepatron>: [OPTIONAL] If set to true, patron UserIds will be included in the results.

- B<destination>: [OPTIONAL] The path to the desired destination, if the default destination in the temp directory is not satisfactory.

=head3 Returns:

- The path to the destination file

=back


=head2 I<extractKeysOfDischargedRecords($args)>

=over 4

- The B<extractKeysOfDischargedRecords> function will make a predefined call to the I<extractdata> function that will return the keys of all records discharged (checked in) within the defined daterange.  Specifically, transactions with the following command codes will be returned: EV (discharge).

The barcodes of these transactions will be checked against the barcode replacement database and sent to selitem to recover the catkeys.  No patron IDs can be included, as discharges are not tied to patrons.

=head3 Parameters:

B<Note: Parameters for this function should be provided in hash form>

- B<duplicates>: [OPTIONAL] If set, this argument will be passed to I<extractdata> as its I<duplicates> parameter.  Valid options are listed in that function's documentation.

- B<destination>: [OPTIONAL] The path to the desired destination, if the default destination in the temp directory is not satisfactory.

=head3 Returns:

- The path to the destination file

=back


=head1 Author/License

(c) Brigham Young University, 2013.

This file is part of the Ostinato Perl Library for SirsiDynix Symphony, developed independently by Brigham Young University.

This work is licensed under the Creative Commons Attribution-ShareAlike 3.0 Unported License. To view a copy of this license, visit http://creativecommons.org/licenses/by-sa/3.0/.
