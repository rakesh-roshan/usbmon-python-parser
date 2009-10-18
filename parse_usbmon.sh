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
submission_datalen=0

iInterface_arr=() #array for saving string desc index
InEpt_interfaceclass=()
OutEpt_interfaceclass=() #save this endpoint belongs to which class?

# NOTE - Please use only bash for now to test this script.
# i.e. run this script only as "bash parse_usbmon.sh"

#************************************************
#  Parse Mass storage specific command and data
#************************************************

cdb=()

# Print SCSI commands
print_cbw_cmd0() {
	local cbw_cmd0="$@"

	printf "\n       CDB => "
	case $cbw_cmd0 in
	04) printf "FormatUnit " ;;
	12) printf "Inquiry " ;;
	15) printf "ModeSel6 " ;;
	55) printf "ModeSel10 " ;;
	1a) printf "ModeSen6 " ;;
	5a) printf "ModeSen10 " ;;
	1e) printf "PAMRemov " ;;
	08) printf "Read6 " ;;
	28) printf "Read10 " ;;
	a8) printf "Read12 " ;;
	25) printf "ReadCapa " ;;
	23) printf "RdFormtCapa " ;;
	17) printf "Release " ;;
	03) printf "ReqSense " ;;
	16) printf "Reserve " ;;
	1d) printf "SendDiag " ;;
	1b) printf "SStopUnit " ;;
	35) printf "SyncCache " ;;
	00) printf "TUnitRdy " ;;
	2f) printf "Verify " ;;
	0a) printf "Write6 " ;;
	2a) printf "Write10 " ;;
	aa) printf "Write12 " ;;
	*) printf "Invalid " ;;
	esac
}

#	/* Command Block Wrapper */
#	struct bulk_cb_wrap {
#		__le32  Signature;              /* Contains 'USBC' */
#		u32     Tag;                    /* Unique per command id */
#		__le32  DataTransferLength;     /* Size of the data */
#		u8      Flags;                  /* Direction in bit 7 */
#		u8      Lun;                    /* LUN (normally 0) */
#		u8      Length;                 /* Of the CDB, <= MAX_COMMAND_SIZE */
#		u8      CDB[16];                /* Command Data Block */
#};

parse_cbw() {
	local cbw="$@"
	cbw_sign=""
	r=1
	printf "\nCBW => "
	for i in $cbw
	do
		case $r in
		1) cbw_sign=${i:6:2}${i:4:2}${i:2:2}${i:0:2} #restructure byte order
		   printf "Sig %s " $cbw_sign
		   if [ $cbw_sign != "43425355" ]
		   then
			printf "ErrInvalidCBW"
			return
		   fi
			;;
		2) printf "Tag %s " ${i:6:2}${i:4:2}${i:2:2}${i:0:2};;
		3) expected_data=$((0x${i:6:2}${i:4:2}${i:2:2}${i:0:2}))
		   printf "DataLen %s " $expected_data
			;;
		4) printf "Flags %s " ${i:0:2}
		   printf "Lun %s " $((${i:2:2}))
		   printf "CmdLen %s " $((0x${i:4:2}))
		   cdb[0]=${i:6:2}
		   print_cbw_cmd0 ${cdb[0]}
			;;
		5) cdb[1]=${i:0:2}
		   cdb[2]=${i:2:2}
		   cdb[3]=${i:4:2}
		   cdb[4]=${i:6:2}
			;;
		6) cdb[5]=${i:0:2}
		   cdb[6]=${i:2:2}
		   cdb[7]=${i:4:2}
		   cdb[8]=${i:6:2}
			;;
		7) cdb[9]=${i:0:2}
		   cdb[10]=${i:2:2}
		   cdb[11]=${i:4:2}
		   cdb[12]=${i:6:2}
			;;
		8) cdb[13]=${i:0:2}
		   cdb[14]=${i:2:2}
		   cdb[15]=${i:4:2}
			;;
		*) break ;;
		esac
		r=`expr $r + 1`
	done
	printf "%s %s %s %s %s %s %s " ${cdb[1]} ${cdb[2]} ${cdb[3]} ${cdb[4]} ${cdb[5]} ${cdb[6]} ${cdb[7]}
	printf "%s %s %s %s %s %s %s %s" ${cdb[8]} ${cdb[9]} ${cdb[10]} ${cdb[11]} ${cdb[12]} ${cdb[13]} ${cdb[14]} ${cdb[15]}
}

#************************************************

parse_bulk_in() {
	local bulk_in="$@"

#	if [ ${InEpt_interfaceclass[$ept_num]} = "08" ]
#	then
#		printf "bulk In endpoint -> class ${InEpt_interfaceclass[$ept_num]} $bulk_in\n"
#	fi
}

parse_bulk_out() {
	local bulk_out="$@"

	l=1
	OIFS=$IFS
	IFS=$(echo -en " ")
	for i in $bulk_out
	do
		if [ $l -le 5 ]
		then
			temp=`expr ${#i} + 1`
			bulk_out=${bulk_out:$temp} # save received data as a string
		else
			break
		fi
		l=`expr $l + 1`
	done

	space_pos=`expr index "$bulk_out" " "` # find out position of first space
	datalen=${bulk_out:0:`expr $space_pos - 1`}
	bulk_out=${bulk_out:$space_pos} # skip characters of datalen and space

#**************************************************************************************
#	Interface class - Mass storage Subclass- ??
#**************************************************************************************
	test \( $event_str = "SUB" \) -a \( ${OutEpt_interfaceclass[$ept_num]} = "08" \)
	if test $? -eq $TRUE
	then
		bulk_out=${bulk_out:2} # skip 2 characters '=' and space
		submission_datalen=$datalen
		bulk_out_submission=$bulk_out # save and process only if we are sure callback has same datalen
	fi

	test \( $event_str = "CBK" \) -a \( ${OutEpt_interfaceclass[$ept_num]} = "08" \)
	if test $? -eq $TRUE
	then
		if [ $submission_datalen -eq $datalen ] #check if submission and callback datalen is same
		then
			case $datalen in
			31) parse_cbw $bulk_out_submission ;;
			esac

			submission_datalen=0 #make it 0 for next processing
			bulk_out_submission="" #we are done with procession, make it null
		fi
	fi
#**************************************************************************************
}

# 09022000 01010680 fa090400 00020806 50070705 01020002 00070581 02000200
parse_config_desc() {
	local temp_config_desc="$@"
	local config_desc=""
	local temp=0 i=0 d_len=0 d_type=0
	local endpoint=0 num_endpoints=0
	local interface_class=0 temp_ept_num=0 bEptAddr=0 ept_direction=0

	i=1
	while [ $i -le "$datalen" ]
	do
		temp=${temp_config_desc:0:1}
		if [ "$temp" = " " ]
		then
			temp_config_desc=${temp_config_desc:1}
			continue
		fi

		if [ "$temp" = "" ]
		then
			datalen=`expr $i - 1` #update newdata length to only actual received data 
			break #exit from loop if we detectedunexpected end of line
		fi
		temp=${temp_config_desc:0:2}
		temp_config_desc=${temp_config_desc:2}
		config_desc=$config_desc$temp #concatanate every byte after removing space
		i=`expr $i + 1`
	done

	i=1
	while [ $i -le "$datalen" ]
	do
		d_len=$((0x${config_desc:0:2}))
		d_type=$((0x${config_desc:2:2}))
		case $d_type in
		2) printf "\nConfig Desc => "

			usb_config_descriptor[0]=$((0x${config_desc:0:2}))
			config_desc=${config_desc:2}

			usb_config_descriptor[1]=$((0x${config_desc:0:2}))
			config_desc=${config_desc:2}

			msb=${config_desc:0:2}
			lsb=${config_desc:2:2}
			usb_config_descriptor[2]=$((0x$lsb$msb))
			config_desc=${config_desc:4}

			usb_config_descriptor[3]=$((0x${config_desc:0:2}))
			config_desc=${config_desc:2}

			usb_config_descriptor[4]=$((0x${config_desc:0:2}))
			config_desc=${config_desc:2}

			usb_config_descriptor[5]=$((0x${config_desc:0:2}))
			config_desc=${config_desc:2}

			usb_config_descriptor[6]=$((0x${config_desc:0:2}))
			config_desc=${config_desc:2}

			usb_config_descriptor[7]=$((0x${config_desc:0:2}))
			config_desc=${config_desc:2} #remove last byte from datastring
												   #but allow if data is only _conf_ desc
			test \( $d_len -ne 9 \) -o \( $datalen -ne ${usb_config_descriptor[2]} \) -a \( $datalen -gt 9 \)
			if test $? -eq $TRUE
			then
				printf "CONFIG_DESC ERR\n"
				return
			fi

			printf " bLen %s " ${usb_config_descriptor[0]}
			printf "bDescType %s " ${usb_config_descriptor[1]}
			printf "wTotalLen %s " ${usb_config_descriptor[2]}
			printf "bNumInterfaces %s " ${usb_config_descriptor[3]}
			printf "bConfVal %s " ${usb_config_descriptor[4]}
			printf "iConf %s " ${usb_config_descriptor[5]}
			printf "bmAttr %s " ${usb_config_descriptor[6]}
			printf "bMaxPower %s " ${usb_config_descriptor[7]}
			i=`expr $i + 9`
			;;
		4) printf "\nInterface Desc => "

			test \( $d_len -ne 9 \)
			if test $? -eq $TRUE
			then
				printf "INTERFACE_DESC ERR\n"
				return
			fi

			printf "bLen %s " $((0x${config_desc:0:2}))
			config_desc=${config_desc:2}

			printf "bDescType %s " $((0x${config_desc:0:2}))
			config_desc=${config_desc:2}

			printf "bINum %s " $((0x${config_desc:0:2}))
			config_desc=${config_desc:2}

			printf "bAltSetting %s " $((0x${config_desc:0:2}))
			config_desc=${config_desc:2}

			num_endpoints=$((0x${config_desc:0:2}))
			printf "bNumEpt %s " $num_endpoints
			config_desc=${config_desc:2}

			interface_class=${config_desc:0:2}
			printf "bIClass %s " $interface_class
			config_desc=${config_desc:2}

			printf "bISubClass %s " $((0x${config_desc:0:2}))
			config_desc=${config_desc:2}

			printf "bIProto %s " $((0x${config_desc:0:2}))
			config_desc=${config_desc:2}

			save_iinterface=$((0x${config_desc:0:2}))
			iInterface_arr[$save_iinterface]=$save_iinterface
			printf "iInterface %s " $save_iinterface
			config_desc=${config_desc:2}

			i=`expr $i + 9`

			for (( endpoint=0; endpoint < $num_endpoints; endpoint++ ))
			do
				printf "\nEpt Desc $endpoint => "

				test \( $((0x${config_desc:0:2})) -ne 7 \)
				if test $? -eq $TRUE
				then
					printf "ENDPOINT_DESC ERR\n"
					return
				fi

				printf "bLen %s " $((0x${config_desc:0:2}))
				config_desc=${config_desc:2}

				printf "bDescType %s " $((0x${config_desc:0:2}))
				config_desc=${config_desc:2}

				bEptAddr=${config_desc:0:2} #no decimal conversion necessary
				printf "bEptAddr %s " $bEptAddr
				temp_ept_num=$((0x$bEptAddr & 0x0F))
				ept_direction=$(($((0x$bEptAddr & 0x80)) >> 7))
				if [ $ept_direction = "1" ]
				then
					InEpt_interfaceclass[$temp_ept_num]=$interface_class
				else
					OutEpt_interfaceclass[$temp_ept_num]=$interface_class
				fi
				config_desc=${config_desc:2}

				printf "bmAttr %s " $((0x${config_desc:0:2}))
				config_desc=${config_desc:2}

				msb=${config_desc:0:2}
				lsb=${config_desc:2:2}
				printf "wMaxPktSize %s " $((0x$lsb$msb))
				config_desc=${config_desc:4}

				printf "bInterval %s " $((0x${config_desc:0:2}))
				config_desc=${config_desc:2}

				i=`expr $i + 7`
			done
			;;
		esac
	done
}

parse_usb_requests(){
	local req_line="$@" # get all args
	local data_str=()
	local temp_interface_desc=() temp_endpoint_desc=()
	local datalen=0 data_available=$INVALID
	local Direction=0 Type=0 Recep=0
	local msb=0 lsb=0
	local equal_pos=0 received_data=0 data_start=0
	local datastr=0 wtotallen=0 char=0

	test \( "$type_dir" = "Bi" \)
	if test $? -eq $TRUE
	then
		parse_bulk_in $req_line
	fi

	test \( "$type_dir" = "Bo" \)
	if test $? -eq $TRUE
	then
		parse_bulk_out $req_line
	fi

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
					2) parse_config_desc $received_data
						;;
					3) i=1
					   printf "\n"
					   desc_idx=$((0x${usb_ctrlrequest[2]} & 0x00FF))
					   case $desc_idx in
					   0) printf "Language => "
						received_data=${received_data:4}
						if [ "$received_data" = "0904" ] #lets compare with 0904 instead 0409
						then
							printf "ENG-US"
						fi
						printf "\n"
						return
						;;
					   ${usb_device_descriptor[10]}) printf "Manufacturer => " ;;
					   ${usb_device_descriptor[11]}) printf "Product => ";;
					   ${usb_device_descriptor[12]}) printf "SerialNumber => ";;
					   ${usb_config_descriptor[5]}) printf "Configuration => ";;
					   ${iInterface_arr[$desc_idx]}) printf "Interface => ";;
					   esac

					   received_data=${received_data:4} #TODO - skipped first 2 bytes ( bLength & bDescriptorType )
					   while [ $i -le `expr $datalen - 2` ]
					   do
						char=${received_data:0:1}
						if [ "$char" = " " ]
						then
							received_data=${received_data:1}
							continue
						fi

						if [ "$char" = "" ]
						then
							printf "\n"
							return # unexpected EOL
						fi

						char=${received_data:0:2}
						received_data=${received_data:2}

						if [ "$char" = "00" ] #skip printing if "00"
						then
							i=`expr $i + 1`
							continue
						fi
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
	5) #process status feild
		test \( "$ept_num" = "0" \) -a  \( "$event_type" = "S" \)
		if test $? -eq $TRUE
		then
			setup_tag=$i
			if [ $setup_tag != "s" ]
			then
				printf "\nSetup packet not captured => $line"
				return
			fi
		fi

		test \( "$ept_num" = "0" \) -a  \( "$event_type" = "C" \)
		if test $? -eq $TRUE
		then
			if [ $setup_tag != "s" ]
			then
				printf "\nSkiping Callback => $line\n"
				return	#don't want to process callback
					#since previous setup tag was wrong.
			fi
			setup_tag=$i
		fi

		test \( "$ept_type" = "Bi" \) -o \( "$ept_type" = "Bo" \)
		if test $? -eq $TRUE
		then
			if [ "$event_type" = "C" ]
			then
				if [ $i -ne 0 ]
				then
					printf "\nurb error $i => $line"
					return #skip parsing
				fi
			fi
		fi

		# This field makes no sense for submissions & non control endpoints, just skip
		;;
	*) break ;; #we are done with for loop now break
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
