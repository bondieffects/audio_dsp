-- MIDI Message Parser
-- Parses MIDI Program Change and Control Change messages
-- Maps to DSP parameters: bit_depth, sample_decimate, master_volume
-- Author: Group 10

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity midi_parser is
    port (
        clk         : in  std_logic;
        reset_n     : in  std_logic;
        
        -- MIDI data input
        midi_data   : in  std_logic_vector(7 downto 0);
        midi_valid  : in  std_logic;
        
        -- DSP parameter outputs
        bitcrush_depth   : out std_logic_vector(3 downto 0);  -- 0-15 (0=no crush, 15=1-bit)
        sample_decimate  : out std_logic_vector(3 downto 0);  -- 0-15 (0=no decimation)
        master_volume    : out std_logic_vector(7 downto 0);  -- 0-255 (volume control)
        
        -- Status outputs
        param_updated    : out std_logic;  -- Pulse when parameter changes
        midi_channel     : out std_logic_vector(3 downto 0)   -- Current MIDI channel
    );
end entity midi_parser;

architecture rtl of midi_parser is
    
    -- MIDI message types
    constant MSG_PROGRAM_CHANGE : std_logic_vector(3 downto 0) := x"C";
    constant MSG_CONTROL_CHANGE : std_logic_vector(3 downto 0) := x"B";
    
    -- MIDI Control Change numbers for our parameters
    constant CC_BITCRUSH_DEPTH  : std_logic_vector(6 downto 0) := "0000001";  -- CC #1
    constant CC_SAMPLE_DECIMATE : std_logic_vector(6 downto 0) := "0000010";  -- CC #2  
    constant CC_MASTER_VOLUME   : std_logic_vector(6 downto 0) := "0000111";  -- CC #7 (standard volume)
    
    -- Program Change mappings for quick preset selection
    constant PC_CLEAN          : std_logic_vector(6 downto 0) := "0000000";  -- PC #0
    constant PC_LIGHT_CRUSH    : std_logic_vector(6 downto 0) := "0000001";  -- PC #1
    constant PC_MEDIUM_CRUSH   : std_logic_vector(6 downto 0) := "0000010";  -- PC #2
    constant PC_HEAVY_CRUSH    : std_logic_vector(6 downto 0) := "0000011";  -- PC #3
    constant PC_RETRO_LOFI     : std_logic_vector(6 downto 0) := "0000100";  -- PC #4
    
    -- Parser state machine
    type parser_state_t is (WAIT_STATUS, WAIT_DATA1, WAIT_DATA2);
    signal state : parser_state_t := WAIT_STATUS;
    
    -- Internal registers
    signal status_byte    : std_logic_vector(7 downto 0);
    signal data_byte1     : std_logic_vector(7 downto 0);
    signal current_channel: std_logic_vector(3 downto 0) := x"0";
    
    -- Parameter registers with default values
    signal bitcrush_reg   : std_logic_vector(3 downto 0) := x"F";  -- No crushing
    signal decimate_reg   : std_logic_vector(3 downto 0) := x"0";  -- No decimation
    signal volume_reg     : std_logic_vector(7 downto 0) := x"7F"; -- Mid volume
    
begin
    
    -- Output assignments
    bitcrush_depth <= bitcrush_reg;
    sample_decimate <= decimate_reg;
    master_volume <= volume_reg;
    midi_channel <= current_channel;
    
    -- MIDI message parser
    parser_process : process(clk, reset_n)
        variable msg_type : std_logic_vector(3 downto 0);
        variable channel  : std_logic_vector(3 downto 0);
        variable cc_num   : std_logic_vector(6 downto 0);
        variable cc_val   : std_logic_vector(6 downto 0);
        variable pc_num   : std_logic_vector(6 downto 0);
    begin
        if reset_n = '0' then
            state <= WAIT_STATUS;
            status_byte <= (others => '0');
            data_byte1 <= (others => '0');
            current_channel <= x"0";
            bitcrush_reg <= x"F";   -- No crushing by default
            decimate_reg <= x"0";   -- No decimation by default
            volume_reg <= x"7F";    -- Mid volume by default
            param_updated <= '0';
            
        elsif rising_edge(clk) then
            param_updated <= '0';  -- Default
            
            if midi_valid = '1' then
                case state is
                    when WAIT_STATUS =>
                        -- Check if this is a status byte (MSB = 1)
                        if midi_data(7) = '1' then
                            status_byte <= midi_data;
                            msg_type := midi_data(7 downto 4);
                            channel := midi_data(3 downto 0);
                            current_channel <= channel;
                            
                            -- Determine next state based on message type
                            if msg_type = MSG_PROGRAM_CHANGE then
                                state <= WAIT_DATA1;  -- PC needs 1 data byte
                            elsif msg_type = MSG_CONTROL_CHANGE then
                                state <= WAIT_DATA1;  -- CC needs 2 data bytes
                            else
                                state <= WAIT_STATUS;  -- Ignore other message types
                            end if;
                        end if;
                    
                    when WAIT_DATA1 =>
                        -- First data byte
                        data_byte1 <= midi_data;
                        msg_type := status_byte(7 downto 4);
                        
                        if msg_type = MSG_PROGRAM_CHANGE then
                            -- Program Change - process immediately
                            pc_num := midi_data(6 downto 0);
                            
                            case pc_num is
                                when PC_CLEAN =>        -- Clean preset
                                    bitcrush_reg <= x"F";  -- No crushing
                                    decimate_reg <= x"0";  -- No decimation
                                    volume_reg <= x"7F";   -- Mid volume
                                    param_updated <= '1';
                                    
                                when PC_LIGHT_CRUSH =>  -- Light crush preset
                                    bitcrush_reg <= x"C";  -- Light crushing (12-bit)
                                    decimate_reg <= x"1";  -- Light decimation
                                    volume_reg <= x"7F";   -- Mid volume
                                    param_updated <= '1';
                                    
                                when PC_MEDIUM_CRUSH => -- Medium crush preset
                                    bitcrush_reg <= x"8";  -- Medium crushing (8-bit)
                                    decimate_reg <= x"2";  -- Medium decimation
                                    volume_reg <= x"7F";   -- Mid volume
                                    param_updated <= '1';
                                    
                                when PC_HEAVY_CRUSH =>  -- Heavy crush preset
                                    bitcrush_reg <= x"4";  -- Heavy crushing (4-bit)
                                    decimate_reg <= x"4";  -- Heavy decimation
                                    volume_reg <= x"6F";   -- Slightly lower volume
                                    param_updated <= '1';
                                    
                                when PC_RETRO_LOFI =>   -- Retro lo-fi preset
                                    bitcrush_reg <= x"2";  -- Very heavy crushing (2-bit)
                                    decimate_reg <= x"6";  -- High decimation
                                    volume_reg <= x"5F";   -- Lower volume
                                    param_updated <= '1';
                                    
                                when others =>
                                    -- Ignore unknown program numbers
                                    null;
                            end case;
                            
                            state <= WAIT_STATUS;
                            
                        elsif msg_type = MSG_CONTROL_CHANGE then
                            state <= WAIT_DATA2;  -- Need second data byte for CC
                        else
                            state <= WAIT_STATUS;
                        end if;
                    
                    when WAIT_DATA2 =>
                        -- Second data byte (for Control Change)
                        cc_num := data_byte1(6 downto 0);
                        cc_val := midi_data(6 downto 0);
                        
                        case cc_num is
                            when CC_BITCRUSH_DEPTH =>
                                -- Map CC value (0-127) to bit depth (15-0)
                                -- Higher CC value = more crushing (fewer bits)
                                bitcrush_reg <= std_logic_vector(15 - unsigned(cc_val(6 downto 3)));
                                param_updated <= '1';
                                
                            when CC_SAMPLE_DECIMATE =>
                                -- Map CC value (0-127) to decimation (0-15)
                                bitcrush_reg <= cc_val(6 downto 3);  -- Use upper 4 bits
                                param_updated <= '1';
                                
                            when CC_MASTER_VOLUME =>
                                -- Map CC value (0-127) to volume (0-255)
                                volume_reg <= cc_val & '0';  -- Multiply by 2 to get 0-254 range
                                param_updated <= '1';
                                
                            when others =>
                                -- Ignore unknown CC numbers
                                null;
                        end case;
                        
                        state <= WAIT_STATUS;
                end case;
            end if;
        end if;
    end process;
    
end architecture rtl;