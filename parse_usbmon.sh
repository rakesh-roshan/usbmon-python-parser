#!/usr/bin/env bash

# accept variable arguments
# addr => device address
# bus => bus number
# ept => endpoint number
# FILE => input file to parse

while getopts 'a:b:e:f:' OPTION
do
	case $OPTION in
	a) addr="$OPTARG"	;;
	b) bus="$OPTARG"	;;
	e) ept="$OPTARG"	;;
	f) FILE="$OPTARG" ;;
	?) printf "Usage: %s: args\n" $(basename $0) >&2
		exit 2	;;
	esac
done
	shift $(($OPTIND - 1))

# NOTE - Please use only bash for now to test this script.
# i.e. run this script only as "bash parse_usbmon.sh"

# parse "Ii:1:001:1" based on semicolon
parse_address(){
	line="$@"
#	echo $line

	k=1

	OIFS=$IFS
	IFS=$(echo -en ":")
	for i in $line
	do

	case "$k" in
	1) type_dir=$i
	   ept_type=$i
		case "$type_dir" in
		Ci) ept_type_str="CtrlIn " ;;
		Co) ept_type_str="CtrlOut " ;;
		Bi) ept_type_str="BlkIn " ;;
		Bo) ept_type_str="BlkOut " ;;
		Ii) ept_type_str="IntrIn " ;;
		Io) ept_type_str="IntrOut ";;
		Zi) ept_type_str="IsoIn " ;;
		Zo) ept_type_str="IsoOut "
		esac;;
	2) bus_str=$i ;;
	3) addr_str=$i ;;
	4) ept_num=$i
	   ept_str=$i ;;
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
	1) urb_str="$i " ;;
	2) time_str="$i " ;;
	3) event_type=$i
		case "$event_type" in
		C) event_str="CBK " ;;
		S) event_str="SUB " ;;
		E) event_str="ERR "
		esac ;;
	4) parse_address $i
	esac

	arg=`expr $arg + 1`
	done

	printf "URB %s Time %s %s %s BUS %s ADDR %s EPT %s\n" $urb_str $time_str $event_str $ept_type_str $bus_str $addr_str $ept_str
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
