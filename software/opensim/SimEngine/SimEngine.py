#!/usr/bin/python

import threading
import logging
import random
import time
import os
import subprocess

import TimeLine
import Propagation
import IdManager
import LocationManager
import DaemonThread

class NullLogHandler(logging.Handler):
    def emit(self, record):
        pass

class SimEngineStats(object):
    def __init__(self):
        self.durationRunning = 0
        self.running = False
        self.txStart = None
    
    def indicateStart(self):
        self.txStart = time.time()
        self.running = True
    
    def indicateStop(self):
        if self.txStart:
            self.durationRunning += time.time()-self.txStart
            self.running = False
    
    def getDurationRunning(self):
        if self.running:
            return self.durationRunning+(time.time()-self.txStart)
        else:
            return self.durationRunning

class SimEngine(object):
    '''
    \brief The main simulation engine.
    '''
    
    def __init__(self,loghandler=NullLogHandler):
        
        # store params
        self.loghandler           = loghandler
        
        # local variables
        self.moteHandlers         = []
        self.timeline             = TimeLine.TimeLine(self)
        self.propagation          = Propagation.Propagation(self)
        self.idmanager            = IdManager.IdManager(self)
        self.locationmanager      = LocationManager.LocationManager(self) 
        self.pauseSem             = threading.Lock()
        self.isPaused             = False
        self.stopAfterSteps       = None
        self.delay                = 0
        self.stats                = SimEngineStats()
        
        # create daemon thread to handle connection of newly created motes
        self.daemonThreadHandler  = DaemonThread.DaemonThread(self)
        
        # logging this module
        self.log                  = logging.getLogger('SimEngine')
        self.log.setLevel(logging.DEBUG)
        self.log.addHandler(NullLogHandler())
        
        # logging core modules
        for loggerName in [
                   'SimEngine',
                   'Timeline',
                   'Propagation',
                   'IdManager',
                   'LocationManager',
                   'SimCli',
                   'DaemonThread',
                   ]:
            temp = logging.getLogger(loggerName)
            temp.setLevel(logging.DEBUG)
            temp.addHandler(loghandler)
    
    def start(self):
        
        # log
        self.log.info('starting')
        
        # start daemon thread (ready to accept connections)
        self.daemonThreadHandler.start()
        
        # start timeline
        self.timeline.start()
    
    #======================== public ==========================================
    
    #=== controlling execution speed
    
    def setDelay(self,delay):
        self.delay = delay
    
    def pause(self):
        if not self.isPaused:
            self.pauseSem.acquire()
            self.isPaused = True
            self.stats.indicateStop()
    
    def step(self,numSteps):
        self.stopAfterSteps = numSteps
        if self.isPaused:
            self.pauseSem.release()
            self.isPaused = False
    
    def resume(self):
        self.stopAfterSteps = None
        if self.isPaused:
            self.pauseSem.release()
            self.isPaused = False
            self.stats.indicateStart()
    
    def pauseOrDelay(self):
        if self.isPaused:
            self.log.debug('pause')
            self.pauseSem.acquire()
            self.pauseSem.release()
        else:
            time.sleep(self.delay)
            
        if self.stopAfterSteps!=None:
            if self.stopAfterSteps>0:
                self.stopAfterSteps -= 1
            if self.stopAfterSteps==0:
                self.pause()
        
        assert(self.stopAfterSteps==None or self.stopAfterSteps>=0)
    
    #=== called from the DaemonThread
    
    def indicateNewMote(self,moteHandler):
        
        # add this mote to my list of motes
        self.moteHandlers.append(moteHandler)
    
    #=== called from timeline
    
    def indicateFirstEventPassed(self):
        self.stats.indicateStart()
    
    #=== getting information about the system
    
    def getNumMotes(self):
        return len(self.moteHandlers)
    
    def getMoteHandler(self,rank):
        return self.moteHandlers[rank]
    
    def getStats(self):
        return self.stats
    
    #======================== private =========================================
    
    #======================== helpers =========================================
    