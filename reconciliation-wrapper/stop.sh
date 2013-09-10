#!/bin/bash

# Make a directory in /var/www for TaxRefine.
TAXREFINE_PATH=/var/www/agrew
sudo su -c "mkdir -p $TAXREFINE_PATH" www-data

# Settings
ERROR_LOG=$TAXREFINE_PATH/error_log.txt
SOCKET_PATH=$TAXREFINE_PATH/agrew.sock
PID_PATH=$TAXREFINE_PATH/agrew.pid

# Are we already running?
if [ ! -e $PID_PATH ]
then
    echo "Error! This script is not running. Use start.sh to start it."
    exit 1
fi

# Send it a SIGQUIT
sudo su -c "kill -QUIT `cat $PID_PATH`" -s /bin/bash www-data
sudo su -c "rm $PID_PATH" -s /bin/bash www-data
