#!/bin/bash
#
# @author Gerhard Steinbeis (info [at] tinned-software [dot] net)
# @copyright Copyright (c) 2012 - 2013
version=1.0.0
# @license http://opensource.org/licenses/gpl-license.php GNU Public License
# @package bash-function
#


#
# Function to print out a string including a time and date info at the 
# beginning of the line. If the string is empty, only the timestamp is printed 
# out.
#
# @param $1 The string to print out
# @param $2 (optional) Option to echo like ">>logfile.log"
#
function echotime {
	TIME=`date "+[%Y-%m-%d %H:%M:%S]"`
	echo -e "$TIME - $1" $2
}
