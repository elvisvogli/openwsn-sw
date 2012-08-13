generic module Msp430SpiDmaAP( uint16_t IFG_addr,//
			      uint16_t TXBUF_addr,
			      uint8_t  TXIFG,
			      uint16_t TXTRIG,
			      uint16_t RXBUF_addr,
			      uint8_t  RXIFG,
			      uint16_t RXTRIG ) {

  provides interface Resource[ uint8_t id ];
  provides interface ResourceConfigure[ uint8_t id ];
  provides interface SpiByte;
  provides interface SpiPacket[ uint8_t id ];

  uses interface Msp430DmaChannel as DmaChannel1;
  uses interface Msp430DmaChannel as DmaChannel2;
  uses interface Resource as UsciResource[ uint8_t id ];
  uses interface Msp430SpiConfigure[uint8_t id ];
  uses interface HplMsp430UsciA as Usci;//
  uses interface HplMsp430UsciInterrupts as UsciInterrupts;
  uses interface Leds;

}

implementation {

#define IFG (*(volatile uint8_t*)IFG_addr)

  uint8_t* m_tx_buf;
  uint8_t* m_rx_buf;
  uint16_t m_len;
  uint8_t m_client;
  uint8_t m_dump;

  void signalDone( error_t error );
  task void signalDone_task();

  async command error_t Resource.immediateRequest[ uint8_t id ]() {
    return call UsciResource.immediateRequest[ id ]();
  }

  async command error_t Resource.request[ uint8_t id ]() {
    return call UsciResource.request[ id ]();
  }

  async command error_t Resource.release[ uint8_t id ]() {
    return call UsciResource.release[ id ]();
  }

  async command void ResourceConfigure.configure[ uint8_t id ]() {
    call Usci.setModeSpi(call Msp430SpiConfigure.getConfig[id]());
  }

  async command void ResourceConfigure.unconfigure[ uint8_t id ]() {
    call Usci.resetUsci(TRUE);
    call Usci.disableSpi();
    call Usci.resetUsci(FALSE);
  }

  event void UsciResource.granted[ uint8_t id ]() {
    signal Resource.granted[ id ]();
  }

  async command uint8_t Resource.isOwner[ uint8_t id ]() {
    return call UsciResource.isOwner[ id ]();
  }

  default async command error_t UsciResource.isOwner[ uint8_t id ]() { return FAIL; }
  default async command error_t UsciResource.request[ uint8_t id ]() { return FAIL; }
  default async command error_t UsciResource.immediateRequest[ uint8_t id ]() { return FAIL; }
  default async command error_t UsciResource.release[ uint8_t id ]() { return FAIL; }
  default async command msp430_spi_union_config_t* Msp430SpiConfigure.getConfig[uint8_t id]() {
    return &msp430_spi_default_config;
  }

  default event void Resource.granted[ uint8_t id ]() {}

  async command uint8_t SpiByte.write( uint8_t tx ) {

    call Usci.tx( tx );
    while( !call Usci.isRxIntrPending() );
    call Usci.clrRxIntr();
    return call Usci.rx();

  }

  async command error_t SpiPacket.send[ uint8_t id ]( uint8_t* tx_buf,
						      uint8_t* rx_buf,
						      uint16_t len ) {

    atomic {
      m_client = id;
      m_tx_buf = tx_buf;
      m_rx_buf = rx_buf;
      m_len = len;
    }

    if ( len ) {
      // clear the interrupt flags
      IFG &= ~( TXIFG | RXIFG );

      // set up the RX xfer
      call DmaChannel1.setupTransfer(DMA_SINGLE_TRANSFER,
				     RXTRIG,
				     DMA_EDGE_SENSITIVE,
				     (void *) RXBUF_addr,
				     rx_buf ? rx_buf : &m_dump,
				     len,
				     DMA_BYTE,
				     DMA_BYTE,
				     DMA_ADDRESS_UNCHANGED,
				     rx_buf ?
				       DMA_ADDRESS_INCREMENTED :
				       DMA_ADDRESS_UNCHANGED);
      // this doesn't start a transfer; it simply enables the channel
      call DmaChannel1.startTransfer();

      // set up the TX xfer
      call DmaChannel2.setupTransfer(DMA_SINGLE_TRANSFER,
				     TXTRIG,
				     DMA_EDGE_SENSITIVE,
				     tx_buf,
				     (void *) TXBUF_addr,
				     len,
				     DMA_BYTE,
				     DMA_BYTE,
				     DMA_ADDRESS_INCREMENTED,
				     DMA_ADDRESS_UNCHANGED);
      // this doesn't start a transfer; it simply enables the channel
      call DmaChannel2.startTransfer();

      // pong the tx flag to get things rolling
      IFG |= TXIFG;
    } else {
      post signalDone_task();
    }

    return SUCCESS;

  }

  task void signalDone_task() {
    atomic signalDone( SUCCESS );
  }

  async event void DmaChannel1.transferDone( error_t error ) {
    signalDone( error );
  }

  async event void DmaChannel2.transferDone( error_t error ) {}

  void signalDone( error_t error ) {
    signal SpiPacket.sendDone[ m_client ]( m_tx_buf, m_rx_buf, m_len, error );
  }

  async event void UsciInterrupts.txDone() {}
  async event void UsciInterrupts.rxDone( uint8_t data ) {}

  default async event void SpiPacket.sendDone[ uint8_t id ]( uint8_t* tx_buf, uint8_t* rx_buf, uint16_t len, error_t error ) {}

}
