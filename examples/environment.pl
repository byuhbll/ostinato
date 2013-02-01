#!perl

# This script extends the functionality introduced in simple.pl to show how the working environment
# may be used, once it is set up.
#
# NOTE: The Perl interpreter has been defined using a symbolic link.  If this script is moved or run 
# from another location, you will need to redefine it.

# Like the interpreter, the path to the Ostinato library is defined using a symbolic link.
use lib "ostinato";
use Ostinato;

my $env = new Ostinato();
# Ostinato has now created our working environment and imported the Symphony environ file.


# Each Ostinato instance has a unique identifier that is prefaced to all temporary files.
# To get this identifier, or envId, use the following: 
$env->getEnvId();

#If for any reason, you need to change the envId, you can call:
my $newId = rand();
$env->setEnvId($newId);


# Ostinato has a built-in log.  We can write a line to the log by calling:
$env->printToLog("This line will be written to the log");


# Ostinato also keeps track of some pathing for us.  To get the temp path, for example, we call:
$env->getPath("temp");

# The default list of paths is stored in the ostinato.conf file, in the ostinato root directory.
# We can set additional paths by calling:
$env->setPath("newpath");


# Other kinds of config data can be set/get in similar manner.
$env->getMarc("holdingInfo");
$env->setOption("autoclean", "true");

# At the most generic level, config data may be accessed or modified using the following:
# Note that the following calls do the exact same thing as the calls above:
$env->getConfigData(Ostinato::CONFIG_CATEGORY_MARC, "holdingInfo");
$env->setConfigData(Ostinato::CONFIG_CATEGORY_OPTION, "autoclean", "true");


# Some scripts/services may be dependent on whether Symphony is operational or not.  Ostinato
# allows you to quickly check the status of Symphony by calling:
$env->getSymphonyStatus();


# When an Ostinato instance is destroyed by the Perl interpreter (happens automatically when
# a script successfully ends), Ostinato will - if the autoclean option is set - automatically
# erase all files in the temp directory that are associated with the envId for that instance.
# If you want to copy those files to another directory for them to be saved, call:
$env->saveTempFiles("path/to/destination");
