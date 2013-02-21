#!perl

# This script demonstrates how to use Ostinato to easily lookup Symphony policies
#
# NOTE: The Perl interpreter has been defined using a symbolic link.  If this script is moved or run 
# from another location, you will need to redefine it.

# Like the interpreter, the path to the Ostinato library is defined using a symbolic link.
use lib "ostinato";
use Ostinato::Policy;

my $policies = new Ostinato::Policy();
# Since we did not instantiate and pass in a parent Ostinato class here, one will be
# created for us automatically.

# The Ostinato::Policy class can import policies from the Policies file into memory by using:
$policies->importPolicies("LIBR");
# This call only imported policies of type LIBR.  Multiple policy types can be imported at once
# by appending additional policy type identifiers.  Note that some identifiers are available
# as constants inside Ostinato::Policy, and it is recommended that you use those constants:
$policies->importPolicies(Ostinato::Policy::LIBRARY, Ostinato::Policy::ITEMTYPE);
# If no policy types are defined, importPolicies will use the LIBRARY, LOCATION, and ITEMTYPE 
# policies by default.


# Once some policies are imported, you can get the index for them by calling:
$policies->getPolicyIndex(Ostinato::Policy::LIBRARY, "LEE");

# Data for this line of policy could be recovered by a similar function call:
$policies->getPolicyData(Ostinato::Policy::LIBRARY, "LEE");


# Some prepopulated functions exist to streamline this process further:
$policies->getLibraryIndex("LEE");
$policies->getItemtypeIndex("BOOK");
$policies->getLocationIndex("CHECKEDOUT");
$policies->isLocationShadowed("CHECKEDOUT");
