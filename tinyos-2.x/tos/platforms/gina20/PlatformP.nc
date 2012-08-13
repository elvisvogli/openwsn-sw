#include "hardware.h"
 
module PlatformP{
  provides interface Init;
  uses interface Init as Msp430ClockInit;
  uses interface Init as LedsInit;
}
implementation {
  command error_t Init.init() {
    call Msp430ClockInit.init();
//the next three lines are to set up the button. The difference between gina and telos is in the wiring. For telos, the pin is always high and when the button is pressed, it goes low. For gina, when the button is pressed, the pin (port1,7) goes low but is floating otherwise. It was assumed that there would be an internal pullup
    P2DIR = P2DIR & 0x7F; //direction of P1,7: input
    P2REN = P2REN | 0x80; //internal pullup/pulldown enable for P1,7
    P2OUT = P2OUT | 0x80; //internal pullUP on P1,7

    //now we initialize the SPI ports
    P3DIR = P3DIR & 
    call LedsInit.init();
    return SUCCESS;
  }
 
  default command error_t LedsInit.init() { 
    return SUCCESS; }
 
}

