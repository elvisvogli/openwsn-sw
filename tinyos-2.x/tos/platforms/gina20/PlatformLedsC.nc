#include "hardware.h"

configuration PlatformLedsC {
  provides interface GeneralIO as Led0;
  provides interface GeneralIO as Led1;
  provides interface GeneralIO as Led2;
  provides interface GeneralIO as Led3; //this is P11_PWM
  uses interface Init;
}
implementation
{
  components
    HplMsp430GeneralIOC as GeneralIOC
    , new Msp430GpioC() as Led0Impl
    , new Msp430GpioC() as Led1Impl
    , new Msp430GpioC() as Led2Impl
    , new Msp430GpioC() as Led3Impl //this is P11_PWM
    ;
  components PlatformP;

  Init = PlatformP.LedsInit;

  Led0 = Led0Impl;
  Led0Impl -> GeneralIOC.Port20;
  //changed from 54

  Led1 = Led1Impl;
  Led1Impl -> GeneralIOC.Port21;
  //changed from 55

  Led2 = Led2Impl;
  Led2Impl -> GeneralIOC.Port22;
  //changed from 56

  Led3 = Led3Impl;
  Led3Impl -> GeneralIOC.Port23;
  //11 for P11_PWM


}

