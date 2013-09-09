#!/bin/bash

# Make a directory in /var/www for TaxRefine.
TAXREFINE_PATH=/var/www/agrew
sudo su -c "mkdir -p $TAXREFINE_PATH" www-data

# Settings
ERROR_LOG=$TAXREFINE_PATH/error_log.txt
SOCKET_PATH=$TAXREFINE_PATH/agrew.sock
PID_PATH=$TAXREFINE_PATH/agrew.pid

# Are we already running?
if [ -e $PID_PATH ]
then
    echo "Error! This script is already running. Use stop.sh to stop it."
    exit 1
fi

# Start TaxRefine in www-data inside a screen
sudo su -c "starman agrew.pl --daemonize --error-log $ERROR_LOG --listen $SOCKET_PATH --pid $PID_PATH &" -s /bin/bash www-data
