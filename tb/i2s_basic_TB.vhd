-- ============================================================================
-- BASIC I2S PASSTHROUGH TEST
-- ============================================================================
-- Very simple test to verify I2S modules work together

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity i2s_basic_test is
end entity i2s_basic_test;

architecture sim of i2s_basic_test is

    component i2s_clocks is
        port (
            i2s_mclk : in  std_logic;
            reset_n  : in  std_logic;
            i2s_bclk : out std_logic;
            i2s_ws   : out std_logic
        );
    end component;
    
    component i2s_rx is
        port (
            i2s_bclk    : in  std_logic;
            i2s_ws      : in  std_logic;
            reset_n     : in  std_logic;
            i2s_sdata   : in  std_logic;
            audio_left  : out std_logic_vector(15 downto 0);
            audio_right : out std_logic_vector(15 downto 0);
            rx_ready    : out std_logic
        );
    end component;
    
    component i2s_tx is
        port (
            i2s_bclk        : in  std_logic;
            i2s_ws          : in  std_logic;
            reset_n         : in  std_logic;
            audio_left      : in  std_logic_vector(15 downto 0);
            audio_right     : in  std_logic_vector(15 downto 0);
            tx_ready        : in  std_logic;
            i2s_sdata       : out std_logic;
            sample_request  : out std_logic
        );
    end component;

    -- Signals
    signal mclk_12288   : std_logic := '0';
    signal reset_n      : std_logic := '0';
    signal i2s_bclk     : std_logic;
    signal i2s_ws       : std_logic;
    signal i2s_din      : std_logic := '0';
    signal i2s_dout     : std_logic;
    
    signal rx_left      : std_logic_vector(15 downto 0);
    signal rx_right     : std_logic_vector(15 downto 0);
    signal rx_ready     : std_logic;
    signal sample_request : std_logic;
    
    signal tx_left      : std_logic_vector(15 downto 0) := x"1234";
    signal tx_right     : std_logic_vector(15 downto 0) := x"5678";
    signal tx_ready     : std_logic := '1';
    
    signal sim_finished : boolean := false;
    constant MCLK_PERIOD : time := 81.38 ns;

begin

    -- Clock generation
    mclk_proc : process
    begin
        if not sim_finished then
            mclk_12288 <= '0';
            wait for MCLK_PERIOD / 2;
            mclk_12288 <= '1';
            wait for MCLK_PERIOD / 2;
        else
            wait;
        end if;
    end process;

    -- Module instantiations
    u_i2s_clocks : i2s_clocks
        port map (
            i2s_mclk => mclk_12288,
            reset_n  => reset_n,
            i2s_bclk => i2s_bclk,
            i2s_ws   => i2s_ws
        );

    u_i2s_rx : i2s_rx
        port map (
            i2s_bclk   => i2s_bclk,
            i2s_ws     => i2s_ws,
            reset_n    => reset_n,
            i2s_sdata  => i2s_din,
            audio_left => rx_left,
            audio_right=> rx_right,
            rx_ready   => rx_ready
        );

    u_i2s_tx : i2s_tx
        port map (
            i2s_bclk       => i2s_bclk,
            i2s_ws         => i2s_ws,
            reset_n        => reset_n,
            audio_left     => tx_left,
            audio_right    => tx_right,
            tx_ready       => tx_ready,
            i2s_sdata      => i2s_dout,
            sample_request => sample_request
        );

    -- Simple test process
    test_proc : process
    begin
        report "Starting basic I2S test";
        
        reset_n <= '0';
        wait for 10 * MCLK_PERIOD;
        
        reset_n <= '1';
        report "Reset released";
        
        -- Wait for clocks to stabilize
        wait for 100 * MCLK_PERIOD;
        
        report "Checking for I2S clocks...";
        
        -- Wait for several I2S frames
        wait for 50 ms;
        
        report "Test completed - check waveforms";
        sim_finished <= true;
        wait;
    end process;
    
    -- Monitor process  
    monitor_proc : process
    begin
        wait until reset_n = '1';
        wait for 50 * MCLK_PERIOD;
        
        while not sim_finished loop
            if rx_ready = '1' then
                report "RX Ready - Left: " & integer'image(to_integer(unsigned(rx_left))) & 
                       " Right: " & integer'image(to_integer(unsigned(rx_right)));
            end if;
            
            if sample_request = '1' then
                report "Sample requested by TX";
            end if;
            
            wait for 1000 * MCLK_PERIOD;
        end loop;
        
        wait;
    end process;

end architecture sim;