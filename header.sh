# This file defines global variables, initializations etc.
# Prints help if input variable are not correct.
# It is sourced in main script.

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
	printf "\n        Abbrivations:"
	printf "\n           BIS - Bulk In Storage Class"
	printf "\n           BOS - Bulk Out Storage Class"
	printf "\n           IIC - Interrupt In Communication Class"
}

usb_ctrlrequest=()
usb_ctrlrequest_str=()

usb_device_descriptor=()
usb_config_descriptor=()

#Supported Classes
USB_CLASS_MASS_STORAGE=08
USB_CLASS_CDC_DATA="0a"
USB_CLASS_COMM=02

# Standard Descriptor Types
DT_CONFIG=02
DT_INTERFACE=04
DT_ENDPOINT=05

# Class Descriptors
DT_CS_INTERFACE=24

#Class Requests
SERIAL_STATE=20

# CDC Class [include/linux/usb/cdc.h]
CDC_HEADER_TYPE=00
CDC_CALL_MANAGEMENT_TYPE=01
CDC_ACM_TYPE=02
CDC_UNION_TYPE=06

# SYNCF, SI,GI,SC,GC, SD,GD,SA,R, SF,R,CF,GS - Table9.4 Ch9
std_req_flag=0x0000

# Global definitions
TRUE=0; FALSE=1
no=0; yes=1
INVALID=-1; skip_parsing=0
save_iinterface=-1
submission_datalen=0
data_printed=0; curr_event=$INVALID; prev_event=$INVALID

iInterface_arr=() #array for saving string desc index
#save this endpoint belongs to which class, initialize as a null string to avoid errors?
InEpt_interfaceclass=("", "", "", "", "", "", "", "", "", "", "", "", "", "", "")
OutEpt_interfaceclass=("", "", "", "", "", "", "", "", "", "", "", "", "", "", "")
