#!/usr/bin/python

import os
import string

# global variable used by multipule functions
urb_tag = None
delta = None
event_type = None
urb_type = None
bus = None
device = None
endpoint = None

# static variable
delta_tmp = None

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
    for i in range(0, len(data), 2):
            tmp = hexstr2asc(data[i:i+2])
            ## if printable
            if tmp in string.letters or tmp in string.hexdigits \
            or tmp in  string.punctuation:
                datax = datax + tmp
            else:
                datax = datax + '.'
    return datax
    
def ctl_parse(post_line):
    global urb_tag
    global delta
    global event_type
    global urb_type
    global bus
    global device
    global endpoint

    try:
        array = post_line.split(' ')
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
        print "ERR!--Raw data:" + post_line
    
def buk_parse(post_line):
    global urb_tag
    global delta
    global event_type
    global urb_type
    global bus
    global device
    global endpoint

    try:
        #print '\n' + post_line + '\n'
        array = post_line.split(' ')
        status = array[0]
        #print status
        length = array[1]
        #print len
        data = ''
        if ((len(array) > 3) and (array[2] == '=')):
            data = ' '.join(array[3:])
        if event_type == 'S':
            print "Sta=%s\tRE=%d\t%s" % (status, int(length), data)
        else:
            print "Sta=%s\t\tRC=%d\t%s" % (status, int(length), data)
        print "\t"*5 + to_ascii(data)
        #print post_line
    except:
        print "ERR!--Raw data:" + post_line

def int_parse(post_line):
    global urb_tag
    global delta
    global event_type
    global urb_type
    global bus
    global device
    global endpoint
    
    print post_line

def iso_parse(post_line):
    global urb_tag
    global delta
    global event_type
    global urb_type
    global bus
    global device
    global endpoint
    
    print post_line


def pre_parse(pre_line):
    global urb_tag
    global delta
    global event_type
    global urb_type
    global bus
    global device
    global endpoint
    
    global delta_tmp

    array = pre_line.split(' ')

    urb_tag = array[0]
    
    if delta_tmp == None:
        delta = 0
        delta_tmp = array[1]
    else:
        deltax = long(array[1]) - long(delta_tmp)
        if (deltax > 1000000) :
            delta = str(deltax/100000) + "s"
        elif (deltax > 1000) :
            delta = str(deltax/1000) + 'ms'
        else:
            delta = str(deltax) + 'us'
        
        delta_tmp = array[1]
    #print array[1]
    event_type = array[2]
    arrayx = array[3].split(':')
    urb_type = urbtype_d[arrayx[0]]
    bus = int(arrayx[1])
    device = int(arrayx[2])
    endpoint = int(arrayx[3])
    print "%d-%d-%d\t%s\t%s\t" % (bus, device, endpoint, \
                                         urb_type, delta),

def post_parse(post_line):
    global urb_tag
    global delta
    global event_type
    global urb_type
    global bus
    global device
    global endpoint
    
    global delta_tmp

    if (urb_type == urbtype_d['Ci'] or urb_type == urbtype_d['Co']):
        ctl_parse(post_line)
    elif (urb_type == urbtype_d['Bi'] or urb_type == urbtype_d['Bo']):
        buk_parse(post_line)
    elif (urb_type == urbtype_d['Ii'] or urb_type == urbtype_d['Ii']):
        int_parse(post_line)
    elif (urb_type == urbtype_d['Zi'] or urb_type == urbtype_d['Zo']):
        iso_parse(post_line)
    else:
        print "---ERR---" + post_line

def run(path):
    try:
        fh = open(path, "r")
        
        while True:
            line = fh.readline()
            
            pre_line = line[:40]
            pre_line = pre_line.strip()
            pre_parse(pre_line)
            
            post_line = line[40:]
            post_line = post_line.strip()
            post_parse(post_line)
    except:
        return

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



