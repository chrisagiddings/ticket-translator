####################################################################################
# Written by: Chris Giddings, last updated on 3/2/2015 to v1.0.0
####################################################################################
# OPERATING THE TRANSLATOR
####################################################################################
	# USING THE SCRIPT IN DEFAULT OR CUSTOM MODES
	################################################################################

	When running the translator the script takes the following format

	== RUN IN DEFAULT MODE ==
	$ ./ticket_translator.pl

	== RUN WITH DESIRED MODE ==
	$ ./ticket_translator.pl --mode={mail|file|test|rerun|invert}

	== RUN IN DEBUG MODE ==
	$ ./ticket_translator.pl -d

	== RUN IN DEBUG MODE WITH OPTIONS ==
	$ ./ticket_translator.pl -debug --m={mail|file|test|rerun|invert}

	################################################################################
	#++ PRO TIPS ++#
	################################################################################
	[1] SINGLE MODE ONLY
	The --mode argument takes an input. Only a single mode type should be specified.

	[2] SHORTENED ARGUMENTS
	The --mode argument can be shortened to --m.

	[3] INCLUDING FILENAMES
	The --mode=file option requires the additional --file={filename} argument which
	should always be the fully qualified filepath to the file to translate.

	################################################################################
	# RUNTIME MODES
	################################################################################
	#
	# mail: Connect to imap, process messages and archives to dated gzip file.
 	# file: Translate contents of specified file(s) as messages. This mode ignores
 	#       the message processing limit.
 	#
 	# test: Does a mock translation in the default mode without dispatching,
 	#       archiving, or deleting originating materials.
 	#
 	# rerun: Runs the most recent previous translation from dated archive.
 	# invert: Runs the most recent previous translation from dated archive in
 	#          inverse of what's configured in the translator's properties.
 	################################################################################

 	Runtime modes allow the translator some flexibility in handling the multitude of
 	situations a user might find need to use the system.

 	From converting messages back to the originating format, to re-running
 	previously translated messages that may not have properly made it to the
 	destination system, runtime modes permit these edge cases.

 	== MAIL MODE ==
 	Mail Mode is default out of the box as it is the system's originally intended
 	purpose. Should the default mode be changed, you can reinstantiate Mail Mode by
 	providing a "-m" argument when running the script.

	== FILE MODE ==
	File Mode is the second most likely scenario for operating the translation
	system. If a message isn't on the mail-server but still needs to be run (say for
	a development test, etc.) File Mode allows you to translate messages in files.

	File mode takes an additional argument, the file path or message ID of the
	message you're wanting to run from file.

	== TEST MODE ==
	Test Mode is intended to provide a "sneak peek" at end results of a translation.
	With this mode, maintenance on the script system has less impact and running
	changes against production don't actually perform any work allowing for better
	overall reliability and trustworthiness.

	== RERUN MODE ==
	Rerun Mode ensures the system can run previously translated messages again in
	the event the original translations didn't make it to the destination.

	Rerun events process an entire day's archive of messages, which may not always
	be advantageous. If only a couple messages need to be rerun, use File Mode
	on specific extracted messages instead.

	Rerun mode will accept an additional argument of the archive date to determine
	which day's messages to run again.

	== INVERSE MODE ==
	Inverse Mode allows for backward translation. If certain messages contain merges
	which are not yet accounted for or are otherwise not properly fitted to the
	destination system Inverse Mode uses the inverse translation directive from the
	configuration file.


####################################################################################
# CONFIGURING THE TRANSLATOR
####################################################################################
	# MAIL SERVER CONFIGURATION
	################################################################################
	#
	# MAIL_SERVER defines the email host server.
	# MAIL_USER is the defined user for logging in to the MAIL_SERVER.
	# MAIL_PASS is the password for the user logging in to the MAIL_SERVER.
	################################################################################

	Configuring the mail server is a critical part of the translation system as mail
	is the primary method by which messages are discovered fopr translation, and
	subsequently dispatched for processing in the destination system.


	################################################################################
	# TRANSLATION DIRECTIVES
	################################################################################
	#
	# casd-to-remedy : Convert CASD messages for use by Remedy
	# remedy-to-casd : Convery Remedy messages for use by CASD
	################################################################################

	Translation directives tall the translator which direction a translation is to
	be performed. Future conversion to another system may be way down the line, but
	anticipating the need will allow this system to maintain its purpose longer.

	Inverse Directives indicate which translation directive to use in Inverse Mode.


####################################################################################
# OPERATIONAL INFORMATION
####################################################################################
	# MESSAGE EXPORT INFORMATION
	################################################################################

	Messages processed by the translator are automatically exported to plaintext
	files with a .msg extension. These files are plaintext and can be opened by any
	standard text editor. It is recommended to NOT use word processor systems such
	as Microsoft Word, Lotus Notes or Open Office variants to edit these files in
	any way as it may alter the file's structure in unintended ways resulting in
	the translator being unable to process the message should it need to be run
	again from file or in a batch using rerun mode.

	Messages exported by the translator have a standardized file naming system in
	the format of {date}-{time}-{messageID}.msg.

	The message ID is an MD5 hash of the actual message's combined text:
	- Header
	- Body
	- Subject
	- Date

	################################################################################
	# ARCHIVAL INFORMATION
	################################################################################
	# === THIS PROCESS IS CURRENTLY BROKEN

	Messages processed by the translator should automatically be inserted into a
	daily archive tarball. The archive is created in the configured archive
	directory and given a name of "TranslationArchive_YYYYMMDD.tar".

	Rerun mode will accept an additional argument of the archive date to determine
	which day's messages to run again.

	################################################################################
	# JSON LOOKUP FILES
	################################################################################
	Translation lookup files are stored in JSON format, a lightweight programming
	language used mostly on the web.

	DO NOT EDIT THESE JSON FILES

	################################################################################
	# CONFIGURATION FILES
	################################################################################
	The translator.properties file contains configuration information for the
	specific environment including mail server connection parameters and both the
	default and inverse translation directives.

	This properties file should be configured with proper connection information for
	whatever environment the translator is deployed to.
