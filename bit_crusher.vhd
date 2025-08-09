-- Digital Bit Crusher Effect
-- Implements bit depth reduction and sample rate decimation
-- Author: Group 10
-- Device: EP4CE6E22C8N

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity bit_crusher is
    port (
        clk             : in  std_logic;
        reset_n         : in  std_logic;
        
        -- Audio input (16-bit signed)
        audio_in_left   : in  std_logic_vector(15 downto 0);
        audio_in_right  : in  std_logic_vector(15 downto 0);
        audio_valid_in  : in  std_logic;
        
        -- Control parameters
        bit_depth       : in  std_logic_vector(3 downto 0);  -- 1-16 bits (0=1bit, 15=16bit)
        decimation      : in  std_logic_vector(3 downto 0);  -- 0-15 (0=no decimation)
        mix_level       : in  std_logic_vector(7 downto 0);  -- 0-255 (dry/wet mix)
        
        -- Audio output
        audio_out_left  : out std_logic_vector(15 downto 0);
        audio_out_right : out std_logic_vector(15 downto 0);
        audio_valid_out : out std_logic
    );
end entity bit_crusher;

architecture rtl of bit_crusher is
    
    -- Bit depth reduction function
    function crush_bits(
        input_sample : signed(15 downto 0);
        target_bits  : natural range 1 to 16
    ) return signed is
        variable temp_sample : signed(15 downto 0);
        variable shift_amount : natural;
        variable quantization_mask : signed(15 downto 0);
    begin
        if target_bits >= 16 then
            -- No bit crushing
            return input_sample;
        else
            -- Calculate how many bits to remove
            shift_amount := 16 - target_bits;
            
            -- Create quantization mask
            quantization_mask := (others => '0');
            for i in shift_amount to 15 loop
                quantization_mask(i) := '1';
            end loop;
            
            -- Apply quantization with proper rounding
            temp_sample := input_sample;
            
            -- Add rounding bias (half of quantization step)
            if shift_amount > 0 then
                if input_sample >= 0 then
                    temp_sample := input_sample + shift_left(to_signed(1, 16), shift_amount - 1);
                else
                    temp_sample := input_sample - shift_left(to_signed(1, 16), shift_amount - 1);
                end if;
            end if;
            
            -- Apply quantization mask
            temp_sample := temp_sample and quantization_mask;
            
            return temp_sample;
        end if;
    end function;
    
    -- Sample rate decimation signals
    signal decimation_counter : unsigned(3 downto 0) := (others => '0');
    signal hold_left         : signed(15 downto 0) := (others => '0');
    signal hold_right        : signed(15 downto 0) := (others => '0');
    signal decimation_active : std_logic := '0';
    
    -- Bit crushed samples
    signal crushed_left  : signed(15 downto 0);
    signal crushed_right : signed(15 downto 0);
    
    -- Mixed output samples
    signal mixed_left    : signed(15 downto 0);
    signal mixed_right   : signed(15 downto 0);
    
    -- Dry/wet mixing signals
    signal dry_gain      : unsigned(7 downto 0);
    signal wet_gain      : unsigned(7 downto 0);
    signal dry_left      : signed(31 downto 0);
    signal dry_right     : signed(31 downto 0);
    signal wet_left      : signed(31 downto 0);
    signal wet_right     : signed(31 downto 0);
    
begin
    
    -- Calculate dry/wet gains
    wet_gain <= unsigned(mix_level);
    dry_gain <= 255 - unsigned(mix_level);
    
    -- Sample rate decimation process
    decimation_process : process(clk, reset_n)
        variable target_decimation : unsigned(3 downto 0);
    begin
        if reset_n = '0' then
            decimation_counter <= (others => '0');
            hold_left <= (others => '0');
            hold_right <= (others => '0');
            decimation_active <= '0';
            
        elsif rising_edge(clk) then
            target_decimation := unsigned(decimation);
            
            if audio_valid_in = '1' then
                if target_decimation = 0 then
                    -- No decimation - pass through
                    hold_left <= signed(audio_in_left);
                    hold_right <= signed(audio_in_right);
                    decimation_active <= '0';
                else
                    -- Apply decimation
                    decimation_active <= '1';
                    
                    if decimation_counter = 0 then
                        -- Update held samples
                        hold_left <= signed(audio_in_left);
                        hold_right <= signed(audio_in_right);
                        decimation_counter <= target_decimation;
                    else
                        -- Hold previous samples
                        decimation_counter <= decimation_counter - 1;
                    end if;
                end if;
            end if;
        end if;
    end process;
    
    -- Bit depth crushing process
    bit_crushing_process : process(clk, reset_n)
        variable target_bit_depth : natural range 1 to 16;
    begin
        if reset_n = '0' then
            crushed_left <= (others => '0');
            crushed_right <= (others => '0');
            
        elsif rising_edge(clk) then
            if audio_valid_in = '1' then
                -- Convert bit_depth control to actual bit depth
                -- bit_depth = 0 means 1 bit, bit_depth = 15 means 16 bits
                target_bit_depth := to_integer(unsigned(bit_depth)) + 1;
                
                -- Apply bit crushing to decimated samples
                crushed_left <= crush_bits(hold_left, target_bit_depth);
                crushed_right <= crush_bits(hold_right, target_bit_depth);
            end if;
        end if;
    end process;
    
    -- Dry/wet mixing process
    mixing_process : process(clk, reset_n)
    begin
        if reset_n = '0' then
            mixed_left <= (others => '0');
            mixed_right <= (others => '0');
            dry_left <= (others => '0');
            dry_right <= (others => '0');
            wet_left <= (others => '0');
            wet_right <= (others => '0');
            
        elsif rising_edge(clk) then
            if audio_valid_in = '1' then
                -- Calculate dry signal (original)
                dry_left <= signed(audio_in_left) * signed('0' & dry_gain);
                dry_right <= signed(audio_in_right) * signed('0' & dry_gain);
                
                -- Calculate wet signal (bit crushed)
                wet_left <= crushed_left * signed('0' & wet_gain);
                wet_right <= crushed_right * signed('0' & wet_gain);
                
                -- Mix dry and wet signals
                -- Scale down by 8 bits (divide by 256) to maintain amplitude
                mixed_left <= resize(shift_right(dry_left + wet_left, 8), 16);
                mixed_right <= resize(shift_right(dry_right + wet_right, 8), 16);
            end if;
        end if;
    end process;
    
    -- Output assignment with saturation protection
    output_process : process(clk, reset_n)
    begin
        if reset_n = '0' then
            audio_out_left <= (others => '0');
            audio_out_right <= (others => '0');
            audio_valid_out <= '0';
            
        elsif rising_edge(clk) then
            audio_valid_out <= audio_valid_in;
            
            if audio_valid_in = '1' then
                -- Left channel saturation protection
                if mixed_left > 32767 then
                    audio_out_left <= std_logic_vector(to_signed(32767, 16));
                elsif mixed_left < -32768 then
                    audio_out_left <= std_logic_vector(to_signed(-32768, 16));
                else
                    audio_out_left <= std_logic_vector(mixed_left);
                end if;
                
                -- Right channel saturation protection
                if mixed_right > 32767 then
                    audio_out_right <= std_logic_vector(to_signed(32767, 16));
                elsif mixed_right < -32768 then
                    audio_out_right <= std_logic_vector(to_signed(-32768, 16));
                else
                    audio_out_right <= std_logic_vector(mixed_right);
                end if;
            end if;
        end if;
    end process;
    
end architecture rtl;