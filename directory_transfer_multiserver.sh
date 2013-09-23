#!/bin/bash
#
# @author Gerhard Steinbeis (info [at] tinned-software [dot] net)
# @copyright Copyright (c) 2012 - 2013
version=0.1.6
# @license http://opensource.org/licenses/gpl-license.php GNU Public License
# @package filesystem
#

#
# Non Config values
#
# Get script directory
SCRIPT_PATH="$(dirname $(readlink -f $0))"

#
# Loading functions
#
. $SCRIPT_PATH/echotime.sh
. $SCRIPT_PATH/directory_transfer_multiserver.conf


# count the servers
COUNT=${#SERVER[@]}

for (( j = 0 ; j < RUNS ; j++))
do
	# 
    if [[ "$j" -ne "0" ]]; then
        echotime "*** Pause for $RUN_PAUSE seconds before the next run Starts ..."
        sleep $RUN_PAUSE
    fi

    echotime "*** Starting run number $j ..."
    for (( i = 0 ; i < COUNT ; i++ ))
    do
        $SCRIPT_PATH/directory_compare_and_transfer.sh --config $CONFIG_FILE --server ${SERVER[$i]}
    done
done

echotime "*** All runs finished."
