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

#	/* USB_DT_DEVICE: Device descriptor */
#	struct usb_device_descriptor {
#		__u8  bLength;
#		__u8  bDescriptorType;
#		__le16 bcdUSB;
#		__u8  bDeviceClass;
#		__u8  bDeviceSubClass;
#		__u8  bDeviceProtocol;
#		__u8  bMaxPacketSize0;
#		__le16 idVendor;
#		__le16 idProduct;
#		__le16 bcdDevice;
#		__u8  iManufacturer;
#		__u8  iProduct;
#		__u8  iSerialNumber;
#		__u8  bNumConfigurations;
#} __attribute__ ((packed));

usb_device_descriptor=()
USB_DT_DEVICE_SIZE=18

#	struct usb_config_descriptor {
#		__u8  bLength;
#		__u8  bDescriptorType;
#		__le16 wTotalLength;
#		__u8  bNumInterfaces;
#		__u8  bConfigurationValue;
#		__u8  iConfiguration;
#		__u8  bmAttributes;
#		__u8  bMaxPower;
#		} __attribute__ ((packed));

usb_config_descriptor=()
USB_DT_CONFIG_SIZE=9

# SYNCF, SI,GI,SC,GC, SD,GD,SA,R, SF,R,CF,GS - Table9.4 Ch9
std_req_flag=0x0000

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
no=0
yes=1
INVALID=-1
save_iinterface=-1

# NOTE - Please use only bash for now to test this script.
# i.e. run this script only as "bash parse_usbmon.sh"

parse_usb_requests(){
	local req_line="$@" # get all args
	local data_str=()
	local temp_interface_desc=() temp_endpoint_desc=()
	local datalen=0 data_available=$INVALID
	local Direction=0 Type=0 Recep=0
	local msb=0 lsb=0
	local equal_pos=0 received_data=0 data_start=0
	local datastr=0 wtotallen=0
	local interface=0 endpoint=0 num_endpoints=0 char=0

	test \( $event_str = "SUB" \) -a  \( -n "$event_str" \) -a \( "$ept_str" = "0" \)
	if test $? -eq $TRUE
	then
		l=1
		OIFS=$IFS
		IFS=$(echo -en " ")
		for i in $req_line
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
				09) conf_num=$((0x$i & 0x00FF))
				    usb_ctrlrequest_str[2]="config-$conf_num" ;;
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
				05) usb_ctrlrequest_str[3]="Idx-0" ;;
				06) desc_type=$(($((0x${usb_ctrlrequest[2]} & 0xFF00)) >> 8 ))
					case $desc_type in
					3)	case $i in
						0409) usb_ctrlrequest_str[3]="Eng-US" ;;
						esac ;;
					*) usb_ctrlrequest_str[3]="Idx-0"
					esac ;;
				07) ;;
				08) ;;
				09) usb_ctrlrequest_str[3]="Idx-0";;
				10) ;;
				11) ;;
				12) ;;
				esac ;;
			10) ;;
			11) usb_ctrlrequest[4]=$i #consider dacimal wLength
			    usb_ctrlrequest_str[4]="wLen-$i" ;;
			esac
		l=`expr $l + 1`
		done

	printf "\nbReqType=%s " ${usb_ctrlrequest[0]}
	printf "bReq=%s " ${usb_ctrlrequest[1]}
	printf "wVal=%s " ${usb_ctrlrequest[2]}
	printf "wIdx=%s " ${usb_ctrlrequest[3]}
	printf "wLen=%s" ${usb_ctrlrequest[4]}

	printf "\n%s " ${usb_ctrlrequest_str[0]}
	printf "%s " ${usb_ctrlrequest_str[1]}
	printf "%s " ${usb_ctrlrequest_str[2]}
	printf "%s " ${usb_ctrlrequest_str[3]}
	printf "%s" ${usb_ctrlrequest_str[4]}

	fi #endof test \( $event_str = "SUB" \)

	test \( $event_str = "CBK" \) -a  \( -n "$event_str" \) -a \( "$ept_str" = "0" \)
	if test $? -eq $TRUE
	then
		m=1 p=0
		OIFS=$IFS
		IFS=$(echo -en " ")
		for i in $req_line
		do
			test \( "$i" = "0" \) -a \( $m = 5 \)
			if test $? -eq $TRUE
			then
				arg5=0 #i think I should exit if this is not 0 with error and skip any parsing
			fi

			if [ "$m" == "6" ]
			then
				if [ "$i" == "0" ]
				then
					data_available=$no
				else
					datalen=$i
					data_available=$yes
				fi
			fi

			if [ "$data_available" == "$no" ]
			then
				printf "\n" # print \n for proper formatting of printing
				return 0
			fi

			if [ "$m" -le 7 ] #ignore first 7 words
			then
				m=`expr $m + 1`
				continue
			fi
				data_str[$p]=$i #save data
		p=`expr $p + 1`
		done

		if [ "$data_available" == "$yes" ]
		then
			equal_pos=`expr index "$req_line" "="` # find out position of "="
			data_start=`expr $equal_pos + 1` # skip space after "="
			received_data=${req_line:$data_start} # save received data as a string

			Type=$(($((0x${usb_ctrlrequest[0]} & 0x60)) >> 5 ))
			case $Type in
			0) #now we have to parse received data as per requests
				case ${usb_ctrlrequest[1]} in
				00) ;;
				01) ;;
				02) ;;
				03) ;;
				04) ;;
				05) ;;
				06)	desc_type=$(($((0x${usb_ctrlrequest[2]} & 0xFF00)) >> 8 ))
					case $desc_type in
					1) #device descriptor with wLen 18 => 4*4 + 1*2 = 5 cases
					   # 12010002 00000040 b8228d60 01000302 0501
						r=1
						for member in ${data_str[*]}
						do
							case $r in
							1) usb_device_descriptor[0]=$(($((0x${data_str[0]} & 0xFF000000)) >> 24 ))
							   printf "\nbLen %s " ${usb_device_descriptor[0]}

							   usb_device_descriptor[1]=$(($((0x${data_str[0]} & 0x00FF0000)) >> 16 ))
							   printf "bDes %s " ${usb_device_descriptor[1]}

							   msb=$((0x${data_str[0]} & 0x000000FF))
							   lsb=$(($((0x${data_str[0]} & 0x0000FF00)) >> 8 ))
							   usb_device_descriptor[2]="$msb$lsb"
							   printf "bcdUSB %.2d%.2d " $msb $lsb
								;;
							2) usb_device_descriptor[3]=$(($((0x${data_str[1]} & 0xFF000000)) >> 24 ))
							   printf "bDevClass %s " ${usb_device_descriptor[3]}

							   usb_device_descriptor[4]=$(($((0x${data_str[1]} & 0x00FF0000)) >> 16 ))
							   printf "bDevSubClass %s " ${usb_device_descriptor[4]}

							   usb_device_descriptor[5]=$(($((0x${data_str[1]} & 0x0000FF00)) >> 8 ))
							   printf "bDevProto %s " ${usb_device_descriptor[5]}

							   usb_device_descriptor[6]=$((0x${data_str[1]} & 0x000000FF))
							   printf "bMaxPkt0 %s " ${usb_device_descriptor[6]}
								;;
							3) msb=$(($((0x${data_str[2]} & 0xFF000000)) >> 24 ))
							   lsb=$(($((0x${data_str[2]} & 0x00FF0000)) >> 16 ))
							   usb_device_descriptor[7]="$msb$lsb" #stored as a concatanated decimal
							   printf "idVendor %.2x%.2x " $lsb $msb

							   msb=$(($((0x${data_str[2]} & 0x0000FF00)) >> 8 ))
							   lsb=$((0x${data_str[2]} & 0x0000FF))
							   usb_device_descriptor[8]="$msb$lsb"
							   printf "idProduct %.2x%.2x " $lsb $msb
								;;
							4) msb=$(($((0x${data_str[3]} & 0xFF000000)) >> 24 ))
							   lsb=$(($((0x${data_str[3]} & 0x00FF0000)) >> 16 ))
							   usb_device_descriptor[9]="$msb$lsb"
							   printf "bcdDev %.2x%.2x " $lsb $msb

							   usb_device_descriptor[10]=$(($((0x${data_str[3]} & 0x0000FF00)) >> 8 ))
							   printf "iManufact %s " ${usb_device_descriptor[10]}

							   usb_device_descriptor[11]=$((0x${data_str[3]} & 0x0000FF))
							   printf "iProduct %s " ${usb_device_descriptor[11]}
								 ;;
							5) usb_device_descriptor[12]=$(($((0x${data_str[4]} & 0x0000FF00)) >> 8 ))
							   printf "iSerialNum %s " ${usb_device_descriptor[12]}

							   usb_device_descriptor[13]=$((0x${data_str[4]} & 0x0000FF))
							   printf "bNumConf %s" ${usb_device_descriptor[13]}
								;;
							esac
							r=`expr $r + 1`
						done
						;;
					2) for i in 1 2 3 #TODO-logic assumes that there is only one conf descriptor
					   do
						case $i in
						1) printf "\nConfig Desc =>"
						   usb_config_descriptor[0]=$(($((0x${data_str[0]} & 0xFF000000)) >> 24 ))
						   printf " bLen %s " ${usb_config_descriptor[0]}

						   usb_config_descriptor[1]=$(($((0x${data_str[0]} & 0x00FF0000)) >> 16 ))
						   printf "bDescType %s " ${usb_config_descriptor[1]}

						   datastr="${data_str[0]}"
						   wtotallen="${datastr:4:4}"
						   msb=${wtotallen:0:2}
						   lsb=${wtotallen:2:2}
						   usb_config_descriptor[2]=$((0x$lsb$msb))
						   printf "wTotalLen %s " ${usb_config_descriptor[2]}
							;;
						2) usb_config_descriptor[3]=$(($((0x${data_str[1]} & 0xFF000000)) >> 24 ))
						   printf "bNumInterfaces %s " ${usb_config_descriptor[3]}

						   usb_config_descriptor[4]=$(($((0x${data_str[1]} & 0x00FF0000)) >> 16 ))
						   printf "bConfVal %s " ${usb_config_descriptor[4]}

						   usb_config_descriptor[5]=$(($((0x${data_str[1]} & 0x0000FF00)) >> 8 ))
						   printf "iConf %s " ${usb_config_descriptor[5]}

						   usb_config_descriptor[6]=$((0x${data_str[1]} & 0x000000FF))
						   printf "bmAttr %s " ${usb_config_descriptor[6]}
							;;
						3) datastr="${data_str[2]}"
						   usb_config_descriptor[7]=$((0x${datastr:0:2})) #store in decimal
						   printf "bMaxPower %s " ${usb_config_descriptor[7]}
							;;
						esac
					   done

					   if [ "$datalen" -eq 9 ]
					   then
						printf "\n"
						return 0
					   fi

					   if [ "${usb_config_descriptor[2]}" -gt 9 ]
					   then
						received_data=${received_data:20}
					   else
						return 0
					   fi

					   for (( interface=0; interface < ${usb_config_descriptor[3]}; interface++ ))
					   do
						i=0
						while [ $i -le 17 ]
						do
							char=${received_data:0:1}
							received_data=${received_data:1}
							if [ "$char" = " " ]
							then
								continue
							fi
								temp_interface_desc[$i]=$char
								i=`expr $i + 1`
						done

						printf "\nInterface descriptor $interface => "
						printf "bLen %s " ${temp_interface_desc[0]}${temp_interface_desc[1]}
						printf "bDescType %s " ${temp_interface_desc[2]}${temp_interface_desc[3]}
						printf "bINum %s " ${temp_interface_desc[4]}${temp_interface_desc[5]}
						printf "bAltSetting %s " ${temp_interface_desc[6]}${temp_interface_desc[7]}
						printf "bNumEpt %s " ${temp_interface_desc[8]}${temp_interface_desc[9]}
						printf "bIClass %s " ${temp_interface_desc[10]}${temp_interface_desc[11]}
						printf "bISubClass %s " ${temp_interface_desc[12]}${temp_interface_desc[13]}
						printf "bIProto %s " ${temp_interface_desc[14]}${temp_interface_desc[15]}
						save_iinterface=$((0x${temp_interface_desc[16]}${temp_interface_desc[17]}))
						printf "iInterface %s " $save_iinterface

						num_endpoints=${temp_interface_desc[8]}${temp_interface_desc[9]}
						for (( endpoint=0; endpoint < $num_endpoints; endpoint++ ))
						do
							i=0
							while [ $i -le 13 ]
							do
								char=${received_data:0:1}
								received_data=${received_data:1}
								if [ "$char" = " " ]
								then
									continue
								fi
									temp_endpoint_desc[$i]=$char
									i=`expr $i + 1`
							done
							printf "\nEndpoint descriptor $endpoint => "
							printf "bLen %s " ${temp_endpoint_desc[0]}${temp_endpoint_desc[1]}
							printf "bDescType %s " ${temp_endpoint_desc[2]}${temp_endpoint_desc[3]}
							printf "bEptAddr %s " ${temp_endpoint_desc[4]}${temp_endpoint_desc[5]}
							printf "bmAttr %s " ${temp_endpoint_desc[6]}${temp_endpoint_desc[7]}
							lsb=${temp_endpoint_desc[8]}${temp_endpoint_desc[9]}
							msb=${temp_endpoint_desc[10]}${temp_endpoint_desc[11]}
							printf "wMaxPktSize %s " $((0x$msb$lsb))
							printf "bInterval %s" ${temp_endpoint_desc[12]}${temp_endpoint_desc[13]}
						done
					   done
						;;
					3) i=0
					   printf "\n"
					   desc_idx=$((0x${usb_ctrlrequest[2]} & 0x00FF))
					   case $desc_idx in
					   ${usb_device_descriptor[10]}) printf "Manufacturer => " ;;
					   ${usb_device_descriptor[11]}) printf "Product => ";;
					   ${usb_device_descriptor[12]}) printf "SerialNumber => ";;
					   ${usb_config_descriptor[5]}) printf "Configuration => ";;
					   $save_iinterface) printf "Interface => ";;
					   esac

					   received_data=${received_data:4} #TODO - skipped first 2 bytes ( bLength & bDescriptorType )
					   while [ $i -le $datalen ]
					   do
						char=${received_data:0:1}
						if [ "$char" = " " ]
						then
							received_data=${received_data:1}
							continue
						fi

						char=${received_data:0:2}
						received_data=${received_data:2}
						printf \\$(printf '%03o' $((0x$char))) #decimal to ascii
						i=`expr $i + 1`
					   done
						;;
					4) ;;
					5) ;;
					6) ;;
					7) ;;
					8) ;;
					*) ;;
					esac
					;;
				07) ;;
				08) ;;
				09) ;;
				10) ;;
				11) ;;
				12) ;;
				esac ;;
			1) ;; #class request
			2) ;;
			3) ;;
			*)
			esac
		fi

		printf "\nreceived data with len=%s is " $datalen
		for member in ${data_str[*]}; do printf "%s " $member;done
	printf "\n"
	fi #endof test \( $event_str = "CBK" \)
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
		if [ $ept_f ]
		then
			test \( "$ept_str" = "$ept" \) -a  \( -n "$ept_str" \)
			if test $? -eq $TRUE
			then
				printf "\nUrb %s Time %s " $urb_str $time_str
				printf "%s %s Bus %s Addr %s Ept %s" $event_str $ept_type_str $bus_str $addr_str $ept_str
				parse_usb_requests $line #decide parsing of line based on endpoint
			fi
		else
			printf "\nUrb %s Time %s " $urb_str $time_str
			printf "%s %s Bus %s Addr %s Ept %s" $event_str $ept_type_str $bus_str $addr_str $ept_str
			parse_usb_requests $line
		fi
	else
		if [ $ept_f ]
		then
			test \( "$ept_str" = "$ept" \) -a  \( -n "$ept_str" \)
			if test $? -eq $TRUE
			then
				parse_usb_requests $line #decide parsing of line based on endpoint
			fi
		else
			parse_usb_requests $line
		fi
	fi
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
