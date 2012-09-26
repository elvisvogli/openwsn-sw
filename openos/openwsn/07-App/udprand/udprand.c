#include "openwsn.h"
#include "udprand.h"
#include "openudp.h"
#include "openqueue.h"
#include "openserial.h"
#include "packetfunctions.h"
#include "opentimers.h"
#include "openrandom.h"
#include "opencoap.h"

//=========================== defines =========================================

/// inter-packet period (in mseconds)
#define UDPRANDPERIOD     10000

//=========================== variables =======================================

typedef struct {
   opentimer_id_t  timerId;
} udprand_vars_t;

udprand_vars_t udprand_vars;

//=========================== prototypes ======================================

void udprand_timer();

//=========================== public ==========================================

void udprand_init() {
   udprand_vars.timerId    = opentimers_start(openrandom_get16b()%UDPRANDPERIOD,
                                          TIMER_PERIODIC,TIME_MS,
                                          udprand_timer);
}

void udprand_timer() {
   OpenQueueEntry_t* pkt;
   
   //prepare packet
   pkt = openqueue_getFreePacketBuffer(COMPONENT_UDPRAND);
   if (pkt==NULL) {
      openserial_printError(COMPONENT_UDPRAND,ERR_NO_FREE_PACKET_BUFFER,
                            (errorparameter_t)0,
                            (errorparameter_t)0);
      return;
   }
   pkt->creator                     = COMPONENT_UDPRAND;
   pkt->owner                       = COMPONENT_UDPRAND;
   pkt->l4_protocol                 = IANA_UDP;
   pkt->l4_sourcePortORicmpv6Type   = WKP_UDP_RAND;
   pkt->l4_destination_port         = WKP_UDP_RAND;
   pkt->l3_destinationORsource.type = ADDR_128B;
   memcpy(&pkt->l3_destinationORsource.addr_128b[0],&ipAddr_motedata,16);
   packetfunctions_reserveHeaderSize(pkt,44);
//   ((uint8_t*)pkt->payload)[0]      = openrandom_get16b()%0xff;
//   ((uint8_t*)pkt->payload)[1]      = openrandom_get16b()%0xff;
   ((uint8_t*)pkt->payload)[0]      = 0x01;
   ((uint8_t*)pkt->payload)[1]      = 0x02;
   ((uint8_t*)pkt->payload)[2]      = 0x03;
   ((uint8_t*)pkt->payload)[3]      = 0x04;
   ((uint8_t*)pkt->payload)[4]      = 0x05;
   ((uint8_t*)pkt->payload)[5]      = 0x06;
   ((uint8_t*)pkt->payload)[6]      = 0x07;
   ((uint8_t*)pkt->payload)[7]      = 0x08;
   ((uint8_t*)pkt->payload)[8]      = 0x09;
   ((uint8_t*)pkt->payload)[9]      = 0x10;
   ((uint8_t*)pkt->payload)[10]      = 0x11;
   ((uint8_t*)pkt->payload)[11]      = 0x12;
   ((uint8_t*)pkt->payload)[12]      = 0x13;
   ((uint8_t*)pkt->payload)[13]      = 0x14;
   ((uint8_t*)pkt->payload)[14]      = 0x15;
   ((uint8_t*)pkt->payload)[15]      = 0x16;
   ((uint8_t*)pkt->payload)[16]      = 0x17;
   ((uint8_t*)pkt->payload)[17]      = 0x18;
   ((uint8_t*)pkt->payload)[18]      = 0x19;
   ((uint8_t*)pkt->payload)[19]      = 0x20;
   ((uint8_t*)pkt->payload)[20]      = 0x21;
   ((uint8_t*)pkt->payload)[21]      = 0x22;
   ((uint8_t*)pkt->payload)[22]      = 0x23;
   ((uint8_t*)pkt->payload)[23]      = 0x24;
   ((uint8_t*)pkt->payload)[24]      = 0x25;
   ((uint8_t*)pkt->payload)[25]      = 0x26;
   ((uint8_t*)pkt->payload)[26]      = 0x27;
   ((uint8_t*)pkt->payload)[27]      = 0x28;
   ((uint8_t*)pkt->payload)[28]      = 0x29;
   ((uint8_t*)pkt->payload)[29]      = 0x30;
   ((uint8_t*)pkt->payload)[30]      = 0x31;
   ((uint8_t*)pkt->payload)[31]      = 0x32;
   ((uint8_t*)pkt->payload)[32]      = 0x33;
   ((uint8_t*)pkt->payload)[33]      = 0x34;
   ((uint8_t*)pkt->payload)[34]      = 0x35;
   ((uint8_t*)pkt->payload)[35]      = 0x36;
   ((uint8_t*)pkt->payload)[36]      = 0x37;
   ((uint8_t*)pkt->payload)[37]      = 0x38;
   ((uint8_t*)pkt->payload)[38]      = 0x39;
   ((uint8_t*)pkt->payload)[39]      = 0x40;
   ((uint8_t*)pkt->payload)[40]      = 0x41;
   ((uint8_t*)pkt->payload)[41]      = 0x42;
   ((uint8_t*)pkt->payload)[42]      = 0x43;
   ((uint8_t*)pkt->payload)[43]      = 0x44;
   
   //send packet
   if ((openudp_send(pkt))==E_FAIL) {
      openqueue_freePacketBuffer(pkt);
   }
}

void udprand_sendDone(OpenQueueEntry_t* msg, error_t error) {
   msg->owner = COMPONENT_UDPRAND;
   if (msg->creator!=COMPONENT_UDPRAND) {
      openserial_printError(COMPONENT_UDPRAND,ERR_UNEXPECTED_SENDDONE,
                            (errorparameter_t)0,
                            (errorparameter_t)0);
   }
   openqueue_freePacketBuffer(msg);
}

void udprand_receive(OpenQueueEntry_t* msg) {
   openqueue_freePacketBuffer(msg);
}

//=========================== private =========================================