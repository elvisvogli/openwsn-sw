#include "msp430usci.h"

generic configuration Msp430SpiA0C() {

  provides interface Resource;
  provides interface ResourceRequested;
  provides interface SpiByte;
  provides interface SpiPacket;

  uses interface Msp430SpiConfigure;
}

implementation {

  enum {
    CLIENT_ID = unique( MSP430_SPIAO_BUS ),
  };

#ifdef ENABLE_SPIA0_DMA
#warning "Enabling SPI DMA on USCIA0"
  components Msp430SpiDmaA0P as SpiP;
#else
  components Msp430SpiNoDmaA0P as SpiP;
#endif

  Resource = SpiP.Resource[ CLIENT_ID ];
  SpiByte = SpiP.SpiByte;
  SpiPacket = SpiP.SpiPacket[ CLIENT_ID ];
  Msp430SpiConfigure = SpiP.Msp430SpiConfigure[ CLIENT_ID ];

  components new Msp430UsciA0C() as UsciC;
  ResourceRequested = UsciC;
  SpiP.ResourceConfigure[ CLIENT_ID ] <- UsciC.ResourceConfigure;
  SpiP.UsciResource[ CLIENT_ID ] -> UsciC.Resource;
  SpiP.UsciInterrupts -> UsciC.HplMsp430UsciInterrupts;

}
