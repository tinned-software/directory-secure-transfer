#!/bin/bash
#
# @author Gerhard Steinbeis (info [at] tinned-software [dot] net)
# @copyright Copyright (c) 2012 - 2013
version=0.6.5
# @license http://opensource.org/licenses/GPL-3.0 GNU General Public License, version 3
# @package filesystem
#


#
# Non Config values
#
# Get script directory
SCRIPT_PATH="$(dirname $(readlink -f $0))"
# Waiting time before the remote MD5 is checked again
MD5_WAIT_SECONDS=3
# Maximum waiting time for the remote MD5 is considered failed
MD5_MAX_WAIT_LOOPS=60


#
# Loading functions
#
. $SCRIPT_PATH/echotime.sh


#
# CONFIG DEFAULT VALUES
#

# the ssh hostname or IP to connect to. This hostname or IP is as well 
# used as a subdirectory if the option "host-subdir" is provided as well.
SERVER_NAME=""

# additional ssh options. See ssh man page for details.
SERVER_SSH_PORT="22"

# the ssh username to connect with
USER_NAME=""

# The remote directory to synchronize. This directory will be searched 
# recursive. Empty directories will not be copied.
REMOTE_PATH=""

# If this option is set the file and path name is filtered using a Perl 
# regular expression. If this option is not set, all files are checked.
REMOTE_FILEPATH_REGEX=""

# This configuration is used for additional filter the file list by 
# modification date. When defined as "+1", the file must be older then
# 1 day (1*24h). When defined as "-1" the file should be junger then
# 1 day. When defined as "1" the file must me exactly 1 day old.
# The man page of find (option -atime) shows all details.
FILE_AGE=""

# The local directory to sync the files to. If the host-subdir option is 
# provided, the subdirectories will be created under this path
LOCAL_PATH=""

# Enable the use of the server host as subdirectory in the local path 
USE_HOST_SUBDIR=0

# Running time for the script in seconds. A started transfer will not be 
# interrupted from this time limit. The transfered File and its related 
# actions will always be completed.
# 1 hour -> 3600
# 1 day -> 24 hours -> 86400
RUN_TIME=0

# Running time until a defined date and time. This allowes to specify 
# the date and time when the script should stop. The transfered File and 
# its related actions will always be completed.
# Format: "2012-11-22 09:58"
RUN_UNTIL=""

# Skip copy operation entirely. This can be used to check the state of 
# the local copy without changeing any data (if ALLOW_REMOTE_DELETE is 
# disabled) or to cleanup the remote copy (if ALLOW_REMOTE_DELETE is 
# enabled)
SKIP_COPY_ACTION=0

# The download speed limit for the file transfer (KB/s)
# 100MBit/s -> Netto 94MBit/s -> 11,75MB/s -> 30%: 3609,6 KB/s
# 1GBit/s -> Netto 940MBit/s -> 117,5MB/s -> 30%: 36096 KB/s
DOWNLOAD_SPEEDLIMIT=500

# Enables the delete of the downloaded and verified files
ALLOW_REMOTE_DELETE=0

# Show verbose output. If not set to 1, the script will be silent.
VERBOSE=0

# Disable the use of trickle for bandwidth shaping. If this setting is set to 
# 0 the script will try to automatic detect if trickle is available or not. 
# For more details about trickle see http://monkey.org/~marius/pages/
DISABLE_TRICKLE=0

#
# CONFIG DEFAULT VALUES END
#


#
# Parse all parameters
#
HELP=0
while [ $# -gt 0 ]; do
    case $1 in
        # General parameter
        -h|--help)
            HELP=1
            shift
            ;;
        -v|--version)
            echo "`basename $0` version $version"
            exit 0
            ;;

        # specific parameters
        --config)
            # load settings file
            if [[ -f "$2" ]]; then
                . $2
                shift 2
            else
                shift 2
                echo "ERROR: Config file does not exist."
                HELP=1
                break;
            fi
            ;;

        --verbose)
            VERBOSE=`expr $VERBOSE + 1`
            shift
            ;;
        
        --server)
            SERVER_NAME=$2
            shift 2
            ;;

        --ssh-port)
            SERVER_SSH_PORT=$2
            shift 2
            ;;

        --user)
            USER_NAME=$2
            shift 2
            ;;

        --remote-path)
            REMOTE_PATH=$2
            shift 2
            ;;

        --file-regex)
            REMOTE_FILEPATH_REGEX=$2
            shift 2
            ;;

        --file-age)
            FILE_AGE=$2
            shift 2
            ;;

        --local-path)
            LOCAL_PATH=$2
            shift 2
            ;;

        --host-subdir)
            USE_HOST_SUBDIR=1
            shift
            ;;
            
        --run-time)
            RUN_TIME=$2
            shift 2
            ;;
            
        --run-until)
            RUN_UNTIL=$2
            shift 2
            ;;
            
        --speedlimit)
            DOWNLOAD_SPEEDLIMIT=$2
            shift 2
            ;;

        --skip-copy)
            SKIP_COPY_ACTION=1
            shift
            ;;

        --delete)
            ALLOW_REMOTE_DELETE=1
            shift
            ;;
            
        # undefined parameter        
        *)
            echo "Unknown option '$1'"
            HELP=1
            shift
            break
            ;;
    esac
done





#
# Check configuration items
#

if [[ -z "${USER_NAME}" ]]; then
    echo "ERROR: ssh user name is missing."
    HELP=1
fi

if [[ -z "${SERVER_NAME}" ]]; then
    echo "ERROR: ssh server name or IP address is missing."
    HELP=1
fi

if [[ "${REMOTE_PATH}" == "" ]]; then
    echo "ERROR: remote-path is required."
    HELP=1
fi

if [[ ! -d "${LOCAL_PATH}" ]]; then
    echo "ERROR: local-path is required or not existing."
    HELP=1
fi



#
# Check OS differences
#
OS_TYPE=`uname -s`
case $OS_TYPE in
    "Darwin")
        if [[ "$VERBOSE" -ge "2" ]]; then
            echo "Operating System      : Darwin"
        fi

        # MD5 program name and arguments
        MD5_CMD="md5"
        MD5_OPT="-r"
        ;;
    "Linux")
        if [[ "$VERBOSE" -ge "2" ]]; then
            echo "Operating System      : Linux"
        fi

        # MD5 program name and arguments
        MD5_CMD="md5sum"
        MD5_OPT=""
        ;;
    *)
        echo "Operating System      : UNKNOWN ($OS_TYPE) - Using Linux definition"

        # MD5 program name and arguments
        MD5_CMD="md5sum"
        MD5_OPT=""
        ;;
esac


# calculate end time
START_TIME=`date "+%s"`
if [[ "$RUN_UNTIL" != "" ]]; then
    # calculate the given time and date into a timestamp
    if [[ "$OS_TYPE" == "Darwin" ]]; then
        END_TIME=`date -j -f "%Y-%m-%d %H:%M" "$RUN_UNTIL" "+%s"`
        RC=$?
        if [[ "$VERBOSE" -ge "2" ]]; then
            echo "   Calculate End time : 'date -j -f \"%Y-%m-%d %H:%M\" \"$RUN_UNTIL\" \"+%s\"'"
            echo "   End time           : $END_TIME"
        fi
    else
        END_TIME=`date --date="$RUN_UNTIL" "+%s"`
        RC=$?
        if [[ "$VERBOSE" -ge "2" ]]; then
            echo "   Calculate End time : 'date --date=\"$RUN_UNTIL\" \"+%s\"'"
            echo "   End time           : $END_TIME"
        fi
    fi        
else
    if [[ "$RUN_TIME" -eq "0" ]]; then
        # if nothing is defined, calculate a far away time stamp
        END_TIME=`expr $START_TIME \* 2`
        RC=$?
    else
        # calculate the end timestamp according to the running time
        END_TIME=`expr $START_TIME + $RUN_TIME`
        RC=$?
    fi
fi
# Check if calculation of the end time was successfull
if [[ "$RC" != "0" ]]; then
    echo "ERROR: Specified runtime was not numeric or rununtil was wrong formated."
    HELP=1
else
    # check if end time is in the past
    if [[ "$END_TIME" -lt "$START_TIME" ]]; then
        echo "ERROR: Specified rununtil was in the past."
        HELP=1
    fi
fi



# show help message
if [ "$HELP" -eq "1" ]; then
    echo 
    echo "This script will connect to the remote host and compares the remote directory to"
    echo "the local directory. All files that are different, will be downloaded to the "
    echo "local directory. when specified, the remote file is deleted after the transfer "
    echo "is completed and veryfied. The run-time parameter defined the time the script "
    echo "should run. This is not a hard limit. The script will not terminate a running "
    echo "file transfer because of the run-time limit."
    echo 
    echo "Usage: `basename $0` [-hv] [--config filename.conf] [--runtime 10] [--speedlimit 500] [--delete] [--host-subdir] --user user --server servername --remote-path /path/on/remote/host --local-path /local/path/"
      echo "  -h  --help         Print this usage and exit"
    echo "  -v  --version      Print version information and exit"
      echo "      --config       Configuration file to read parameters from"
      echo "      --user         The ssh username to connect with"
      echo "      --server       The ssh hostname or IP to connect to (used as subdirectory if enabled)"
      echo "      --ssh-port     Additional ssh options"
      echo "      --remote-path  The path on the remote server to sync from"
      echo "      --file-regex   A file and path name regex pattern applied when reading remote file list"
      echo "      --file-age     Filter on file date. \"+1\" means older ten one day, \"-1\" means junger then one day"
      echo "      --local-path   The local path to sync to (host-subdir are created here if enabled)"
      echo "      --verbose      Show verbose output. can be called multiple times (2 times)."
      echo "      --run-time     Running time for the script in seconds (running transfer will not be interrupted)"
      echo "      --run-until    Running until specified time (running transfer will not be interrupted) Format: \"2012-11-22 09:58\""
      echo "      --speedlimit   The download speed limit for the file transfer (KB/s)"
      echo "      --skip-copy    Skip copy operations entirely"
      echo "      --delete       Enables the delete of the downloaded and verified files"
      echo "      --host-subdir  Use ssh server host as subdirectory in the local path"
      echo 
    exit 1
fi


#
# PROCEDURE
#
# 1) Get a list of files from remote host
# 2) Go through the list and ...
# 2.1 ) Get the MD5 hash of the remote file
# 2.2 ) Check if the remote file exists localy by filename and MD5 hash
# 2.3 ) If file is not existing or MD5 hash missmatch, mark it for copy
# 2.4 ) If file exists and MD5 hash match, mark it for delete remote file
# 2.5 ) If copy, check if local directory exists and create it if not
# 2.6 ) if copy, transfer file with defined download speed limit
# 2.7 ) Check transfer result
# 2.8 ) If tranfser successful, check with MD5 hash of remote file
# 2.9 ) If MD5 hash check match, mark it for delete remote file
# 2.10) If marked Delete and Deleting is enabled, delete remote file
# 2.11) Check running time, if exeeded end the loop
# 3) Print the list of errors at the end of the script (no verbose option needed to show them)
#


if [[ "$VERBOSE" -ge "1" ]]; then
    echotime 
    echotime "**********************************************************"
    echotime "*** Starting for $USER_NAME@$SERVER_NAME ... "
    echotime "**********************************************************"
fi

# get the subdirectory if enabled
if [[ "$USE_HOST_SUBDIR" -eq "1" ]]; then
    LOCAL_SUBDIR="/$SERVER_NAME"
fi



# If regex to filter file list is defined
REMOTE_LIST_FILTER=""
if [[ "$REMOTE_FILEPATH_REGEX" != "" ]]; then
    REMOTE_LIST_FILTER="| grep -P \"$REMOTE_FILEPATH_REGEX\""
fi



# Check for trickle. If it is disabled, akt as it is not installed on 
# the system. If it is not disabled, try to find it.
if [[ "$DISABLE_TRICKLE" -eq "1" ]]; then
    RC=1
else
    RES=`which trickle`
    RC=$?
fi
# Check if trickle was found
if [[ "$RC" == "0" ]]; then
    # use trickle to shape the bandwidth
    BANDWITH_SHAPER="trickle"
    if [[ "$VERBOSE" -ge "1" ]]; then
        echotime "Shape bandwidth using : $BANDWITH_SHAPER"
    fi
else
    # Calculate ssh speed limit (Kbit/s) from trickle limit (KB/s)
    DOWNLOAD_SPEEDLIMIT_SSH=`expr $DOWNLOAD_SPEEDLIMIT \* 8`
    # use scp to shape the bandwidth
    BANDWITH_SHAPER="scp"
    if [[ "$VERBOSE" -ge "1" ]]; then
        echotime "Shape bandwidth using : $BANDWITH_SHAPER"
    fi
fi



# initialize statistic variables
ACT_COPY=0
ACT_COPY_SKIP=0
ACT_DEL=0
ACT_DEL_SKIP=0


#
# Read the list of files to be transfered from remote server
#
if [[ "$VERBOSE" -ge "1" ]]; then
    echotime "Remote file list      : Request file list"
fi
if [[ "$FILE_AGE" != "" ]]; then
    if [[ "$VERBOSE" -ge "2" ]]; then
        echotime "Read remote file list : 'ssh -p $SERVER_SSH_PORT $USER_NAME@$SERVER_NAME \"cd $REMOTE_PATH ; find . -type f -atime $FILE_AGE $REMOTE_LIST_FILTER\""
    fi
    SECTION_START_TIME=`date "+%s"`
    REMOTE_FILELIST=`ssh -p $SERVER_SSH_PORT $USER_NAME@$SERVER_NAME "cd $REMOTE_PATH ; find . -type f -atime $FILE_AGE $REMOTE_LIST_FILTER"`
    RC=$?
else
    if [[ "$VERBOSE" -ge "2" ]]; then
        echotime "Read remote file list : 'ssh -p $SERVER_SSH_PORT $USER_NAME@$SERVER_NAME \"cd $REMOTE_PATH ; find . -type f $REMOTE_LIST_FILTER\""
    fi
    SECTION_START_TIME=`date "+%s"`
    REMOTE_FILELIST=`ssh -p $SERVER_SSH_PORT $USER_NAME@$SERVER_NAME "cd $REMOTE_PATH ; find . -type f $REMOTE_LIST_FILTER"`
    RC=$?
fi
if [[ $RC != 0 ]] ; then
    echotime "*** Error while reading file list from '$SERVER_NAME' at remote path '$REMOTE_PATH'. ERROR: '$REMOTE_FILELIST'"
    exit 1
fi
SECTION_END_TIME=`date "+%s"`
SECTION_RUN_TIME=$(($SECTION_END_TIME - $SECTION_START_TIME))



#
# Go through the list of files and check them localy
#
if [[ "$VERBOSE" -ge "1" ]]; then
    echotime "Compare local files with remote files ... Starting"
    echotime "==================================="
fi
# go through every entry in the file list
IFS="
"
for REMOTE_FILELINE in $REMOTE_FILELIST; do
    # initialize variables for the loop
    REMOTE_MD5HASH=""
    REMOTE_FILENAME=""
    REMOTE_FILEINFO=""
    REMOTE_FILESIZE=""
    LOCAL_MD5HASH=""
    COPY_REASON="-"
    MARK_COPY=0
    MARK_DELETE=0
    SECTION_START_TIME=`date "+%s"`

    # format the path and filename
    REMOTE_FILENAME=`echo "$REMOTE_FILELINE" | sed 's/^\.\///'`

    if [[ "$VERBOSE" -ge "1" ]]; then
        echotime "   Check   REMOTE file: '$REMOTE_PATH/$REMOTE_FILENAME'"
    fi

    # get the remote file size
    if [[ "$VERBOSE" -ge "2" ]]; then
        echotime "   Read file size     : 'ssh -p $SERVER_SSH_PORT $USER_NAME@$SERVER_NAME \"cd $REMOTE_PATH ; ls -lh $REMOTE_FILENAME\" | awk '{FS=" "}{print $5}'"
    fi
    REMOTE_FILESIZE=`ssh -p $SERVER_SSH_PORT $USER_NAME@$SERVER_NAME "cd $REMOTE_PATH ; ls -lh $REMOTE_FILENAME" | awk '{FS=" "}{print $5}'`
    RC=$?
    if [[ $RC != 0 ]] ; then
        ERROR=$ERROR"*** Error while reading remote file size. Server: '$SERVER_NAME' REMOTE File: '$REMOTE_PATH/$REMOTE_FILENAME' Details: '$RESULT'\n"
        if [[ "$VERBOSE" -ge "1" ]]; then
            echotime "                        *** Error while reading remote file size. Server: '$SERVER_NAME' REMOTE File: '$REMOTE_PATH/$REMOTE_FILENAME' Details: '$RESULT'\n"
        fi
        continue
    else
        if [[ "$VERBOSE" -ge "1" ]]; then
            echotime "   Size    REMOTE file: $REMOTE_FILESIZE"
        fi        
    fi

    #
    # check if the file localy exists
    #
    if [[ "$VERBOSE" -ge "1" ]]; then
        echotime "   Check   LOCAL file : '$LOCAL_PATH$LOCAL_SUBDIR/$REMOTE_FILENAME'"
    fi
    if [[ -e "$LOCAL_PATH$LOCAL_SUBDIR/$REMOTE_FILENAME" ]]; then
        #
        # calculate the checksum of local file
        #
        if [[ "$VERBOSE" -ge "2" ]]; then
            echotime "   Get local MD5 hash : '$MD5_CMD $MD5_OPT $LOCAL_PATH$LOCAL_SUBDIR/$REMOTE_FILENAME >$LOCAL_PATH/$$.md5sum &'"
        fi
        LOCAL_MD5HASH=`$MD5_CMD $MD5_OPT $LOCAL_PATH$LOCAL_SUBDIR/$REMOTE_FILENAME >$LOCAL_PATH/$$.md5sum &`


        #
        # calculate the checksum of remote file
        #
        if [[ "$VERBOSE" -ge "2" ]]; then
            echotime "   Get remote MD5 hash: 'ssh -p $SERVER_SSH_PORT $USER_NAME@$SERVER_NAME \"cd $REMOTE_PATH ; md5sum $REMOTE_FILENAME\""
        fi
        REMOTE_FILEINFO=`ssh -p $SERVER_SSH_PORT $USER_NAME@$SERVER_NAME "cd $REMOTE_PATH ; md5sum $REMOTE_FILENAME"`
        RC=$?
        if [[ $RC != 0 ]] ; then
            ERROR=$ERROR"*** Error while getting remote MD5 hash. Server: '$SERVER_NAME' REMOTE File: '$REMOTE_PATH/$REMOTE_FILENAME' Details: '$RESULT'\n"
            if [[ "$VERBOSE" -ge "1" ]]; then
                echotime "                        *** Error while getting remote MD5 hash. Server: '$SERVER_NAME' REMOTE File: '$REMOTE_PATH/$REMOTE_FILENAME' Details: '$RESULT'\n"
            fi
            continue
        fi
        # split the md5 sum from the path
        REMOTE_MD5HASH="${REMOTE_FILEINFO%% *}"    # get the part before the first " " (the md5 checksum)
        if [[ "$VERBOSE" -ge "1" ]]; then
            echotime "   Checked REMOTE md5 : '$REMOTE_MD5HASH'"
        fi
        # Check if filename is "-" (means a error occoured)
        if [[ "$REMOTE_FILENAME" == "-" ]]; then
            ERROR=$ERROR"***ERROR while reading file list from remote host. Server: '$SERVER_NAME'"    
            continue
        fi


        #
        # reading the checksum of local file
        #
        LC=0
        # check the file size to be bigger then 0 to know if process is finished
        MD5_SIZE=`ls -l $LOCAL_PATH/$$.md5sum | awk '{FS=" "}{print $5}'`
        while [[ "$MD5_SIZE"  == "0" ]]; do

            if [[ "$VERBOSE" -ge "2" ]]; then
                echotime "   Waiting LOCAL md5  : Waiting $MD5_WAIT_SECONDS seconds for MD5 hash"
            fi

            # sleep a moment before the next check
            sleep $MD5_WAIT_SECONDS
            
            # Loop Counter
            LC=`expr $LC + 1`

            # check the file size to be bigger then 0 to know if process is finished
            MD5_SIZE=`ls -l $LOCAL_PATH/$$.md5sum | awk '{FS=" "}{print $5}'`

            # avoid endless loop
            if [[ "$LC" -gt "$MD5_MAX_WAIT_LOOPS" ]]; then
                echotime "   Waiting LOCAL md5  : MD5 calculation timed out, SKIP this file"
                break
            fi
        done
        MD5_SIZE=`ls -l $LOCAL_PATH/$$.md5sum | awk '{FS=" "}{print $5}'`
        if [[ "$MD5_SIZE"  != "0" ]]; then
            echotime "   Waiting LOCAL md5  : Done ($MD5_SIZE bytes)"
            LOCAL_MD5HASH=`cat $LOCAL_PATH/$$.md5sum`
            #rm $LOCAL_PATH/$$.md5sum
            LOCAL_MD5HASH="${LOCAL_MD5HASH%% *}"    # get the part before the first " " (the md5 checksum)
        fi
        if [[ "$VERBOSE" -ge "1" ]]; then
            echotime "   Checked LOCAL md5  : '$LOCAL_MD5HASH'"
        fi
        

        # check if the file is identical
        if [[ "$LOCAL_MD5HASH" != "$REMOTE_MD5HASH" ]]; then
            # if file is not identical, mark it for copy
            MARK_COPY=1
            COPY_REASON="COPY, MD5 hash missmatch"
            ACT_COPY=`expr $ACT_COPY + 1`
        else
            # The file localy exists and has a matching md5 hash, so it can be deleted remotely
            if [[ "$ALLOW_REMOTE_DELETE" -eq 1 ]]; then
                MARK_DELETE=1
                COPY_REASON="DELETE, MD5 hash match"
                ACT_DEL=`expr $ACT_DEL + 1`
            else
                COPY_REASON="DELETE-SKIP, MD5 hash match"
                ACT_DEL=`expr $ACT_DEL_SKIP + 1`
            fi
        fi
    else
        # if file does not exist, mark it for copy
        MARK_COPY=1

        # if the copy action is NOT sjipped, the MD5 hash needs to be generated
        if [[ "$SKIP_COPY_ACTION" -ne "1" ]]; then
            #
            # calculate the checksum of remote file
            #
            if [[ "$VERBOSE" -ge "2" ]]; then
                echotime "   Get remote MD5 hash: 'ssh -p $SERVER_SSH_PORT $USER_NAME@$SERVER_NAME \"cd $REMOTE_PATH ; md5sum $REMOTE_FILENAME\""
            fi
            REMOTE_FILEINFO=`ssh -p $SERVER_SSH_PORT $USER_NAME@$SERVER_NAME "cd $REMOTE_PATH ; md5sum $REMOTE_FILENAME"`
            RC=$?
            if [[ $RC != 0 ]] ; then
                ERROR=$ERROR"*** Error while getting remote MD5 hash. Server: '$SERVER_NAME' REMOTE File: '$REMOTE_PATH/$REMOTE_FILENAME' Details: '$RESULT'\n"
                if [[ "$VERBOSE" -ge "1" ]]; then
                    echotime "                        *** Error while getting remote MD5 hash. Server: '$SERVER_NAME' REMOTE File: '$REMOTE_PATH/$REMOTE_FILENAME'. Details: '$RESULT'\n"
                fi
                continue
            fi
            # split the md5 sum from the path
            REMOTE_MD5HASH="${REMOTE_FILEINFO%% *}"    # get the part before the first " " (the md5 checksum)
            if [[ "$VERBOSE" -ge "1" ]]; then
                echotime "   Checked REMOTE md5 : '$REMOTE_MD5HASH'"
            fi
            # Check if filename is "-" (means a error occoured)
            if [[ "$REMOTE_FILENAME" == "-" ]]; then
                ERROR=$ERROR"***ERROR while reading file list from remote host. Server: '$SERVER_NAME'"    
                continue
            fi

            # copy action should be performed
            COPY_REASON="COPY, File not existing"
            ACT_COPY=`expr $ACT_COPY + 1`
        else
            # copy actoin is skipped
            COPY_REASON="COPY-SKIP, File not existing"
            ACT_COPY_SKIP=`expr $ACT_COPY_SKIP + 1`
        fi
    fi

    if [[ "$VERBOSE" -ge "1" ]]; then
        echotime "   Transfer action    : $COPY_REASON"
    fi

    #
    # Perform detected copy action action
    #
    if [[ "$MARK_COPY" -eq "1" ]] && [[ "$SKIP_COPY_ACTION" -eq "0" ]]; then
        # create directories if they dont exist
        LOCAL_DIRNAME=$(dirname $LOCAL_PATH$LOCAL_SUBDIR/$REMOTE_FILENAME)
        if [[ ! -d "$LOCAL_DIRNAME" ]]; then
            # create directories that do not exist
            if [[ "$VERBOSE" -ge "1" ]]; then
                echotime "    Create directory ... $LOCAL_DIRNAME"
            fi
            mkdir -p $LOCAL_DIRNAME
        fi

        if [[ "$BANDWITH_SHAPER" == "trickle" ]]; then
            # Copy the file
            if [[ "$VERBOSE" -ge "2" ]]; then
                echotime "   Copy one File      : 'trickle -s -d $DOWNLOAD_SPEEDLIMIT scp -P $SERVER_SSH_PORT $USER_NAME@$SERVER_NAME:$REMOTE_PATH/$REMOTE_FILENAME $LOCAL_PATH$LOCAL_SUBDIR/$REMOTE_FILENAME'"
            fi
            RESULT=`trickle -s -d $DOWNLOAD_SPEEDLIMIT scp -P $SERVER_SSH_PORT $USER_NAME@$SERVER_NAME:$REMOTE_PATH/$REMOTE_FILENAME $LOCAL_PATH$LOCAL_SUBDIR/$REMOTE_FILENAME 2>&1`
            RC=$?
        else
            # Copy the file
            if [[ "$VERBOSE" -ge "2" ]]; then
                echotime "   Copy one File      : 'scp -l $DOWNLOAD_SPEEDLIMIT_SSH -P $SERVER_SSH_PORT $USER_NAME@$SERVER_NAME:$REMOTE_PATH/$REMOTE_FILENAME $LOCAL_PATH$LOCAL_SUBDIR/$REMOTE_FILENAME'"
            fi
            RESULT=`scp -l $DOWNLOAD_SPEEDLIMIT_SSH -P $SERVER_SSH_PORT $USER_NAME@$SERVER_NAME:$REMOTE_PATH/$REMOTE_FILENAME $LOCAL_PATH$LOCAL_SUBDIR/$REMOTE_FILENAME 2>&1`
            RC=$?
        fi

        # check result of shell program execution
        if [[ $RC != 0 ]] ; then
            ERROR=$ERROR"*** Error while copy. Server: '$SERVER_NAME' REMOTE File: $REMOTE_PATH/$REMOTE_FILENAME' LOCAL File: '$LOCAL_PATH$LOCAL_SUBDIR/$REMOTE_FILENAME' Details: '$RESULT'\n"
            if [[ "$VERBOSE" -ge "1" ]]; then
                echotime "                        *** Error while copy. Server: '$SERVER_NAME' REMOTE File: $REMOTE_PATH/$REMOTE_FILENAME' LOCAL File: '$LOCAL_PATH$LOCAL_SUBDIR/$REMOTE_FILENAME' Details: '$RESULT'\n"
            fi
            #break
        fi

        #
        # check copy result OK/ NOK
        #
        LOCAL_MD5HASH=`$MD5_CMD $MD5_OPT $LOCAL_PATH$LOCAL_SUBDIR/$REMOTE_FILENAME`
        LOCAL_MD5HASH="${LOCAL_MD5HASH%% *}"    # get the part before the first " " (the md5 checksum)
        echotime "   Checked LOCAL md5  : '$LOCAL_MD5HASH'"

        # check if the file is identical
        if [[ "$LOCAL_MD5HASH" == "$REMOTE_MD5HASH" ]]; then
            # The file localy exists and has a matching md5 hash, so it can be deleted remotely
            if [[ "$VERBOSE" -ge "1" ]]; then
                echotime "   Transfer result    : SUCCESS"
                if [[ "$ALLOW_REMOTE_DELETE" -eq 1 ]]; then
                    echotime "   Transfer action    : DELETE, MD5 hash match"
                else
                    echotime "   Transfer action    : NO ACTION"
                fi
            fi
            MARK_DELETE=1
        else
            if [[ "$VERBOSE" -ge "1" ]]; then
                echotime "   Transfer result    : FAILED"
                echotime "   Transfer action    : NO ACTION, keep file for next run"
            fi
        fi
    fi

    #
    # Perform detected delete action
    #
    if [[ "$ALLOW_REMOTE_DELETE" -eq "1" ]]; then
        # check if file is marked for delete
        if [[ "$MARK_DELETE" -eq "1" ]]; then
            # delete the file remotely
            if [[ "$VERBOSE" -ge "2" ]]; then
                echotime "   Delete remote file : 'ssh -p $SERVER_SSH_PORT $USER_NAME@$SERVER_NAME \"rm -f $REMOTE_PATH/$REMOTE_FILENAME\"'"
            fi
            RESULT=`ssh -p $SERVER_SSH_PORT $USER_NAME@$SERVER_NAME "rm -f $REMOTE_PATH/$REMOTE_FILENAME"  2>&1`
            RC=$?
            if [[ $RC != 0 ]] ; then
                ERROR=$ERROR"*** Error while deleting. Server: '$SERVER_NAME' REMOTE File '$REMOTE_PATH/$REMOTE_FILENAME' Details: '$RESULT'\n"
                if [[ "$VERBOSE" -ge "1" ]]; then
                    echotime "   Transfer result    : FAILED"
                    echotime "                        *** Error while deleting. Server: '$SERVER_NAME' REMOTE File '$REMOTE_PATH/$REMOTE_FILENAME' Details: '$RESULT'\n"
                fi
            else
                if [[ "$VERBOSE" -ge "1" ]]; then
                    echotime "   Transfer result    : SUCCESS"
                fi
            fi
        fi
    fi

    # calculate loop execution time
    SECTION_END_TIME=`date "+%s"`
    SECTION_RUN_TIME=$(($SECTION_END_TIME - $SECTION_START_TIME))

    # last verbose line of this loop
    if [[ "$VERBOSE" -ge "1" ]]; then
        echotime "   Execution time     : $SECTION_RUN_TIME sec"
        echotime "-----------------------------------"
    fi

    # Check if another loop is possible within the time limit
    NOW_TIME=`date "+%s"`
    if [[ "$END_TIME" -le "$NOW_TIME" ]]; then
        # calculate the running time and define exit reason text
        RUNNING_TIME=$(($NOW_TIME - $START_TIME))
        EXIT_REASON="Time limit reached ($RUNNING_TIME sec)"
        # stop the loop
        break
    fi

done


# end of execution verbose line
if [[ "$VERBOSE" -ge "1" ]]; then
    echotime "$EXIT_REASON"
fi


# show error messages
echotime 
echotime $ERROR


# last verbose line of this loop
if [[ "$VERBOSE" -ge "1" ]]; then
    NOW_TIME=`date "+%s"`
    TS_TEXT_NOW=`date "+%Y-%m-%d %H:%M"`
    RUNNING_TIME=$(($NOW_TIME - $START_TIME))
    echotime "==================================="
    echotime "Total execution time     : $TS_TEXT_NOW ($RUNNING_TIME sec)"
    echotime "Total COPY action        : $ACT_COPY"
    echotime "Total COPY-SKIP action   : $ACT_COPY_SKIP"
    echotime "Total DELETE action      : $ACT_DEL"
    echotime "Total DELETE-SKIP action : $ACT_DEL_SKIP"
fi



exit 0
