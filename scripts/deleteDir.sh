#!/bin/bash
# Use this script to delete a directory, can be much faster than rm -rf

set -e

if [ $# -ne 1 ];
   then 
   printf "Error: Need exactly one directory to delete.\n"
   exit 1
fi

if [ ! -d $1 ]
then
    printf "Error: The given directory doesn't exist.\n"
    exit 1
fi


startDir=$PWD
cd $1
perl -e 'for(<*>){((stat)[9]<(unlink))}'
cd $startDir
rm -rf $1
