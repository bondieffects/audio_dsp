library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

-- ============================================================================
-- MIDI Parser
-- ============================================================================
-- Accepts MIDI bytes from midi_uart_rx and extracts Control Change values used
-- to drive the audio processing parameters.
--
-- Supported mapping:
--   Control Change #20 -> Bit depth (maps 0..127 to 1..16)
--   Control Change #21 -> Decimation factor (maps 0..127 to 1..64)
-- ============================================================================
entity midi_parser is
    port (
        clk                : in  std_logic;
        reset_n            : in  std_logic;
        data_byte          : in  std_logic_vector(7 downto 0);
        data_valid         : in  std_logic;
        bit_depth_value    : out unsigned(4 downto 0);
        decimation_value   : out unsigned(6 downto 0);
        cc_event           : out std_logic;
        cc_number          : out unsigned(6 downto 0);
        cc_value_raw       : out unsigned(6 downto 0);
        pc_event           : out std_logic;
        pc_number          : out unsigned(6 downto 0)
    );
end entity midi_parser;

architecture rtl of midi_parser is
    type parser_state_t is (WAIT_STATUS, WAIT_DATA1, WAIT_DATA2);
    signal state           : parser_state_t := WAIT_STATUS;
    signal status_byte     : std_logic_vector(7 downto 0) := (others => '0');
    signal controller_byte : std_logic_vector(7 downto 0) := (others => '0');

    signal bit_depth_reg   : unsigned(4 downto 0) := to_unsigned(3, 5);  -- default 3 bits
    signal decimation_reg  : unsigned(6 downto 0) := to_unsigned(2, 7);  -- default factor 2

    signal cc_event_reg    : std_logic := '0';
    signal cc_number_reg   : unsigned(6 downto 0) := (others => '0');
    signal cc_value_reg    : unsigned(6 downto 0) := (others => '0');
    signal pc_event_reg    : std_logic := '0';
    signal pc_number_reg   : unsigned(6 downto 0) := (others => '0');

    constant STATUS_CC_MASK  : std_logic_vector(3 downto 0) := "1011";  -- 0xB for Control Change
    constant STATUS_PC_MASK  : std_logic_vector(3 downto 0) := "1100";  -- 0xC for Program Change
    constant CC_BIT_DEPTH    : integer := 20;
    constant CC_DECIMATION   : integer := 21;

    function map_bit_depth(val : integer) return integer is
        variable result : integer;
    begin
        -- 0..127 -> 1..16 using 8-step buckets
        result := (val / 8) + 1;
        if result < 1 then
            result := 1;
        elsif result > 16 then
            result := 16;
        end if;
        return result;
    end function;

    function map_decimation(val : integer) return integer is
        variable result : integer;
    begin
        -- 0..127 -> 1..64 using 2-step buckets
        result := (val / 2) + 1;
        if result < 1 then
            result := 1;
        elsif result > 64 then
            result := 64;
        end if;
        return result;
    end function;

begin
    process(clk, reset_n)
        variable data_is_status : boolean;
        variable data_value     : integer;
        variable controller     : integer;
        variable scaled_value   : integer;
    begin
        if reset_n = '0' then
            state           <= WAIT_STATUS;
            status_byte     <= (others => '0');
            controller_byte <= (others => '0');
            bit_depth_reg   <= to_unsigned(3, 5);
            decimation_reg  <= to_unsigned(2, 7);
            cc_event_reg    <= '0';
            cc_number_reg   <= (others => '0');
            cc_value_reg    <= (others => '0');
            pc_event_reg    <= '0';
            pc_number_reg   <= (others => '0');
        elsif rising_edge(clk) then
            cc_event_reg <= '0';
            pc_event_reg <= '0';

            if data_valid = '1' then
                data_is_status := (data_byte(7) = '1');

                if data_is_status then
                    if unsigned(data_byte) >= 248 then
                        -- MIDI real-time messages (0xF8-0xFF) are single-byte and
                        -- should not disturb running status. Ignore them.
                        null;
                    else
                        status_byte <= data_byte;
                        state       <= WAIT_DATA1;
                    end if;
                else
                    data_value := to_integer(unsigned(data_byte(6 downto 0)));

                    case state is
                        when WAIT_STATUS =>
                            -- Running status: reuse last status byte
                            if status_byte(7 downto 4) = STATUS_CC_MASK then
                                controller_byte <= data_byte;
                                state           <= WAIT_DATA2;
                            elsif status_byte(7 downto 4) = STATUS_PC_MASK then
                                pc_number_reg <= to_unsigned(data_value, pc_number_reg'length);
                                pc_event_reg  <= '1';
                                state         <= WAIT_STATUS;
                            end if;

                        when WAIT_DATA1 =>
                            if status_byte(7 downto 4) = STATUS_CC_MASK then
                                controller_byte <= data_byte;
                                state           <= WAIT_DATA2;
                            elsif status_byte(7 downto 4) = STATUS_PC_MASK then
                                pc_number_reg <= to_unsigned(data_value, pc_number_reg'length);
                                pc_event_reg  <= '1';
                                state         <= WAIT_STATUS;
                            else
                                state <= WAIT_STATUS;
                            end if;

                        when WAIT_DATA2 =>
                            controller := to_integer(unsigned(controller_byte(6 downto 0)));

                            if status_byte(7 downto 4) = STATUS_CC_MASK then
                                cc_number_reg <= to_unsigned(controller, cc_number_reg'length);
                                cc_value_reg  <= to_unsigned(data_value, cc_value_reg'length);
                                cc_event_reg  <= '1';

                                if controller = CC_BIT_DEPTH then
                                    scaled_value := map_bit_depth(data_value);
                                    bit_depth_reg <= to_unsigned(scaled_value, bit_depth_reg'length);
                                elsif controller = CC_DECIMATION then
                                    scaled_value := map_decimation(data_value);
                                    decimation_reg <= to_unsigned(scaled_value, decimation_reg'length);
                                end if;

                                state <= WAIT_DATA1;  -- Expect next data byte or new status for CC running status
                            else
                                state <= WAIT_STATUS;
                            end if;
                    end case;
                end if;
            end if;
        end if;
    end process;

    bit_depth_value  <= bit_depth_reg;
    decimation_value <= decimation_reg;
    cc_event         <= cc_event_reg;
    cc_number        <= cc_number_reg;
    cc_value_raw     <= cc_value_reg;
    pc_event         <= pc_event_reg;
    pc_number        <= pc_number_reg;

end architecture rtl;
