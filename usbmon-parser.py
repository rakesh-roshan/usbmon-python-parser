#!/usr/bin/python

import cmd
import os
import sys
import parser

class CLI(cmd.Cmd):

    def __init__(self):
        cmd.Cmd.__init__(self)
        self.prompt = '>>> '

    def do_hello(self, arg):
        print "hello again", arg, "!"

    def help_hello(self):
        print "syntax: hello [message]",
        print "-- prints a hello message"
        
    def do_ls(self, arg):
        print "ID\tDevice"
        output = os.popen('lsusb').read()
        array = output.splitlines()
        for i in array[:]:
            ID = int(i.split(' ')[1])
            print "%du\t%s" % (ID, i)
        #print output        
    def do_cat(self, arg):
        path = "/sys/kernel/debug/usb/usbmon/" + arg
        #print path
        parser.run(path)
        
    def do_quit(self, arg):
        sys.exit(1)

    def help_quit(self):
        print "syntax: quit",
        print "-- terminates the application"

    # shortcuts
    do_q = do_quit

#
# try it out

cli = CLI()
cli.cmdloop()
