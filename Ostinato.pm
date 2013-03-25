package Ostinato;

use strict;
use warnings;
use utf8;
use Carp;
use File::Basename;
use YAML qw'LoadFile';

our $VERSION    = '2.0.0';

#Some class-level definitions
use constant TRUE => 1;
use constant FALSE => 0;
use constant STDIN_PATH => "/proc/self/fd/0";
use constant STDOUT_PATH => "/proc/self/fd/1";
use constant CONFIG_CATEGORY_OPTION => "option";
use constant CONFIG_CATEGORY_MARC   => "marc";
use constant CONFIG_CATEGORY_PATH   => "path";

sub new
{
	my $class = shift;
	my $self = {};
	bless($self,$class);

	#Import the initial config file
	my $configFile = shift;
	if(!defined $configFile)
	{
		$configFile = dirname(__FILE__) . "/ostinato.conf";
	}
	$self->importConfig($configFile);

	#Initialize the environment
	$self->importEnvironment();
	my $envId = $self->setEnvId(rand());
	$self->setPath("log", $self->getPath("temp") . "/" . $envId . ".ostinato.log");
	$self->printToLog("New Ostinato environment created with envId: " . $envId);

	return $self;
}

sub DESTROY
{
	my $self = shift;

	$self->printToLog("Destroying environment");
	#If the autoclean option is set, we will delete all temporary files associated with this envId
	if(defined $self->{config}->{option}->{autoclean} && $self->{config}->{option}->{autoclean} eq "true")
	{
		my $tmpdir = $self->getPath('temp');
		my $log    = $self->getPath('log');
		my $envId  = $self->getEnvId();
		my $cmd = "rm $tmpdir/$envId.* 2>/dev/null;";

		#If the autoclean function is set, but so is the keeplog option, we will not delete the log when we delete all the other temp files
		if(defined $self->{config}->{option}->{keeplog} && $self->{config}->{option}->{keeplog} eq "true")
		{
			$self->printToLog("\tAll temporary files will be deleted; except the log, which will be saved.");
			$cmd = "mv $log $tmpdir/keep.$envId.log;" . $cmd . "mv $tmpdir/keep.$envId.log $log";
		}

		#Make sure we are not deleting anything from the root directory
		if(defined($tmpdir) && $tmpdir ne "") { system($cmd); }
	}
}

sub importConfig
{
	my $self = shift;
	my $filename = shift;
	$self->{config} = YAML::LoadFile($filename) or Carp::confess($!);
	return $self->{config};
}

sub importEnvironment
{
	my $self = shift;
	my $environPath = `echo \`getpathname config\`/environ`;
	chomp $environPath;

	#The current environment must first be purged
	%ENV = ();

	#Import environment values from Symphony's environ file
	open ENVFILE, "<", $environPath or Carp::confess("Cannot open file \"" . $environPath . "\": " . $!);
	while(<ENVFILE>)
	{
			next if ! m/=/;
			s/\s+$//;
			my ($var, $value) = split /=/, $_, 2;
			next if ! $var;
			$ENV{$var} = $value;
	}
	close(ENVFILE);

	#Set any additional environment values
	$ENV{'TERM'} = "xterm";
}

sub saveTempFiles
{
	my $self            = shift;
	my $destinationPath = shift;
	if(-w $destinationPath)
	{
		my $cmd = "cp " . $self->getPath('temp') . "/" . $self->getEnvId() . ".* \"$destinationPath\";";
		system($cmd);
	}
	else
	{
		Carp::confess("The destination path ($destinationPath) does not exist or is not writable.");
	}
	return $destinationPath;
}

sub getSymphonyStatus
{
	my $self = shift;
	my $cmd = "serverstatus wsserver";
	my $response = (split /\=/, `$cmd`)[1];
	chomp $response;
	return $response;
}

sub printToLog
{
	my $self    = shift;
	my $string  = shift;
	my $logfile = $self->getPath("log");
	open LOGFILE, '>>', $logfile or Carp::confess("The log could not be written: $logfile.");
	print LOGFILE "$string\n";
	close(LOGFILE);
	return $string;
}

#Getters and Setters
sub getEnvId
{
	my $self = shift;
	return $self->{envId};
}
sub setEnvId
{
	my $self	= shift;
	my $id		= shift;
	$self->{envId}	= $id;
	return $self->{envId};
}

sub getConfigData
{
	my $self = shift;
	my $typeOfData = shift;
	my $key = shift;
	return $self->{config}->{$typeOfData}->{$key};
}
sub setConfigData
{
	my $self = shift;
	my $typeOfData = shift;
	my $key = shift;
	my $value = shift;

	$self->{config}->{$typeOfData}->{$key} = $value;
	return $value;
}

sub getMarc  { return $_[0]->getConfigData(CONFIG_CATEGORY_MARC, $_[1]); }
sub setMarc  { return $_[0]->setConfigData(CONFIG_CATEGORY_MARC, $_[1], $_[2]); }

sub getOption{ return $_[0]->getConfigData(CONFIG_CATEGORY_OPTION, $_[1]); }
sub setOption{ return $_[0]->setConfigData(CONFIG_CATEGORY_OPTION, $_[1], $_[2]); }

sub getPath  { return $_[0]->getConfigData(CONFIG_CATEGORY_PATH, $_[1]); }
sub setPath  { return $_[0]->setConfigData(CONFIG_CATEGORY_PATH, $_[1], $_[2]); }

1;  ##END PACKAGE
__END__

=pod

=head1 NAME

Ostinato - Provides a standardized way of interacting with common components of SirsiDynix Symphony


=head1 SYNOPSIS

  #Importing the module
  use lib "path/to/ostinato";  #Only required if module is not in the Perl include path already
  use Ostinato;

  #Create a new instance of the class.  This will give it a unique ID to avoid file overwriting.
  my $ost = new Ostinato();

  #Sample function calls
  $ost->getEnvId();  # Will return the unique ID
  $ost->getPath("temp");  # Will return the path to the temp directory as defined
  $ost->printToLog("New log entry...");  #Will write a line in the dedicated log file
  $ost->setOption("autoclean", "false");  #Will disable the "autoclean" functionality of this module instance


=head1 DESCRIPTION

This module imports variables both from Symphony itself as well as a locally-defined YAML config file to provide a standardized framework for interacting with Symphony.  This module can be used by itself to automate some mundane environment handling, and becomes invaluable when used in conjunction with the other modules in the Ostinato package.

WARNING: This library has serious potential to damage your system if not used carefully.  Make sure you know what you're doing, and restrict access to trusted users only.

=head1 CONFIGURATION

This module will read configuration from a YAML file.  By default, this file is in the same directory as this module, and is named ostinato.conf. The configuration is split into 3 sections: option, marc, paths.  The values of this configuration can be retrieved using the getter functions described below, and can be modified (or added to) during runtime using the setter functions. 


=head1 DEPENDENCIES

This module requires the following Perl/CPAN modules:

- strict

- warnings

- utf8

- Carp

- File::Basename

- YAML


=head1 FUNCTIONS

=head2 I<new($configFile)>

=over 4

The B<new> function creates a new instance of the Ostinato module as a class.  It will automatically import the default config file,generate an envId, and begin a log.

=head3 Parameters:

- B<$configFile>: [OPTIONAL] The path to a custom config file if you don't wish to use the default

=head3 Returns:

- A reference to the now-instantiated and blessed Ostinato class

=back


=head2 DESTROY()

=over 4

The B<DESTROY> function is automatically called when an instance of the Ostinato module is destroyed/dereferenced, usually at script termination.  By default, this function will remove any temporary files generated by the Ostinato modules tied to this instance.  This behavior can be changed by modifying the F<ostinato.conf> file or at runtime by calling C<setOption("autoclean", "false");>.

=head3 Parameters: 

- [none]

=head3 Returns: 

- [none]

=back


=head2 I<importConfig($filename)>

=over 4

The B<importConfig> function will overwrite the default config file with the one provided.  Of note, this is how the default config file is imported initially.

=head3 Parameters:

- B<$filename>: [REQUIRED] The path to the new config file

=head3 Returns:

- A reference to the configuration hash created from the config file

=back


=head2 importEnvironment()

=over 4

The B<importEnvironment> function will reset the global $ENV variable, using the Symphony F<environ> file as a reference.

=head3 Parameters:

- [none]

=head3 Returns:

- [none]

=back


=head2 I<saveTempFiles($destination)>

=over 4

The B<saveTempFiles> function will copy all the temporary files associated with the envId of this Ostinato class to the specified destination.

=head3 Parameters:

- B<$destination>: [REQUIRED] The destination to copy the temporary files to

=head3 Returns:

- The provided I<$destination> variable

=back


=head2 getSymphonyStatus()

=over 4

The B<getSymphonyStatus> function will query the wsserver application to determine whether the Symphony server is operational.

=head3 Parameters:

- [none]

=head3 Returns:

- The response given by wsserver.  A response of "RUNNING" indicates the server is operational.  Any other value indicates a problem.

=back


=head2 I<printToLog($string)>

=over 4

The B<printToLog> function will append the provided text to the log file associated with this Ostinato class

=head3 Parameters:

- B<$string>: [Required] The text to be written to the log file

=head3 Returns:

- The provided I<$string> variable

=back


=head2 getEnvId()

=over 4

The B<getEnvId> function will return the envId associated with this Ostinato class

=head3 Parameters:

- [none]

=head3 Returns:

- The envId associated with this Ostinato class, this will be a long decimal number between 0 and 1

=back


=head2 I<setEnvId($id)>

=over 4

The B<setEnvId> function will overwrite the envId associated with this Ostinato class

=head3 Parameters:

- B<$id>: [REQUIRED] The new envId to be associated with this Ostinato instance

=head3 Returns:

- The provided I<$id> variable

=back


=head2 I<getConfigData($typeOfData,$key)>

=over 4

The B<getConfigData> function will return a value from the config data for this Ostinato instance.  Of note, this function is called by the I<getOption>, I<getMarc>, and I<getPath> functions.

=head3 Parameters:

- B<$typeOfData>: [REQUIRED] The parent type of the data to return (by default, it will only be "option", "marc", or "path")

- B<$key>: [REQUIRED] The key of the data to return

=head3 Returns:

- The value associated with the I<$typeOfData> and I<$key> in the config data

=back


=head2 I<setConfigData($typeOfData,$key,$value)>

=over 4

The B<setConfigData> function will overwrite (or create) a value in the config data for this Ostinato instance.  Of note, this function is called by the I<setOption>, I<setMarc>, and I<setPath> functions.

=head3 Parameters:

- B<$typeOfData>: [REQUIRED] The parent type of the config data to write

- B<$key>: [REQUIRED] The key of the data to overwrite/create

- B<$value>: [REQUIRED] The value to assign to the variable associated with the provided I<$typeOfData> and I<$key>

=head3 Returns:

- The provided I<$value> variable

=back


=head2 I<getMarc($key)> I<getOption($key)> I<getPath($key)> 

=over 4

The B<getMarc($key)> B<getOption($key)> and B<getPath($key)> functions will return the associated data from the Marc, Option, or Path config data of this Ostinato instance.

=head3 Parameters:

- B<$key>: [REQUIRED] The key of the data to return

=head3 Returns:

- The value of the variable associated with the provided I<$key>

=back


=head2 I<setOption($key)> I<setMarc($key)> I<setPath($key)>

=over 4

The B<getMarc($key)> B<getOption($key)> and B<getPath($key)> functions will overwrite (or create) a value in the respective config data for this Ostinato instance.

=head3 Parameters:

- B<$key>: [REQUIRED] The key of the data to return

- B<$value>: [REQUIRED] The value of assign to the variable associated with the provided I<$key>

=head3 Returns:

- The provided I<$value> variable

=back


=head1 Author/License

(c) Brigham Young University, 2013.

This file is part of the Ostinato Perl Library for SirsiDynix Symphony, developed independently by Brigham Young University.

This work is licensed under the Creative Commons Attribution-ShareAlike 3.0 Unported License. To view a copy of this license, visit http://creativecommons.org/licenses/by-sa/3.0/.
