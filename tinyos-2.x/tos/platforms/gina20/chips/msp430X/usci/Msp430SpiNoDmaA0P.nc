configuration Msp430SpiNoDmaA0P {

  provides interface Resource[ uint8_t id ];
  provides interface ResourceConfigure[uint8_t id ];
  provides interface SpiByte;
  provides interface SpiPacket[ uint8_t id ];

  uses interface Resource as UsciResource[ uint8_t id ];
  uses interface Msp430SpiConfigure[ uint8_t id ];
  uses interface HplMsp430UsciInterrupts as UsciInterrupts;

}

implementation {

  components new Msp430SpiNoDmaAP() as SpiP;
  Resource = SpiP.Resource;
  ResourceConfigure = SpiP.ResourceConfigure;
  Msp430SpiConfigure = SpiP.Msp430SpiConfigure;
  SpiByte = SpiP.SpiByte;
  SpiPacket = SpiP.SpiPacket;
  UsciResource = SpiP.UsciResource;
  UsciInterrupts = SpiP.UsciInterrupts;

  components HplMsp430UsciA0C as UsciC;
  SpiP.Usci -> UsciC;

  components LedsC as Leds;
  SpiP.Leds -> Leds;

}
