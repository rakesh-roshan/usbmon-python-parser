#!/usr/bin/python

from __future__ import print_function
import os
import string
import traceback
from   optparse  import OptionParser

# global variable used by multipule functions

urb_tag = None
delta = None
event_type = None
urb_type = None
bus = None
device = None
endpoint = None
outf = None
count = 1
# static variable
delta_tmp = {}
last_delta = None

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
           '0b': 'SET_INTERFACE', \
           '0c': 'SYNCH_FRAME'
           }


parser = OptionParser()
parser.add_option("-f","--file",dest="filename")

def lsusb():
    output = os.popen('lsusb').read()
    print (output)

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
    
def ctl_parse(array,store=True):
    global urb_tag
    global delta
    global event_type
    global urb_type
    global bus
    global device
    global endpoint
    global outf
    try:
        #array = post_line.split(' ')
        if event_type == 'S':
	    raw_cmd=""
            array2=[]
            #if array[0] != 's':
            #    print "---Bad---" + post_line
            #    return
            #raw_cmd = ' '.join(array[1:-2])
            for num in array[1:]:
		if(num.isalnum()):
 			array2.append(num)
		else:
			break

            raw_cmd = ' '.join(array2[:-1])
            try:
              req_len = int(array2[-1])
   	    except:
              print ("ERR!-- int conv in ctl_parse:", array2[-1],raw_cmd,file=outf)
              req_len=0
		
	    try:
	            cmd = cmd_parse(raw_cmd)
   	    except:
              print ("ERR!-- cmd parse in ctl_parse:", raw_cmd,file=outf)
              cmd="UNKNOWN"
            if(not store):
                print ("%s\tRE=%d\t%s\n" % (cmd, 
                       req_len,raw_cmd),file=outf)
            else:
                delta_tmp[urb_tag]["sub_cmd"]=cmd
                delta_tmp[urb_tag]["sub_length"]=req_len
                delta_tmp[urb_tag]["sub_raw_cmd"]=raw_cmd
                
        elif event_type == 'C':
            status = array[0]
            act_len = array[1]
            #data = post_line[7:]
            data = ' '.join(array[3:])
            if delta_tmp.has_key(urb_tag):
            	print ("%s\tRE=%d\t%s" % (delta_tmp[urb_tag]["sub_cmd"], 
                       delta_tmp[urb_tag]["sub_length"], delta_tmp[urb_tag]["sub_raw_cmd"]),file=outf)
                del delta_tmp[urb_tag]
            print ("Sta=%s\t\tRC=%d\t%s" % (status, int(act_len), data),file=outf)
            print ("\t"*5 + to_ascii(data),file=outf)
    except:
        print ("ERR!--Raw data in ctl_parse:", array,raw_cmd,file=outf)
        traceback.print_exc()
    
def bulk_parse(array,store=True):
    global urb_tag
    global delta
    global event_type
    global urb_type
    global bus
    global device
    global endpoint
    global outf

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
            if(store):
                delta_tmp[urb_tag]["sub_length"]=length
                delta_tmp[urb_tag]["sub_status"]=status
                delta_tmp[urb_tag]["sub_data"]=data
            else:
                print ("Sta=%s\t\tRC=%d\t%s\n" % (status, 
                                               int(length), 
                                               data.strip()),file=outf)
           
        else:
            if delta_tmp.has_key(urb_tag):
                print ("\nSta=%s\t\tRE=%d\t%s" % (delta_tmp[urb_tag]["sub_status"], 
                                               int(delta_tmp[urb_tag]["sub_length"]), 
                                               delta_tmp[urb_tag]["sub_data"].strip()),file=outf)
                del delta_tmp[urb_tag]
            print ("Sta=%s\t\tRC=%d\t%s" % (status, int(length), data),file=outf)
            print ("\t"*5 + to_ascii(data),file=outf)
        #print post_line
    except:
        print ("ERR!--Raw data in bulk_parse",array,file=outf)
        traceback.print_exc()

def int_parse(post_line,store=True):
    global urb_tag
    global delta
    global event_type
    global urb_type
    global bus
    global device
    global endpoint
    
    #print post_line

def iso_parse(post_line,store=True):
    global urb_tag
    global delta
    global event_type
    global urb_type
    global bus
    global device
    global endpoint
    global outf
    print ("",file=outf)
    #print post_line


def pre_parse(array):
    global urb_tag
    global delta
    global event_type
    global urb_type
    global bus
    global device
    global endpoint
    global outf
    global count    

    global delta_tmp

    #array = pre_line.split(' ')

    try:
    	arrayx = array[3].split(':')
    except:
	print("array index error",array)
	raise
    bus = int(arrayx[1])
    device = int(arrayx[2])
    endpoint = int(arrayx[3])
    urb_tag = array[0]
    urb_type = urbtype_d[arrayx[0]]
    event_type = array[2]
    if(event_type == 'S'):        
        delta = 0
        if(not delta_tmp.has_key(urb_tag)):
            delta_tmp[urb_tag]={"sub_time":array[1],"sub_length":0}
        delta_tmp[urb_tag]["sub_time"] = array[1]            
        return 0
    if(event_type == 'E'):
        print ('Error packet',file=outf)
        return 0
    if delta_tmp == None or not delta_tmp.has_key(urb_tag) or delta_tmp[urb_tag]["sub_time"]==None:
        return 0;
    deltax = long(array[1]) - long(delta_tmp[urb_tag]["sub_time"])
    '''if (deltax > 1000000) :
        delta = str(deltax/100000) + "s"
    elif (deltax > 1000) :
        delta = str(deltax/1000) + 'ms'
    else:'''
    delta = str(deltax) + 'us'
        
    delta_tmp[urb_tag]["sub_time"] = None
    #print array[1]
    print ("%d %s %d-%d-%d\t%s\t%s\t" % (count,urb_tag,bus, device, endpoint, \
                                         urb_type, delta),file=outf,)
    count = count + 1
    return 1

def pre_parse_freq(array):
    global urb_tag
    global delta
    global event_type
    global urb_type
    global bus
    global device
    global endpoint
    global outf
    global count    

    global delta_tmp
    global last_delta
    #array = pre_line.split(' ')

    try:
    	arrayx = array[3].split(':')
    except:
	print("array index error",array)
	raise
    bus = int(arrayx[1])
    device = int(arrayx[2])
    endpoint = int(arrayx[3])
    urb_tag = array[0]
    urb_type = urbtype_d[arrayx[0]]
    event_type = array[2]
    if(last_delta == None):
        last_delta = array[1]

    if(event_type == 'S'):        
        deltax = long(array[1]) - long(last_delta)
        '''if (deltax > 1000000) :
            delta = str(deltax/100000) + "s"
        elif (deltax > 1000) :
            delta = str(deltax/1000) + 'ms'
        else:'''
        delta = str(deltax) + 'us'
        
        last_delta = array[1]
    #print array[1]
        print ("%d %s %d-%d-%d\t%s\t%s\t" % (count,urb_tag,bus, device, endpoint, \
                                                 urb_type, delta),file=outf,)
        count = count + 1
        return 1
    return 0

def post_parse(post_line_fields,store=True):
    global urb_tag
    global delta
    global event_type
    global urb_type
    global bus
    global device
    global endpoint
    global outf
    global delta_tmp

    if (urb_type == urbtype_d['Ci'] or urb_type == urbtype_d['Co']):
        ctl_parse(post_line_fields,store)
    elif (urb_type == urbtype_d['Bi'] or urb_type == urbtype_d['Bo']):
        bulk_parse(post_line_fields,store)
    elif (urb_type == urbtype_d['Ii'] or urb_type == urbtype_d['Ii']):
        int_parse(post_line_fields,store)
    elif (urb_type == urbtype_d['Zi'] or urb_type == urbtype_d['Zo']):
        iso_parse(post_line_fields,store)
    else:
        print ("---ERR--- post_parse" ,urb_type, post_line_fields,file=outf)

def run(path):
    global urb_tag
    global delta
    global event_type
    global urb_type
    global bus
    global device
    global endpoint
    global count 
    global delta_tmp
    global outf
    args = path.strip().split(' ')
    (options,path)=parser.parse_args(args)
    if options.filename !=None:
	outf=open(options.filename,"w")
    else:
	outf = None
    try:
        fh = open(path[0], "r")
        count=1
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

def frequency(path):
    global urb_tag
    global delta
    global event_type
    global urb_type
    global bus
    global device
    global endpoint
    global count 
    global delta_tmp
    global last_delta
    global outf
    args = path.strip().split(' ')
    (options,path)=parser.parse_args(args)
    if options.filename !=None:
	outf=open(options.filename,"w")
    else:
	outf = None
    try:
        fh = open(path[0], "r")
        count=1
        while True:
            line = fh.readline()
            line.strip();
            line_fields=line.split(' ');
            
            pre_line_fields = line_fields[:4]
            #pre_line = pre_line.strip()
            ret=pre_parse_freq(pre_line_fields)
            if(event_type=='S'):
                #print "Post"
                post_line_fields = line_fields[4:]
                #post_line = post_line.strip()
                post_parse(post_line_fields,False)
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


