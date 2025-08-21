-- ============================================================================
-- AUDIO DSP PROCESSOR - PIPELINE VERSION
-- ============================================================================
-- Clean pipeline implementation for audio DSP processing
-- Author: Group 10: Jon Ashley, Alix Guo, Finn Harvey
-- 16-bit stereo audio at 48kHz sample rate
--
-- PIPELINE STAGES:
-- Stage 0: Input capture and validation
-- Stage 1: Processing preparation  
-- Stage 2: Effect processing (pass-through for now)
-- Stage 3: Output formatting and validation

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity audio_dsp_processor is
    port (
        -- System interface
        clk_audio       : in  std_logic;  -- 12.288MHz audio clock
        reset_n         : in  std_logic;  -- Active low reset
        
        -- Audio input (from ADC)
        audio_in_left   : in  std_logic_vector(15 downto 0);
        audio_in_right  : in  std_logic_vector(15 downto 0);
        audio_in_valid  : in  std_logic;
        
        -- Audio output (to DAC)
        audio_out_left  : out std_logic_vector(15 downto 0);
        audio_out_right : out std_logic_vector(15 downto 0);
        audio_out_valid : out std_logic;
        
        -- Control interface (for future expansion)
        effect_enable   : in  std_logic;  -- Enable/disable effects
        effect_select   : in  std_logic_vector(2 downto 0);  -- Select effect (0-7)
        effect_param    : in  std_logic_vector(7 downto 0)   -- Effect parameter
    );
end entity audio_dsp_processor;

architecture rtl of audio_dsp_processor is

    -- ========================================================================
    -- PIPELINE STAGE SIGNALS
    -- ========================================================================
    
    -- Stage 0: Input Capture
    signal stage0_left      : std_logic_vector(15 downto 0);
    signal stage0_right     : std_logic_vector(15 downto 0);
    signal stage0_valid     : std_logic;
    signal stage0_enable    : std_logic;
    signal stage0_select    : std_logic_vector(2 downto 0);
    signal stage0_param     : std_logic_vector(7 downto 0);
    
    -- Stage 1: Processing Preparation
    signal stage1_left      : std_logic_vector(15 downto 0);
    signal stage1_right     : std_logic_vector(15 downto 0);
    signal stage1_valid     : std_logic;
    signal stage1_enable    : std_logic;
    signal stage1_select    : std_logic_vector(2 downto 0);
    signal stage1_param     : std_logic_vector(7 downto 0);
    
    -- Stage 2: Effect Processing  
    signal stage2_left      : std_logic_vector(15 downto 0);
    signal stage2_right     : std_logic_vector(15 downto 0);
    signal stage2_valid     : std_logic;
    
    -- Stage 3: Output Formatting
    signal stage3_left      : std_logic_vector(15 downto 0);
    signal stage3_right     : std_logic_vector(15 downto 0);
    signal stage3_valid     : std_logic;

    -- ========================================================================
    -- PIPELINE CONTROL SIGNALS
    -- ========================================================================
    
    -- Pipeline enable (can be used for flow control if needed)
    signal pipeline_enable  : std_logic;
    
    -- Sample counting for debugging/monitoring
    signal sample_counter   : unsigned(15 downto 0);

begin

    -- ========================================================================
    -- PIPELINE CONTROL
    -- ========================================================================
    -- For now, pipeline always enabled
    -- In future, this could be used for flow control or backpressure
    pipeline_enable <= '1';

    -- ========================================================================
    -- STAGE 0: INPUT CAPTURE AND VALIDATION
    -- ========================================================================
    -- Capture inputs and control signals synchronously
    -- This stage ensures all inputs are stable and synchronized
    
    process(clk_audio, reset_n)
    begin
        if reset_n = '0' then
            stage0_left     <= (others => '0');
            stage0_right    <= (others => '0');
            stage0_valid    <= '0';
            stage0_enable   <= '0';
            stage0_select   <= (others => '0');
            stage0_param    <= (others => '0');
            sample_counter  <= (others => '0');
        elsif rising_edge(clk_audio) then
            if pipeline_enable = '1' then
                -- Capture audio data
                stage0_left     <= audio_in_left;
                stage0_right    <= audio_in_right;
                stage0_valid    <= audio_in_valid;
                
                -- Capture control signals  
                stage0_enable   <= effect_enable;
                stage0_select   <= effect_select;
                stage0_param    <= effect_param;
                
                -- Count samples for monitoring
                if audio_in_valid = '1' then
                    sample_counter <= sample_counter + 1;
                end if;
            end if;
        end if;
    end process;

    -- ========================================================================
    -- STAGE 1: PROCESSING PREPARATION
    -- ========================================================================
    -- Prepare data for processing, apply any pre-processing
    -- This stage can be used for format conversion, range checking, etc.
    
    process(clk_audio, reset_n)
    begin
        if reset_n = '0' then
            stage1_left     <= (others => '0');
            stage1_right    <= (others => '0');
            stage1_valid    <= '0';
            stage1_enable   <= '0';
            stage1_select   <= (others => '0');
            stage1_param    <= (others => '0');
        elsif rising_edge(clk_audio) then
            if pipeline_enable = '1' then
                -- For now, just pass through with validation
                -- Future: Add input validation, format conversion, etc.
                
                if stage0_valid = '1' then
                    -- Valid sample - pass through
                    stage1_left     <= stage0_left;
                    stage1_right    <= stage0_right;
                    stage1_valid    <= '1';
                else
                    -- Invalid sample - maintain previous or zero
                    stage1_left     <= stage1_left;  -- Hold previous
                    stage1_right    <= stage1_right; -- Hold previous  
                    stage1_valid    <= '0';
                end if;
                
                -- Always pass control signals
                stage1_enable   <= stage0_enable;
                stage1_select   <= stage0_select;
                stage1_param    <= stage0_param;
            end if;
        end if;
    end process;

    -- ========================================================================
    -- STAGE 2: EFFECT PROCESSING
    -- ========================================================================
    -- Main processing stage - effects will be implemented here
    -- For now: Clean pass-through with bypass option
    
    process(clk_audio, reset_n)
    begin
        if reset_n = '0' then
            stage2_left     <= (others => '0');
            stage2_right    <= (others => '0');
            stage2_valid    <= '0';
        elsif rising_edge(clk_audio) then
            if pipeline_enable = '1' then
                -- Pass through audio data
                -- Future: This is where effects will be implemented
                
                if stage1_enable = '1' then
                    -- Effects enabled - for now just pass through
                    stage2_left     <= stage1_left;
                    stage2_right    <= stage1_right;
                else
                    -- Effects bypassed - direct pass through  
                    stage2_left     <= stage1_left;
                    stage2_right    <= stage1_right;
                end if;
                
                stage2_valid    <= stage1_valid;
            end if;
        end if;
    end process;

    -- ========================================================================
    -- STAGE 3: OUTPUT FORMATTING AND VALIDATION
    -- ========================================================================
    -- Final stage - prepare outputs, apply any post-processing
    -- This stage ensures clean, valid outputs
    
    process(clk_audio, reset_n)
    begin
        if reset_n = '0' then
            stage3_left     <= (others => '0');
            stage3_right    <= (others => '0');
            stage3_valid    <= '0';
        elsif rising_edge(clk_audio) then
            if pipeline_enable = '1' then
                -- Final output stage
                stage3_left     <= stage2_left;
                stage3_right    <= stage2_right;
                stage3_valid    <= stage2_valid;
                
                -- Future: Add output limiting, dithering, format conversion
            end if;
        end if;
    end process;

    -- ========================================================================
    -- OUTPUT ASSIGNMENTS
    -- ========================================================================
    -- Connect final pipeline stage to outputs
    
    audio_out_left  <= stage3_left;
    audio_out_right <= stage3_right;
    audio_out_valid <= stage3_valid;

end architecture rtl;
