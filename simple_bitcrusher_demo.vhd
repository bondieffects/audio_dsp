-- Simple Bit Crusher Demo
-- Standalone demonstration of bit crushing algorithms
-- Use this to understand the core concepts before integration
-- Author: Group 10

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity simple_bitcrusher_demo is
    port (
        clk         : in  std_logic;
        reset_n     : in  std_logic;
        
        -- Simple audio input (could connect to switches for testing)
        audio_in    : in  std_logic_vector(15 downto 0);
        
        -- Control inputs (connect to switches/buttons)
        bit_depth   : in  std_logic_vector(3 downto 0);  -- 0-15 (maps to 1-16 bits)
        decimation  : in  std_logic_vector(3 downto 0);  -- 0-15 decimation factor
        
        -- Audio output
        audio_out   : out std_logic_vector(15 downto 0);
        
        -- Visual outputs (connect to LEDs)
        quantization_indicator : out std_logic_vector(3 downto 0);  -- Shows current bit depth
        decimation_indicator   : out std_logic_vector(3 downto 0);  -- Shows decimation
        output_activity        : out std_logic                       -- Flashes with output
    );
end entity simple_bitcrusher_demo;

architecture demo of simple_bitcrusher_demo is
    
    -- Decimation signals
    signal decimation_counter : unsigned(3 downto 0) := (others => '0');
    signal held_sample       : signed(15 downto 0) := (others => '0');
    
    -- Bit crushing signals
    signal crushed_sample    : signed(15 downto 0);
    
    -- Activity indicator
    signal activity_counter  : unsigned(15 downto 0) := (others => '0');
    
begin
    
    -- Main bit crushing and decimation process
    crusher_process : process(clk, reset_n)
        variable target_bits : natural range 1 to 16;
        variable shift_amount : natural range 0 to 15;
        variable quantization_mask : signed(15 downto 0);
        variable temp_sample : signed(15 downto 0);
        variable target_decimation : unsigned(3 downto 0);
    begin
        if reset_n = '0' then
            held_sample <= (others => '0');
            crushed_sample <= (others => '0');
            decimation_counter <= (others => '0');
            audio_out <= (others => '0');
            activity_counter <= (others => '0');
            
        elsif rising_edge(clk) then
            
            -- Activity indicator (creates blinking LED)
            activity_counter <= activity_counter + 1;
            
            -- Sample rate decimation (sample and hold)
            target_decimation := unsigned(decimation);
            
            if target_decimation = 0 then
                -- No decimation - pass input directly to bit crusher
                held_sample <= signed(audio_in);
            else
                -- Apply decimation
                if decimation_counter = 0 then
                    -- Update held sample
                    held_sample <= signed(audio_in);
                    decimation_counter <= target_decimation;
                else
                    -- Hold previous sample
                    decimation_counter <= decimation_counter - 1;
                end if;
            end if;
            
            -- Bit depth reduction (quantization)
            target_bits := to_integer(unsigned(bit_depth)) + 1;  -- 1-16 bits
            
            if target_bits >= 16 then
                -- No bit crushing
                crushed_sample <= held_sample;
            else
                -- Apply bit crushing
                shift_amount := 16 - target_bits;
                
                -- Create quantization mask (upper bits = 1, lower bits = 0)
                quantization_mask := (others => '0');
                for i in shift_amount to 15 loop
                    quantization_mask(i) := '1';
                end loop;
                
                -- Apply quantization with simple rounding
                temp_sample := held_sample;
                
                -- Add rounding bias (half of quantization step)
                if shift_amount > 0 then
                    if held_sample >= 0 then
                        temp_sample := held_sample + shift_left(to_signed(1, 16), shift_amount - 1);
                    else
                        temp_sample := held_sample - shift_left(to_signed(1, 16), shift_amount - 1);
                    end if;
                end if;
                
                -- Apply mask to quantize
                crushed_sample <= temp_sample and quantization_mask;
            end if;
            
            -- Output the processed sample
            audio_out <= std_logic_vector(crushed_sample);
            
        end if;
    end process;
    
    -- Visual indicators for debugging/demonstration
    indicators_process : process(clk, reset_n)
    begin
        if reset_n = '0' then
            quantization_indicator <= (others => '0');
            decimation_indicator <= (others => '0');
            output_activity <= '0';
            
        elsif rising_edge(clk) then
            -- Show current bit depth on LEDs (inverted for intuitive display)
            -- More LEDs on = less bit crushing
            case bit_depth is
                when x"F" => quantization_indicator <= "1111";  -- 16-bit (all LEDs on)
                when x"E" => quantization_indicator <= "1111";  -- 15-bit
                when x"D" => quantization_indicator <= "1110";  -- 14-bit
                when x"C" => quantization_indicator <= "1110";  -- 13-bit
                when x"B" => quantization_indicator <= "1100";  -- 12-bit
                when x"A" => quantization_indicator <= "1100";  -- 11-bit
                when x"9" => quantization_indicator <= "1100";  -- 10-bit
                when x"8" => quantization_indicator <= "1000";  -- 9-bit
                when x"7" => quantization_indicator <= "1000";  -- 8-bit
                when x"6" => quantization_indicator <= "1000";  -- 7-bit
                when x"5" => quantization_indicator <= "1000";  -- 6-bit
                when x"4" => quantization_indicator <= "0000";  -- 5-bit
                when x"3" => quantization_indicator <= "0000";  -- 4-bit (heavy crushing)
                when x"2" => quantization_indicator <= "0000";  -- 3-bit
                when x"1" => quantization_indicator <= "0000";  -- 2-bit
                when x"0" => quantization_indicator <= "0000";  -- 1-bit (extreme)
                when others => quantization_indicator <= "0000";
            end case;
            
            -- Show decimation level
            if unsigned(decimation) = 0 then
                decimation_indicator <= "1111";  -- No decimation
            elsif unsigned(decimation) <= 3 then
                decimation_indicator <= "1110";  -- Light decimation
            elsif unsigned(decimation) <= 7 then
                decimation_indicator <= "1100";  -- Medium decimation
            elsif unsigned(decimation) <= 11 then
                decimation_indicator <= "1000";  -- Heavy decimation
            else
                decimation_indicator <= "0000";  -- Extreme decimation
            end if;
            
            -- Activity indicator (blinks with audio processing)
            output_activity <= activity_counter(15);  -- Blink at ~763 Hz (visible rate)
        end if;
    end process;
    
end architecture demo;

-- Example pin assignments for EP4CE6E22C8N:
-- 
-- # Audio input (from switches or test pattern)
-- set_location_assignment PIN_91 -to audio_in[15]
-- set_location_assignment PIN_90 -to audio_in[14]
-- set_location_assignment PIN_89 -to audio_in[13]
-- set_location_assignment PIN_88 -to audio_in[12]
-- # ... continue for all 16 bits
-- 
-- # Control inputs
-- set_location_assignment PIN_91 -to bit_depth[3]
-- set_location_assignment PIN_90 -to bit_depth[2]  
-- set_location_assignment PIN_89 -to bit_depth[1]
-- set_location_assignment PIN_88 -to bit_depth[0]
-- 
-- set_location_assignment PIN_87 -to decimation[3]
-- set_location_assignment PIN_86 -to decimation[2]
-- set_location_assignment PIN_85 -to decimation[1]
-- set_location_assignment PIN_84 -to decimation[0]
-- 
-- # Visual outputs  
-- set_location_assignment PIN_87 -to quantization_indicator[3]
-- set_location_assignment PIN_86 -to quantization_indicator[2]
-- set_location_assignment PIN_85 -to quantization_indicator[1]
-- set_location_assignment PIN_84 -to quantization_indicator[0]
-- 
-- set_location_assignment PIN_83 -to decimation_indicator[3]
-- set_location_assignment PIN_82 -to decimation_indicator[2]
-- set_location_assignment PIN_81 -to decimation_indicator[1]
-- set_location_assignment PIN_80 -to decimation_indicator[0]
-- 
-- set_location_assignment PIN_133 -to output_activity