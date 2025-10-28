library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

-- ============================================================================
-- MIDI Parser (Control Change Only)
-- ============================================================================
-- Parses incoming MIDI byte stream from midi_uart_rx and extracts Control 
-- Change (CC) messages for audio DSP control. Implements a simple 3-state
-- state machine that decodes MIDI Control Change messages.
--
-- Targeted MIDI Messages:
--   - Control Change #20: Bit depth parameter (0-127 → 1-16 bits)
--   - Control Change #21: Sample rate decimation (0-127 → 1-64x)
--
-- Features:
--   - Running status support (omitted status bytes reuse previous)
--   - Automatic parameter scaling to hardware-appropriate ranges
-- ============================================================================
entity midi_parser is
    port (
        -- ====================================================================
        -- System Interface
        -- ====================================================================
        clk                : in  std_logic;                      -- 50 MHz system clock
        reset_n            : in  std_logic;                      -- Active-low async reset
        
        -- ====================================================================
        -- UART Receiver Interface
        -- ====================================================================
        data_byte          : in  std_logic_vector(7 downto 0);   -- Received MIDI byte
        data_valid         : in  std_logic;                      -- Single-cycle strobe for new byte
        
        -- ====================================================================
        -- Audio DSP Parameters (continuously held)
        -- ====================================================================
        bit_depth_value    : out unsigned(4 downto 0);           -- Bitcrusher depth: 1-16 bits
        decimation_value   : out unsigned(6 downto 0);           -- Sample rate reduction: 1-64x
        
        -- ====================================================================
        -- Generic MIDI CC Event Outputs (single-cycle strobes)
        -- ====================================================================
        cc_event           : out std_logic;                      -- Control Change received pulse
        cc_number          : out unsigned(6 downto 0);           -- CC controller number (0-127)
        cc_value_raw       : out unsigned(6 downto 0)            -- CC value unscaled (0-127)
    );
end entity midi_parser;

architecture rtl of midi_parser is
    -- ========================================================================
    -- State Machine Definition
    -- ========================================================================
    -- WAIT_STATUS : Awaiting a Control Change status byte (or using running status)
    -- WAIT_DATA1  : Expecting controller number (first data byte)
    -- WAIT_DATA2  : Expecting controller value (second data byte)
    type parser_state_t is (WAIT_STATUS, WAIT_DATA1, WAIT_DATA2);
    
    -- ========================================================================
    -- Parser State Registers
    -- ========================================================================
    signal state           : parser_state_t := WAIT_STATUS;
    signal controller_byte : std_logic_vector(6 downto 0) := (others => '0'); -- CC number (data byte 1)

    -- ========================================================================
    -- Audio Processing Parameter Registers
    -- ========================================================================
    signal bit_depth_reg   : unsigned(4 downto 0) := to_unsigned(3, 5);  -- Power-on: 3-bit depth
    signal decimation_reg  : unsigned(6 downto 0) := to_unsigned(2, 7);  -- Power-on: 2x decimation

    -- ========================================================================
    -- MIDI CC Event Output Registers
    -- ========================================================================
    signal cc_event_reg    : std_logic := '0';                           -- CC event strobe
    signal cc_number_reg   : unsigned(6 downto 0) := (others => '0');    -- Last CC number
    signal cc_value_reg    : unsigned(6 downto 0) := (others => '0');    -- Last CC value

    -- ========================================================================
    -- MIDI Message Type Constants
    -- ========================================================================
    -- MIDI Control Change status byte: 0xBn (where n = MIDI channel 0-15)
    -- Upper nibble = 0xB, lower nibble = channel
    constant STATUS_CC_MASK  : std_logic_vector(3 downto 0) := "1011";  -- 0xB_ Control Change
    
    -- ========================================================================
    -- Application-Specific CC Assignments
    -- ========================================================================
    constant CC_BIT_DEPTH    : integer := 20;  -- CC#20 controls bitcrusher depth
    constant CC_DECIMATION   : integer := 21;  -- CC#21 controls sample rate decimation

    -- ========================================================================
    -- Parameter Scaling Functions
    -- ========================================================================
    -- Convert MIDI's 7-bit data range (0-127) to hardware-specific ranges
    -- with appropriate quantization steps for smooth control.
    
    -- Maps MIDI value 0-127 to bit depth 1-16 (quantized in 8-step buckets)
    -- Examples: 0-7→1, 8-15→2, 16-23→3, ... 120-127→16
    function map_bit_depth(val : integer) return integer is
        variable result : integer;
    begin
        result := (val / 8) + 1;  -- Divide into 16 steps (128/8 = 16)
        if result < 1 then
            result := 1;           -- Clamp minimum
        elsif result > 16 then
            result := 16;          -- Clamp maximum
        end if;
        return result;
    end function;

    -- Maps MIDI value 0-127 to decimation factor 1-64 (quantized in 2-step buckets)
    -- Examples: 0-1→1, 2-3→2, 4-5→3, ... 126-127→64
    function map_decimation(val : integer) return integer is
        variable result : integer;
    begin
        result := (val / 2) + 1;  -- Divide into 64 steps (128/2 = 64)
        if result < 1 then
            result := 1;           -- Clamp minimum
        elsif result > 64 then
            result := 64;          -- Clamp maximum
        end if;
        return result;
    end function;

begin
    -- ========================================================================
    -- MIDI Control Change Parser State Machine
    -- ========================================================================
    -- Decodes Control Change messages from the MIDI byte stream.
    -- 
    -- MIDI Control Change Message Structure:
    --   [Status 0xBn][Controller# 0-127][Value 0-127]
    --   - Status byte: MSB=1, upper nibble=0xB, lower nibble=channel
    --   - Data bytes: MSB=0, 7-bit value (0-127)
    --
    -- Running Status Support:
    --   After a CC status is received, subsequent controller/value pairs
    --   can be sent without repeating the status byte.
    process(clk, reset_n)
        variable data_is_status : boolean;   -- True if byte has MSB=1 (status byte)
        variable data_value     : integer;   -- Data byte value (lower 7 bits)
        variable controller     : integer;   -- CC controller number
        variable scaled_value   : integer;   -- Mapped parameter value for DSP
    begin
        if reset_n = '0' then
            state           <= WAIT_STATUS;
            controller_byte <= (others => '0');
            bit_depth_reg   <= to_unsigned(3, 5);
            decimation_reg  <= to_unsigned(2, 7);
            cc_event_reg    <= '0';
            cc_number_reg   <= (others => '0');
            cc_value_reg    <= (others => '0');
        elsif rising_edge(clk) then
            -- Clear event strobe by default (only high for 1 cycle per CC message)
            cc_event_reg <= '0';

            if data_valid = '1' then
                -- Check if incoming byte is a status byte (MSB=1) or data byte (MSB=0)
                data_is_status := (data_byte(7) = '1');

                if data_is_status then
                    -- ========================================================
                    -- STATUS BYTE RECEIVED
                    -- ========================================================
                    if data_byte(7 downto 4) = STATUS_CC_MASK then
                        -- Control Change status byte (0xBn): expect controller# next
                        state <= WAIT_DATA1;
                    else
                        -- Non-CC status byte: ignore and wait for CC status
                        state <= WAIT_STATUS;
                    end if;
                else
                    -- ========================================================
                    -- DATA BYTE RECEIVED
                    -- ========================================================
                    -- Extract 7-bit value (ignore MSB which is always 0 for data)
                    data_value := to_integer(unsigned(data_byte(6 downto 0)));

                    case state is
                        -- ====================================================
                        -- WAIT_STATUS: Running Status Mode
                        -- ====================================================
                        -- In running status mode, we receive data bytes without
                        -- a new status byte. Assume it's a controller number.
                        when WAIT_STATUS =>
                            controller_byte <= data_byte(6 downto 0);  -- Store controller number
                            state           <= WAIT_DATA2;             -- Wait for value byte

                        -- ====================================================
                        -- WAIT_DATA1: First Data Byte (Controller Number)
                        -- ====================================================
                        when WAIT_DATA1 =>
                            controller_byte <= data_byte(6 downto 0);  -- Store controller number
                            state           <= WAIT_DATA2;             -- Wait for value byte

                        -- ====================================================
                        -- WAIT_DATA2: Second Data Byte (Controller Value)
                        -- ====================================================
                        when WAIT_DATA2 =>
                            controller := to_integer(unsigned(controller_byte));

                            -- Complete Control Change message received
                            -- Output raw CC event for any downstream processing
                            cc_number_reg <= unsigned(controller_byte);
                            cc_value_reg  <= to_unsigned(data_value, cc_value_reg'length);
                            cc_event_reg  <= '1';  -- Pulse event output for one cycle

                            -- Check if this CC# controls our specific audio parameters
                            if controller = CC_BIT_DEPTH then
                                -- CC#20: Scale 0-127 to 1-16 bit depth
                                scaled_value := map_bit_depth(data_value);
                                bit_depth_reg <= to_unsigned(scaled_value, bit_depth_reg'length);
                            elsif controller = CC_DECIMATION then
                                -- CC#21: Scale 0-127 to 1-64 decimation factor
                                scaled_value := map_decimation(data_value);
                                decimation_reg <= to_unsigned(scaled_value, decimation_reg'length);
                            end if;

                            -- After CC completion, expect next controller# (running status)
                            -- or new status byte
                            state <= WAIT_DATA1;
                    end case;
                end if;
            end if;
        end if;
    end process;

    -- ========================================================================
    -- Output Assignment
    -- ========================================================================
    -- Drive output ports with internal registers
    bit_depth_value  <= bit_depth_reg;   -- Continuously held: current bit depth (1-16)
    decimation_value <= decimation_reg;  -- Continuously held: current decimation (1-64)
    cc_event         <= cc_event_reg;    -- Single-cycle pulse when CC received
    cc_number        <= cc_number_reg;   -- Last CC controller number (0-127)
    cc_value_raw     <= cc_value_reg;    -- Last CC value unscaled (0-127)

end architecture rtl;
