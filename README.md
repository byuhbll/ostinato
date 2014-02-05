Ostinato Perl Library for Symphony, v.2.1.x
===========================================

The Ostinato library provides a set of Perl modules designed to automate some
common processes and environment handling for writing Symphony API-based
scripts.

WARNING: OSTINATO IS DESIGNED FOR EXPERIENCED USERS ONLY.  IT DOES NOT PROVIDE
EXTENSIVE DATA OR COMMAND VALIDATION, SO THERE IS POTENTIAL TO DAMAGE YOUR 
SYMPHONY DATABASE OR EVEN YOUR HOST SYSTEM.  DO NOT USE THIS LIBRARY UNLESS
YOU KNOW WHAT YOU ARE DOING, AND RESTRICT ACCESS TO TRUSTED USERS ONLY!!

NO WARRANTY OR SUPPORT OF ANY KIND IS PROVIDED FOR THIS SOFTWARE.

Dependencies
------------

Ostinato uses the barcodeReplacer application 
(https://github.com/byuhbll/barcodeReplacer) in its Ostinato::Transaction module to 
resolve any updates to ItemIDs/barcodes.

Additionally, the yaz-marcdump utility (https://www.indexdata.com/yaz) is 
required to convert catalog dumps to XML.

Installation and Usage
----------------------
Configure your instance of Ostinato by copying “./ostinato.example.conf” to 
“./ostinato.conf” and modifying that file to match your server setup and 
preferences.

No additional installation is required to use this software.  Simply drop it somewhere on
your Symphony server (but NOT in the Unicorn directory) and include a line in
your Perl code to add it to your path:

<pre>
"use lib path/to/ostinato/location;"
</pre>

Then add the following line(s):

<pre>
"use Ostinato::ModuleName"
</pre>

Each Ostinato module comes extensive documentation, accessible by using the
"perldoc Ostinato::ModuleName" command, where 'ModuleName' is replaced by
the name of the module (or just "perldoc Ostinato" for the parent Ostinato 
class.

Additionally, there are a series of example uses and function calls 
available in the "examples" directory.


License
-------
Ostinato was developed by Brigham Young University and is licensed under the 
Creative Commons Attribution-ShareAlike 3.0 Unported License.  To view a copy
of this license, visit http://creativecommons.org/licenses/by-sa/3.0/.

Symphony is owned and copyrighted by SirsiDynix.  All rights reserved.
