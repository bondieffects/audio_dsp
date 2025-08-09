-- I2S Clock Generator using PLL
-- Generates audio clocks from 50MHz system clock
-- Target: 48kHz sample rate, 16-bit stereo
-- BCLK = 48kHz * 64 = 3.072MHz
-- LRCLK = 48kHz

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity i2s_clock_gen is
    port (
        clk_50mhz  : in  std_logic;  -- 50MHz system clock
        reset_n    : in  std_logic;  -- Active low reset
        clk_audio  : out std_logic;  -- 12.288MHz audio master clock
        i2s_bclk   : out std_logic;  -- 3.072MHz bit clock
        i2s_lrclk  : out std_logic;  -- 48kHz left/right clock
        pll_locked : out std_logic   -- PLL lock status
    );
end entity i2s_clock_gen;

architecture rtl of i2s_clock_gen is
    
    -- PLL component (Altera/Intel PLL IP)
    component audio_pll is
        port (
            inclk0  : in  std_logic := '0';  -- 50MHz input
            c0      : out std_logic;         -- 12.288MHz output
            locked  : out std_logic          -- PLL locked
        );
    end component;
    
    -- Internal signals
    signal clk_audio_int : std_logic;
    signal pll_locked_int : std_logic;
    signal bclk_counter : unsigned(1 downto 0) := "00";  -- Divide by 4: 12.288/4 = 3.072MHz
    signal lrclk_counter : unsigned(5 downto 0) := "000000"; -- Divide by 64: 3.072/64 = 48kHz
    signal i2s_bclk_int : std_logic := '0';
    signal i2s_lrclk_int : std_logic := '0';
    
begin
    
    -- Instantiate PLL to generate 12.288MHz from 50MHz
    -- Note: This requires creating a PLL IP core in Quartus
    -- For simulation, you can comment this out and use a simple clock divider
    u_audio_pll : audio_pll
        port map (
            inclk0 => clk_50mhz,
            c0     => clk_audio_int,
            locked => pll_locked_int
        );
    
    -- Alternative simple clock divider for simulation/testing
    -- Uncomment if PLL IP is not available
    -- process(clk_50mhz, reset_n)
    --     variable clk_div_counter : unsigned(7 downto 0) := (others => '0');
    -- begin
    --     if reset_n = '0' then
    --         clk_div_counter := (others => '0');
    --         clk_audio_int <= '0';
    --         pll_locked_int <= '0';
    --     elsif rising_edge(clk_50mhz) then
    --         clk_div_counter := clk_div_counter + 1;
    --         if clk_div_counter = 1 then  -- Rough approximation
    --             clk_audio_int <= not clk_audio_int;
    --             clk_div_counter := (others => '0');
    --         end if;
    --         pll_locked_int <= '1';  -- Assume always locked for simulation
    --     end if;
    -- end process;
    
    -- Generate BCLK (3.072MHz) by dividing audio clock by 4
    process(clk_audio_int, reset_n)
    begin
        if reset_n = '0' then
            bclk_counter <= "00";
            i2s_bclk_int <= '0';
        elsif rising_edge(clk_audio_int) then
            if pll_locked_int = '1' then
                bclk_counter <= bclk_counter + 1;
                if bclk_counter = "01" then  -- Toggle every 2 clocks (divide by 4)
                    i2s_bclk_int <= not i2s_bclk_int;
                    bclk_counter <= "00";
                end if;
            end if;
        end if;
    end process;
    
    -- Generate LRCLK (48kHz) by dividing BCLK by 64
    process(i2s_bclk_int, reset_n)
    begin
        if reset_n = '0' then
            lrclk_counter <= "000000";
            i2s_lrclk_int <= '0';
        elsif rising_edge(i2s_bclk_int) then
            if pll_locked_int = '1' then
                lrclk_counter <= lrclk_counter + 1;
                if lrclk_counter = "011111" then  -- 32 cycles (half of 64)
                    i2s_lrclk_int <= not i2s_lrclk_int;
                    lrclk_counter <= "000000";
                end if;
            end if;
        end if;
    end process;
    
    -- Output assignments
    clk_audio <= clk_audio_int;
    i2s_bclk <= i2s_bclk_int;
    i2s_lrclk <= i2s_lrclk_int;
    pll_locked <= pll_locked_int;
    
end architecture rtl;