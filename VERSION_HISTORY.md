Ostinato Version History
========================

Ostinato v2.1.0 (released: 5 Feb 2013)
--------------------------------------
NEW FEATURES:
- Improved capability of Export.pm to better handle catalog keys that do not
  appear in the ILS, and added the ability to wrap and export non-visible keys.

OTHER CHANGES:
- Changed license to BSD 3-clause license

Ostinato v2.0.3 (released: 1 Feb 2013)
---------------------------------------
OTHER CHANGES:
- Renamed readme.txt to README.md and version_history.txt to VERSION_HISTORY.md
  and updated for public release.


Ostinato v2.0.2 (released: 25 Jan 2013)
---------------------------------------
BUG FIXES:
- Renamed ostinato.conf to onstinato.example.conf in the repository so the local
  ostinato.conf will not be overwritten when a new version is pulled from the
  repository.

OTHER CHANGES:
- Changed the config reference for the barcodeUpdater path to barcodeReplacer,
  to match the final name of the barcode replacement application.


Ostinato v2.0.1 (released: 08 Jan 2013)
---------------------------------------
NEW FEATURES:
- Added a readme.txt file to the root directory.

BUG FIXES:
- In the environment.pl example file, setEnvId() was accidentally referenced as 
  getEnvId().
- In Ostinato::Transaction module, localtime() was being called instead of time()
  when setting up the default date ranges
- In Ostinato::Transaction, the extractBarcodeChangeMap function now takes
  arguments in hash format, matching the structure of the other extract...
  functions.


Ostinato v2.0.0 (released: 17 Dec 2012)
---------------------------------------
- Initial release of the LIS Perl Library under the Ostinato name.
- Complete rewrite of the codebase.
