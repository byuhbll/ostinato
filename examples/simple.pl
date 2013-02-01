#!perl

# This script demonstrates the simplest possible usage of the Ostinato library.  
# The only thing that we do is instantiate a new Ostinato class to set up a working environment.
#
# NOTE: The Perl interpreter has been defined using a symbolic link.  If this script is moved or run 
# from another location, you will need to redefine it.

# Like the interpreter, the path to the Ostinato library is defined using a symbolic link.
use lib "ostinato";
use Ostinato;

my $env = new Ostinato();
# Ostinato has now created our working environment and imported the Symphony environ file.
