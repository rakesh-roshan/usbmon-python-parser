#!/usr/bin/env bash

# accept variable arguments
# addr => device address
# bus => bus number
# ept => endpoint number
# FILE => input file to parse

#	struct usb_ctrlrequest {
#		 __u8 bRequestType;
#		 __u8 bRequest;
#		__le16 wValue;
#		__le16 wIndex;
#		__le16 wLength;
#	} __attribute__ ((packed));

usb_ctrlrequest=()
usb_ctrlrequest_str=()


while getopts 'a:b:e:f:v' OPTION
do
	case $OPTION in
	a) addr="$OPTARG"	;;
	b) bus="$OPTARG"	;;
	e) ept_f=1
	   ept="$OPTARG"	;;
	f) FILE="$OPTARG" ;;
	v) verbose=1 ;;
	*) printf "Usage: %s: args\n" $(basename $0) >&2
		exit 2	;;
	esac
done
	shift $(($OPTIND - 1))

# Global definitions
TRUE=0
FALSE=1

# NOTE - Please use only bash for now to test this script.
# i.e. run this script only as "bash parse_usbmon.sh"

parse_usb_requests(){
	req_line="$@" # get all args
#	echo $req_line

	test \( $event_str = "SUB" \) -a  \( -n "$event_str" \) -a \( "$ept_str" = "0" \)
	if test $? -eq $TRUE
	then
		l=1
		OIFS=$IFS
		IFS=$(echo -en " ")
		for i in $line
		do
			case "$l" in
			5) ;; #TODO
			6) usb_ctrlrequest[0]=$i
				case $i in #TODO - bitwise parsing
				80) usb_ctrlrequest_str[0]="StdInDev" ;;
				00) usb_ctrlrequest_str[0]="StdOutDev" ;;
				*)  usb_ctrlrequest_str[0]="Invalid" #TODO - handling of class request
				esac ;;
			7) usb_ctrlrequest[1]=$i ;;
			8) usb_ctrlrequest[2]=$i ;;
			9) usb_ctrlrequest[3]=$i ;;
			10) ;;
			11) usb_ctrlrequest[4]=$i ;; #consider dacimal wLength
			esac
		l=`expr $l + 1`
		done

	printf "%s " ${usb_ctrlrequest_str[0]}
	printf "bReqType=%s bReq=%s wVal=%s wIdx=%s wLen=%s\n" ${usb_ctrlrequest[0]} ${usb_ctrlrequest[1]} ${usb_ctrlrequest[2]} ${usb_ctrlrequest[3]} ${usb_ctrlrequest[4]}

#		for member in ${usb_ctrlrequest[*]}; do echo $member;done
	fi
}

# parse "Ii:1:001:1" based on semicolon
parse_address(){
	addr_line="$@"
#	echo $addr_line

	k=1

	OIFS=$IFS
	IFS=$(echo -en ":")
	for i in $addr_line
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
	4) parse_address $i ;;
	esac

	arg=`expr $arg + 1`
	done

	if [ $verbose ]
	then
		printf "Urb %s Time %s" $urb_str $time_str
	fi

	if [ $ept_f ]
	then
		test \( "$ept_str" = "$ept" \) -a  \( -n "$ept_str" \)
		if test $? -eq $TRUE
		then
			printf "%s %s Bus %s Addr %s Ept %s\n" $event_str $ept_type_str $bus_str $addr_str $ept_str
		fi
	else
			printf "%s %s Bus %s Addr %s Ept %s\n" $event_str $ept_type_str $bus_str $addr_str $ept_str
	fi

	parse_usb_requests $line
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
