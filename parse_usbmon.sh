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

			# D7:	Data Transfer Direction
			#	0 - Host-to-Device [Out]
			#	1 - Device-to-Host [In]
			# D6-D5	Type => 0 - Standard 1 - Class 2 - Vendor 3 - Reserved
			# D4...D0 Receipent => 0 - Device 1 - Interface
			#			2 - Endpoint 3 - Other 4...31 - Reserved
			6) usb_ctrlrequest[0]=$i
				Direction=$(($((0x$i & 0x80)) >> 7 ))
				Type=$(($((0x$i & 0x60)) >> 5 ))
				Recep=$((0x$i & 0x1F))
				case "$Direction" in
				0) Direction_str="Out";;
				1) Direction_str="In";;
				*) Direction_str="Invalid";;
				esac

				case "$Type" in
				0) Type_str="Std";;
				1) Type_str="Class";;
				2) Type_str="Vend";;
				3) Type_str="Reserved";;
				*) Type_str="Invalid";;
				esac

				case "$Recep" in
				0) Recep_str="Dev";;
				1) Recep_str="Interf";;
				2) Recep_str="Ept";;
				3) Recep_str="Other";;
				*) Recep_str="Reserved";;
				esac

				usb_ctrlrequest_str[0]="$Type_str$Direction_str$Recep_str" ;;

			7) usb_ctrlrequest[1]=$i
				case $i in
				00) usb_ctrlrequest_str[1]="GetStatus";;
				01) usb_ctrlrequest_str[1]="ClrFeature";;
				02) usb_ctrlrequest_str[1]="Reserved";;
				03) usb_ctrlrequest_str[1]="SetFeature";;
				04) usb_ctrlrequest_str[1]="Reserved";;
				05) usb_ctrlrequest_str[1]="SetAddr";;
				06) usb_ctrlrequest_str[1]="GetDesc";;
				07) usb_ctrlrequest_str[1]="SetDesc";;
				08) usb_ctrlrequest_str[1]="GetConf";;
				09) usb_ctrlrequest_str[1]="SetConf";;
				10) usb_ctrlrequest_str[1]="GetIntf";;
				11) usb_ctrlrequest_str[1]="SetIntf";;
				12) usb_ctrlrequest_str[1]="SyncFrame";;
				*) usb_ctrlrequest_str[1]="Invalid";;
				esac ;;
			8) usb_ctrlrequest[2]=$i
				case ${usb_ctrlrequest[1]} in
				00) ;;
				01) case $i in
				    0) ;; # Feature Selector - ENDPOINT_HALT
				    1) ;; # DEVICE_REMOTE_WAKEUP
				    2) ;; # TEST_MODE
				    *) ;; # INVALID
				    esac ;;
				02) ;;
				03) ;;
				04) ;;
				05) usb_ctrlrequest_str[2]="addr=$((0x${usb_ctrlrequest[2]} & 0x007F))" ;;
				06)	desc_type=$(($((0x$i & 0xFF00)) >> 8 ))
					desc_idx=$((0x$i & 0x00FF))
					case $desc_type in
					1) usb_ctrlrequest_str[2]="Dev";;
					2) usb_ctrlrequest_str[2]="Conf";;
					3) usb_ctrlrequest_str[2]="Str";;
					4) usb_ctrlrequest_str[2]="Intf";;
					5) usb_ctrlrequest_str[2]="Ept";;
					6) usb_ctrlrequest_str[2]="DevQual";;
					7) usb_ctrlrequest_str[2]="OtherSpeed";;
					8) usb_ctrlrequest_str[2]="IntfPowr";;
					*) usb_ctrlrequest_str[2]="Invalid";;
					esac ;;
				07) ;;
				08) ;;
				09) ;;
				10) ;;
				11) ;;
				12) ;;
				esac ;;
			9) usb_ctrlrequest[3]=$i
				case ${usb_ctrlrequest[1]} in
				00) ;;
				01) ;;
				02) ;;
				03) ;;
				04) ;;
				05) ;;
				06) desc_type=$(($((0x${usb_ctrlrequest[2]} & 0xFF00)) >> 8 ))
					case $desc_type in
					3)	case $i in
						0409) usb_ctrlrequest_str[3]="Eng-US" ;;
						*) usb_ctrlrequest_str[3]="0000"
						esac ;;
					esac ;;
				07) ;;
				08) ;;
				09) ;;
				10) ;;
				11) ;;
				12) ;;
				esac ;;
			10) ;;
			11) usb_ctrlrequest[4]=$i ;; #consider dacimal wLength
			esac
		l=`expr $l + 1`
		done

	printf "\n%s %s %s %s" ${usb_ctrlrequest_str[0]} ${usb_ctrlrequest_str[1]} ${usb_ctrlrequest_str[2]} ${usb_ctrlrequest_str[3]}
	printf "\nbReqType=%s bReq=%s wVal=%s wIdx=%s wLen=%s\n" ${usb_ctrlrequest[0]} ${usb_ctrlrequest[1]} ${usb_ctrlrequest[2]} ${usb_ctrlrequest[3]} ${usb_ctrlrequest[4]}

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
		printf "Urb %s Time %s\n" $urb_str $time_str
		if [ $ept_f ]
		then
			test \( "$ept_str" = "$ept" \) -a  \( -n "$ept_str" \)
			if test $? -eq $TRUE
			then
				printf "%s %s Bus %s Addr %s Ept %s\n" $event_str $ept_type_str $bus_str $addr_str $ept_str
			else
				printf "%s %s Bus %s Addr %s Ept %s\n" $event_str $ept_type_str $bus_str $addr_str $ept_str
			fi
		fi
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
