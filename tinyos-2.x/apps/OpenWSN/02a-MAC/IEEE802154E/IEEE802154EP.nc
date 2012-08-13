#include "OpenWSN.h"
#include "CC2420.h"
#include "IEEE802154E.h"

//slot states
enum {
   //synchronizing
   S_SYNCHRONIZING       =  0,
   //transmitter
   S_TX_TXDATAPREPARE    =  1,
   S_TX_TXDATAREADY      =  2,
   S_TX_TXDATA           =  3,
   S_TX_RXACKPREPARE     =  4,
   S_TX_RXACKREADY       =  5,
   S_TX_RXACK            =  6,
   //receiver
   S_RX_RXDATAPREPARE    =  7,
   S_RX_RXDATAREADY      =  8,
   S_RX_RXDATA           =  9,
   S_RX_TXACKPREPARE     = 10,
   S_RX_TXACKREADY       = 11,
   S_RX_TXACK            = 12,
   //cooldown
   S_SLEEP               = 13,
};

enum {
   FRAME_BASED_RESYNC = TRUE,
   ACK_BASED_RESYNC = FALSE,
};

enum {
   WAS_ACKED = TRUE,
   WAS_NOT_ACKED = FALSE,
};

module IEEE802154EP {
   //admin
   uses interface Boot;
   provides interface Init as SoftwareInit;            //private
   //time
   uses interface Alarm<T32khz,uint32_t> as FastAlarm; //private
   uses interface Alarm<T32khz,uint32_t> as SlotAlarm; //private
   uses interface Timer<TMilli> as LosingSyncTimer;    //private
   uses interface Timer<TMilli> as LostSyncTimer;      //private
   provides interface GlobalTime;
   provides interface GlobalSync;
   //down the stack
   provides interface OpenSend as OpenSendFromUpper;
   uses interface OpenQueue;
   uses interface RadioControl;
   uses interface RadioSend;
   uses interface RadioReceive;
   //up the stack
   uses interface OpenReceive as OpenReceiveToUpper;
   //debug
   provides interface DebugPrint;
   uses interface OpenSerial;
   uses interface CellStats;
   uses interface Leds;                           //private, Led2=blue=synchronized, Led1=green=radio on
   uses interface HplMsp430GeneralIO as Port26;   //private, new slot
   uses interface HplMsp430GeneralIO as Port35;   //private, radio on
   uses interface HplMsp430GeneralIO as Port67;   //private, new slotframe
   uses interface HplMsp430GeneralIO as Port34;   //private, general debug
   //misc
   uses interface PacketFunctions;
   uses interface NeighborStats;
   uses interface Malloc;
   uses interface CellUsageGet;
   uses interface IDManager;
   uses interface NeighborGet;
   uses interface Random;                              //private
}

implementation {

   /*------------------------------ variables -------------------------------------------*/

   timervalue_t       fastAlarmStartSlotTimestamp;
   timervalue_t       slotAlarmStartSlotTimestamp;
   uint8_t            state;
   asn_t              asn;
   OpenQueueEntry_t*  dataFrameToSend; //NULL at beginning and end
   OpenQueueEntry_t*  packetACK;       //NULL at beginning and end, free at end of slot
   OpenQueueEntry_t*  frameReceived;   //NULL at beginning and end
   bool               isSync;
   uint8_t            dsn;
   uint8_t            frequencyChannel;
   OpenQueueEntry_t*  sendDoneMessage;
   error_t            sendDoneError;

   /*------------------------------ prototypes ------------------------------------------*/

#include "IEEE802154_common.c"
   void change_state(uint8_t newstate);
   void resynchronize(bool resyncType, open_addr_t* node_id, timervalue_t dataGlobalSlotOffset, int16_t timeCorrection);
   void endSlot();
   task void taskDebugPrint();
   task void taskResetLosingLostTimers();

   //the two following tasks are used to break the asynchronicity: everything in MAC and below is async, all the above not
   task void taskReceive();
   void postTaskSendDone(OpenQueueEntry_t* param_sendDoneMessage, error_t param_sendDoneError);
   task void taskSendDone();

   /*------------------------------ start/stop sequence ---------------------------------*/

   event void Boot.booted() {
      atomic isSync=FALSE;
      call Leds.led2Off();
      call RadioControl.start();
   }
   async event void RadioControl.startDone(error_t error) {
      call SlotAlarm.startAt((call SlotAlarm.getNow()),SLOT_TIME);
   }
   async event void RadioControl.stopDone(error_t error) {
      return;//radio turned off not implemented
   }

   /*------------------------------ recording a new packet to send ----------------------*/

   //OpenSendFromUpper
   command error_t OpenSendFromUpper.send(OpenQueueEntry_t* msg) {
      msg->owner           = COMPONENT_MAC;
      if (call PacketFunctions.isBroadcastMulticast(&(msg->l2_nextORpreviousHop))==TRUE) {
         msg->l2_retriesLeft  = 1;
      } else {
         msg->l2_retriesLeft  = TXRETRIES;
      }
      msg->l1_txPower      = TX_POWER;
      prependIEEE802154header(msg,
            msg->l2_frameType,
            IEEE154_SEC_NO_SECURITY,
            dsn++,
            &(msg->l2_nextORpreviousHop)
            );
      return SUCCESS;
   }

   /*------------------------------ new slot (TX or RX) ---------------------------------*/

   async event void SlotAlarm.fired() {

      asn_t                   temp_asn;
      uint8_t                 temp_state;
      bool                    temp_isSync;
      OpenQueueEntry_t*       temp_dataFrameToSend;
      error_t                 temp_error;
      //open_addr_t             temp_addr_16b;
      //open_addr_t             temp_addr_64b;
      ieee802154_header_iht   transmitted_ieee154_header;
      uint8_t                 temp_channelOffset;

      fastAlarmStartSlotTimestamp     = call FastAlarm.getNow();
      slotAlarmStartSlotTimestamp     = call SlotAlarm.getNow();
      atomic asn++;

      call OpenSerial.stop();
      call SlotAlarm.startAt((call SlotAlarm.getAlarm()),SLOT_TIME);

      //reset WDT
      atomic WDTCTL = WDTPW + WDTCNTCL + WDTSSEL;

      atomic dataFrameToSend   = NULL;

      atomic{
         temp_asn             = asn;
         temp_state           = state;
         temp_isSync          = isSync;
         temp_dataFrameToSend = dataFrameToSend;
      }

      call Port26.toggle();
      if (temp_asn%LENGTHCELLFRAME==0) {
         call Port67.toggle();
         /*{
           temp_addr_64b.type = ADDR_64B;
           temp_addr_64b.addr_64b[0] = 0x00;
           temp_addr_64b.addr_64b[1] = 0x00;
           temp_addr_64b.addr_64b[2] = 0x00;
           temp_addr_64b.addr_64b[3] = 0x00;
           temp_addr_64b.addr_64b[4] = 0x00;
           temp_addr_64b.addr_64b[5] = 0x00;
           temp_addr_64b.addr_64b[6] = 0x00;
           temp_addr_64b.addr_64b[7] = 0x12;
           call PacketFunctions.mac64bToMac16b(&temp_addr_64b,&temp_addr_16b);
           call IDManager.setMyID(&temp_addr_64b);
           call IDManager.setMyID(&temp_addr_16b);
           } else {
           temp_addr_64b.type        = ADDR_64B;
           temp_addr_64b.addr_64b[0] = 0x00;
           temp_addr_64b.addr_64b[1] = 0x00;
           temp_addr_64b.addr_64b[2] = 0x00;
           temp_addr_64b.addr_64b[3] = 0x00;
           temp_addr_64b.addr_64b[4] = 0x00;
           temp_addr_64b.addr_64b[5] = 0x00;
           temp_addr_64b.addr_64b[6] = 0x00;
           temp_addr_64b.addr_64b[7] = TOS_NODE_ID;
           call PacketFunctions.mac64bToMac16b(&temp_addr_64b,&temp_addr_16b);
           call IDManager.setMyID(&temp_addr_64b);
           call IDManager.setMyID(&temp_addr_16b);
           }*/
      }

      //----- switch to/from S_SYNCHRONIZING
      if ((call IDManager.getIsDAGroot())==TRUE) {
         //if I'm DAGroot, I'm synchronized
         post taskResetLosingLostTimers();
         atomic isSync=TRUE;
         call Leds.led2On();
         atomic {
            if (state==S_SYNCHRONIZING) {//happens right after node becomes LBR
               endSlot();
               return;
            }
         }
      } else if (temp_isSync==FALSE) {
         //If I'm not in sync, enter/stay in S_SYNCHRONIZING
         atomic if (temp_asn%2==1) {
            call OpenSerial.startOutput();
         } else {
            call OpenSerial.startInput();
         }
         if (temp_state!=S_SYNCHRONIZING) {
            change_state(S_SYNCHRONIZING);
            if ((call RadioControl.prepareReceive(11))!=SUCCESS) {
               call OpenSerial.printError(COMPONENT_MAC,ERR_PREPARERECEIVE_FAILED,
                     (errorparameter_t)temp_asn%LENGTHCELLFRAME,(errorparameter_t)0);
               //I will just retry in the next slot
               endSlot();
            };
         }
         return;
      }

      //----- state error
      if (temp_state!=S_SLEEP) {
         call OpenSerial.printError(COMPONENT_MAC,ERR_WRONG_STATE_IN_STARTSLOTTASK,
               (errorparameter_t)temp_state,(errorparameter_t)temp_asn%LENGTHCELLFRAME);
         endSlot();
         return;
      }

      switch (call CellUsageGet.getType(temp_asn%LENGTHCELLFRAME)) {
         case CELLTYPE_TXRX:
            //get a packet out of the buffer (if any)
            if ( call CellUsageGet.isTX(temp_asn%LENGTHCELLFRAME) || call CellUsageGet.isSH_TX(temp_asn%LENGTHCELLFRAME)) {
               atomic {
                  dataFrameToSend = call OpenQueue.inQueue(call CellUsageGet.isADV(temp_asn%LENGTHCELLFRAME));
                  temp_dataFrameToSend = dataFrameToSend;                 
               }
            }
            //put packet back in buffer if not in the right slot (for video transmission only)
            /*if (temp_dataFrameToSend!=NULL) {
               if (  (temp_dataFrameToSend->l2_transmitInFirstSlot==TRUE  && temp_asn%LENGTHCELLFRAME==2) ||
                     (temp_dataFrameToSend->l2_transmitInFirstSlot==FALSE && temp_asn%LENGTHCELLFRAME==1)) {
                  atomic {
                     dataFrameToSend = NULL;
                     temp_dataFrameToSend = dataFrameToSend;                 
                  }
               }
            }*/
            //the following channelOffset assignment is used for video transmission only
            /*if (call CellUsageGet.isADV(temp_asn%LENGTHCELLFRAME)) {          //ADV, channelOffset is 0
               temp_channelOffset = 0;
            } else if (temp_dataFrameToSend!=NULL) {                          //TX, channelOffset is destination's addr_16b
               temp_channelOffset = temp_dataFrameToSend->l2_nextORpreviousHop.addr_16b[1];
            } else {                                                          //RX, channelOffset is my addr_16b
               temp_channelOffset = (call IDManager.getMyID(ADDR_16B))->addr_16b[1];
            }*/
            temp_channelOffset = call CellUsageGet.getChannelOffset(temp_asn%LENGTHCELLFRAME);
            if (HOPPING_ENABLED) {
               atomic frequencyChannel = ((temp_asn+temp_channelOffset)%16)+11;
            } else {
               atomic frequencyChannel =((temp_channelOffset)%16)+11;
            }

            if (temp_dataFrameToSend!=NULL) {                                  //start the TX sequence
               dataFrameToSend->owner = COMPONENT_MAC;
               atomic dataFrameToSend->l1_channel = frequencyChannel;
               transmitted_ieee154_header = retrieveIEEE802154header(temp_dataFrameToSend);
               if (call CellUsageGet.isADV(temp_asn%LENGTHCELLFRAME)) {
                  //I will be sending an ADV frame
                  ((IEEE802154E_ADV_t*)((dataFrameToSend->payload)+transmitted_ieee154_header.headerLength))->timingInformation=(call GlobalTime.getASN());
               }
               change_state(S_TX_TXDATAPREPARE);
               atomic temp_error = call RadioSend.prepareSend(dataFrameToSend);
               if (temp_error!=SUCCESS) {
                  //retry sending the packet later
                  temp_dataFrameToSend->l2_retriesLeft--;
                  if (temp_dataFrameToSend->l2_retriesLeft==0) {
                     postTaskSendDone(temp_dataFrameToSend,FAIL);
                  }
                  call OpenSerial.printError(COMPONENT_MAC,ERR_PREPARESEND_FAILED,
                        (errorparameter_t)temp_asn%LENGTHCELLFRAME,(errorparameter_t)0);
                  endSlot();
               };
               atomic call FastAlarm.startAt(fastAlarmStartSlotTimestamp,TsTxOffset);
            } else {
               if (call CellUsageGet.isRX(temp_asn%LENGTHCELLFRAME)) {        //start the RX sequence
                  change_state(S_RX_RXDATAPREPARE);
                  atomic temp_error = call RadioControl.prepareReceive(frequencyChannel);
                  if (temp_error!=SUCCESS) {
                     //abort
                     call OpenSerial.printError(COMPONENT_MAC,ERR_PREPARERECEIVE_FAILED,
                           (errorparameter_t)temp_asn%LENGTHCELLFRAME,(errorparameter_t)0);
                     endSlot();
                  };
                  atomic call FastAlarm.startAt(fastAlarmStartSlotTimestamp,TsRxOffset);
               } else {                                                        //nothing to do, abort
                  call OpenSerial.startOutput();
                  endSlot();
                  return;
               }
            }
            return;
            break;

         case CELLTYPE_RXSERIAL:
            call OpenSerial.startInput();
            endSlot();
            return;

         case CELLTYPE_OFF:
            call OpenSerial.startOutput();
            endSlot();
            return;

         default:
            call OpenSerial.printError(COMPONENT_MAC,ERR_WRONG_CELLTYPE,
                  (errorparameter_t)call CellUsageGet.getType(temp_asn%LENGTHCELLFRAME),0);
            endSlot();
            return;
      }
   }

   //prepareSendDone
   async event void RadioSend.prepareSendDone(error_t error){
      asn_t   temp_asn;
      uint8_t temp_state;
      atomic {
         temp_asn   = asn;
         temp_state = state;
      }
      switch (temp_state) {
         case S_TX_TXDATAPREPARE:
            if (error==SUCCESS) {
               change_state(S_TX_TXDATAREADY);
            } else {
               atomic {
                  dataFrameToSend->l2_retriesLeft--;
                  if (dataFrameToSend->l2_retriesLeft==0) {
                     postTaskSendDone(dataFrameToSend,FAIL);
                  }
               }
               call OpenSerial.printError(COMPONENT_MAC,ERR_PREPARESENDDONE_FAILED,
                     (errorparameter_t)error,(errorparameter_t)temp_asn%LENGTHCELLFRAME);
               endSlot();
            }
            break;
         case S_RX_TXACKPREPARE:
            if (error==SUCCESS) {
               change_state(S_RX_TXACKREADY);
            } else {
               //abort
               call OpenSerial.printError(COMPONENT_MAC,ERR_PREPARESENDDONE_FAILED,
                     (errorparameter_t)error,(errorparameter_t)temp_asn%LENGTHCELLFRAME);
               endSlot();
            }
            break;
         default:
            call OpenSerial.printError(COMPONENT_MAC,ERR_WRONG_STATE_IN_PREPARESENDDONE,
                  (errorparameter_t)temp_state,(errorparameter_t)temp_asn%LENGTHCELLFRAME);
            endSlot();
            return;
            break;
      }
   }

   //prepareReceiveDone
   async event void RadioControl.prepareReceiveDone(error_t error) {
      asn_t   temp_asn;
      uint8_t temp_state;
      atomic {
         temp_asn = asn;
         temp_state = state;
      }
      if (error!=SUCCESS) {
         //abort
         call OpenSerial.printError(COMPONENT_MAC,ERR_PREPARERECEIVEDONE_FAILED,
               (errorparameter_t)error,(errorparameter_t)temp_asn%LENGTHCELLFRAME);
         endSlot();
      }
      switch (temp_state) {
         case S_TX_RXACKPREPARE:
            change_state(S_TX_RXACKREADY);
            break;
         case S_RX_RXDATAPREPARE:
            change_state(S_RX_RXDATAREADY);
            break;
         case S_SYNCHRONIZING:
            if ( (call RadioControl.receiveNow(TIME_LIMITED_RX,TsRxWaitTime))!=SUCCESS ) {
               //abort
               call OpenSerial.printError(COMPONENT_MAC,ERR_RECEIVENOW_FAILED,
                     (errorparameter_t)temp_state,(errorparameter_t)temp_asn%LENGTHCELLFRAME);
               endSlot();
            }
            break;
         default:
            call OpenSerial.printError(COMPONENT_MAC,ERR_WRONG_STATE_IN_PREPARERECEIVEDONE,
                  (errorparameter_t)temp_state,(errorparameter_t)temp_asn%LENGTHCELLFRAME);
            endSlot();
            return;
            break;
      }
   }

   //FastAlarm.fired
   async event void FastAlarm.fired() {
      asn_t             temp_asn;
      uint8_t           temp_state;
      OpenQueueEntry_t* temp_dataFrameToSend;
      atomic{
         temp_asn             = asn;
         temp_state           = state;
         temp_dataFrameToSend = dataFrameToSend;
      }
      switch (temp_state) {
         /*------------------- TX sequence ------------------------*/
         case S_TX_TXDATAPREPARE:                                    //[timer fired] transmitter (ERROR state)
            //I'm a transmitter, didn't have time to prepare for TX
            postTaskSendDone(temp_dataFrameToSend,FAIL);
            call OpenSerial.printError(COMPONENT_MAC,ERR_NO_TIME_TO_PREPARE_TX,
                  (errorparameter_t)temp_asn%LENGTHCELLFRAME,0);
            endSlot();
            break;
         case S_TX_TXDATAREADY:                                      //[timer fired] transmitter
            //I'm a transmitter, Tx data now
            change_state(S_TX_TXDATA);
            if ((call RadioSend.sendNow())!=SUCCESS) {
               //retry later
               temp_dataFrameToSend->l2_retriesLeft--;
               if (temp_dataFrameToSend->l2_retriesLeft==0) {
                  postTaskSendDone(temp_dataFrameToSend,FAIL);
               }
               call OpenSerial.printError(COMPONENT_MAC,ERR_SENDNOW_FAILED,
                     (errorparameter_t)temp_state,(errorparameter_t)temp_asn%LENGTHCELLFRAME);
               endSlot();
            }
            break;
         case S_TX_RXACKREADY:                                       //[timer fired] transmitter
            //I'm a transmitter, switch on RX for ACK now
            //this is done automatically after Tx is finished, rx is already on.
            //I'm calling receiveNow anyways because it reports receivedNothing
            change_state(S_TX_RXACK);
            if ( (call RadioControl.receiveNow(TIME_LIMITED_RX,TsRxWaitTime))!=SUCCESS ) {
               //abort
               call OpenSerial.printError(COMPONENT_MAC,ERR_RECEIVENOW_FAILED,
                     (errorparameter_t)temp_state,(errorparameter_t)0);
               endSlot();
            };
            break;

            /*------------------- RX sequence -----------------------*/
         case S_RX_RXDATAPREPARE:                                    //[timer fired] receiver (ERROR state)
            //I'm a receiver, didn't have time to prepare for RX
            call OpenSerial.printError(COMPONENT_MAC,ERR_NO_TIME_TO_PREPARE_RX,
                  (errorparameter_t)temp_asn%LENGTHCELLFRAME,0);
            endSlot();
            break;
         case S_RX_RXDATAREADY:                                      //[timer fired] receiver
            //I'm a receiver, switch RX radio on for data now
            change_state(S_RX_RXDATA);
            if ( (call RadioControl.receiveNow(TIME_LIMITED_RX,TsRxWaitTime))!=SUCCESS ) {
               //abort
               call OpenSerial.printError(COMPONENT_MAC,ERR_RECEIVENOW_FAILED,
                     (errorparameter_t)temp_state,(errorparameter_t)0);
               endSlot();
            };
            break;
         case S_RX_TXACKPREPARE:                                     //[timer fired] receiver (ERROR state)
            //I'm a receiver, didn't have time to prepare ACK
            call OpenSerial.printError(COMPONENT_MAC,ERR_NO_TIME_TO_PREPARE_ACK,
                  (errorparameter_t)temp_asn%LENGTHCELLFRAME,0);
            endSlot();
            break;
         case S_RX_TXACKREADY:                                       //[timer fired] receiver
            //I'm a receiver, TX ACK now
            change_state(S_RX_TXACK);
            if ((call RadioSend.sendNow())!=SUCCESS) {
               //abort
               call OpenSerial.printError(COMPONENT_MAC,ERR_SENDNOW_FAILED,
                     (errorparameter_t)temp_state,(errorparameter_t)temp_asn%LENGTHCELLFRAME);
               endSlot();
            }
            break;

         default:
            call OpenSerial.printError(COMPONENT_MAC,ERR_WRONG_STATE_IN_FASTTIMER_FIRED,
                  (errorparameter_t)temp_state,(errorparameter_t)temp_asn%LENGTHCELLFRAME);
            endSlot();
            break;
      }
   }

   //receivedNothing
   async event void RadioControl.receivedNothing() {
      asn_t                   temp_asn;
      uint8_t                 temp_state;
      OpenQueueEntry_t*       temp_dataFrameToSend;
      atomic{
         temp_asn             = asn;
         temp_state           = state;
         temp_dataFrameToSend = dataFrameToSend;
      }
      switch(temp_state) {
         case S_RX_RXDATA:                                           //[receivedNothing] receiver (WARNING state)
            //I'm a receiver, didn't receive data
            endSlot();
            break;
         case S_TX_RXACK:                                            //[receivedNothing] transmitter (WARNING state)
            //I'm a transmitter, didn't receive ACK (end of TX sequence)
            call CellStats.indicateUse(temp_asn%LENGTHCELLFRAME,WAS_NOT_ACKED);
            call NeighborStats.indicateTx(&(temp_dataFrameToSend->l2_nextORpreviousHop),WAS_NOT_ACKED);
            temp_dataFrameToSend->l2_retriesLeft--;
            if (temp_dataFrameToSend->l2_retriesLeft==0) {
               postTaskSendDone(temp_dataFrameToSend,FAIL);
            }
            endSlot();
            break;
         case S_SYNCHRONIZING:                                       //[receivedNothing] synchronizer
            //it's OK not to receive anything after TsRxWaitTime when trying to synchronize
            break;
         default:
            call OpenSerial.printError(COMPONENT_MAC,ERR_WRONG_STATE_IN_RECEIVEDNOTHING,
                  (errorparameter_t)temp_state,(errorparameter_t)temp_asn%LENGTHCELLFRAME);
            endSlot();
            break;
      }
   }

   //sendNowDone
   async event void RadioSend.sendNowDone(error_t error) {
      asn_t                   temp_asn;
      uint8_t                 temp_state;
      OpenQueueEntry_t*       temp_dataFrameToSend;
      atomic {
         temp_asn             = asn;
         temp_state           = state;
         temp_dataFrameToSend = dataFrameToSend;
      }
      switch (temp_state) {
         case S_TX_TXDATA:                                           //[sendNowDone] transmitter
            //I'm a transmitter, finished sending data
            if (error!=SUCCESS) {
               //retry later
               temp_dataFrameToSend->l2_retriesLeft--;
               if (temp_dataFrameToSend->l2_retriesLeft==0) {
                  postTaskSendDone(temp_dataFrameToSend,FAIL);
               }
               call OpenSerial.printError(COMPONENT_MAC,ERR_SENDNOWDONE_FAILED,
                     (errorparameter_t)temp_state,
                     (errorparameter_t)temp_asn%LENGTHCELLFRAME);
               endSlot();
               return;
            }
            if (call CellUsageGet.isADV(temp_asn%LENGTHCELLFRAME)==TRUE) {
               //ADV slot, don't have to listen for ACK
               call NeighborStats.indicateTx(&(temp_dataFrameToSend->l2_nextORpreviousHop),WAS_NOT_ACKED);
               call CellStats.indicateUse(temp_asn%LENGTHCELLFRAME,WAS_NOT_ACKED);
               postTaskSendDone(temp_dataFrameToSend,SUCCESS);
               endSlot();
            } else {
               call FastAlarm.start(TsRxAckDelay);
               change_state(S_TX_RXACKREADY);
            }
            break;
         case S_RX_TXACK:                                            //[sendNowDone] receiver
            //I'm a receiver, finished sending ACK (end of RX sequence)
            if (error!=SUCCESS) {
               //don't do anything if error==FAIL
               call OpenSerial.printError(COMPONENT_MAC,ERR_SENDNOWDONE_FAILED,
                     (errorparameter_t)temp_state,
                     (errorparameter_t)temp_asn%LENGTHCELLFRAME);
            }
            /* //sync off of DATA I received before I sent ACK
             * poipoi for simplicity, only resync from ADV
             resynchronize(FRAME_BASED_RESYNC,
             &(frameReceived->l2_nextORpreviousHop),
             frameReceived->l1_rxTimestamp,
             (int16_t)((int32_t)(frameReceived->l1_rxTimestamp)-(int32_t)radio_delay)-(int32_t)TsTxOffset);*/
            post taskReceive();
            endSlot();
            break;
         default:
            call OpenSerial.printError(COMPONENT_MAC,ERR_WRONG_STATE_IN_SUBSEND_SENDDONE,
                  (errorparameter_t)temp_state,(errorparameter_t)temp_asn%LENGTHCELLFRAME);
            endSlot();
            break;
      }
   }

   void postTaskSendDone(OpenQueueEntry_t* param_sendDoneMessage, error_t param_sendDoneError) {
      atomic {
         if (sendDoneMessage!=NULL) {
            call OpenSerial.printError(COMPONENT_MAC,ERR_BUSY_SENDDONE,
                  (errorparameter_t)state,(errorparameter_t)asn%LENGTHCELLFRAME);
         }
         sendDoneMessage = param_sendDoneMessage;
         sendDoneError   = param_sendDoneError;
      }
      post taskSendDone();
   }

   task void taskSendDone() {
      OpenQueueEntry_t*  temp_sendDoneMessage;
      error_t            temp_sendDoneError;
      atomic {
         temp_sendDoneMessage = sendDoneMessage;
         temp_sendDoneError   = sendDoneError;
      }
      signal OpenSendFromUpper.sendDone(temp_sendDoneMessage,temp_sendDoneError);
      atomic sendDoneMessage = NULL;
   }

   void endSlot() {
      asn_t   temp_asn;
      uint8_t temp_state;
      atomic {
         temp_asn   = asn;
         temp_state = state;
         if (packetACK!=NULL) {
            call Malloc.freePacketBuffer(packetACK);
            packetACK=NULL;
         }
      }
      if (call RadioControl.rfOff()!=SUCCESS) {
         //abort
         call OpenSerial.printError(COMPONENT_MAC,ERR_RFOFF_FAILED,
               (errorparameter_t)temp_state,(errorparameter_t)temp_asn%LENGTHCELLFRAME);
      }
      change_state(S_SLEEP);
   }

   /*------------------------------ reception -----------------------------------------*/

   //RadioReceive
   async event void RadioReceive.receive(OpenQueueEntry_t* msg) {
      asn_t                   temp_asn;
      uint8_t                 temp_state;
      bool                    temp_isSync;
      OpenQueueEntry_t*       temp_dataFrameToSend;
      OpenQueueEntry_t*       temp_packetACK;
      error_t                 temp_error;
      ieee802154_header_iht   received_ieee154_header;
      ieee802154_header_iht   transmitted_ieee154_header;

      atomic{
         temp_asn             = asn;
         temp_isSync          = isSync;
         temp_state           = state;
         temp_dataFrameToSend = dataFrameToSend;
      }

      msg->owner = COMPONENT_MAC;

      received_ieee154_header = retrieveIEEE802154header(msg);
      call PacketFunctions.tossHeader(msg,received_ieee154_header.headerLength);
      call PacketFunctions.tossFooter(msg,2);

      msg->l2_frameType = received_ieee154_header.frameType;
      memcpy(&(msg->l2_nextORpreviousHop),&(received_ieee154_header.src),sizeof(open_addr_t));
      /*call OpenSerial.printError(COMPONENT_MAC,ERR_POIPOI,
        (errorparameter_t)received_ieee154_header.headerLength,
        (errorparameter_t)0);
        call OpenSerial.printError(COMPONENT_MAC,ERR_POIPOI,
        (errorparameter_t)received_ieee154_header.frameType,
        (errorparameter_t)1);
        call OpenSerial.printError(COMPONENT_MAC,ERR_POIPOI,
        (errorparameter_t)received_ieee154_header.securityEnabled,
        (errorparameter_t)2);
        call OpenSerial.printError(COMPONENT_MAC,ERR_POIPOI,
        (errorparameter_t)received_ieee154_header.framePending,
        (errorparameter_t)3);
        call OpenSerial.printError(COMPONENT_MAC,ERR_POIPOI,
        (errorparameter_t)received_ieee154_header.ackRequested,
        (errorparameter_t)4);
        call OpenSerial.printError(COMPONENT_MAC,ERR_POIPOI,
        (errorparameter_t)received_ieee154_header.panIDCompression,
        (errorparameter_t)5);
        call OpenSerial.printError(COMPONENT_MAC,ERR_POIPOI,
        (errorparameter_t)received_ieee154_header.sequenceNumber,
        (errorparameter_t)6);
        call OpenSerial.printError(COMPONENT_MAC,ERR_POIPOI,
        (errorparameter_t)received_ieee154_header.panid.panid,
        (errorparameter_t)7);
        call OpenSerial.printError(COMPONENT_MAC,ERR_POIPOI,
        (errorparameter_t)received_ieee154_header.dest.addr_64b,
        (errorparameter_t)8);
        call OpenSerial.printError(COMPONENT_MAC,ERR_POIPOI,
        (errorparameter_t)received_ieee154_header.src.addr_64b,
        (errorparameter_t)9);*/

      if (received_ieee154_header.frameType==IEEE154_TYPE_DATA &&
            !(call IDManager.isMyAddress(&received_ieee154_header.panid))) {
         call OpenSerial.printError(COMPONENT_MAC,ERR_WRONG_PANID,
               (errorparameter_t)received_ieee154_header.panid.panid[0]*256+received_ieee154_header.panid.panid[1],
               (errorparameter_t)0);
         call Malloc.freePacketBuffer(msg);
         return;
      }

      switch (temp_state) {

         /*------------------- TX sequence ------------------------*/
         case S_TX_RXACK:                                            //[receive] transmitter
            //I'm a transmitter, just received ACK (end of TX sequence)
            transmitted_ieee154_header = retrieveIEEE802154header(temp_dataFrameToSend);
            if (received_ieee154_header.dsn == transmitted_ieee154_header.dsn) {
               //I'm a transmitter, sync off of ACK message
               /* poipoi for simplicity, only resync from ADV
                  resynchronize(ACK_BASED_RESYNC,
                  &received_ieee154_header.src,
                  TsTxOffset,
                  (((IEEE802154E_ACK_ht*)(msg->payload))->timeCorrection));//poipoi /32  poipoipoipoi*/
               call CellStats.indicateUse(temp_asn%LENGTHCELLFRAME,WAS_ACKED);
               call NeighborStats.indicateTx(&(temp_dataFrameToSend->l2_nextORpreviousHop),WAS_ACKED);
               postTaskSendDone(temp_dataFrameToSend,SUCCESS);
            } else {
               call CellStats.indicateUse(temp_asn%LENGTHCELLFRAME,WAS_NOT_ACKED);
               call NeighborStats.indicateTx(&(temp_dataFrameToSend->l2_nextORpreviousHop),WAS_NOT_ACKED);
               temp_dataFrameToSend->l2_retriesLeft--;
               if (temp_dataFrameToSend->l2_retriesLeft==0) {
                  postTaskSendDone(temp_dataFrameToSend,FAIL);
               }
            }
            call Malloc.freePacketBuffer(msg);//free ACK
            endSlot();
            break;

            /*------------------- RX sequence ------------------------*/
         case S_SYNCHRONIZING:
         case S_RX_RXDATA:                                           //[receive] receiver
            //I'm a receiver, just received data
            if (call IDManager.isMyAddress(&(received_ieee154_header.dest)) && received_ieee154_header.ackRequested) {
               //ACK requested
               if (call RadioControl.rfOff()!=SUCCESS) {
                  //do nothing about it
                  call OpenSerial.printError(COMPONENT_MAC,ERR_RFOFF_FAILED,
                        (errorparameter_t)temp_state,(errorparameter_t)temp_asn%LENGTHCELLFRAME);
               }
               call FastAlarm.start(TsTxAckDelay);
               change_state(S_RX_TXACKPREPARE);
               atomic {
                  packetACK = call Malloc.getFreePacketBuffer();
                  temp_packetACK = packetACK;
               }
               if (temp_packetACK==NULL) {
                  call OpenSerial.printError(COMPONENT_MAC,ERR_NO_FREE_PACKET_BUFFER,
                        (errorparameter_t)0,(errorparameter_t)0);
                  call Malloc.freePacketBuffer(msg);
                  endSlot();
                  return;
               }
               temp_packetACK->creator       = COMPONENT_MAC;
               temp_packetACK->owner         = COMPONENT_MAC;
               //ACK payload
               call PacketFunctions.reserveHeaderSize(temp_packetACK,sizeof(IEEE802154E_ACK_ht));
               ((IEEE802154E_ACK_ht*)(temp_packetACK->payload))->dhrAckNack     = IEEE154E_ACK_dhrAckNack_DEFAULT;
               ((IEEE802154E_ACK_ht*)(temp_packetACK->payload))->timeCorrection =
                  (int16_t)((int32_t)(TsTxOffset+radio_delay)-(int32_t)(msg->l1_rxTimestamp));//poipoi *32
               //154 header
               prependIEEE802154header(temp_packetACK,
                     IEEE154_TYPE_ACK,
                     IEEE154_SEC_NO_SECURITY,
                     received_ieee154_header.dsn,
                     NULL
                     );
               //l2 metadata
               temp_packetACK->l2_retriesLeft  = 1;
               //l1_metadata
               temp_packetACK->l1_txPower        = TX_POWER;
               atomic temp_packetACK->l1_channel = frequencyChannel;
               atomic temp_error = call RadioSend.prepareSend(temp_packetACK);
               if (temp_error!=SUCCESS) {
                  //abort
                  call OpenSerial.printError(COMPONENT_MAC,ERR_PREPARESEND_FAILED,
                        (errorparameter_t)temp_asn%LENGTHCELLFRAME,(errorparameter_t)0);
                  endSlot();
               };
               atomic frameReceived = msg;
            } else if (call PacketFunctions.isBroadcastMulticast(&(received_ieee154_header.dest))) {
               //I'm a receiver, sync off of DATA I received iif ADV (I will not send an ACK)
               if (received_ieee154_header.frameType==IEEE154_TYPE_CMD &&
                     ((IEEE802154E_ADV_t*)(msg->payload))->commandFrameId==IEEE154E_ADV) {
                  atomic asn = ((IEEE802154E_ADV_t*)(msg->payload))->timingInformation;
                  resynchronize(FRAME_BASED_RESYNC,
                        &received_ieee154_header.src,
                        msg->l1_rxTimestamp,
                        (int16_t)((int32_t)(msg->l1_rxTimestamp)-(int32_t)radio_delay)-(int32_t)TsTxOffset);
               }
               atomic frameReceived = msg;
               post taskReceive();
               endSlot();
            } else {
               call Malloc.freePacketBuffer(msg);
               endSlot();
            }
            break;

         default:
            call Malloc.freePacketBuffer(msg);
            endSlot();
            call OpenSerial.printError(COMPONENT_MAC,ERR_WRONG_STATE_IN_RECEIVE,
                  (errorparameter_t)temp_state,(errorparameter_t)temp_asn%LENGTHCELLFRAME);
            endSlot();
            break;
      }
   }

   task void taskReceive() {
      asn_t              temp_asn;
      OpenQueueEntry_t*  temp_frameReceived;
      atomic{
         temp_asn = asn;
         temp_frameReceived = frameReceived;
      }
      //zhen I receive in first slot, I retransmit in second (for video transmission only)
      /* switch (temp_asn%LENGTHCELLFRAME){
         case 1:
            temp_frameReceived->l2_transmitInFirstSlot = FALSE;
            break;
         case 2:
            temp_frameReceived->l2_transmitInFirstSlot = TRUE;
            break;
         default:
            break;
      }*/
      call CellStats.indicateUse(temp_asn%LENGTHCELLFRAME,FALSE);
      call NeighborStats.indicateRx(&(temp_frameReceived->l2_nextORpreviousHop),temp_frameReceived->l1_rssi);
      call OpenReceiveToUpper.receive(temp_frameReceived);
   }

   /*------------------------------ resynchronization ---------------------------------*/
   void resynchronize(bool resyncType, open_addr_t* node_id, timervalue_t dataGlobalSlotOffset, int16_t timeCorrection) {

      bool          temp_isSync;
      open_addr_t   timeParent;
      bool          iShouldSynchronize;

      atomic{
         temp_isSync = isSync;
      }

      if ((call IDManager.getIsDAGroot())==FALSE) {        //I resync only if I'm not a DAGroot
         //---checking whether I should synchronize
         iShouldSynchronize=FALSE;
         if (temp_isSync==FALSE) {                    //I'm not synchronized, I sync off of all ADV packets
            if (resyncType==FRAME_BASED_RESYNC) {
               iShouldSynchronize=TRUE;
               atomic isSync=TRUE;
               call OpenSerial.printError(COMPONENT_MAC,ERR_ACQUIRED_SYNC,0,0);//not an error!
               call Leds.led2On();
            }
         } else {                                //I'm already synchronized
            call NeighborGet.getPreferredParent(&timeParent,node_id->type);
            if (timeParent.type!=ADDR_NONE) {  //I have a timeparent, I sync off of any packet from it
               if (call PacketFunctions.sameAddress(&timeParent,node_id)) {
                  iShouldSynchronize=TRUE;
               }
            } else {                        //I don't have a timeparent, I sync off of any packet
               iShouldSynchronize=TRUE;
            }
         }
         //---synchronize iif I need to
         if (iShouldSynchronize==TRUE) {
            atomic {
               if (resyncType==FRAME_BASED_RESYNC) {
                  if (dataGlobalSlotOffset!=INVALID_TIMESTAMP){
                     if (slotAlarmStartSlotTimestamp+dataGlobalSlotOffset<call SlotAlarm.getNow()) {
                        call SlotAlarm.startAt((uint32_t)((int32_t)slotAlarmStartSlotTimestamp+(int32_t)timeCorrection),SLOT_TIME);
                     } else {
                        atomic isSync=FALSE;
                        atomic call OpenSerial.printError(COMPONENT_MAC,ERR_SYNC_RACE_CONDITION,
                              (errorparameter_t)asn%LENGTHCELLFRAME,
                              (errorparameter_t)dataGlobalSlotOffset);
                        call Leds.led2Off();
                        call SlotAlarm.startAt((call SlotAlarm.getNow())-(SLOT_TIME/2),SLOT_TIME);
                        endSlot();
                     }
                  }
               } else {
                  call SlotAlarm.startAt((uint32_t)((int32_t)slotAlarmStartSlotTimestamp+(int32_t)timeCorrection),SLOT_TIME);
               }
            }
            post taskResetLosingLostTimers();
         }
      }
   }

   /*------------------------------ misc ----------------------------------------------*/

   task void taskResetLosingLostTimers() {
      call LosingSyncTimer.startOneShot(DELAY_LOSING_NEIGHBOR_1KHZ);
      call LostSyncTimer.startOneShot(DELAY_LOST_NEIGHBOR_1KHZ);
   }

   task void taskDebugPrint() {
      //nothing to output
   }

   //SoftwareInit
   command error_t SoftwareInit.init() {
      change_state(S_SLEEP);
      atomic dataFrameToSend = NULL;
      atomic asn = 0;
      //WDT configuration
      WDTCTL = WDTPW + WDTHOLD;
      WDTCTL = WDTPW + WDTCNTCL + WDTSSEL;//run from ACLK, ~1s
      return SUCCESS;
   }

   //LosingSyncTimer
   event void LosingSyncTimer.fired() {
      signal GlobalSync.losingSync();
      call OpenSerial.printError(COMPONENT_MAC,ERR_LOSING_SYNC,0,0);
   }

   //LostSyncTimer
   event void LostSyncTimer.fired() {
      call OpenSerial.printError(COMPONENT_MAC,ERR_LOST_SYNC,0,0);
      atomic isSync=FALSE;
      call Leds.led2Off();
      signal GlobalSync.lostSync();
   }

   //GlobalTime
   async command timervalue_t GlobalTime.getGlobalSlotOffset() {
      //SlotAlarm.getNow() is epoch of now
      //(SlotAlarm.getAlarm()-SLOT_TIME) is epoch of the start of the slot
      //(call SlotAlarm.getNow())-(SlotAlarm.getAlarm()-SLOT_TIME) is the time since start of cell
      return ((call SlotAlarm.getNow())-((call SlotAlarm.getAlarm())-(uint32_t)SLOT_TIME));
   }
   async command timervalue_t GlobalTime.getLocalTime() {
      atomic return (call SlotAlarm.getNow());
   }
   async command asn_t GlobalTime.getASN() {
      atomic return asn;
   }

   async command bool GlobalSync.getIsSync() {
      atomic return isSync;
   }

   command void DebugPrint.print() {
      post taskDebugPrint();
   }

   void change_state(uint8_t newstate) {
      atomic state = newstate;
      switch (newstate) {
         case S_SYNCHRONIZING:
         case S_TX_TXDATA:
         case S_TX_RXACK:
         case S_RX_RXDATA:
         case S_RX_TXACK:
            call Port35.set();
            call Leds.led1On();
            break;
         case S_TX_TXDATAPREPARE:
         case S_TX_TXDATAREADY:
         case S_TX_RXACKPREPARE:
         case S_TX_RXACKREADY:
         case S_RX_RXDATAPREPARE:
         case S_RX_RXDATAREADY:
         case S_RX_TXACKPREPARE:
         case S_RX_TXACKREADY:
         case S_SLEEP:
            call Port35.clr();
            call Leds.led1Off();
            break;
      }
   }
}
