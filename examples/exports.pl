#!perl

# This script demonstrates how to use Ostinato to export bibliographic records from Symphony
#
# NOTE: The Perl interpreter has been defined using a symbolic link.  If this script is moved or run 
# from another location, you will need to redefine it.

# Like the interpreter, the path to the Ostinato library is defined using a symbolic link.
use lib "ostinato";
use Ostinato::Export;

# Although we could let Ostinato::Export create its own instance of the parent Ostinato class
# (see "policies.pl" as an example of this), we will create our own ahead of time.
my $env = new Ostinato();
my $exporter = new Ostinato::Export($env);


my $keysfile  = "test.keys";

# In its most basic usage, Ostinato::Export can make a call to the catalogdump API:
my $dumpFile1 = $exporter->catalogdump({
	source => $keysfile,
});


# However, the strength of this module is better seen when we want to be more filtered in the dump
$env->{class}->{policy}->importPolicies();
$env->{class}->{filter}->autofilter_excludeShadowLocations();
$env->{class}->{filter}->setFilter("LIBR", "LEE");
$env->{class}->{filter}->setFilter(Ostinato::Policy::ITEMTYPE, "~FACULTYUSE");
# We just set up a series of filters to only consider records for the "LEE" library which are not
# in a shadowed location and are not "FACULTYUSE" items.

# With the filters set up, we can split our original set of keys according to whether they should
# be visible or not in our catalogdump.
my ($visibleKeys, $hiddenKeys) = $exporter->splitByVisibility({
	source => "test.keys",
});


# Now we can instruct our catalogdump to export only the keys which we have identified as "visible"
# for this export.  Since this is our final export, we will define an output format and destination:
my $dumpFile2 = $exporter->catalogdump({
	source     => $visibleKeys,
	format     => Ostinato::Export::FORMAT_XML,
	desination => "catalogdump.xml",
});
