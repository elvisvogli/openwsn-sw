#!/usr/bin/python

import struct
import BspModule

class BspRadiotimer(BspModule.BspModule):
    '''
    \brief Emulates the 'radiotimer' BSP module
    '''
    
    INTR_COMPARE  = 'radiotimer.compare'
    INTR_OVERFLOW = 'radiotimer.overflow'
    PERIOD        = 32768
    
    def __init__(self,engine,motehandler):
        
        # store params
        self.engine          = engine
        self.motehandler     = motehandler
        
        # local variables
        self.timeline        = self.engine.timeline
        self.hwCrystal       = self.motehandler.hwCrystal
        self.running         = False   # whether the counter is currently running
        self.timeLastReset   = 0       # time at last counter reset
        self.period          = None    # counter period
        self.compareArmed    = False   # whether the compare is armed
        
        # initialize the parent
        BspModule.BspModule.__init__(self,'BspRadiotimer')
    
    #======================== public ==========================================
    
    #=== commands
    
    def cmd_init(self,params):
        '''emulates
           void radiotimer_init()'''
        
        # make sure length of params is expected
        assert(len(params)==0)
        
        # log the activity
        self.log.debug('cmd_init')
        
        # remember that module has been intialized
        self.isInitialized = True
        
        # respond
        self.motehandler.sendCommand(self.motehandler.commandIds['OPENSIM_CMD_radiotimer_init'])
    
    def cmd_start(self,params,internal=False):
        '''emulates
           void radiotimer_start(uint16_t period)'''
        
        # unpack the parameters
        (self.period,)            = struct.unpack('<H', params)
        
        # log the activity
        self.log.debug('cmd_start period='+str(self.period))
        
        # remember the time of last reset
        self.timeLastReset   = self.hwCrystal.getTimeLastTick()
        
        # calculate time at overflow event (in 'period' ticks)
        overflowTime         = self.hwCrystal.getTimeIn(self.period)
        
        # schedule overflow event
        self.timeline.scheduleEvent(overflowTime,
                                    self.motehandler.getId(),
                                    self.intr_overflow,
                                    self.INTR_OVERFLOW)

        # the counter is now running
        self.running         = True
        
        # respond
        if internal:
            return []
        else:
            self.motehandler.sendCommand(self.motehandler.commandIds['OPENSIM_CMD_radiotimer_start'])
    
    def cmd_getValue(self,params,internal=False):
        '''emulates
           uint16_t radiotimer_getValue()'''
        
        # make sure length of params is expected
        assert(len(params)==0)
        
        # log the activity
        self.log.debug('cmd_getValue')
        
        # get current counter value
        counterVal           = self.hwCrystal.getTicksSince(self.timeLastReset)
        
        # respond
        params = []
        for i in struct.pack('<H',counterVal):
            params.append(ord(i))
        # respond
        if internal:
            return params
        else:
            self.motehandler.sendCommand(self.motehandler.commandIds['OPENSIM_CMD_radiotimer_getValue'],
                                     params)
    
    def cmd_setPeriod(self,params,internal=False):
        '''emulates
           void radiotimer_setPeriod(uint16_t period)'''
        
        # unpack the parameters
        (self.period,)       = struct.unpack('<H', params)
        
        # log the activity
        self.log.debug('cmd_setPeriod period='+str(self.period))
        
        # how many ticks since last reset
        ticksSinceReset      = self.hwCrystal.getTicksSince(self.timeLastReset)
        
        # calculate time at overflow event (in 'period' ticks)
        if ticksSinceReset<self.period:
            ticksBeforeEvent = self.period-ticksSinceReset
        else:
            ticksBeforeEvent = self.PERIOD-ticksSinceReset+self.period
        
        # calculate time at overflow event (in 'period' ticks)
        overflowTime         = self.hwCrystal.getTimeIn(ticksBeforeEvent)
        
        # schedule overflow event
        self.timeline.scheduleEvent(overflowTime,
                                    self.motehandler.getId(),
                                    self.intr_overflow,
                                    self.INTR_OVERFLOW)
        
        # respond
        if internal:
            return []
        else:
            self.motehandler.sendCommand(self.motehandler.commandIds['OPENSIM_CMD_radiotimer_setPeriod'])
    
    def cmd_getPeriod(self,params,internal=False):
        '''emulates
           uint16_t radiotimer_getPeriod()'''
        
        # log the activity
        self.log.debug('cmd_getPeriod')
        
        # respond
        params = []
        for i in struct.pack('<H',self.period):
            params.append(ord(i))
        # respond
        if internal:
            return params
        else:
            self.motehandler.sendCommand(self.motehandler.commandIds['OPENSIM_CMD_radiotimer_getPeriod'],
                                     params)
    
    def cmd_schedule(self,params):
        '''emulates
           void radiotimer_schedule(uint16_t offset)'''
        
        # unpack the parameters
        (offset,)            = struct.unpack('<H', params)
        
        # log the activity
        self.log.debug('cmd_schedule offset='+str(offset))
        
        # get current counter value
        counterVal           = self.hwCrystal.getTicksSince(self.timeLastReset)
        
        # how many ticks until compare event
        if counterVal<offset:
            ticksBeforeEvent = offset-counterVal
        else:
            ticksBeforeEvent = self.period-counterVal+offset
        
        # calculate time at overflow event
        compareTime          = self.hwCrystal.getTimeIn(ticksBeforeEvent)
        
        # schedule compare event
        self.timeline.scheduleEvent(compareTime,
                                    self.motehandler.getId(),
                                    self.intr_compare,
                                    self.INTR_COMPARE)
                                    
        # the compare is now scheduled
        self.compareArmed    = True
        
        # respond
        self.motehandler.sendCommand(self.motehandler.commandIds['OPENSIM_CMD_radiotimer_schedule'])
    
    def cmd_cancel(self,params):
        '''emulates
           void radiotimer_cancel()'''
        
        # log the activity
        self.log.debug('cmd_cancel')
        
        # cancel the compare event
        numCanceled = self.timeline.cancelEvent(self.motehandler.getId(),
                                                self.INTR_COMPARE)
        assert(numCanceled<=1)
        
        # respond
        self.motehandler.sendCommand(self.motehandler.commandIds['OPENSIM_CMD_radiotimer_cancel'])
    
    def cmd_getCapturedTime(self,params):
        '''emulates
           uint16_t radiotimer_getCapturedTime()'''
        
        # log the activity
        self.log.debug('cmd_getCapturedTime')
        
        raise NotImplementedError()
    
    def getCounterVal(self):
        return self.hwCrystal.getTicksSince(self.timeLastReset)
    
    #======================== interrupts ======================================
    
    def intr_compare(self):
        '''
        \brief A compare event happened.
        '''
        
        # reschedule the next compare event
        # Note: as long as radiotimer_cancel() is not called, the intr_compare
        #       will fire every self.period
        nextCompareTime      = self.hwCrystal.getTimeIn(self.period)
        self.timeline.scheduleEvent(nextCompareTime,
                                    self.motehandler.getId(),
                                    self.intr_compare,
                                    self.INTR_COMPARE)
        
        # send interrupt to mote
        self.motehandler.sendCommand(self.motehandler.commandIds['OPENSIM_CMD_radiotimer_isr_compare'])
    
    def intr_overflow(self):
        '''
        \brief An overflow event happened.
        '''
        
        # remember the time of this reset; needed internally to schedule further events
        self.timeLastReset   = self.hwCrystal.getTimeLastTick()
        
        # reschedule the next overflow event
        # Note: the intr_overflow will fire every self.period
        nextOverflowTime     = self.hwCrystal.getTimeIn(self.period)
        self.timeline.scheduleEvent(nextOverflowTime,
                                    self.motehandler.getId(),
                                    self.intr_overflow,
                                    self.INTR_OVERFLOW)
    
        # send interrupt to mote
        self.motehandler.sendCommand(self.motehandler.commandIds['OPENSIM_CMD_radiotimer_isr_overflow'])
    
    #======================== private =========================================
    
    