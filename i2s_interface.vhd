-- I2S Interface Module
-- Handles I2S protocol for audio data transfer
-- Supports 16-bit stereo at 48kHz sample rate
-- FPGA acts as I2S master

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity i2s_interface is
    port (
        -- Clock and reset
        clk_audio      : in  std_logic;  -- Audio clock domain
        reset_n        : in  std_logic;  -- Active low reset
        
        -- I2S signals
        i2s_bclk       : in  std_logic;  -- Bit clock (3.072MHz)
        i2s_lrclk      : in  std_logic;  -- Left/Right clock (48kHz)
        i2s_din        : in  std_logic;  -- Data input from CODEC
        i2s_dout       : out std_logic;  -- Data output to CODEC
        
        -- Parallel audio data
        audio_left_in  : out std_logic_vector(15 downto 0);  -- Left channel input
        audio_right_in : out std_logic_vector(15 downto 0);  -- Right channel input
        audio_left_out : in  std_logic_vector(15 downto 0);  -- Left channel output
        audio_right_out: in  std_logic_vector(15 downto 0);  -- Right channel output
        audio_valid    : out std_logic   -- New sample available
    );
end entity i2s_interface;

architecture rtl of i2s_interface is
    
    -- State machine for I2S reception/transmission
    type i2s_state_t is (IDLE, LEFT_CHANNEL, RIGHT_CHANNEL);
    signal rx_state : i2s_state_t := IDLE;
    signal tx_state : i2s_state_t := IDLE;
    
    -- Shift registers for serial data
    signal rx_shift_reg : std_logic_vector(15 downto 0) := (others => '0');
    signal tx_shift_reg : std_logic_vector(15 downto 0) := (others => '0');
    
    -- Bit counters
    signal rx_bit_count : unsigned(4 downto 0) := (others => '0');
    signal tx_bit_count : unsigned(4 downto 0) := (others => '0');
    
    -- Internal registers for audio data
    signal left_channel_reg  : std_logic_vector(15 downto 0) := (others => '0');
    signal right_channel_reg : std_logic_vector(15 downto 0) := (others => '0');
    
    -- LRCLK edge detection
    signal lrclk_prev : std_logic := '0';
    signal lrclk_edge : std_logic := '0';
    
    -- Valid signal generation
    signal audio_valid_int : std_logic := '0';
    
begin
    
    -- LRCLK edge detection
    process(i2s_bclk, reset_n)
    begin
        if reset_n = '0' then
            lrclk_prev <= '0';
            lrclk_edge <= '0';
        elsif rising_edge(i2s_bclk) then
            lrclk_prev <= i2s_lrclk;
            lrclk_edge <= i2s_lrclk xor lrclk_prev;  -- Edge detected
        end if;
    end process;
    
    -- I2S Reception Process
    process(i2s_bclk, reset_n)
    begin
        if reset_n = '0' then
            rx_state <= IDLE;
            rx_shift_reg <= (others => '0');
            rx_bit_count <= (others => '0');
            left_channel_reg <= (others => '0');
            right_channel_reg <= (others => '0');
            audio_valid_int <= '0';
        elsif falling_edge(i2s_bclk) then  -- Sample on falling edge
            audio_valid_int <= '0';  -- Default
            
            case rx_state is
                when IDLE =>
                    if lrclk_edge = '1' then
                        rx_bit_count <= (others => '0');
                        rx_shift_reg <= (others => '0');
                        if i2s_lrclk = '0' then  -- Left channel (LRCLK low)
                            rx_state <= LEFT_CHANNEL;
                        else  -- Right channel (LRCLK high)
                            rx_state <= RIGHT_CHANNEL;
                        end if;
                    end if;
                
                when LEFT_CHANNEL =>
                    if rx_bit_count < 16 then
                        rx_shift_reg <= rx_shift_reg(14 downto 0) & i2s_din;
                        rx_bit_count <= rx_bit_count + 1;
                    else
                        left_channel_reg <= rx_shift_reg;
                        rx_state <= IDLE;
                    end if;
                
                when RIGHT_CHANNEL =>
                    if rx_bit_count < 16 then
                        rx_shift_reg <= rx_shift_reg(14 downto 0) & i2s_din;
                        rx_bit_count <= rx_bit_count + 1;
                    else
                        right_channel_reg <= rx_shift_reg;
                        audio_valid_int <= '1';  -- Both channels received
                        rx_state <= IDLE;
                    end if;
            end case;
        end if;
    end process;
    
    -- I2S Transmission Process
    process(i2s_bclk, reset_n)
    begin
        if reset_n = '0' then
            tx_state <= IDLE;
            tx_shift_reg <= (others => '0');
            tx_bit_count <= (others => '0');
            i2s_dout <= '0';
        elsif rising_edge(i2s_bclk) then  -- Transmit on rising edge
            
            case tx_state is
                when IDLE =>
                    if lrclk_edge = '1' then
                        tx_bit_count <= (others => '0');
                        if i2s_lrclk = '0' then  -- Left channel
                            tx_shift_reg <= audio_left_out;
                            tx_state <= LEFT_CHANNEL;
                        else  -- Right channel
                            tx_shift_reg <= audio_right_out;
                            tx_state <= RIGHT_CHANNEL;
                        end if;
                    end if;
                    i2s_dout <= '0';
                
                when LEFT_CHANNEL =>
                    if tx_bit_count < 16 then
                        i2s_dout <= tx_shift_reg(15);  -- MSB first
                        tx_shift_reg <= tx_shift_reg(14 downto 0) & '0';
                        tx_bit_count <= tx_bit_count + 1;
                    else
                        i2s_dout <= '0';
                        tx_state <= IDLE;
                    end if;
                
                when RIGHT_CHANNEL =>
                    if tx_bit_count < 16 then
                        i2s_dout <= tx_shift_reg(15);  -- MSB first
                        tx_shift_reg <= tx_shift_reg(14 downto 0) & '0';
                        tx_bit_count <= tx_bit_count + 1;
                    else
                        i2s_dout <= '0';
                        tx_state <= IDLE;
                    end if;
            end case;
        end if;
    end process;
    
    -- Output assignments
    audio_left_in <= left_channel_reg;
    audio_right_in <= right_channel_reg;
    audio_valid <= audio_valid_int;
    
end architecture rtl;