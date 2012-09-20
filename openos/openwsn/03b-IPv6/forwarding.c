#include "openwsn.h"
#include "forwarding.h"
#include "iphc.h"
#include "openqueue.h"
#include "openserial.h"
#include "idmanager.h"
#include "packetfunctions.h"
#include "neighbors.h"
#include "icmpv6.h"
#include "openudp.h"
#include "opentcp.h"

//=========================== variables =======================================

//=========================== prototypes ======================================

void    getNextHop(open_addr_t* destination, open_addr_t* addressToWrite);
error_t fowarding_send_internal(OpenQueueEntry_t *msg);
error_t fowarding_send_internal_SourceRouting(OpenQueueEntry_t *msg, ipv6_header_iht ipv6_header);

//=========================== public ==========================================

void forwarding_init() {
}

error_t forwarding_send(OpenQueueEntry_t *msg) {
   msg->owner = COMPONENT_FORWARDING;
   return fowarding_send_internal(msg);
}

void forwarding_sendDone(OpenQueueEntry_t* msg, error_t error) {
   msg->owner = COMPONENT_FORWARDING;
   if (msg->creator==COMPONENT_RADIO) {//that was a packet I had relayed
      openqueue_freePacketBuffer(msg);
   } else {//that was a packet coming from above
      switch(msg->l4_protocol) {
      case IANA_TCP:
         opentcp_sendDone(msg,error);
         break;
      case IANA_UDP:
         openudp_sendDone(msg,error);
         break;
      case IANA_ICMPv6:
         icmpv6_sendDone(msg,error);
         break;
      default:
         openserial_printError(COMPONENT_FORWARDING,ERR_WRONG_TRAN_PROTOCOL,
                               (errorparameter_t)msg->l4_protocol,
                               (errorparameter_t)0);
         // free the corresponding packet buffer
         openqueue_freePacketBuffer(msg);
      }
   }
}

void forwarding_receive(OpenQueueEntry_t* msg, ipv6_header_iht ipv6_header) {
   msg->owner = COMPONENT_FORWARDING;
   msg->l4_protocol            = ipv6_header.next_header;
   msg->l4_protocol_compressed = ipv6_header.next_header_compressed;
   if (idmanager_isMyAddress(&ipv6_header.dest) || packetfunctions_isBroadcastMulticast(&ipv6_header.dest)) {//for me
      memcpy(&(msg->l3_destinationORsource),&ipv6_header.src,sizeof(open_addr_t));
      switch(msg->l4_protocol) {
         case IANA_TCP:
            opentcp_receive(msg);
            break;
         case IANA_UDP:
            openudp_receive(msg);
            break;
         case IANA_ICMPv6:
            icmpv6_receive(msg);
            break;
         default:
            openserial_printError(COMPONENT_FORWARDING,ERR_WRONG_TRAN_PROTOCOL,
                                  (errorparameter_t)msg->l4_protocol,
                                  (errorparameter_t)1);
      }
   } else { //relay
      memcpy(&(msg->l3_destinationORsource),&ipv6_header.dest,sizeof(open_addr_t));//because initially contains source
      //TBC: source address gets changed!
      // change the creator to this components (should have been MAC)
      msg->creator = COMPONENT_FORWARDING;
      if(ipv6_header.next_header !=SourceFWNxtHdr) // no numbers define it >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> NEED TO DEFINE (define SourceFWNxtHdr)
      {
          // resend as if from upper layer
          if (fowarding_send_internal(msg)==E_FAIL) {
             openqueue_freePacketBuffer(msg);
          }
      }
      else
      {
        // source route
         if (fowarding_send_internal_SourceRouting(msg, ipv6_header)==E_FAIL) {
             openqueue_freePacketBuffer(msg);
          }
      }
   }
}

//=========================== private =========================================

error_t fowarding_send_internal(OpenQueueEntry_t *msg) {
   getNextHop(&(msg->l3_destinationORsource),&(msg->l2_nextORpreviousHop));
   if (msg->l2_nextORpreviousHop.type==ADDR_NONE) {
      openserial_printError(COMPONENT_FORWARDING,ERR_NO_NEXTHOP,
                            (errorparameter_t)0,
                            (errorparameter_t)0);
      return E_FAIL;
   }
   return iphc_sendFromForwarding(msg);
}

error_t fowarding_send_internal_SourceRouting(OpenQueueEntry_t *msg, ipv6_header_iht ipv6_header) {
  // It has to be forwarded to dest. so, next hop should be extracted from the message.
  uint8_t local_CmprE;
  uint8_t local_CmprI;
  uint8_t j;
  uint8_t loopLimit;
  uint8_t* runningPointer;
  uint8_t foundFlag;
  uint8_t octetsAddressSize;
  runningPointer=(msg->payload);
  
//  ipv6_Source_Routing_Header_t ipv6_Source_Routing_Header;
//  ipv6_Source_Routing_Header.nextHeader=(((ipv6_Source_Routing_Header_t*)(msg->payload))->nextHeader);
//  ipv6_Source_Routing_Header.HdrExtLen=(((ipv6_Source_Routing_Header_t*)(msg->payload))->HdrExtLen);
//  ipv6_Source_Routing_Header.RoutingType=(((ipv6_Source_Routing_Header_t*)(msg->payload))->RoutingType);
//  ipv6_Source_Routing_Header.SegmentsLeft=(((ipv6_Source_Routing_Header_t*)(msg->payload))->SegmentsLeft); // to be decremented each time u forward
//  ipv6_Source_Routing_Header.CmprICmprE=(((ipv6_Source_Routing_Header_t*)(msg->payload))->CmprICmprE);
//  ipv6_Source_Routing_Header.PadRes=(((ipv6_Source_Routing_Header_t*)(msg->payload))->PadRes);
//  ipv6_Source_Routing_Header.Reserved=(((ipv6_Source_Routing_Header_t*)(msg->payload))->Reserved);
 
  
  // getting local_CmprE and CmprI;
  local_CmprE= ((((ipv6_Source_Routing_Header_t*)(msg->payload))->CmprICmprE) & 0xf);
  local_CmprI=((((ipv6_Source_Routing_Header_t*)(msg->payload))->CmprICmprE) & 0xf0);
  //local_CmprI>>4; // shifting it by 4.
  local_CmprI=local_CmprI/16; // shifting it by 4.
  foundFlag=0;
  
  runningPointer+=sizeof(ipv6_Source_Routing_Header_t);
  
  // tossing the header 
 // packetfunctions_tossHeader(msg,sizeof(ipv6_Source_Routing_Header_t));
  
    if(local_CmprI==2)
    {
      octetsAddressSize=2;
       msg->l2_nextORpreviousHop.type = ADDR_16B;
       if(local_CmprE==0)
            {
              loopLimit= ((((ipv6_Source_Routing_Header_t*)(msg->payload))->HdrExtLen)-16)/octetsAddressSize;
            }
       else if(local_CmprE==2)
             {
               loopLimit= ((((ipv6_Source_Routing_Header_t*)(msg->payload))->HdrExtLen)-2)/octetsAddressSize;
             }
       else if(local_CmprE==8)
            {
              loopLimit= ((((ipv6_Source_Routing_Header_t*)(msg->payload))->HdrExtLen)-8)/octetsAddressSize;
            }
       else
           {
             // compiler shouldn't access this !
             msg->l2_nextORpreviousHop.type = ADDR_NONE;
           }
            
    }
    else if(local_CmprI==8)
    {
      octetsAddressSize=8;
      msg->l2_nextORpreviousHop.type = ADDR_64B;
           if(local_CmprE==0)
            {
              loopLimit= ((((ipv6_Source_Routing_Header_t*)(msg->payload))->HdrExtLen)-16)/octetsAddressSize;
            }
           else if(local_CmprE==8)
            {
              loopLimit= ((((ipv6_Source_Routing_Header_t*)(msg->payload))->HdrExtLen)-8)/octetsAddressSize;
            }
          else if(local_CmprE==2)
          {
            loopLimit= ((((ipv6_Source_Routing_Header_t*)(msg->payload))->HdrExtLen)-2)/octetsAddressSize;
          }
           else
           {
             // compiler shouldn't access this !
             msg->l2_nextORpreviousHop.type = ADDR_NONE;
           }
           
    }
    else if(local_CmprI==0)
    {
          octetsAddressSize=16;
          msg->l2_nextORpreviousHop.type = ADDR_128B;
            if(local_CmprE==0)
           {
            loopLimit= ((((ipv6_Source_Routing_Header_t*)(msg->payload))->HdrExtLen)-16)/octetsAddressSize;
           }
            else if(local_CmprE==8)
            {
              loopLimit= ((((ipv6_Source_Routing_Header_t*)(msg->payload))->HdrExtLen)-8)/octetsAddressSize;
            }
          else if(local_CmprE==2)
          {
            loopLimit= ((((ipv6_Source_Routing_Header_t*)(msg->payload))->HdrExtLen)-2)/octetsAddressSize;
          }
           else
           {
             // compiler shouldn't access this !
             msg->l2_nextORpreviousHop.type = ADDR_NONE;
           }
    }
    else
    {
       // compiler shouldn't access this !
        msg->l2_nextORpreviousHop.type = ADDR_NONE;
    }
    
    
  for(j=0;j<loopLimit;j++) {
    if((memcmp(idmanager_getMyID((msg->l2_nextORpreviousHop.type)),runningPointer+(j*octetsAddressSize),octetsAddressSize))==0)
    {
      // if found print the next address to be the next hop
 
      //check if it's loopLimit -2 then it means, the last address will be taken as next hop.
      if(j!=loopLimit-1)
      {
      memcpy(&(msg->l2_nextORpreviousHop),(runningPointer+(j+1)*octetsAddressSize),octetsAddressSize);
      }
      else
      {
          runningPointer=runningPointer+((j+1)*octetsAddressSize);
          
          if(local_CmprE==0)
            {
              msg->l2_nextORpreviousHop.type = ADDR_16B;
              octetsAddressSize=2;
            }
           else if(local_CmprE==8)
            {
               msg->l2_nextORpreviousHop.type = ADDR_64B;
               octetsAddressSize=8;
            }
           else if(local_CmprE==2)
            {
              msg->l2_nextORpreviousHop.type = ADDR_128B;
              octetsAddressSize=16;
            }
            else
            {
              msg->l2_nextORpreviousHop.type = ADDR_NONE;
            }
          
             memcpy(&(msg->l2_nextORpreviousHop),runningPointer,octetsAddressSize);
       
        
      }
      // SegmentsLeft to be decremented each time u forward
     (((ipv6_Source_Routing_Header_t*)(msg->payload))->SegmentsLeft)--;
      foundFlag=1;
      break;
    }
    
  }
  if(foundFlag==0)
  {
    while(1); // it shouldn't access this, my address was not found in the route.
  }
    
  
  
  // getNextHop(&(msg->l3_destinationORsource),&(msg->l2_nextORpreviousHop));
   if (msg->l2_nextORpreviousHop.type==ADDR_NONE) {
      openserial_printError(COMPONENT_FORWARDING,ERR_NO_NEXTHOP,
                            (errorparameter_t)0,
                            (errorparameter_t)0);
      return E_FAIL;
   }
   return iphc_sendFromForwarding(msg);
}

void getNextHop(open_addr_t* destination128b, open_addr_t* addressToWrite64b) {
   uint8_t i;
   open_addr_t temp_prefix64btoWrite;
   if (packetfunctions_isBroadcastMulticast(destination128b)) {
      // IP destination is broadcast, send to 0xffffffffffffffff
      addressToWrite64b->type = ADDR_64B;
      for (i=0;i<8;i++) {
         addressToWrite64b->addr_64b[i] = 0xff;
      }
   } else if (neighbors_isStableNeighbor(destination128b)) {
       // IP destination is 1-hop neighbor, send directly
      packetfunctions_ip128bToMac64b(destination128b,&temp_prefix64btoWrite,addressToWrite64b);
   } else {
      // destination is remote, send to preferred parent
      neighbors_getPreferredParent(addressToWrite64b,ADDR_64B);
   }
}