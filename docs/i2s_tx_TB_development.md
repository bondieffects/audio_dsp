In my i2s_tx_TB, I was sampling on the falling edge, but “Subsequent bits appear on following falling edges”. I²S receivers must latch on the rising edge.

The TB for the RX acts like the TX and the TB for the TX acts like the RX.