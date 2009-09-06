#!/bin/bash
 
FILE=$1

# parse "Ii:1:001:1" based on semicolon
parse_address(){
	line="$@"
#	echo $line

	k=1

	OIFS=$IFS
	IFS=$(echo -en ":")
	for i in $line
	do

#	echo $i
	case "$k" in
	1) type_dir=$i
		case "$type_dir" in
		Ci) printf "CtrlIn " ;;
		Co) printf "CtrlOut " ;;
		Bi) printf "BlkIn " ;;
		Bo) printf "BlkOut " ;;
		Ii) printf "IntrIn " ;;
		Io) printf "IntrOut ";;
		Zi) printf "IsoIn " ;;
		Zo) printf "IsoOut "
		esac;;
#		printf "Type and Dir %s " $i ;;
	2) printf "Bus %s " $i ;;
	3) printf "Addr %s " $i ;;
	4) printf "Ept %s\n" $i ;;
	esac

	k=`expr $k + 1`
	done
	
	# Restore seperator as space for further line processing
	IFS=$(echo -en " ")
}
processLine(){
	line="$@" # get all args
#	echo $line
	
	arg=1

	# parse line "f667e680 1127762832 C Ii:1:001:1 0:2048 2 = 2000"
	# according to spaces

	OIFS=$IFS
	IFS=$(echo -en " ")
	for i in $line
	do

	case "$arg" in
	1) printf "URB %s " $i ;;
	2) printf "Time %s " $i ;;
	3) event_type=$i
		case "$event_type" in
		C) printf "CBK " ;;
		S) printf "SUB " ;;
		E) printf "ERR "
		esac ;;
	4) parse_address $i
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
