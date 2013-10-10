# Directory-Secure-Transfer

The Directory-Secure-Transfer is a shell script initially created to download files from a server to another one. The script includes as well a second script to download from multiple servers.

This Directory-Secure-Transfer script aims to download files located in a specified directory. The list of functionality includes the following:

*     Download via SCP and checking for changed files via SSH
*     Download files into hostname subdirectories
*     Only download files that are changed or localy missing
*     The file is verified via md5 checksum to ensure its correct transfer
*     Download only files that have a specific age (find -atime option)
*     Only download files that match a spefic regular expression
*     Limit the download time by specifying the duration
*     Limit the download time by specifying a date and time
*     Optionaly delete files from server after backup
*     Limit download speed to avoid filling up the internet uplink
*     Limit download speed using trickle
*     Configuration via commandline options or configuration file
*     Backup from multiple configured servers via included script

## Download & Installation

[Download Download Directory-Secure-Transfer from Github](https://github.com/tinned-software/directory-secure-transfer)

To install the the script download it from Github and upload it to your server. Modify the confiuration file or start the script with -h to see there commandline options.

## Description

This Directory-Secure-Transfer script was designed to download backup files from multiple servers to a storage server. The challange thereby was to ensure that the backups where correctly transferred before they where deleted on the remote server. The second challange was to download the files while the server keeps responsive and available. So the download speed needed to be limited. As those requirements resulted in a long download time, it was important to limit the doewnload time to limit it to the night hours for example.

It got more complicate when you have a couple of servers where you need to download the files. Usually programs like rsync and others start downloading from one server and only after they are finished downloading all files from that server you can start the download from the next one. This can result inone server getting downloaded and the other server beeing missed out every night causing the disc to get full. This script is different as it downloads file by file and checks in between every file if it was running already longer then the configured time. That way the additional script can loop through the servers downloading for example for about one our each. That way you the files get more less evenly downloaded from all the servers.

The Directory-Secure-Transfer script provides the possibility to define a configuration file. The included example config file describe in detail all the configuration options available.

The Directory-Secure-Transfer script will establishing a number of connections via ssh and scp to check for files to copy as well as for the file copy itself. Entering the password on every connect can be annoying. I suggest a [SSH passwordless login with SSH key](http://blog.tinned-software.net/ssh-passwordless-login-with-ssh-key/) setup. This allows the script to run without user interaction.
