#!/bin/bash
 
FILE=$1
NUM_OF_LINE=$2

processLine(){
  line="$@" # get all args
  echo $line
}
 
# Set loop separator to end of line
BAKIFS=$IFS
IFS=$(echo -en "\n\b")
exec 3<&0
exec 0<$FILE
	# use $line variable to process line in processLine() function
	# lets take few lines, for initial work
	for (( i=0; i<$NUM_OF_LINE; i++))
	do
	read line
	# use $line variable to process line in processLine() function
	processLine $line
	done
exec 0<&3
 
# restore $IFS which was used to determine what the field separators are
IFS=$BAKIFS
exit 0
