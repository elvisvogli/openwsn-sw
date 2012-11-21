import logging
import openhdlc
class NullHandler(logging.Handler):
    def emit(self, record):
        pass
log = logging.getLogger('moteProbeSerialThread')
log.setLevel(logging.ERROR)
log.addHandler(NullHandler())

import threading
import serial
import time
import traceback

from pydispatch import dispatcher

class moteProbeSerialThread(threading.Thread):

    def __init__(self,serialportName,serialportBaudrate):
        
        # log
        log.debug("create instance")
        
        # store params
        self.serialportName       = serialportName
        self.serialportBaudrate   = serialportBaudrate
        
        # local variables
        self.serialInput          = ''
        self.serialOutput         = ''
        self.serialOutputLock     = threading.Lock()
        self.state                = 'WAIT_HEADER'
        self.numdelimiter         = 0
        
        # initialize the parent class
        threading.Thread.__init__(self)
        
        # give this thread a name
        self.name                 = 'moteProbeSerialThread@'+self.serialportName
        
        # connect to dispatcher
        dispatcher.connect(
            self.send,
            signal = 'bytesFromTcpPort'+self.serialportName,
        )
    
    def run(self):
        
        try:
            # log
            log.debug("start running")
        
            while True:     # open serial port
                log.debug("open serial port")
                self.serial = serial.Serial(self.serialportName,self.serialportBaudrate)
                while True: # read bytes from serial port
                    try:
                        char = self.serial.read(1)
                    except Exception as err:
                        log.warning(err)
                        time.sleep(1)
                        break
                    else:
                        if    self.state == 'WAIT_HEADER':
                            if char == '~':
                                self.numdelimiter     += 1
                            else:
                                self.numdelimiter      = 0
                            if self.numdelimiter==1:
                                self.state             = 'RECEIVING_COMMAND'
                                self.serialInput       = char
                                self.numdelimiter      = 0
                        elif self.state == 'RECEIVING_COMMAND':
                            self.serialInput = self.serialInput+char
                            if char == '~':
                                self.numdelimiter     += 1
                            else:
                                self.numdelimiter      = 0
                            if self.numdelimiter==1:
                                self.state             = 'WAIT_HEADER'
                                self.numdelimiter      = 0
                                log.debug(' '.join([hex(ord(c))[2:] for c in self.serialInput[:]]))
                                self.serialInput       = openhdlc.dehdlcify(self.serialInput)
                                log.debug(' '.join([hex(ord(c))[2:] for c in self.serialInput[:]]))

                                #byte 0 is the type of status message
                                if self.serialInput[0]=="R":     #request for data
                                    if (ord(self.serialInput[1])==251):  # byte 1 indicates free space in mote's input buffer
                                        with self.serialOutputLock:
                                            if(len(self.serialOutput)>0):
                                                self.serial.write(openhdlc.hdlcify(self.serialOutput))
                                                self.serialOutput = ''
                                else:
                                    # dispatch
                                    dispatcher.send(
                                        signal        = 'bytesFromSerialPort'+self.serialportName,
                                        data          = self.serialInput[:],
                                    )
                        else:
                            raise SystemError("invalid state {0}".format(state))
        
        except Exception as err:
            output  = []
            output += ["Crash in thread {0}.".format(self.name)]
            output += ["error={0}".format(err)]
            output += ["traceback={0}".format(traceback.format_exc())]
            output  = '\n'.join(output)
            log.critical(output)
            print output
            raise
    
    #======================== public ==========================================
    
    def send(self,data):
        self.serialOutputLock.acquire()
        if len(self.serialOutput)>255:
            log.error("serialOutput overflow ({0} bytes)".format(len(self.serialOutput)))
        
        self.serialOutput += data[0]+ chr(len(self.serialOutput)) + data[1:]
        print self.serialOutput
        if len(self.serialOutput)>251:
            log.warning("serialOutput overflowing ({0} bytes)".format(len(self.serialOutput)))
        self.serialOutputLock.release()
    
    #======================== private =========================================