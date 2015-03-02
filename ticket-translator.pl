#!/usr/bin/perl -w
####################################################################################
# Written by: Chris Giddings, last updated on 2/20/2015 to v0.0.1
####################################################################################
#
# As of this writing this script is intended to:
#   1) Connect to CASD Mailbox
#   2) Traverse CASD Mailbox
#   3) Map Fields Between CASD & Remedy
#   4) Send Translated Message to Remedy
#   5) Process ONLY Incidents & Requests (not Changes, Problems or others types)
#   6) Output messages to flat files for storage, rerun and audit
#
####################################################################################
# DEPENDENCY DECLARATIONS
####################################################################################
use Archive::Tar;
use Cwd;
use Data::Dumper;
use diagnostics;
use Digest::MD5 qw(md5_hex);
use Fcntl qw(:flock);
use File::Temp qw(tempdir);
use Getopt::Long qw(GetOptions);
use JSON;
use MIME::Parser;
use Net::IMAP::Client;
use Net::SMTP;
use POSIX qw(ctime);
use POSIX qw(strftime);
use strict;
use Switch;
use warnings;
####################################################################################
# GLOBAL DECLARATIONS
####################################################################################
Getopt::Long::Configure qw(gnu_getopt);

  no warnings 'uninitialized';
  #+################################################################################
  # RUNTIME DATA
  #+################################################################################
  my $runtimeMode="mail"; # OPTIONS: mail, file, test, rerun, invert
  my $operatingSystem="$^O";
  my $workingDirectory=cwd($0); #For local use & testing.
  # my $workingDirectory="/home/WebMon/scripts/tickettranslator"; #Standardized directory.
  my $perlVersion = "$^V";
  #+################################################################################
  # DIRECTORY DECLARATIONS
  #+################################################################################
  my $tmpDir="/tmp/scripts/translation";
  my $archiveDir="$workingDirectory/archive/";
  my $testLogdir="$workingDirectory/logs/";
  #+################################################################################
  # CONFIG & DEBUG VALUES
  #+################################################################################
  my $configDir="$workingDirectory/config/";
  my $configFile="$configDir/translator-local.properties";
  # my $configFile="$configDir/translator-dev.properties";
  # my $configFile="$configDir/translator-prod.properties";
  my $logFile="$workingDirectory/logs/ticket-translation.log";
  my $logging=0;
  my $DEBUG=0;                          # Some log messages require DEBUG turned on.
  #+################################################################################
  # BLANK INITIALIZATIONS FOR CONFIGURATION FILE PARAMETERS
  #
  # Presented in order of organization in 
  #+################################################################################
  my $RUNTIME_ENVIRONMENT="";
  my $DEVELOPMENT_SERVER="";
  my $PRODUCTION_SERVER="";
  my $MESSAGE_SENDER="";
  my $MESSAGE_RECEIVER="";
  my $MAIL_SERVER="";
  my $SMTP_SERVER="";
  my $MAIL_USER="";
  my $MAIL_PASS="";
  my $FIRST_NAME="";
  my $LAST_NAME="";
  my $DEFAULT_DIRECTIVE="";
  my $INVERSE_DIRECTIVE="";
  my $MAX_TO_PROCESS="";          # The cap of messages to translate in one session.
  my $REMEDY_USER="";
  my $REMEDY_PASSWORD="";
  #+################################################################################
  # TRANSLATION VALUES
  #+################################################################################
  my $messageBundle="nil";
  my $currentMessage="";
  my $translationID='';
  my $fullMessageBlock="";
  #+################################################################################
  # BOOLEANS
  #+################################################################################
  my $successBoolean=0;
  my $beforeOrAfter=0;
  #+################################################################################
  # RUNTIME ARGUMENT INFO FOR THIS SCRIPT
  #+################################################################################
  my $runtime_arguments=($#ARGV + 1);
  #+################################################################################
  # RECEIVED MESSAGE SOURCE DATA
  #+################################################################################
  my $messageHeader="";
  my $messageSubject="";
  my $messageBody="";
  my $messageDate="";
  my $messageSender="";
  my $messageReceiver="";
  #+################################################################################
  # GLOBAL VARIABLES FOR DISPATCHING TRANSLATED MESSAGES
  #+################################################################################
  my $binaryAttachmentFilePath="";
  my $textAttachmentFilePath="";
  my $translatedMessage="";
    #++#############################################################################
    # DISPATCHER BOOLEANS
    #++#############################################################################
    my $readyForDispatch=0;
  #+################################################################################
  # EMPTY INITIALIZATIONS FOR GLOBAL ACCESS
  #+################################################################################
  my $RUNTIME_SERVER="";
  my $CURRENT_DIRECTIVE="";
  my $translationArchive='';
  my @fileList='';
  my $decodedJSON;
####################################################################################
# LOGGING AND PROCESS INSTANTIATION
####################################################################################
sub openLog {
  if(!open(LOGF, ">>", $logFile))
  {
    print "NOTICE: Attempting to create file for logging: $logFile\n\n";

    if(!open(LOGF, ">>", $logFile))
    {
      print "WARNING: UNABLE TO OPEN LOG FILE AFTER MULTIPLE ATTEMPTS!\n";
      print "$!\n\n";
      print "Translation will continue without logging.\n";
      return;
    }
  }
  flock(LOGF, LOCK_EX);  # Lock file
  seek(LOGF, 0, 2);  # skip to end in case we had to wait for the lock
  $logging=1;
}
####################################################################################
# WRITE ACTIVITY TO LOG
####################################################################################
sub writeLog {
  my $log_message=shift;
  if($logging) {
    print LOGF $log_message;
  }
  print $log_message if($DEBUG>=2);
}
####################################################################################
# CLOSE LOG FILE & RELEASE
####################################################################################
sub closeLog {
  if($logging) {
    flock(LOGF, LOCK_UN);  # Unlock file
    close(LOGF);
  }
}
####################################################################################
# LOAD TRANSLATION CONFIGURATION
####################################################################################
sub loadConfig
{
  #+################################################################################
  # DETERMINE IF TRANSLATOR IS RUNNING ON THE CURRENT FAILOVER MASTER
  #+################################################################################

  open my $fh, '<', "$configFile" or die "INITIALIZATION ERROR: UNABLE TO LOAD TRANSLATOR CONFIGURATION: $!\n";
    my %config_hash = map { split /=|\s+/; } <$fh>;
  close $fh; 

  writeLog("\nLOADING TRANSLATOR CONFIGURATION FROM $configFile\n");
  while (my ($key, $value) = each %config_hash)
  {
    switch($key)
    {
      case "RUNTIME_ENVIRONMENT"
      {
        $RUNTIME_ENVIRONMENT="$value";
        writeLog("DEBUG: Running in $RUNTIME_ENVIRONMENT.\n") if($DEBUG);
      }
      case "DEVELOPMENT_SERVER"
      {
        $DEVELOPMENT_SERVER="$value";
      }
      case "PRODUCTION_SERVER"
      {
        $PRODUCTION_SERVER="$value";
      }
      case "MESSAGE_SENDER"
      {
        $MESSAGE_SENDER="$value";
        writeLog("DEBUG: Translated messages will be sent from: $MESSAGE_SENDER.\n") if($DEBUG);
      }
      case "MESSAGE_RECEIVER"
      {
        $MESSAGE_RECEIVER="$value";
        writeLog("DEBUG: Translated messages will be sent to: $MESSAGE_RECEIVER.\n") if($DEBUG);
      }
      case "MAIL_SERVER"
      {
        writeLog("DEBUG: Mail server address set to: $value\n") if($DEBUG);
        $MAIL_SERVER="$value";
      }
      case "SMTP_SERVER"
      {
        writeLog("DEBUG: Mail server to send from is: $value\n") if($DEBUG);
        $SMTP_SERVER="$value";
      }
      case "MAIL_USER"
      {
        writeLog("DEBUG: Mail username registered.\n") if($DEBUG);
        $MAIL_USER="$value";
      }
      case "MAIL_PASS"
      {
        writeLog("DEBUG: Mail password registered.\n") if($DEBUG);
        $MAIL_PASS="$value";
      }
      case "FIRST_NAME"
      {
        $FIRST_NAME="$value";
        writeLog("DEBUG: Default first name set to: $FIRST_NAME.\n") if($DEBUG);
      }
      case "LAST_NAME"
      {
        $LAST_NAME="$value";
        writeLog("DEBUG: Default last name set to: $LAST_NAME.\n") if($DEBUG);
      }
      case "DEFAULT_DIRECTIVE"
      {
        $DEFAULT_DIRECTIVE="$value";
        writeLog("DEBUG: Default translation directive set to: $DEFAULT_DIRECTIVE.\n") if($DEBUG);
      }
      case "INVERSE_DIRECTIVE"
      {
        $INVERSE_DIRECTIVE="$value";
        writeLog("DEBUG: Inverse translation directive set to: $INVERSE_DIRECTIVE.\n") if($DEBUG);
      }
      case "MAX_TO_PROCESS"
      {
        $MAX_TO_PROCESS="$value";
        writeLog("DEBUG: Set to translate a maximum of $MAX_TO_PROCESS messages per session.\n") if($DEBUG);
      }
      case "REMEDY_USER"
      {
        $REMEDY_USER="$value";
        writeLog("DEBUG: Using $REMEDY_USER to connect to BMC Remedy.\n") if($DEBUG);
      }
      case "REMEDY_PASSWORD"
      {
        $REMEDY_PASSWORD="$value";
        writeLog("DEBUG: Remedy login credentials detected.\n") if($DEBUG);
      }
      else
      {
        writeLog("WARNING: SKIPPING UNRECOGNIZED KEY IN CONFIGURATION: $key => $value\n");
      }
    }
  }
  writeLog("FINISHED LOADING CONFIGURATION\n\n");
  if($RUNTIME_ENVIRONMENT eq "development")
  {
      $RUNTIME_SERVER=$DEVELOPMENT_SERVER;
  }

  if($RUNTIME_ENVIRONMENT eq "production")
  {
      $RUNTIME_SERVER=$PRODUCTION_SERVER;
  }

  writeLog("DEBUG: $RUNTIME_ENVIRONMENT server set to: $RUNTIME_SERVER.\n") if($DEBUG);
  if(!$RUNTIME_SERVER)
  {
    writeLog("CRITICAL ERROR: RUNTIME_SERVER UNDECLARED!\n") if($DEBUG);
    exit 10;
  }
}
####################################################################################
# LOAD COMPARE TABLES FOR CASD-TO-REMEDY TRANSLATION
####################################################################################
sub loadCASDToRemedy
{
  my $jsonStream=JSON::XS->new->utf8->pretty->relaxed->allow_nonref;

  if($CURRENT_DIRECTIVE eq "casd-to-remedy")
  {
    #################################### JSON ######################################
    my $jsonFileName="$configDir/casd-remedy-lookup.json";

    if(!$decodedJSON)
    {
      writeLog("DEBUG: Loading JSON file for directive: $CURRENT_DIRECTIVE.\n") if($DEBUG);

      local $/ = undef;
      open(my $jsonFileHandle, '<', $jsonFileName) or die "CRITICAL ERROR: Unable to load CASD to Remedy translation file. $!\n";
      
      my $rawJSON=<$jsonFileHandle>;
      close $jsonFileHandle or die "$!\n";
      $decodedJSON=$jsonStream->decode($rawJSON) or die "CRITICAL ERROR: JSON LOADED BUT UNPARSABLE: $!\n";

      #++###########################################################################
      # DUMPER USAGE FOR LOCAL DEBUGGING
      #
      # Leaving Dumpers in to assist with any long-term issues.
      #++###########################################################################
      #print Dumper($decodedJSON->{Group});
    }

    if(!$decodedJSON)
    {
      writeLog("CRITICAL ERROR: Unable to load JSON file for directive: $CURRENT_DIRECTIVE.\n");
      exit 10;
    }
    writeLog("DEBUG: Test parameter: ".$decodedJSON->{Urgency}->[1]."\n") if($DEBUG);
    writeLog("DEBUG: JSON file looks valid and true.\n") if($DEBUG);
    writeLog("Successfully loaded JSON file for directive: $CURRENT_DIRECTIVE.\n");
    translateMessageToRemedy();
  }
}
####################################################################################
# LOAD COMPARE TABLES FOR REMEDY-TO-CASD TRANSLATION
####################################################################################
sub loadRemedyToCASD
{
  if($CURRENT_DIRECTIVE eq "remedy-to-casd")
  {
    writeLog("DEBUG: REMEDY TO CASD METHODS HAVE NOT BEEN WRITTEN YET.") if($DEBUG);
  }
}
####################################################################################
# MANAGE TRANSLATION
####################################################################################
sub translateMessage
{
  my $readyForDispatch=0;

  if(!$CURRENT_DIRECTIVE)
  {
    writeLog("CRITICAL ERROR: No translation directive configured. Aborting translation process.\n");
    exit 10
  }
  elsif($CURRENT_DIRECTIVE="casd-to-remedy")
  {
    loadCASDToRemedy() or die "CRITICAL ERROR: UNABLE TO INITIALIZE JSON FOR TRANSLATION DIRECTIVE!\n";
  }
  elsif($CURRENT_DIRECTIVE="remedy-to-casd")
  {
    writeLog("DEBUG: Remedy to CASD directive not yet implemented.\n") if($DEBUG);
    loadRemedyToCASD() or die "CRITICAL ERROR: UNABLE TO INITIALIZE JSON FOR TRANSLATION DIRECTIVE!\n";
  } else {
    writeLog("WARNING: UNRECOGNIZED DIRECTIVE DECLARED!\n");
  }
}
####################################################################################
# TRANSLATE MESSAGE FROM BASE TO TARGET
#
# Unless inverse mode is active, which reverse the direction of translation
# from the configured default.
#
# Takes ingested JSON formatted data and seeks matching key/value pairs.
#
# "Key": ["BaseValue","TargetValue"],
####################################################################################
sub translateMessageToRemedy
{
  writeLog("Translating message for BMC Remedy.\n");

  #+################################################################################
  # STATIC & DERIVED VALUES
  #+################################################################################
  my $casdContent = $messageBody;
  $casdContent =~ s/.*"start-request"(.*)"end-request".*/$1/ms;
  
  my $validGroups=$decodedJSON->{'validUSGroups'};
  my ($casdGroup)=($casdContent =~ m/%GROUP=\s*(.*)/);
  $casdGroup=cleanCAData($casdGroup);

  my $groupName=$validGroups->{$casdGroup};
  writeLog("DEBUG: Searching groups for a valid match: \n");

  my ($casdCategory)=($casdContent =~ m/%CATEGORY=\s*(.*)/);
  $casdCategory=cleanCAData($casdCategory);

  if(!$groupName && $casdCategory) {
      writeLog("DEBUG: Could not find explicit group. Searching categories for a match.\n") if($DEBUG);
      my $validAreas=$decodedJSON->{'casdAreaToBMCGroups'};
      $groupName=$validAreas->{$casdCategory};
  }

  my $okToDelete=0;
  if($groupName)
  {
    writeLog("\nDEBUG: Group Match: $casdGroup : $groupName.\n");
  } else {
    writeLog("WARNING: No matching valid groups or categories found. Ok to delete message.\n");
    return $okToDelete=1;
  }

  my $casdContactUsingAlarmPoint="";
  my $casdAlarmPointGroupID="G00000";
  my $casdProcessName="";
  my $casdProcessID="";
  my $casdStepName="";
  my $casdFailureCode="";
  my $casdAffectedRC="";
  my $casdEnvironment="";
  my $casdAssignee="";
  my $casdStatus="";
  my $casdSummary="";

  my ($casdDescription)=($casdContent =~ m/%DESCRIPTION=(.*?)(%|$)/s);

  ($casdContactUsingAlarmPoint)=($casdContent =~ m/%ZCONTACTUSINGALARMPOINT=\s*(.*)/);
  $casdContactUsingAlarmPoint=cleanCAData($casdContactUsingAlarmPoint);
  $casdContactUsingAlarmPoint=lc($casdContactUsingAlarmPoint);

  ($casdAlarmPointGroupID)=($casdContent =~ m/%ZALARMPOINTID=\s*(.*)/);
  $casdAlarmPointGroupID=cleanCAData($casdAlarmPointGroupID);
  if($casdAlarmPointGroupID)
  {
    writeLog("DEBUG: Contact Using AlarmPoint?: $casdContactUsingAlarmPoint, with group ID: $casdAlarmPointGroupID.\n");
  } else {
    $casdAlarmPointGroupID="";
  }

  ($casdSummary)=($casdContent =~ m/%SUMMARY=\s*(.*)/);
  $casdSummary=cleanCAData($casdSummary);

  ($casdProcessName)=($casdContent =~ m/%ZPROCESSNAME=\s*(.*)/);
  $casdProcessName=cleanCAData($casdProcessName);

  ($casdProcessID)=($casdContent =~ m/%ZPROCESSID=\s*(.*)/);
  $casdProcessID=cleanCAData($casdProcessID);

  ($casdStepName)=($casdContent =~ m/%ZSTEPNAME=\s*(.*)/);
  $casdStepName=cleanCAData($casdStepName);

  ($casdFailureCode)=($casdContent =~ m/%ZFAILURECODE=\s*(.*)/);
  $casdFailureCode=cleanCAData($casdFailureCode);

  ($casdAffectedRC)=($casdContent =~ m/%AFFECTED_RC=\s*(.*)/);
  $casdAffectedRC=cleanCAData($casdAffectedRC);

  ($casdAssignee)=($casdContent =~ m/%ASSIGNEE=\s*(.*)/);
  $casdAssignee=cleanCAData($casdAssignee);

  ($casdStatus)=($casdContent =~ m/%STATUS=\s*(.*)/);
  $casdStatus=cleanCAData($casdStatus);

  #+################################################################################
  # Determine Environment Translation
  #+################################################################################
  ($casdEnvironment)=($casdContent =~ m/%ZENVIRONMENT=\s*(.*)/);
  $casdEnvironment=cleanCAData($casdEnvironment);

  my $translatedEnvironment="Production";
  if($casdEnvironment)
  {
    switch($casdEnvironment)
    {
      case ("Development")
      {
        $translatedEnvironment="Unit Test";
      }
      case ("Test")
      {
        $translatedEnvironment="Unit Test";
      }
      case ("Production")
      {
        $translatedEnvironment="Production";
      }
      case ("Disaster Recovery")
      {
        $translatedEnvironment="Production";
      }
      case ("Model")
      {
        $translatedEnvironment="Quality Assurance";
      }
      case ("Education")
      {
        $translatedEnvironment="Education";
      }
      case ("Staging")
      {
        $translatedEnvironment="Staging";
      }
      case ("Regression")
      {
        $translatedEnvironment="Regression";
      }
      case ("Integration")
      {
        $translatedEnvironment="Integration";
      }
      case ("Pre-Prod")
      {
        $translatedEnvironment="Load";
      }
      case ("Load")
      {
        $translatedEnvironment="Load";
      }
    }
    writeLog("\nDEBUG: Matching environment found: $casdEnvironment : $translatedEnvironment.\n");
  } else {
    writeLog("WARNING: No matching valid environment found, using default: $translatedEnvironment.\n");
  }

  #+################################################################################
  # BUILD NEW MESSAGE BODY
  #
  # (text).(json){key}[index].(captured-value)
  #
  # OR
  #
  # (text).(json){key}[index].(json){key}[index]
  #+################################################################################
  my $newMessageBody="";
  $newMessageBody=($decodedJSON->{'OpenTag'}->[0]).
            ('Server: ').($RUNTIME_SERVER).("\n").
            ('Action: Submit').("\n").
            ('Format: Short').("\n").
            ('Login: ').($REMEDY_USER).("\n").
            ('Password: ').($REMEDY_PASSWORD).("\n").
            ('Status: ').($decodedJSON->{'Status'}->[0]).("New").("\n").
            ('First Name: ').($decodedJSON->{'First Name'}->[0]).($FIRST_NAME).("\n").
            ('Last Name: ').($decodedJSON->{'Last Name'}->[0]).($LAST_NAME).("\n").
            ('CI Name: ').($decodedJSON->{'CI Name'}->[0]).($casdAffectedRC).("\n").
            ('Urgency: ').($decodedJSON->{'Urgency'}->[0]).($decodedJSON->{'Urgency'}->[3]).("\n").
            ('Impact: ').($decodedJSON->{'Impact'}->[0]).($decodedJSON->{'Impact'}->[3]).("\n").
            ('Contact Using AlarmPoint: ').($decodedJSON->{'AlarmPoint'}->[0]).($casdContactUsingAlarmPoint).("\n").
            ('AlarmPoint Group ID: ').($decodedJSON->{'AlarmPoint Group'}->[0]).($casdAlarmPointGroupID).("\n").
            ('Assigned Group: ').($decodedJSON->{'Assigned Group'}->[0]).($groupName).("\n").
            ('Assignee: ').($decodedJSON->{'Assignee'}->[0]).($casdAssignee).("\n").
            ('Failure Code: ').($decodedJSON->{'Failure Code'}->[0]).($casdFailureCode).("\n").
            ('Environment: ').($decodedJSON->{'Environment'}->[0]).($translatedEnvironment).("\n").
            ('Service Type: ').($decodedJSON->{'Service Type'}->[0]).($decodedJSON->{'Service Type'}->[5]).("\n").
            ('Reported Source: ').($decodedJSON->{'Reported Source'}->[0]).($decodedJSON->{'Reported Source'}->[6]).("\n").
            ('Service Categorization Tier 1: ').($decodedJSON->{'Tier 1'}->[0]).('Review').("\n").
            ('Service Categorization Tier 2: ').($decodedJSON->{'Tier 2'}->[0]).('Software').("\n").
            ('Service Categorization Tier 3: ').($decodedJSON->{'Tier 3'}->[0]).('Event').("\n").
            ('Process Name: ').($decodedJSON->{'Process Name'}->[0]).($casdProcessName).("\n").
            ('Process ID: ').($decodedJSON->{'Process ID'}->[0]).($casdProcessID).("\n").
            ('Step Name: ').($decodedJSON->{'Step Name'}->[0]).($casdStepName).("\n").
            ('Details: ').($decodedJSON->{'Details'}->[0]).'[$$'.$casdDescription.'$$]'.("\n"). #The [$$ $scalar $$] allows the value to properly span multiple lines.
            ('Description: ').($decodedJSON->{'Description'}->[0]).($casdSummary).("\n");

  #+################################################################################
  # REQUIRED REMEDY FIELD VALUES
  #+################################################################################
  my $translatedMessageHeader="$messageHeader";
  # writeLog("DEBUG: Header translated to: $translatedMessageHeader\n") if($DEBUG);

  my $translatedMessageSubject="Translated message with ID: $translationID";
  writeLog("DEBUG: Subject translated to: $translatedMessageSubject\n") if($DEBUG);

  my $translatedMessageBody="$newMessageBody";
  writeLog("DEBUG: Message body translated to: \n\n") if($DEBUG);
  writeLog("$translatedMessageBody\n\n") if($DEBUG);

  my $translatedMessageDate="$messageDate";
  writeLog("DEBUG: Message date translated to: $translatedMessageDate\n") if($DEBUG);

  my $translatedMessageSender="$MESSAGE_SENDER";
  writeLog("DEBUG: Sender set to: $translatedMessageSender\n") if($DEBUG);

  my $translatedMessageReceiver="$MESSAGE_RECEIVER";
  writeLog("DEBUG: Receiver set to: $translatedMessageReceiver\n") if($DEBUG);

  #+################################################################################
  # COMBINE TRANSLATED PARTS TO FORM FINAL TRANSLATED MESSAGE
  #+################################################################################
  writeLog("Finalizing translation for sending to receiver.\n");
  $beforeOrAfter=1;
  exportMessageToFile();
  $readyForDispatch=1;
  dispatchTranslatedMessage($translatedMessageSubject, $translatedMessageBody);
}
####################################################################################
# MANAGE TRANSLATION
####################################################################################
sub cleanCAData
{
  writeLog("DEBUG: Stripping leading/trailing whitespace, quotes and HTML elements from message portion: $1\n") if($DEBUG);
  my $dirtyData=shift;

  return "" if(!defined($dirtyData));
  #+################################################################################
  # REMOVE LEADING AND TRAILING SPACES
  #+################################################################################
  $dirtyData=~s/^\s+//;
  $dirtyData=~s/\s+$//;
  #+################################################################################
  # SOME MESSAGES CONTAIN DOUBLE QUOTES "" AROUND GROUP NAME
  #+################################################################################
  $dirtyData=~s/^"//;
  $dirtyData=~s/"$//;
  #+################################################################################
  # SOME MESSAGES CONTAIN HTML <br> ELEMENTS
  #+################################################################################
  $dirtyData=~s/\<br\>//g;

  return $dirtyData;
}
####################################################################################
# TRANSLATE MESSAGE FROM BASE TO TARGET
#
# Unless inverse mode is active, which reverse the direction of translation
# from the configured default.
#
# Takes ingested JSON formatted data and seeks matching key/value pairs.
#
# "Key": ["BaseValue","TargetValue"],
####################################################################################
sub translateMessageToCASD
{
  writeLog("Begin translating message to CA Service Desk.\n");
}
####################################################################################
# TAKE TRANSLATION AND SEND MESSAGE AND ATTACHMENTS TO CONFIGURED RECEIVER
####################################################################################
sub dispatchTranslatedMessage
{
  my $translatedMessageSubject=shift;
  my $translatedMessageBody=shift;
  $translatedMessageBody =~ s!\n!\r\n!g;
  # print $translatedMessageBody;

  if($readyForDispatch)
  {
    my $smtp = Net::SMTP->new($SMTP_SERVER, Timeout => 60) || die("CRITICAL ERROR: Unable to create message for dispatch: $!");
    $smtp->mail($MESSAGE_SENDER); #from
    $smtp->recipient($MESSAGE_RECEIVER);
    $smtp->data();
    $smtp->datasend("From: $MESSAGE_SENDER\r\n");
    $smtp->datasend("To: $MESSAGE_RECEIVER\r\n");
    $smtp->datasend("Subject: $translatedMessageSubject\r\n");
    $smtp->datasend("\r\n");
    $smtp->datasend("$translatedMessageBody");
    $smtp->dataend();
    $smtp->quit();
  }
}
####################################################################################
# DETERMINE & ANNOUNCE RUNTIME ENVIRONMENT
####################################################################################
sub determineRuntime 
{
  writeLog("Attempting translation initialization on: $operatingSystem.\n");
  writeLog("Translation matrix housed at: $workingDirectory.\n");
  writeLog("Translation is using Perl version: $perlVersion.\n");

  GetOptions(
  'mode|m=s' => \($runtimeMode),
  'file|f=s' => \($messageBundle),
  'debug|d' => \($DEBUG),
  ) or die "CRITICAL ERROR: UNRECOGNIZED RUNTIME ARGUMENT: $0 $runtimeMode\n";

  if($runtimeMode)
  {
    writeLog("Proceeding with translation in $runtimeMode mode.\n");
  } else {
    writeLog("TRANSLATION ABORTED AT RUNTIME WITH INVALID STATE: $!.\n");
  }
}
####################################################################################
# CREATE OR MANAGE MESSAGE ARCHIVES
#
# If daily archive doesn't exist, create it. Afterward, insert message to archive
# into the existing daily archive using the --append flag for tar.
#
# Archival is run once for each message processed.
####################################################################################
sub manageArchive
{
  $translationArchive = Archive::Tar->new;
  @fileList = ("$currentMessage");

  my $dateForFilename = strftime "%Y%m%d", localtime;
  my $archiveName = ("$archiveDir"."/TranslationArchive_"."$dateForFilename".".tar");

  if(!$successBoolean)
  {
    writeLog("CRITICAL ERROR: Unable to export message with id $translationID to file.\n");
    exit 10
  }

  open(my $messageFile, '>', $currentMessage) or die "CRITICAL ERROR: COULD NOT CREATE FILE FOR ARCHIVING. - $!";

  if(! -f $archiveName)
  {
    #++#############################################################################
    # CREATE THE ARCHIVE AND INSERT THE FILE
    #++#############################################################################
    writeLog("Today's archive does not exist. Creating dated archive now.\n");
    #$translationArchive->write( "$archiveName", COMPRESS_GZIP);
    $translationArchive->write("$archiveName");
    insertMessageToArchive();

    if(! -f $archiveName)
    {
      writeLog("CRITICAL ERROR: Failed to create daily archive: $!\n");
      exit 10;
    }
  } else {
    # Insert the message file into the pre-existing archive.
    writeLog("Today's dated archive already exists.\n");
    insertMessageToArchive();
  }
  close $messageFile or die "CRITICAL ERROR: CANNOT CLOSE MESSAGE FILE!";
}
####################################################################################
# TAKE THE CURRENT MESSAGE AND INSERT IT INTO TODAY'S ARCHIVE
####################################################################################
sub insertMessageToArchive
{
  @fileList = ("$currentMessage");

  writeLog("Attempting to add $currentMessage to dated archive.\n") if($DEBUG);

  open($translationArchive, '>', $currentMessage) or die "CRITICAL ERROR: COULD NOT CREATE FILE FOR ARCHIVING. - $!";
  $translationArchive->add_files($currentMessage);

  if(!$translationArchive->contains_file("$currentMessage"))
  {
    writeLog("CRITICAL ERROR: Failed to add $fileList[0] to dated archive: $!\n");
    exit 10;
  }
  else
  {
    writeLog("Successfully added $currentMessage to dated archive $translationArchive.\n");
  }

  close $translationArchive or die "CRITICAL ERROR: UNABLE TO CLOSE MESSAGE FILE!";
}
####################################################################################
# TAKE MESSAGE CONTENTS AND GENERATE A CHECKSUM
####################################################################################
sub generateTranslationID
{
  my $hashData = ($fullMessageBlock);
  my $md5Hash =(md5_hex("$hashData"));
  my $hashLength = (length $md5Hash);

  $translationID = $md5Hash;

  if($hashLength==32)
  {
    writeLog("\nCurrent message has been assigned an ID of ".$translationID.".\n");
  } else {
    writeLog("WARNING: Invalid ID length of $hashLength for translation ID: ".$translationID.".\n");
  }
}
####################################################################################
# EXPORT MESSAGE TO FILE
####################################################################################
sub exportMessageToFile
{
  my $fileDateTime = (strftime("%Y%m%d-%H%M%S", localtime(time)));

  if(!$beforeOrAfter)
  {
    $currentMessage = ("$archiveDir"."before/"."$fileDateTime-$translationID.msg");
  } else {
    $currentMessage = ("$archiveDir"."after/"."$fileDateTime-$translationID.msg");
  }
  #+################################################################################
  # TEST IF EXPORT ALREADY EXISTS FOR TRANSLATION ID
  #+################################################################################
  my $exportExists=0;
  my $exportDir;

  if(!$beforeOrAfter)
  {
    $exportDir=("$archiveDir"."before/");
  } else {
    $exportDir=("$archiveDir"."after/");
  }

  opendir(DIR,("$exportDir"));
    my @archiveFileArray=readdir(DIR);
  closedir DIR;

  foreach my $archiveFile (@archiveFileArray)
  {
    if(index($archiveFile,$translationID) != -1)
    {
      $exportExists=1;
      last;
    }
  }
  #+################################################################################
  # EXPORT IF UNIQUE AND WARN IF NOT UNIQUE
  #+################################################################################
  if($exportExists)
  {
    writeLog("WARNING: Message with translation ID $translationID already archived. Skipping export.\n");
  } else {
    open(my $fh, '>>', "$currentMessage") or die "CRITICAL ERROR: Could not write message to $currentMessage. $!\n";
      print $fh "$messageHeader\n";
      print $fh "$messageSubject\n";
      print $fh "$messageDate\n";
      print $fh "$messageBody\n";
    close $fh;
    #+++############################################################################
    # Verify the message file was written to disk.
    #+++############################################################################
    if($currentMessage)
    {
      $successBoolean=1;
      writeLog("Message exported to file: $currentMessage\n");
    } else {
      $successBoolean=0;
      writeLog("CRITICAL ERROR: Unable to export message with ID $translationID to file, aborting translation.\n");
      exit 10;
    }
  }
}
####################################################################################
# CHECK FOR TRANSLATABLE MESSAGES
####################################################################################
sub retrieveMessages
{
  my $remoteConnection;

  my $imap = Net::IMAP::Client->new(
    server => $MAIL_SERVER, # (Mailserver address.)
    user   => $MAIL_USER,   # (Mail account user.)
    pass   => $MAIL_PASS,   # (Email account password.)
    ssl    => 0,            # (BOOLEAN: use SSL? default of 0 is no. )
    port   => 143,          # (STRING:  but defaults are sane)
    uid_mode => 1,          # (BOOLEAN: use the UID mode) 
  );

  if(!$imap)
  {
    writeLog("CRITICAL ERROR: Unable to connect to mail server.\n");
    exit 10;
  }
  writeLog("DEBUG: Contact made with $MAIL_SERVER.\n") if($DEBUG);

  #+################################################################################
  # MAKE SURE LOGIN IS SUCCESSFUL
  #+################################################################################
  $remoteConnection=$imap->login;

  if(!$remoteConnection)
  { 
    writeLog("CRITICAL ERROR: Unable to login to mail server: $remoteConnection:".$imap->last_error."\n"); 
    exit 10;
  }
  writeLog("DEBUG: Connected to $MAIL_SERVER.\n") if($DEBUG);
  #+################################################################################
  # MAKE SURE INBOX IS SELCTABLE
  #+################################################################################
  # $remoteConnection=$imap->select('/Translator');
  $remoteConnection=$imap->select('INBOX');
  if(!$remoteConnection)
  { 
    writeLog("CRITICAL ERROR: Unable to select mailbox: $remoteConnection:".$imap->last_error."\n"); 
    exit 10;
  }
  writeLog("DEBUG: Checking mailbox for messages to translate.\n") if($DEBUG);

  my $messages = $imap->search('ALL', undef, 'US-ASCII');
  #+################################################################################
  # MAKE SURE MAILBOX IS SEARCHABLE
  #+################################################################################
  if(!defined($messages))
  {
    writeLog("CRITICAL ERROR: Unable to search mailbox.\n");
    exit 10;
  }
  #+################################################################################
  # HOW MANY MESSAGES NEED TRANSLATING?
  #+################################################################################
  my $messageCount=scalar(@$messages);

  if ($messageCount <= 0)
  {
    writeLog("NO MESSAGES TO TRANSLATE, GOING BACK TO SLEEP.\n\n");
  } else {
    writeLog("Found " . $messageCount . " messages to translate.\n\n");
  }
                                                                                
  if(!defined($messageCount))
  {
    writeLog("CRITICAL ERROR: UNABLE TO DETERMINE MESSAGE COUNT FROM MAILBOX.\n");
    exit 10;
  }

  my $messagesProcessed=0;
  #+################################################################################
  # PROCESS EACH MESSAGE AND REMOVE IT FROM THE SERVER
  #+################################################################################
  foreach my $message (@$messages)
  {
    my $msg=$imap->get_rfc822_body($message);
    
    if($msg)
    {
      if(processMessage($$msg)==0)
      {
        #++++######################################################################
        # DELETE MESSAGES WITH NO CA SUMMARY AS GARBAGE
        #++++######################################################################
        # TO DO, DELETE PROCESSED MESSAGES!
        writeLog("DEBUG: Moving message to mailbox trash.\n") if($DEBUG);
        $imap->delete_message($message);

        writeLog("DEBUG: Permanently deleting message from mail server.\n") if($DEBUG);
        $imap->expunge();
      }
    } else {
      writeLog("CRITICAL ERROR: Error retrieving message $messagesProcessed from mail server for translation.\n");
    }
    
    $messagesProcessed++;
    if($messagesProcessed>=$MAX_TO_PROCESS)
    {
      writeLog("Translator has completed maximum allowable consecutive translations. Translation will resume after a break.\n");
      last;
    }
  }
  $imap->logout;
}
####################################################################################
# PROCESS MESSAGE - READ MESSAGE CONTENTS
####################################################################################
sub processMessage
{
  my $mimeMessage=shift;
  my $entity;
  $messageSubject="";
  $messageBody="";
  $messageDate="";
  my $parser=new MIME::Parser;
  my $directory=tempdir(DIR=>$tmpDir, CLEANUP=>1);#  0 for testing

  writeLog("\n[:::] Starting analysis of new message.\n");

  $parser->output_under($directory);
  eval {$entity=$parser->parse_data($mimeMessage);};

  if($@)
  {
    my $results=$parser->results;
    writeLog("WARNING: Deleting message because translation failed while reading message:".$results->errors."\n");
    # If I can't parse it, delete it.
    return -1;
  }
 
  #$entity->dump_skeleton(\*STDERR);
  #+################################################################################
  # READ THE (UNENCODED) BODY DATA:
  #+################################################################################
  my $numparts=$entity->parts;
  writeLog("DEBUG: Message contains ".$numparts." parts in total.\n") if($DEBUG);
  if($numparts==0)
  {
    $messageBody=$entity->bodyhandle->as_string();
  } else {

    for(my $i=0; $i<$numparts; $i++) {
      my $thisPart=$entity->parts($i);
      my $mimeType=$thisPart->mime_type;
      #if($mimetype =~ /^text\/plain/) {
      if($mimeType =~ /^multipart\/alternative/)
      {
        #+++########################################################################
        # IF THE ATTACHMENT IS NESTED.
        #+++########################################################################
        if($thisPart->parts>0)
        {
          writeLog("DEBUG: Multipart message, beginning with first part.\n") if($DEBUG);
          $thisPart=$thisPart->parts(0);
          $mimeType=$thisPart->mime_type;
        } else {
          writeLog("DEBUG: Multipart message with no parts?.\n") if($DEBUG);
        }
      }
      my $cd=$thisPart->head->get('Content-Disposition');
      $cd="" if(!$cd); # to hide warning.
      writeLog("$i:mime:$mimeType:cd:$cd\n") if($DEBUG);
      #++###########################################################################
      # IF IT'S TEXT AND NOT AN ATTACHMENT PART, USE IT AS THE BODY
      #++###########################################################################
      if($mimeType =~ /^text\/plain/ && (!$cd || $cd !~ /attachment;/))
      {
        $messageBody.=$thisPart->bodyhandle->as_string();
      }
    }
  }
  $messageHeader=$entity->header_as_string;


  $messageBody =~ s/\r//g;  # Strip CRs
  $messageHeader =~ s/\r//g;  # Strip CRs

  writeLog("Header is: $messageHeader\n") if($DEBUG);
  writeLog("Body is: $messageBody\n") if($DEBUG);

  ($messageSubject) = ($messageHeader =~ /^Subject:(.*)$/m);
  writeLog("Subject:$messageSubject\n") if($DEBUG);

  ($messageDate) = ($messageHeader =~ /^Date: (.*)$/m);
  writeLog("Date:$messageDate\n") if($DEBUG);

  #+################################################################################
  # FULL MESSAGE BLOCK IS USED BY THE GENERATETRANSLATIONID METHOD
  #+################################################################################
  $fullMessageBlock=("$messageHeader"."$messageBody"."$messageSubject"."$messageDate");

  $beforeOrAfter=0;
  generateTranslationID();
  exportMessageToFile();
  translateMessage();

  return 0;
}
####################################################################################
# RUNTIME MODE TREES
####################################################################################
sub runtimeTree
{
  switch($runtimeMode)
  {
    case ("mail" | "m")
    {
      $CURRENT_DIRECTIVE="$DEFAULT_DIRECTIVE";
      writeLog("Using default runtime directive: $CURRENT_DIRECTIVE.\n");
      writeLog("DEBUG: Looking for messages to translate.\n") if($DEBUG);
      retrieveMessages();
    }
    case ("file" | "f")
    {
      #++###########################################################################
      # Take supplied tarball, explode it into a temporary directory and iterate
      # over the contents, ignoring $maximumMessages.
      #++###########################################################################
      $CURRENT_DIRECTIVE="$DEFAULT_DIRECTIVE";
      writeLog("Using default runtime directive: $CURRENT_DIRECTIVE.\n");
      writeLog("=== Here is where I would translate some messages. ===\n") if($DEBUG);

      writeLog("DEBUG: FILE BASED RUNTIME MODE NOT YET IMPLEMENTED.\n") if($DEBUG);
    }
    case ("test" | "t")
    {
      #++###########################################################################
      # Take supplied defaults and run as usual without exporting results to archive
      # or sending translated messages to default recipient mailbox.
      #++###########################################################################
      $CURRENT_DIRECTIVE="$DEFAULT_DIRECTIVE";
      writeLog("Using default runtime directive: $CURRENT_DIRECTIVE.\n");
      writeLog("=== Here is where I would translate some messages in \"preview\" mode. ===\n") if($DEBUG);

      writeLog("DEBUG: TEST RUNTIME MODE NOT YET IMPLEMENTED.\n") if($DEBUG);
    }
    case ("rerun" | "r")
    {
      #++###########################################################################
      # Take supplied date, reach into the corresponding archive to extract the
      # message with the supplied translationID and rerun the "before" message.
      #++###########################################################################
      $CURRENT_DIRECTIVE="$DEFAULT_DIRECTIVE";
      writeLog("Using default runtime directive: $CURRENT_DIRECTIVE.\n");
      writeLog("=== Here is where I would translate a single message. ===\n") if($DEBUG);

      writeLog("DEBUG: RERUN RUNTIME MODE NOT YET IMPLEMENTED.\n") if($DEBUG);
    }
    case ("inverse" | "i")
    {
      #++###########################################################################
      # Assume directive should be reverse, and use the appropriate conversion
      # method for each message in the mailbox.
      #++###########################################################################
      $CURRENT_DIRECTIVE="$INVERSE_DIRECTIVE";
      writeLog("Using inverse runtime directive: $CURRENT_DIRECTIVE.\n");
      writeLog("DEBUG: INVERSION RUNTIME MODE NOT YET IMPLEMENTED.\n") if($DEBUG);
      retrieveMessages();
    }
    else
    {
      writeLog("TRANSLATION ABORTED DURING TRANSLATION WITH INVALID ARGUMENT: $!.\n");
    }
  }
}
####################################################################################
# MAIN FUNCTIONAL DECLARATIONS
####################################################################################
sub main
{
  #+################################################################################
  # LOGGING AND PROCESS INSTANTIATION
  #+################################################################################
  openLog();
  writeLog("\n############################### START ######################################\n");
  writeLog("Translation commenced at: ".ctime(time())."\n");

  #+################################################################################
  # TRANSLATE MESSAGES ONLY IF RUNNING ON THE CURRENT SITESCOPE MASTER
  #+################################################################################
  if ( ! -e "/opt/scripts/failoverstatus/sitescope")
  {
    writeLog("Translator is NOT running on the current SiteScope master. Aborting translation.\n");
  } else {
    writeLog("Translator is running on the current SiteScope master.\n");

    determineRuntime();
    loadConfig();
    runtimeTree();
  }

  writeLog("\nTranslation concluded at: ".ctime(time())."\n");
  writeLog("############################### STOP #######################################\n");
  closeLog();
}
main();
