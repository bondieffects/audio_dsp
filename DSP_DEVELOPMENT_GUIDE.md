# Audio DSP Development Guide

## Current Status
You now have a **functional DSP framework** integrated into your audio pass-through system!

## What's Been Added

### 1. DSP Processor (`audio_dsp_processor.vhd`)
- **Gain Control**: Volume adjustment with 8-bit parameter
- **Delay Effect**: Simple echo with configurable delay (up to 255 samples)
- **Low-Pass Filter**: First-order IIR filter for removing high frequencies
- **Effect Selection**: 3-bit selection for different effects
- **Pipeline Architecture**: Proper timing for real-time audio processing

### 2. Integration (`audio_dsp_top.vhd`)
- DSP processor instantiated between I2S input and output
- Default settings: Gain effect enabled with moderate level
- Clean audio data flow: ADC → DSP → DAC

### 3. Control Example (`dsp_control_example.vhd`)
- Shows how to control effects with switches/buttons
- Parameter adjustment with edge detection
- Reference for effect parameters and meanings

## Next Steps for DSP Development

### Phase 1: Test Current Effects
1. **Compile and test** the current design
2. **Verify gain effect** is working (should be audible immediately)
3. **Test effect switching** by changing `effect_select` values
4. **Adjust parameters** to understand effect ranges

### Phase 2: Add More Effects
```vhdl
-- Ideas for additional effects:
-- High-pass filter (remove low frequencies)
-- Reverb (multiple delays with feedback)
-- Chorus (delayed + pitch shifted)
-- Distortion/saturation
-- Dynamic range compression
-- Equalizer (multiple band-pass filters)
```

### Phase 3: Advanced Features
```vhdl
-- Control interfaces:
-- SPI/I2C for external control
-- UART for parameter adjustment
-- Multiple effect chains
-- Real-time parameter interpolation
```

## Testing Your DSP

### Quick Test Procedure
1. **Load the design** onto your FPGA
2. **Connect audio input** (microphone or line input)
3. **Listen to output** - you should hear processed audio
4. **Check LEDs** for system status

### Effect Testing
```
Effect 000 (Passthrough): Should sound identical to input
Effect 001 (Gain):        Should be quieter/louder than input  
Effect 010 (Delay):       Should have echo/repetition
Effect 011 (Low-pass):    Should sound muffled (less treble)
```

### Troubleshooting
- **No audio**: Check that `effect_enable = '1'` and PLL is locked
- **Distorted audio**: Reduce gain parameter (try 0x40 instead of 0x80)
- **No effect heard**: Verify `effect_select` is set correctly

## Understanding the Audio Pipeline

```
Input Audio → I2S ADC → DSP Processor → I2S DAC → Output Audio
               ↑              ↑               ↑
           16-bit PCM    Effect Processing  16-bit PCM
           48kHz Stereo                     48kHz Stereo
```

## Adding Your Own Effects

### Template for New Effect
```vhdl
-- In audio_dsp_processor.vhd, add:
signal my_effect_left  : std_logic_vector(15 downto 0);
signal my_effect_right : std_logic_vector(15 downto 0);

-- Add processing logic:
process(clk_audio, reset_n)
begin
    if reset_n = '0' then
        my_effect_left  <= (others => '0');
        my_effect_right <= (others => '0');
    elsif rising_edge(clk_audio) then
        if input_valid_reg = '1' then
            -- Your effect processing here
            my_effect_left  <= processed_input_left;
            my_effect_right <= processed_input_right;
        end if;
    end if;
end process;

-- Add to effect selection MUX:
when "101" =>  -- New effect code
    processed_left  <= my_effect_left;
    processed_right <= my_effect_right;
```

## Resource Usage Guidelines

### Current Design Uses:
- **Logic Elements**: ~500-1000 (estimate)
- **Memory**: ~2KB for delay buffers
- **DSP Blocks**: 0 (using fabric multipliers)

### For Advanced Effects:
- **Use BRAM** for longer delays (>1ms)
- **Use DSP blocks** for complex math
- **Pipeline** heavy computations across multiple clock cycles

## Performance Considerations

### Timing Constraints
- **Audio Clock**: 12.288MHz (plenty of time for processing)
- **Sample Rate**: 48kHz (20.8μs between samples)
- **Processing Budget**: ~256 clock cycles per sample

### Optimization Tips
1. **Pipeline** complex operations
2. **Use lookup tables** for non-linear functions
3. **Quantize carefully** to avoid artifacts
4. **Test with sine waves** first, then complex audio

## Common DSP Techniques

### Fixed-Point Math
```vhdl
-- For fractional multiplication (0.5 * input):
signal temp : signed(16 downto 0);
temp := signed('0' & input) + signed(input & '0');  -- Add input + 2*input
output <= temp(16 downto 1);  -- Divide by 2 = 1.5 * input / 2 = 0.75 * input
```

### Saturation
```vhdl
-- Prevent overflow:
if temp > 32767 then
    output <= x"7FFF";  -- Max positive
elsif temp < -32768 then
    output <= x"8000";  -- Max negative  
else
    output <= temp(15 downto 0);
end if;
```

### Filters
```vhdl
-- Moving average (low-pass):
signal sum : signed(18 downto 0);
sum := signed(sample1) + signed(sample2) + signed(sample3) + signed(sample4);
output <= sum(17 downto 2);  -- Divide by 4
```

## Next Recommended Steps

1. **Verify current design works**
2. **Add switches/buttons for control** (use `dsp_control_example.vhd`)
3. **Implement high-pass filter**
4. **Add reverb effect**
5. **Create multi-effect chains**

Your DSP framework is now ready for expansion! Start with simple modifications and gradually add complexity.
