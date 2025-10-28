library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

-- ============================================================================
-- Bitcrusher
-- ============================================================================
-- Purpose:
--   Reduces the bit depth of audio samples by quantizing to fewer bits,
--   creating harmonic distortion and a characteristic "digital" sound.
--
-- Operation:
--   - Takes a sample with IN_WIDTH bits (e.g., 16-bit audio)
--   - Quantizes it down to 'bit_depth' bits by zeroing lower bits
--   - Uses arithmetic shifts to preserve the sign bit (works with signed audio)
--
-- Algorithm:
--   1. Calculate shift amount = IN_WIDTH - bit_depth
--   2. Right-shift by shift_amt (divides by 2^shift_amt, discards LSBs)
--   3. Left-shift by shift_amt (multiplies back, but LSBs are now zero)
--   4. Result: only the top 'bit_depth' bits contain information
--
-- Examples (16-bit input):
--   bit_depth = 16  →  no quantization (full quality)
--   bit_depth = 8   →  8-bit audio (classic lo-fi sound)
--   bit_depth = 4   →  4-bit audio (severe distortion)
--   bit_depth = 1   →  1-bit audio (extreme distortion, almost square wave)
--
-- Use Case:
--   Audio bitcrushing effect - creates retro/lo-fi sound by reducing
--   resolution, commonly used for 8-bit video game style audio.
-- ============================================================================
entity bitcrusher is
    generic (
        IN_WIDTH : integer := 16  -- bit width of input audio samples (typically 16 or 24)
    );
    port (
        sample_in  : in  std_logic_vector(IN_WIDTH - 1 downto 0);  -- incoming audio sample
        bit_depth  : in  unsigned(4 downto 0);                     -- target bit depth (1..31, clamped to IN_WIDTH)
        sample_out : out std_logic_vector(IN_WIDTH - 1 downto 0)   -- quantized output sample
    );
end entity bitcrusher;

architecture rtl of bitcrusher is
begin
    -- ========================================================================
    -- Combinational bit-depth reduction logic
    -- ========================================================================
    -- This is a purely combinational process (no clock) - output updates
    -- immediately when inputs change.
    -- ========================================================================
    process(sample_in, bit_depth)
        variable working_sample : signed(IN_WIDTH - 1 downto 0);  -- signed conversion of input
        variable target_bits    : integer;                        -- validated bit depth
        variable shift_amt      : integer;                        -- how many LSBs to zero
        variable quantised      : signed(IN_WIDTH - 1 downto 0);  -- result after quantization
    begin
        -- Convert input to signed for arithmetic shifts
        working_sample := signed(sample_in);
        target_bits    := to_integer(bit_depth);

        -- Clamp bit_depth to valid range [1..IN_WIDTH]
        if target_bits > IN_WIDTH then
            target_bits := IN_WIDTH;  -- no quantization possible beyond input width
        elsif target_bits < 1 then
            target_bits := 1;         -- minimum: 1-bit (sign only)
        end if;

        -- Calculate how many lower bits to discard
        shift_amt := IN_WIDTH - target_bits;

        if shift_amt <= 0 then
            -- No quantization needed (bit_depth >= IN_WIDTH)
            quantised := working_sample;
        else
            -- Quantize by right-shifting (discard LSBs), then left-shifting back
            -- Example: 16-bit sample, bit_depth=8, shift_amt=8
            --   Original:      0x1234 = 0001 0010 0011 0100
            --   After >> 8:    0x0012 = 0000 0000 0001 0010
            --   After << 8:    0x1200 = 0001 0010 0000 0000
            --   Result: Top 8 bits preserved, bottom 8 bits zeroed
            quantised := shift_left(shift_right(working_sample, shift_amt), shift_amt);
        end if;

        -- Output the quantized result
        sample_out <= std_logic_vector(quantised);
    end process;
end architecture rtl;
