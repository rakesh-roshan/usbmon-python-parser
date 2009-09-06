#!/bin/bash
 
FILE=$1

# parse "Ii:1:001:1" based on semicolon
parse4(){
	line="$@"
	echo $line

	OIFS=$IFS
	IFS=$(echo -en ":")
	for i in $line
	do
	echo $i
	done
	
	# Restore seperator as space for further line processing
	IFS=$(echo -en " ")
}
processLine(){
	line="$@" # get all args
	echo $line
	
	arg=1

	# parse line "f667e680 1127762832 C Ii:1:001:1 0:2048 2 = 2000"
	# according to spaces

	OIFS=$IFS
	IFS=$(echo -en " ")
	for i in $line
	do

	case "$arg" in
	1) #echo $i
	;;
	2) #echo $i
	;;
	3) #echo $i
	;;
	4) #parse4 $i
	esac

	arg=`expr $arg + 1`
	done
}
 
# Set loop separator to end of line
BAKIFS=$IFS
IFS=$(echo -en "\n\b")
exec 3<&0
exec 0<$FILE
	# use $line variable to process line in processLine() function
	# lets take few lines, for initial work
	while read line
	do
	# use $line variable to process line in processLine() function
	processLine $line
	done
exec 0<&3
 
# restore $IFS which was used to determine what the field separators are
IFS=$BAKIFS
exit 0
