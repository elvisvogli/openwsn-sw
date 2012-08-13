COMPONENT=OpenWSNWiring

#CFLAGS += -fnesc-dump=wiring -fnesc-dumpfile=wiring.xml

CFLAGS += -I $(TOSROOT)/apps/OpenWSN
CFLAGS += -I $(TOSROOT)/apps/OpenWSN/interfaces

CFLAGS += -I $(TOSROOT)/apps/OpenWSN/07-App/apptcpecho
CFLAGS += -I $(TOSROOT)/apps/OpenWSN/07-App/apptcpinject
CFLAGS += -I $(TOSROOT)/apps/OpenWSN/07-App/apptcpohlone
CFLAGS += -I $(TOSROOT)/apps/OpenWSN/07-App/apptcpprint
CFLAGS += -I $(TOSROOT)/apps/OpenWSN/07-App/appudpecho
CFLAGS += -I $(TOSROOT)/apps/OpenWSN/07-App/appudpinject
CFLAGS += -I $(TOSROOT)/apps/OpenWSN/07-App/appudpprint
CFLAGS += -I $(TOSROOT)/apps/OpenWSN/07-App/appudpsensor

CFLAGS += -I $(TOSROOT)/apps/OpenWSN/04-TRAN/udp
CFLAGS += -I $(TOSROOT)/apps/OpenWSN/04-TRAN/tcp

CFLAGS += -I $(TOSROOT)/apps/OpenWSN/03b-IPv6/forwarding
CFLAGS += -I $(TOSROOT)/apps/OpenWSN/03b-IPv6/icmpv6
CFLAGS += -I $(TOSROOT)/apps/OpenWSN/03b-IPv6/icmpv6echo
CFLAGS += -I $(TOSROOT)/apps/OpenWSN/03b-IPv6/icmpv6router
CFLAGS += -I $(TOSROOT)/apps/OpenWSN/03b-IPv6/icmpv6rpl

CFLAGS += -I $(TOSROOT)/apps/OpenWSN/03a-IPHC/iphc
CFLAGS += -I $(TOSROOT)/apps/OpenWSN/03a-IPHC/openbridge

CFLAGS += -I $(TOSROOT)/apps/OpenWSN/02b-RES/nores
CFLAGS += -I $(TOSROOT)/apps/OpenWSN/02b-RES/nres
CFLAGS += -I $(TOSROOT)/apps/OpenWSN/02b-RES/ures
CFLAGS += -I $(TOSROOT)/apps/OpenWSN/02b-RES/neighbors

CFLAGS += -I $(TOSROOT)/apps/OpenWSN/02a-MAC
CFLAGS += -I $(TOSROOT)/apps/OpenWSN/02a-MAC/cellusage
CFLAGS += -I $(TOSROOT)/apps/OpenWSN/02a-MAC/IEEE802154E
CFLAGS += -I $(TOSROOT)/apps/OpenWSN/02a-MAC/stupidMAC

CFLAGS += -DENABLE_SPI0_DMA #Enable DMA for CC2420 Packet Transfer (for transfering large packets?)
CFLAGS += -I $(TOSROOT)/apps/OpenWSN/01-PHY/cc2420/
CFLAGS += -I $(TOSROOT)/apps/OpenWSN/01-PHY/cc2420/control/
CFLAGS += -I $(TOSROOT)/apps/OpenWSN/01-PHY/cc2420/interfaces/
CFLAGS += -I $(TOSROOT)/apps/OpenWSN/01-PHY/cc2420/packet/
CFLAGS += -I $(TOSROOT)/apps/OpenWSN/01-PHY/cc2420/receive/
CFLAGS += -I $(TOSROOT)/apps/OpenWSN/01-PHY/cc2420/spi/
CFLAGS += -I $(TOSROOT)/apps/OpenWSN/01-PHY/cc2420/cc2420driver/
CFLAGS += -I $(TOSROOT)/apps/OpenWSN/01-PHY/cc2420/transmit/

CFLAGS += -I $(TOSROOT)/apps/OpenWSN/cross-layers/idmanager
CFLAGS += -I $(TOSROOT)/apps/OpenWSN/cross-layers/openqueue
CFLAGS += -I $(TOSROOT)/apps/OpenWSN/cross-layers/openserial
CFLAGS += -I $(TOSROOT)/apps/OpenWSN/cross-layers/packetfunctions

include $(MAKERULES)
