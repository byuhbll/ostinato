#!perl

# This script demonstrates how to use Ostinato to quickly extract information from the Symphony
# transaction history logs
#
# NOTE: The Perl interpreter has been defined using a symbolic link.  If this script is moved or run 
# from another location, you will need to redefine it.

# Like the interpreter, the path to the Ostinato library is defined using a symbolic link.
use lib "ostinato";
use Ostinato::Transaction;

# Although we could let Ostinato::Transactions create its own instance of the parent Ostinato class
# (see "policies.pl" as an example of this), we will create our own ahead of time.
my $env = new Ostinato();
my $transactions = new Ostinato::Transaction($env);


# For the sake of readability, we are going to define our dates using the ISO format and let Perl
# convert them to Unix timestamps for us:
my $startDate = Date::Parse::str2time("2011-01-01T00:00:00");
my $endDate   = Date::Parse::str2time("2011-03-31T23:59:59");


# Before Ostinato::Transaction can extract data, it must first prepare the data source
# The recommended way of doing this is to use the following function:
$transactions->autoprepare($startDate, $endDate);
# This function will automatically decompress transactions from the transaction logs (associated
# with the dates provided) to the temp directory.

# However, in some cases, we may wish to manually prepare the data.  For example, let's assume
# that we have a set of transactions already stored at the file: "test.transactions":
$transactions->setSource("test.transactions");

# By setting the source manually, however, we have not yet told Ostinato::Transaction what date
# range should be considered.  By default, it will consider all transactions occuring in the Unix
# Epoch, but we can limit this to a more specific range by calling:
$transactions->setDates($startDate, $endDate);


# Once the data has been prepared, we can extract information from it using the following function:
# NOTE:  The syntax of the code patterns should match that of the seltrans API call.
$transactions->extractdata({
	cmdcode     => "CV,RV",             #Equivalent to the -c filter in the seltrans API call
	datacode    => "NQ^31197232436003", #Equivalent to the -d filter in the seltrans API call
	outcode     => "NQ,FF",             #Equivalent to the -o filter in the seltrans API call
	command     => "selitem -iB -oCS",  #Additional commands to send the returned transactions through
	timestamp   => 1,                   #If TRUE, the timestamp of the transaction will be appended
	duplicates  => DUPLICATES_IGNORE,   #Instructs what to do with duplicate lines
	destination => "destination.file"   #An alternate destination, if the temp directory is not wanted
});


# Since a raw call to the extractData function can be lengthy and is nearly as cryptic as a raw
# seltrans API call, some helper functions exist to prepopulate common calls.
my $barcodeChangeFile  = $transactions->extractBarcodeChangeMap();
my $allAvailChangeFile = $transactions->extractKeysOfAllAvailabilityChanges();
my $checkoutsFile      = $transactions->extractKeysOfChargedRecords();
my $checkinsFile       = $transactions->extractKeysOfDischargedRecords();
