configuration Msp430SpiDmaB0P {

  provides interface Resource[ uint8_t id ];
  provides interface ResourceConfigure[ uint8_t id ];
  provides interface SpiByte;
  provides interface SpiPacket[ uint8_t id ];

  uses interface Resource as UsciResource[ uint8_t id ];
  uses interface Msp430SpiConfigure[ uint8_t id ];
  uses interface HplMsp430UsciInterrupts as UsciInterrupts;

}

implementation {

#include "Msp430Dma.h"

  components new Msp430SpiDmaBP(IFG2_,
			       UCA0TXBUF_,
			       UCA0TXIFG,
			       (uint16_t) DMA_TRIGGER_UCA0TXIFG,
			       UCA0RXBUF_,
			       UCA0RXIFG,
			       (uint16_t) DMA_TRIGGER_UCA0RXIFG) as SpiP;
  Resource = SpiP.Resource;
  ResourceConfigure = SpiP.ResourceConfigure;
  Msp430SpiConfigure = SpiP.Msp430SpiConfigure;
  SpiByte = SpiP.SpiByte;
  SpiPacket = SpiP.SpiPacket;
  UsciResource = SpiP.UsciResource;
  UsciInterrupts = SpiP.UsciInterrupts;

  components HplMsp430UsciA0C as UsciC;
  SpiP.Usci -> UsciC;

  components Msp430DmaC as DmaC;
  SpiP.DmaChannel1 -> DmaC.Channel1;
  SpiP.DmaChannel2 -> DmaC.Channel2;

  components LedsC as Leds;
  SpiP.Leds -> Leds;

}
