#!perl

# This script demonstrates how to setup and use filters in Ostinato to limit the consideration
# of records to the ones you're interested in.
#
# NOTE: The Perl interpreter has been defined using a symbolic link.  If this script is moved or run 
# from another location, you will need to redefine it.

# Like the interpreter, the path to the Ostinato library is defined using a symbolic link.
use lib "ostinato";
use Ostinato::Filter;

# Although we could let Ostinato::Filter create its own instance of the parent Ostinato class
# (see "policies.pl" as an example of this), we will create our own ahead of time.
my $env = new Ostinato();
my $filters = new Ostinato::Filter($env);


# Filters can be created by calling:
$filters->setFilter("LIBR", "LEE");
# This filter will instruct all future Ostinato calls to only consider records appearing in the
# "LEE" library.  


# Of note, Ostinato::Filter will create an instance of Ostinato::Policy and associate it with
# the same parent Ostinato instance, if one does not already exist.  This associated class can
# be referenced using:
my $policies = $env->class->{policy};

# This partnership can be quite useful.  For example, we could replace the literal "LIBR" with 
# a reference to Ostinato::Policy::LIBRARY to further abstract our code.
# 
# Additionally, Ostinato::Filters can automatically set up filters based off information in the
# Symphony policies file:
$policies->importPolicies(Ostinato::Policy::LOCATION);
$filters->autofilter_excludeShadowLocations();


# To see the filter created by this process (or any other filter), we can use our getter function:
$filters->getFilter(Ostinato::Policy::LOCATION);
