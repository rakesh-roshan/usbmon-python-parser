#!/usr/bin/env bash

# NOTE - Please use only bash for now to test this script.
# i.e. run this script only as "bash parse_usbmon.sh -f usbmonlog.txt"

# accept variable arguments
# addr => device address
# bus => bus number
# ept => endpoint number
# FILE => input file to parse

while getopts 'a:b:e:f:vh' OPTION
do
	case $OPTION in
	a) addr="$OPTARG"
	   addr_f=1		;;
	b) bus="$OPTARG"	;;
	e) ept="$OPTARG"
	   ept_f=1		;;
	f) FILE="$OPTARG"
	   file_f=1		;;
	v) verbose=1		;;
	h) printhelp=1		;;
	*) invalid_args=1	;;
	esac
done
	shift $(($OPTIND - 1))

print_help () {
	printf "\nHELP => "
	printf "\n        Before Running this script, Please make sure you have"
	printf "\n        debugfs mounted and usbmon logging redirected to a text file"
	printf "\n        1. mount -t debugfs none_debugs /sys/kernel/debug"
	printf "\n        2. modprobe usbmon [only, if module not already loaded]"
	printf "\n        3. cat /sys/kernel/debug/usbmon/0u > ~/usbmonlog.txt"
	printf "\n        4. connect device and do necessary operations"
	printf "\n        5. start parsing using \"bash parse_usbmon.sh -f ~/usbmonlog.txt\""
	printf "\n           along with -f , following _optional_ variable args are supported"
	printf "\n           \"-e X\" parse only endpoint X [currently supported only ept 0]"
	printf "\n           \"-a XXX\" parse only device addr XXX"
	printf "\n           \"-v\" print URB Tag, Timestamp in microseconds, Event Type & addr"
	printf "\n           \"-h\" print this help"
}

usb_ctrlrequest=()
usb_ctrlrequest_str=()

usb_device_descriptor=()
usb_config_descriptor=()

#Supported Classes
USB_CLASS_MASS_STORAGE=08

# SYNCF, SI,GI,SC,GC, SD,GD,SA,R, SF,R,CF,GS - Table9.4 Ch9
std_req_flag=0x0000

# Global definitions
TRUE=0
FALSE=1
no=0
yes=1
INVALID=-1
save_iinterface=-1
submission_datalen=0
data_printed=0; curr_event=$INVALID; prev_event=$INVALID

iInterface_arr=() #array for saving string desc index
InEpt_interfaceclass=()
OutEpt_interfaceclass=() #save this endpoint belongs to which class?

#************************************************
#  Parse Mass storage specific command and data
#************************************************

cdb=()

# Reference http://www-ccf.fnal.gov/enstore/AMUdocs/Scalar1000/s1k_scsi.pdf
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
parse_cbw() {
	local cbw="$@"
	local r=0
	cbw_sign=""
	r=1
	printf "\nCBW => "

	cbw_sign=${cbw:6:2}${cbw:4:2}${cbw:2:2}${cbw:0:2} #restructure byte order
	printf "Sig %s " $cbw_sign
	if [ $cbw_sign != "43425355" ]
	then
		printf "ErrInvalidCBW"
		return
	fi
	cbw=${cbw:9} #include space

	printf "Tag %s " ${cbw:6:2}${cbw:4:2}${cbw:2:2}${cbw:0:2}
	cbw=${cbw:9} #include space

	expected_data=$((0x${cbw:6:2}${cbw:4:2}${cbw:2:2}${cbw:0:2}))
	printf "DataLen %s " $expected_data
	cbw=${cbw:9} #include space

	printf "Flags %s Lun %s CmdLen %s " ${cbw:0:2} $((${cbw:2:2})) $((0x${cbw:4:2}))
	cdb[0]=${cbw:6:2}
	print_cbw_cmd0 ${cdb[0]}
	cbw=${cbw:9} #include space

	cdb[1]=${cbw:0:2} cdb[2]=${cbw:2:2} cdb[3]=${cbw:4:2} cdb[4]=${cbw:6:2}
	cbw=${cbw:9} #include space

	cdb[5]=${cbw:0:2} cdb[6]=${cbw:2:2} cdb[7]=${cbw:4:2} cdb[8]=${cbw:6:2}
	cbw=${cbw:9} #include space

	cdb[9]=${cbw:0:2} cdb[10]=${cbw:2:2} cdb[11]=${cbw:4:2} cdb[12]=${cbw:6:2}
	cbw=${cbw:9} #include space

	cdb[13]=${cbw:0:2} cdb[14]=${cbw:2:2} cdb[15]=${cbw:4:2}

	printf "%s %s %s %s %s %s %s " ${cdb[1]} ${cdb[2]} ${cdb[3]} ${cdb[4]} ${cdb[5]} ${cdb[6]} ${cdb[7]}
	printf "%s %s %s %s %s %s %s %s" ${cdb[8]} ${cdb[9]} ${cdb[10]} ${cdb[11]} ${cdb[12]} ${cdb[13]} ${cdb[14]} ${cdb[15]}
}

mass_storage_bulkindata() {
	local blkin="$@"
	local r=0 char=0

	data_printed=1
	printf "\nData => "

	# Inquiry Reference http://en.wikipedia.org/wiki/SCSI_Inquiry_Command
	test \( ${cdb[0]} = "12" \) -a \( $bulkin_sub_datalen = "36" \)
	if test $? -eq $TRUE
	then
		printf "PDT %s RMB %s ANSI_3 %s RDF_4 %s " ${blkin:0:2} ${blkin:2:2} ${blkin:4:2} ${blkin:6:2}
		blkin=${blkin:9}

		printf "ALEN %s " $((0x${bulkin:0:2}))
		blkin=${blkin:9}

		printf "Vendor "
		for ((r=0; r<9; r++)) #continue if space
		do
			char=${blkin:0:1}
			if [ "$char" = " " ]
			then
				blkin=${blkin:1}
				continue
			fi
			char=${blkin:0:2}
			blkin=${blkin:2}
			printf \\$(printf '%03o' $((0x$char))) #decimal to ascii
		done

		blkin=${blkin:1} #skip space

		printf " Product "
		for ((r=0; r<19; r++)) #continue if space
		do
			char=${blkin:0:1}
			if [ "$char" = " " ]
			then
				blkin=${blkin:1}
				continue
			else
				if [ "$char" = "" ] #unexpected EOL
				then
					return
				fi
			fi
			char=${blkin:0:2}
			blkin=${blkin:2}
			printf \\$(printf '%03o' $((0x$char))) #decimal to ascii
		done

		# blkin=${blkin:1} #skip space
		# TODO print revision
		return #done, now return from function
	fi

	# reference http://manpages.ubuntu.com/manpages/karmic/man8/sg_readcap.8.html
	test \( ${cdb[0]} = "25" \) -a \( $bulkin_sub_datalen = "8" \)
	if test $? -eq $TRUE
	then
		r=1
		for i in $blkin
		do
			case $r in
			1) lastblkaddr=$((0x$i))
			   num_blks=`expr $lastblkaddr + 1`
			   printf "Blks %s " $num_blks
				;;
			2) blk_size=$((0x$i))
			   total_capa=`expr $num_blks \* $blk_size`
			   printf "BlkSize %s TotalCapa %sMB" $blk_size `expr $total_capa / 1000000` #round up to MB's
			esac
			r=`expr $r + 1`
		done
		return
	fi

	printf "$blkin"
}

parse_csw() {
	local csw="$@"
	local r=0 csw_sign=0

	r=1
	printf "\nCSW => "
	for i in $csw
	do
		case $r in
		1) csw_sign=${i:6:2}${i:4:2}${i:2:2}${i:0:2} #restructure byte order
		   printf "Sig %s " $csw_sign
		   if [ $csw_sign != "53425355" ]
		   then
			printf "ErrInvalidCSW\n"
			return
		   fi
			;;
		2) printf "Tag %s " ${i:6:2}${i:4:2}${i:2:2}${i:0:2};;
		3) printf "Residue %s " $((0x${i:6:2}${i:4:2}${i:2:2}${i:0:2}));;
		4) printf "Status "
			case $i in
			00) printf "Pass" ;;
			01) printf "FAIL" ;;
			02) printf "ERROR" ;;
			esac
		esac
		r=`expr $r + 1`
	done
	printf "\n" #one transaction of CBW, DATA & CSW is completed
}

#************************************************
bulkin_sub_datalen=0

parse_bulk_in() {
	local bulk_in="$@"
	local datalen=0

	l=1
	OIFS=$IFS
	IFS=$(echo -en " ")
	for i in $bulk_in
	do
		if [ $l -le 5 ]
		then
			temp=`expr ${#i} + 1`
			bulk_in=${bulk_in:$temp} # save received data as a string
		else
			break
		fi
		l=`expr $l + 1`
	done

	space_pos=`expr index "$bulk_in" " "` # find out position of first space
	datalen=${bulk_in:0:`expr $space_pos - 1`}
	bulk_in=${bulk_in:$space_pos} # skip characters of datalen and space

#**************************************************************************************
#	Interface class - Mass storage Subclass- ??
#**************************************************************************************
	test \( $event_str = "SUB" \) -a \( ${InEpt_interfaceclass[$ept_num]} = "$USB_CLASS_MASS_STORAGE" \)
	if test $? -eq $TRUE
	then
		data_printed=0
		bulkin_sub_datalen=`expr $bulkin_sub_datalen + $datalen`
	fi

	test \( $event_str = "CBK" \) -a \( ${InEpt_interfaceclass[$ept_num]} = "$USB_CLASS_MASS_STORAGE" \)
	if test $? -eq $TRUE
	then
		bulk_in=${bulk_in:2} # skip 2 characters '=' and space
		if [ $expected_data != 0 ]
		then
			if [ $bulkin_sub_datalen -eq $expected_data ] #check if submission and callback datalen is same
			then
				mass_storage_bulkindata $bulk_in
				if [ $bulkin_sub_datalen -gt 32 ]
				then
					printf " snip..."
				fi
				bulkin_sub_datalen=0	#ignore any more data for printing
			fi

			test \( $bulkin_sub_datalen = "13" \)
			if test $? -eq $TRUE
			then
				parse_csw $bulk_in
				bulkin_sub_datalen=0
			fi
		fi

		if [ $expected_data = 0 ]
		then
			test \( $bulkin_sub_datalen = "13" \)
			if test $? -eq $TRUE
			then
				parse_csw $bulk_in
				bulkin_sub_datalen=0
			fi
		fi
	fi
}

parse_bulk_out() {
	local bulk_out="$@"
	local datalen=0

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
	test \( $event_str = "SUB" \) -a \( ${OutEpt_interfaceclass[$ept_num]} = "$USB_CLASS_MASS_STORAGE" \)
	if test $? -eq $TRUE
	then
		bulk_out=${bulk_out:2} # skip 2 characters '=' and space
		submission_datalen=$datalen
		bulk_out_submission=$bulk_out # save and process only if we are sure callback has same datalen
	fi

	test \( $event_str = "CBK" \) -a \( ${OutEpt_interfaceclass[$ept_num]} = "$USB_CLASS_MASS_STORAGE" \)
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
	local temp=0 i=0 d_len=0 d_type=0 datalen=0
	local endpoint=0 num_endpoints=0
	local interface_class=0 temp_ept_num=0 bEptAddr=0 ept_direction=0
	local intrf_desc=()
	local ept_desc=()

	config_desc=`echo $temp_config_desc | sed 's/ //g'` #remove space's from string
	datalen=`expr ${#config_desc} / 2` #update newdata length to only actual received data

	i=1
	while [ $i -le "$datalen" ]
	do
		d_len=$((0x${config_desc:0:2}))
		d_type=$((0x${config_desc:2:2}))
		case $d_type in
		2) printf "\nConfig Desc => "

			usb_config_descriptor[0]=$((0x${config_desc:0:2}))
			usb_config_descriptor[1]=$((0x${config_desc:2:2}))
			msb=${config_desc:4:2}
			lsb=${config_desc:6:2}
			usb_config_descriptor[2]=$((0x$lsb$msb))
			usb_config_descriptor[3]=$((0x${config_desc:8:2}))
			usb_config_descriptor[4]=$((0x${config_desc:10:2}))
			usb_config_descriptor[5]=$((0x${config_desc:12:2}))
			usb_config_descriptor[6]=$((0x${config_desc:14:2}))
			usb_config_descriptor[7]=$((0x${config_desc:16:2}))
			config_desc=${config_desc:18} #remove config desc for next processing
												   #but allow if data is only _conf_ desc
			test \( $d_len -ne 9 \) -o \( $datalen -ne ${usb_config_descriptor[2]} \) -a \( $datalen -gt 9 \)
			if test $? -eq $TRUE
			then
				printf "CONFIG_DESC ERR\n"
				return
			fi

			printf " bLen %s bDescType %s " ${usb_config_descriptor[0]} ${usb_config_descriptor[1]}
			printf "wTotalLen %s bNumInterfaces %s " ${usb_config_descriptor[2]} ${usb_config_descriptor[3]}
			printf "bConfVal %s iConf %s " ${usb_config_descriptor[4]} ${usb_config_descriptor[5]}
			printf "bmAttr %s bMaxPower %s " ${usb_config_descriptor[6]} ${usb_config_descriptor[7]}
			i=`expr $i + 9`
			;;
		4) printf "\nInterface Desc => "

			test \( $d_len -ne 9 \)
			if test $? -eq $TRUE
			then
				printf "INTERFACE_DESC ERR\n"
				return
			fi
			intrf_desc[0]=$((0x${config_desc:0:2}))
			intrf_desc[1]=$((0x${config_desc:2:2}))
			intrf_desc[2]=$((0x${config_desc:4:2}))
			intrf_desc[3]=$((0x${config_desc:6:2}))
			num_endpoints=$((0x${config_desc:8:2}))
			intrf_desc[4]=$num_endpoints
			interface_class=${config_desc:10:2}
			intrf_desc[5]=$interface_class
			intrf_desc[6]=$((0x${config_desc:12:2}))
			intrf_desc[7]=$((0x${config_desc:14:2}))
			save_iinterface=$((0x${config_desc:16:2}))
			iInterface_arr[$save_iinterface]=$save_iinterface
			intrf_desc[8]=$save_iinterface
			config_desc=${config_desc:18}

			printf "bLen %s bDescType %s bINum %s " ${intrf_desc[0]} ${intrf_desc[1]} ${intrf_desc[2]}
			printf "bAltSetting %s bNumEpt %s bIClass %s " ${intrf_desc[3]} ${intrf_desc[4]} ${intrf_desc[5]}
			printf "bISubClass %s bIProto %s iInterface %s " ${intrf_desc[6]} ${intrf_desc[7]} ${intrf_desc[8]}

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

				ept_desc[0]=$((0x${config_desc:0:2}))
				ept_desc[1]=$((0x${config_desc:2:2}))

				bEptAddr=${config_desc:4:2} #no decimal conversion necessary
				ept_desc[2]=$bEptAddr
				temp_ept_num=$((0x$bEptAddr & 0x0F))
				ept_direction=$(($((0x$bEptAddr & 0x80)) >> 7))
				if [ $ept_direction = "1" ]
				then
					InEpt_interfaceclass[$temp_ept_num]=$interface_class
				else
					OutEpt_interfaceclass[$temp_ept_num]=$interface_class
				fi

				ept_desc[3]=$((0x${config_desc:6:2}))
				msb=${config_desc:8:2}
				lsb=${config_desc:10:2}
				ept_desc[4]=$((0x$lsb$msb))
				ept_desc[5]=$((0x${config_desc:12:2}))
				config_desc=${config_desc:14}

				printf "bLen %s bDescType %s bEptAddr %s " ${ept_desc[0]} ${ept_desc[1]} ${ept_desc[2]}
				printf "bmAttr %s wMaxPktSize %s bInterval %s " ${ept_desc[3]} ${ept_desc[4]} ${ept_desc[5]}

				i=`expr $i + 7`
			done
			;;
		esac
	done
}

ep0_datalen=0 data_available=$INVALID
parse_usb_requests(){
	local req_line="$@" # get all args
	local temp_interface_desc=() temp_endpoint_desc=()
	local Direction=0 Type=0 Recep=0
	local msb=0 lsb=0
	local equal_pos=0 received_data=0 data_start=0
	local datastr=0 wtotallen=0 char=0

	[[ "$type_dir" = "Bi" ]] && parse_bulk_in $req_line

	[[ "$type_dir" = "Bo" ]] && parse_bulk_out $req_line

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

			7) usb_ctrlrequest[1]=$i # __u8 bRequest
				if [ $Type_str = "Std" ]
				then
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
					esac
				fi

				if [ $Type_str = "Class" ]
				then
					case $i in
							#mass-storage
					fe) usb_ctrlrequest_str[1]="GetMaxLun" ;;
					ff) usb_ctrlrequest_str[1]="BulkReset" ;;
					esac
				fi
				;;
			8) usb_ctrlrequest[2]=$i
				if [ $Type_str = "Std" ]
				then
					case ${usb_ctrlrequest[1]} in
					00) ;;
					01) 	case $i in
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
					esac
				fi

				if [ $Type_str = "Class" ]
				then
					case ${usb_ctrlrequest[1]} in
					fe) usb_ctrlrequest_str[2]="WVal-0" ;;
					ff) usb_ctrlrequest_str[2]="WVal-0" ;;
					esac
				fi
				;;
			9) usb_ctrlrequest[3]=$i
				if [ $Type_str = "Std" ]
				then
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
					esac
				fi

				if [ $Type_str = "Class" ]
				then
					case ${usb_ctrlrequest[1]} in
					fe) usb_ctrlrequest_str[3]="Interface-$i" ;;
					ff) usb_ctrlrequest_str[3]="Interface-$i" ;;
					esac
				fi
				;;
			10) ;; # skip hex value for wLength
			11) usb_ctrlrequest[4]=$i #consider dacimal wLength
			    usb_ctrlrequest_str[4]="wLen-$i" ;;
			esac
		l=`expr $l + 1`
		done

	printf "\nbReqType=%s bReq=%s wVal=%s " ${usb_ctrlrequest[0]} ${usb_ctrlrequest[1]} ${usb_ctrlrequest[2]}
	printf "wIdx=%s wLen=%s" ${usb_ctrlrequest[3]} ${usb_ctrlrequest[4]}

	printf "\n%s %s %s " ${usb_ctrlrequest_str[0]} ${usb_ctrlrequest_str[1]} ${usb_ctrlrequest_str[2]}
	printf "%s %s" ${usb_ctrlrequest_str[3]} ${usb_ctrlrequest_str[4]}

	fi #endof test \( $event_str = "SUB" \)

	test \( $event_str = "CBK" \) -a  \( -n "$event_str" \) -a \( "$ept_str" = "0" \)
	if test $? -eq $TRUE
	then

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
						usb_device_descriptor[0]=$((${received_data:0:2}))
						usb_device_descriptor[1]=$((${received_data:2:2}))
						lsb=${received_data:4:2}; msb=${received_data:6:2}
						usb_device_descriptor[2]="$msb$lsb"
						printf "\nbLen %s bDes %s " ${usb_device_descriptor[0]} ${usb_device_descriptor[1]}
						printf "bcdUSB %.2d%.2d " $msb $lsb
						received_data=${received_data:9}

						usb_device_descriptor[3]=$((${received_data:0:2}))
						usb_device_descriptor[4]=$((${received_data:2:2}))
						usb_device_descriptor[5]=$((${received_data:4:2}))
						usb_device_descriptor[6]=$((0x${received_data:6:2}))
						printf "bDevClass %s bDevSubClass %s " ${usb_device_descriptor[3]} ${usb_device_descriptor[4]}
						printf "bDevProto %s bMaxPkt0 %s " ${usb_device_descriptor[5]} ${usb_device_descriptor[6]}
						received_data=${received_data:9}

						lsb=${received_data:0:2}; msb=${received_data:2:2}
						usb_device_descriptor[7]="$msb$lsb"
						lsb=${received_data:4:2}; msb=${received_data:6:2}
						usb_device_descriptor[8]="$msb$lsb"
						printf "idVendor %s idProduct %s " ${usb_device_descriptor[7]} ${usb_device_descriptor[8]}
						received_data=${received_data:9}

						lsb=${received_data:0:2}; msb=${received_data:2:2}
						usb_device_descriptor[9]="$msb$lsb"
						usb_device_descriptor[10]=$((${received_data:4:2}))
						usb_device_descriptor[11]=$((${received_data:6:2}))
						printf "bcdDev %s iManufact %s " ${usb_device_descriptor[9]} ${usb_device_descriptor[10]}
						printf "iProduct %s " ${usb_device_descriptor[11]}
						received_data=${received_data:9}

						usb_device_descriptor[12]=$((${received_data:0:2}))
						usb_device_descriptor[13]=$((${received_data:2:2}))
						printf "iSerialNum %s bNumConf %s" ${usb_device_descriptor[12]} ${usb_device_descriptor[13]}
						printf "\n"
						return
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
					   while [ $i -le `expr $ep0_datalen - 2` ]
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
			1) #class request
				case ${usb_ctrlrequest[1]} in
				fe) printf "\nMaxLun $(($received_data))" ;;
				esac
				;;
			2) ;;
			3) ;;
			*)
			esac
		else #no data available
			printf "\n" # print \n for proper formatting of printing
			return 0
		fi
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
	prev_event=$curr_event

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
		esac
		curr_event=$event_str #below logic, doesnt process any same event lines onces,
					#data is printed, implented to save parsing time.
		[[ "$curr_event" = "$prev_event" ]] && [[ $data_printed = "1" ]] && return
		;;
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
					bulkin_sub_datalen=0	#make this 0 since we are skiping
								#parsing of BulkIn Callback
					printf "\nurb error $i => $line"
					return #skip parsing
				fi
			fi
		fi

		# This field makes no sense for submissions & non control endpoints, just skip
		;;
	6)
		test \( $event_str = "CBK" \) -a \( "$ept_str" = "0" \)
		if test $? -eq $TRUE
		then
			if [ "$i" == "0" ]
			then
				data_available=$no
			else
				ep0_datalen=$i
				data_available=$yes
			fi
			break
		fi
		;;
	*) break ;; #we are done with for loop now break
	esac

	arg=`expr $arg + 1`
	done

	test \( "$ept_f" = "1" \) -a  \( "$addr_f" = "1" \)
	if test $? -eq $TRUE
	then
		test \( "$ept_str" = "$ept" \) -a  \( "$addr_str" = "$addr" \)
		if test $? -eq $TRUE
		then
			if [ $verbose ]
			then
				printf "\nUrb %s Time %s " $urb_str $time_str
				printf "%s %s Bus %s Addr %s Ept %s" $event_str $ept_type_str $bus_str $addr_str $ept_str
			fi
			parse_usb_requests $line
			return
		else
			return
		fi
	fi

	test \( "$ept_f" = "1" \) -o  \( "$addr_f" = "1" \)
	if test $? -eq $TRUE
	then
		test \( "$ept_str" = "$ept" \) -o  \( "$addr_str" = "$addr" \)
		if test $? -eq $TRUE
		then
			if [ $verbose ]
			then
				printf "\nUrb %s Time %s " $urb_str $time_str
				printf "%s %s Bus %s Addr %s Ept %s" $event_str $ept_type_str $bus_str $addr_str $ept_str
			fi
			parse_usb_requests $line #decide parsing of line based on endpoint
			return
		else
			return
		fi
	fi

	if [ $verbose ]
	then
		printf "\nUrb %s Time %s " $urb_str $time_str
		printf "%s %s Bus %s Addr %s Ept %s" $event_str $ept_type_str $bus_str $addr_str $ept_str
	fi
	parse_usb_requests $line
}

# Following logic is based upon implementation from
# http://bash.cyberciti.biz/file-management/read-a-file-line-by-line/
 
BAKIFS=$IFS
IFS=$(echo -en "\n\b")

exec 3<&0

test \( "$printhelp" = "1" \) -o  \( "$file_f" != "1" \) -o \( "$ept" != "0" \) -a \( "$ept_f" = "1" \) -o \( "$invalid_args" = "1" \)
if test $? -eq $TRUE
then
	print_help
	printf "\n\n"
	exit
fi

exec 0<$FILE
	while read line
	do
	processLine $line
	done
exec 0<&3
 
IFS=$BAKIFS
exit 0
