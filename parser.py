#!/usr/bin/python

import os
import string
import traceback

# global variable used by multipule functions

urb_tag = None
delta = None
event_type = None
urb_type = None
bus = None
device = None
endpoint = None

# static variable
delta_tmp = {}

# readonly global variable
#event_type = {'S': 'Submission', 'C': 'Callback', 'E': 'Error'}
urbtype_d = {'Ci': 'Ci', 'Co': 'Co', \
             'Zi': 'Zi', 'Zo': 'Zo', \
             'Ii': 'Ii', 'Io': 'Io', \
             'Bi': 'Bi', 'Bo': 'Bo'}
std_req = {'00': 'GET_STATUS', \
           '01': 'CLEAR_FEATURE', \
           '03': 'SET_FEATURE', \
           '05': 'SET_ADDRESS', \
           '06': 'GET_DESCRIPTOR', \
           '07': 'SET_DESCRIPTOR', \
           '08': 'GET_CONFIG', \
           '09': 'SET_CONFIG', \
           '0a': 'GET_INTERFACE', \
           '11': 'SET_INTERFACE', \
           '12': 'SYNCH_FRAME'
           }


def lsusb():
    output = os.popen('lsusb').read()
    print output

def hexstr2asc(hexstr):
    return chr(int(hexstr, 16))
    
def cmd_parse(cmd):
    cmd = cmd.split(' ')
    return std_req[cmd[1]]

def to_ascii(data):
    datax = ''
    data = data.replace(' ', '')
    for i in range(0, len(data)-2, 2):
            tmp = hexstr2asc(data[i:i+2])
            ## if printable
            if tmp in string.letters or tmp in string.hexdigits \
            or tmp in  string.punctuation:
                datax = datax + tmp
            else:
                datax = datax + '.'
    return datax
    
def ctl_parse(array):
    global urb_tag
    global delta
    global event_type
    global urb_type
    global bus
    global device
    global endpoint

    try:
        #array = post_line.split(' ')
        if event_type == 'S':
            #if array[0] != 's':
            #    print "---Bad---" + post_line
            #    return
            raw_cmd = ' '.join(array[1:-2])
            cmd = cmd_parse(raw_cmd)
            req_len = int(array[-2])
            print "%s\tRE=%d\t%s" % (cmd, req_len, raw_cmd)
        elif event_type == 'C':
            status = array[0]
            act_len = array[1]
            #data = post_line[7:]
            data = ' '.join(array[3:])
            print "Sta=%s\t\tRC=%d\t%s" % (status, int(act_len), data)
            print "\t"*5 + to_ascii(data)
    except:
        print "ERR!--Raw data:", array
        traceback.print_exc()
    
def buk_parse(array):
    global urb_tag
    global delta
    global event_type
    global urb_type
    global bus
    global device
    global endpoint

    try:
        #print '\n' + post_line + '\n'
        #array = post_line.split(' ')
        status = array[0]
        #print status
        length = array[1]
        #print len
        data = ''
        if ((len(array) > 3) and (array[2] == '=')):
            data = ' '.join(array[3:])
        if event_type == 'S':
            #print "Sta=%s\tRE=%d\t%s" % (status, int(length), data)
            delta_tmp[urb_tag]["sub_length"]=length
            delta_tmp[urb_tag]["sub_status"]=status
            delta_tmp[urb_tag]["sub_data"]=data
            
        else:
            if delta_tmp.has_key(urb_tag):
                print "\nSta=%s\t\tRC=%d\t%s" % (delta_tmp[urb_tag]["sub_status"], 
                                               int(delta_tmp[urb_tag]["sub_length"]), 
                                               delta_tmp[urb_tag]["sub_data"].strip())
                del delta_tmp[urb_tag]
            print "Sta=%s\t\tRC=%d\t%s" % (status, int(length), data)
            print "\t"*5 + to_ascii(data)
        #print post_line
    except:
        print "ERR!--Raw data:",array
        traceback.print_exc()

def int_parse(post_line):
    global urb_tag
    global delta
    global event_type
    global urb_type
    global bus
    global device
    global endpoint
    
    #print post_line

def iso_parse(post_line):
    global urb_tag
    global delta
    global event_type
    global urb_type
    global bus
    global device
    global endpoint
    print ""
    #print post_line


def pre_parse(array):
    global urb_tag
    global delta
    global event_type
    global urb_type
    global bus
    global device
    global endpoint
    
    global delta_tmp

    #array = pre_line.split(' ')

    urb_tag = array[0]
    event_type = array[2]
    if(event_type == 'S'):        
        delta = 0
        if(not delta_tmp.has_key(urb_tag)):
            delta_tmp[urb_tag]={"sub_time":array[1],"sub_length":0}
        delta_tmp[urb_tag]["sub_time"] = array[1]            
        return 0
    if(event_type == 'E'):
        print 'Error packet'
        return 0
    if delta_tmp == None or not delta_tmp.has_key(urb_tag) or delta_tmp[urb_tag]["sub_time"]==None:
        return 0;
    deltax = long(array[1]) - long(delta_tmp[urb_tag]["sub_time"])
    if (deltax > 1000000) :
        delta = str(deltax/100000) + "s"
    elif (deltax > 1000) :
        delta = str(deltax/1000) + 'ms'
    else:
        delta = str(deltax) + 'us'
        
    delta_tmp[urb_tag]["sub_time"] = None
    #print array[1]
    arrayx = array[3].split(':')
    urb_type = urbtype_d[arrayx[0]]
    bus = int(arrayx[1])
    device = int(arrayx[2])
    endpoint = int(arrayx[3])
    print "%d-%d-%d\t%s\t%s\t" % (bus, device, endpoint, \
                                         urb_type, delta),
    return 1

def post_parse(post_line_fields):
    global urb_tag
    global delta
    global event_type
    global urb_type
    global bus
    global device
    global endpoint
    
    global delta_tmp

    if (urb_type == urbtype_d['Ci'] or urb_type == urbtype_d['Co']):
        ctl_parse(post_line_fields)
    elif (urb_type == urbtype_d['Bi'] or urb_type == urbtype_d['Bo']):
        buk_parse(post_line_fields)
    elif (urb_type == urbtype_d['Ii'] or urb_type == urbtype_d['Ii']):
        int_parse(post_line_fields)
    elif (urb_type == urbtype_d['Zi'] or urb_type == urbtype_d['Zo']):
        iso_parse(post_line_fields)
    else:
        print "---ERR---" ,urb_type, post_line_fields

def run(path):
    global urb_tag
    global delta
    global event_type
    global urb_type
    global bus
    global device
    global endpoint
    
    global delta_tmp
    try:
        fh = open(path, "r")
        
        while True:
            line = fh.readline()
            line.strip();
            line_fields=line.split(' ');
            
            pre_line_fields = line_fields[:4]
            #pre_line = pre_line.strip()
            ret=pre_parse(pre_line_fields)
            if(ret!=0 or event_type=='S'):
                #print "Post"
                post_line_fields = line_fields[4:]
                #post_line = post_line.strip()
                post_parse(post_line_fields)
    except:
        urb_tag = None
        delta = None
        event_type = None
        urb_type = None
        bus = None
        device = None
        endpoint = None
        
# static variable
        delta_tmp = {}

        traceback.print_exc()
        return


def main():
	fh = open("/sys/kernel/debug/usb/usbmon/2u", "r")

	while True:
	    line = fh.readline()
    	
	    pre_line = line[:40]
	    pre_line = pre_line.strip()
	    pre_parse(pre_line)
    
	    post_line = line[40:]
	    post_line = post_line.strip()
	    post_parse(post_line)
    #print post_line


if __name__=="__main__":
	main()


