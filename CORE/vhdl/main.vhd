----------------------------------------------------------------------------------
-- MiSTer2MEGA65 Framework
--
-- Wrapper for the MiSTer core that runs exclusively in the core's clock domanin
--
-- MiSTer2MEGA65 done by sy2002 and MJoergen in 2022 and licensed under GPL v3
----------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.video_modes_pkg.all;

entity main is
   generic (
      G_VDNUM                 : natural                     -- amount of virtual drives
   );
   port (
      clk_main_i              : in  std_logic;
      reset_soft_i            : in  std_logic;
      reset_hard_i            : in  std_logic;
      pause_i                 : in  std_logic;
      dim_video_o             : out std_logic;
      
      ioctl_download          : in  std_logic;
      qnice_dev_id_i          : in  std_logic_vector(15 downto 0);


      -- MiSTer core main clock speed:
      -- Make sure you pass very exact numbers here, because they are used for avoiding clock drift at derived clocks
      clk_main_speed_i        : in  natural;
      
      -- Video output
      video_ce_o              : out std_logic;
      video_ce_ovl_o          : out std_logic;
      video_red_o             : out std_logic_vector(2 downto 0);
      video_green_o           : out std_logic_vector(2 downto 0);
      video_blue_o            : out std_logic_vector(1 downto 0);
      video_vs_o              : out std_logic;
      video_hs_o              : out std_logic;
      video_hblank_o          : out std_logic;
      video_vblank_o          : out std_logic;

      -- Audio output (Signed PCM)
      audio_left_o            : out signed(15 downto 0);
      audio_right_o           : out signed(15 downto 0);

      -- M2M Keyboard interface
      kb_key_num_i            : in  integer range 0 to 79;    -- cycles through all MEGA65 keys
      kb_key_pressed_n_i      : in  std_logic;                -- low active: debounced feedback: is kb_key_num_i pressed right now?

      -- MEGA65 joysticks and paddles/mouse/potentiometers
      joy_1_up_n_i            : in  std_logic;
      joy_1_down_n_i          : in  std_logic;
      joy_1_left_n_i          : in  std_logic;
      joy_1_right_n_i         : in  std_logic;
      joy_1_fire_n_i          : in  std_logic;

      joy_2_up_n_i            : in  std_logic;
      joy_2_down_n_i          : in  std_logic;
      joy_2_left_n_i          : in  std_logic;
      joy_2_right_n_i         : in  std_logic;
      joy_2_fire_n_i          : in  std_logic;

      pot1_x_i                : in  std_logic_vector(7 downto 0);
      pot1_y_i                : in  std_logic_vector(7 downto 0);
      pot2_x_i                : in  std_logic_vector(7 downto 0);
      pot2_y_i                : in  std_logic_vector(7 downto 0);
      
       -- Dipswitches
      dsw_a_i                 : in  std_logic_vector(7 downto 0);
      dsw_b_i                 : in  std_logic_vector(7 downto 0);

      dn_clk_i                : in  std_logic;
      dn_addr_i               : in  std_logic_vector(16 downto 0);
      dn_data_i               : in  std_logic_vector(7 downto 0);
      dn_wr_i                 : in  std_logic;

      
      osm_control_i      : in  std_logic_vector(255 downto 0)
      
   );
end entity main;

architecture synthesis of main is

signal keyboard_n        : std_logic_vector(79 downto 0);
signal pause_cpu         : std_logic;
signal flip              : std_logic := '0';
signal forced_scandoubler: std_logic;
signal gamma_bus         : std_logic_vector(21 downto 0);
signal audio             : std_logic_vector(7 downto 0);
signal speech            : std_logic_vector(15 downto 0);
signal audsum            : std_logic_vector(16 downto 0);

-- I/O board button press simulation ( active high )
-- b[1]: user button
-- b[0]: osd button

signal buttons           : std_logic_vector(1 downto 0);
signal reset             : std_logic  := reset_hard_i or reset_soft_i or ioctl_download;


-- highscore system
signal hs_address       : std_logic_vector(9 downto 0);
signal hs_data_in       : std_logic_vector(7 downto 0);
signal hs_data_out      : std_logic_vector(7 downto 0);
signal hs_write_enable  : std_logic;

signal hs_pause         : std_logic;
signal options          : std_logic_vector(1 downto 0);
signal self_test        : std_logic;

signal blitter_sc2      : std_logic := '0';
signal sinistar         : std_logic := '0';
signal sg_state         : std_logic;

constant C_MENU_OSMPAUSE   : natural := 2;
constant C_MENU_OSMDIM     : natural := 3;
constant C_MENU_FLIP       : natural := 9;
constant C_MENU_CTRL_MODE  : natural := 30;

-- Game player inputs
constant m65_1             : integer := 56; --Player 1 Start
constant m65_2             : integer := 59; --Player 2 Start
constant m65_5             : integer := 16; --Insert coin 1
constant m65_left_shift    : integer := 15; --Left shift

-- Offer some keyboard controls in addition to Joy 1 Controls
constant m65_up_crsr       : integer := 73; --Player up
constant m65_vert_crsr     : integer := 7;  --Player down
constant m65_left_crsr     : integer := 74; --Player left
constant m65_horz_crsr     : integer := 2;  --Player right
constant m65_space         : integer := 60; --Smart Bomb
constant m65_mega          : integer := 61; --Fire
constant m65_ctrl          : integer := 58;
constant m65_z             : integer := 12;
constant m65_x             : integer := 23;

-- Pause, credit button & test mode
constant m65_p             : integer := 41; --Pause button
constant m65_help          : integer := 67; --Help key

signal   mem_addr : std_logic_vector(15 downto 0);
signal   mem_do   : std_logic_vector(7 downto 0);
signal   mem_di   : std_logic_vector(7 downto 0);
signal   mem_we   : std_logic;
signal   ramcs    : std_logic;
signal   ramlb    : std_logic;
signal   ramub    : std_logic;

signal   ram_do   : std_logic_vector(7 downto 0);
signal   rom_do   : std_logic_vector(7 downto 0);

signal   lcnt     : unsigned(10 downto 0);
signal   pcnt     : unsigned(10 downto 0);
signal   old_clk  : std_logic;

signal   old_vs   : std_logic;
signal   old_hs   : std_logic;

signal   ioctl_upload     : std_logic;
signal   ioctl_upload_req : std_logic;

signal m_fire_f   : std_logic;
signal m_up       : std_logic;
signal m_down     : std_logic;
signal m_fire_e   : std_logic;
signal m_right    : std_logic;
signal m_left     : std_logic;
signal m_fire_d   : std_logic;
signal m_fire_c   : std_logic;
signal m_fire_b   : std_logic;
signal m_fire_a   : std_logic;
signal JA         : std_logic_vector(7 downto 0);
signal JB         : std_logic_vector(7 downto 0);

signal condition4 : std_logic;
signal condition7 : std_logic;
signal ioctl_addr : std_logic_vector(15 downto 0);
signal dn_nvram   : std_logic := '0';

begin
   
    audsum <= std_logic_vector(unsigned(audio & "00000000") + unsigned(speech & "0"));
    audio_left_o(15) <= not audio(7);
    audio_left_o(14 downto 0)  <= "0" & signed(audsum(16 downto 3));
    audio_right_o(15) <= not audio(7);
    audio_right_o(14 downto 0) <= "0" & signed(audsum(16 downto 3));
    
    options(0) <= osm_control_i(C_MENU_OSMPAUSE);
    options(1) <= osm_control_i(C_MENU_OSMDIM);
    flip       <= osm_control_i(C_MENU_FLIP);
    
    mem_do <= ram_do when not ramcs else rom_do;
    
    video_ce_o <= pcnt(0); -- 6mhz pixel clock
    
    m_fire_f   <= keyboard_n(m65_z);                            -- Inviso
    m_up       <= keyboard_n(m65_up_crsr) and joy_1_up_n_i;     -- Up
    m_down     <= keyboard_n(m65_vert_crsr) and joy_1_down_n_i; -- Down   
    m_fire_e   <= keyboard_n(m65_ctrl);                         -- Reverse
    m_right    <= keyboard_n(m65_horz_crsr) and joy_1_right_n_i;-- Right
    m_left     <= keyboard_n(m65_left_crsr) and joy_1_left_n_i; -- Left
    m_fire_d   <= keyboard_n(m65_x);                            -- Hyperspace
    m_fire_c   <= keyboard_n(m65_space);                        -- Smart bomb
    m_fire_b   <= keyboard_n(m65_left_shift);                   -- Thrust
    m_fire_a   <= keyboard_n(m65_mega) and joy_1_fire_n_i;      -- Fire 
    
    process(m_fire_e, m_right, m_left, sg_state)
    begin
        if sg_state = '1' then
                condition4 <= m_right;  -- turn right condition
                condition7 <= m_left;   
        else
                condition4 <= m_left;   -- turn left condition
                condition7 <= m_right;
        end if;
    end process;
    
    process(clk_main_i)
    begin 
        if rising_edge(clk_main_i) then
            if osm_control_i(C_MENU_CTRL_MODE) = '0' then
                JA <= m_fire_f & m_up & m_down & m_fire_e & m_fire_d & m_fire_c & m_fire_b & m_fire_a;      -- Mode 1 controls
            else
                JA <= m_fire_f & m_up & m_down & condition4 & m_fire_d & m_fire_c & condition7 & m_fire_a;  -- Mode 2 controls
            end if;
        end if;
    end process;
   
    i_soc : entity work.williams_soc
    port map (
    
    clock       => clk_main_i,
    vgaRed      => video_red_o,
    vgaGreen    => video_green_o,
    vgaBlue     => video_blue_o,
    Hsync       => video_hs_o,
    Vsync       => video_vs_o,
    audio_out   => audio,
    blitter_sc2 => blitter_sc2,
    sinistar    => sinistar,
    sg_state    => sg_state,
    speech_out  => speech,
	BTN         => keyboard_n(m65_2) & keyboard_n(m65_1) & keyboard_n(m65_5) & reset,
    SIN_FIRE    => '0',
    SIN_BOMB    => '0',
    SW          => (others=>'0'),
    JA          => JA,
    JB          => JB,
    MemAdr      => mem_addr,
    MemDin      => mem_di,
    MemDout     => mem_do,
    MemWR       => mem_we,
    RamCS       => ramcs,
    RamLB       => ramlb,
    RamUB       => ramub,
    pause      => pause_cpu or pause_i,
    dl_clock   => dn_clk_i,    
    dl_addr    => dn_addr_i,
    dl_data    => dn_data_i,
    dl_wr      => dn_wr_i and ioctl_download,
    dl_upload  => '0'
 );
 
 -- generate video blanking and pixel clock signals
 process(clk_main_i)  -- 12mhz
        
    begin
        if rising_edge(clk_main_i) then 
        
            if pcnt /= "11111111111" then
                pcnt <= pcnt + 1;
            end if;
    
            old_hs <= video_hs_o;
            if (not old_hs and video_hs_o) then
                pcnt <= (others => '0');
                if lcnt /= "11111111111" then
                    lcnt <= lcnt + 1;
                end if;
    
                old_vs <= video_vs_o;
                if (not old_vs and video_vs_o) then
                    lcnt <= (others => '0');
                end if;
            end if;
    
            if pcnt(10 downto 1) = 336 then
                video_hblank_o <= '1';
            end if;
            
            if pcnt(10 downto 1) = 040 then
                video_hblank_o <= '0';
            end if;
    
            if lcnt = 254 then
                video_vblank_o <= '1';
            end if;
            
            if lcnt = 14 then
                video_vblank_o <= '0';
            end if;
            
         end if;
    end process;
    
    process(dn_clk_i)
    begin
        if falling_edge(dn_clk_i) then 
            if qnice_dev_id_i =  x"0101" then
                dn_nvram <= '1';
            else
                dn_nvram <= '0';
            end if;
            ioctl_addr <= dn_addr_i(15 downto 0) when ioctl_download = '1' else ("000000" & hs_address);
        end if;  
    end process;
    
    
  i_ram : entity work.williams_ram
     port map (
        CLK    => not clk_main_i,
        ENL    => not ramlb,
        ENH    => not ramub,
        WE     => not ramcs and not mem_we,
        ADDR   => mem_addr,
        DI     => mem_di,
        DO     => ram_do,
    
        dn_clock => dn_clk_i,
        dn_addr  => ioctl_addr,
        dn_data  => dn_data_i,
        dn_wr    => dn_wr_i and ioctl_download,
        dn_din   => hs_data_out,
        dn_nvram => dn_nvram
     );
     
     
      
 i_hi : entity work.nvram
 generic map 
 (
    DUMPWIDTH => 10,
	DUMPINDEX => 4,
	PAUSEPAD  => 2
 )
 port map(
	
	reset              => reset,
	ioctl_upload       => '0', -- to do later
	ioctl_download     => ioctl_download,
	ioctl_wr           => dn_wr_i,
	ioctl_addr         => dn_addr_i,
	ioctl_dout         => dn_data_i,
	ioctl_index        => (others=>'0'),
	OSD_STATUS         => '0', -- to do
	clk                => clk_main_i,
	paused             => pause_cpu,
	autosave           => '1',  -- to do later
	nvram_address      => hs_address,
	nvram_data_out     => hs_data_out,
	pause_cpu          => hs_pause
);
 

 
	cpu_prog_rom : entity work.dualport_2clk_ram
	generic map 
    (
        FALLING_B    => TRUE,
        ADDR_WIDTH   => 17,
        DATA_WIDTH   => 8
    )
	port map
	(
		clock_a   => not clk_main_i,
		address_a => '0' & mem_addr(15) & (not mem_addr(15) and mem_addr(14)) & mem_addr(13 downto 0),
		q_a       => rom_do,
		
		clock_b   => dn_clk_i,
		address_b => dn_addr_i(16 downto 0),
		data_b    => dn_data_i,
		wren_b    => dn_wr_i and ioctl_download
	);
 
    
    i_pause : entity work.pause
     generic map (
     
        RW  => 3,
        GW  => 3,
        BW  => 2,
        CLKSPD => 12
        
     )         
     port map (
     
         clk_sys        => clk_main_i,
         reset          => reset,
         user_button    => keyboard_n(m65_p),
         pause_request  => hs_pause,
         options        => options,  -- not status(11 downto 10), - TODO, hookup to OSD.
         OSD_STATUS     => '0',       -- disabled for now - TODO, to OSD
         r              => video_red_o,
         g              => video_green_o,
         b              => video_blue_o,
         pause_cpu      => pause_cpu,
         dim_video      => dim_video_o
         --rgb_out        TODO
         
      );
      
   -- @TODO: Keyboard mapping and keyboard behavior
   -- Each core is treating the keyboard in a different way: Some need low-active "matrices", some
   -- might need small high-active keyboard memories, etc. This is why the MiSTer2MEGA65 framework
   -- lets you define literally everything and only provides a minimal abstraction layer to the keyboard.
   -- You need to adjust keyboard.vhd to your needs
   i_keyboard : entity work.keyboard
      port map (
         clk_main_i           => clk_main_i,

         -- Interface to the MEGA65 keyboard
         key_num_i            => kb_key_num_i,
         key_pressed_n_i      => kb_key_pressed_n_i,

         example_n_o          => keyboard_n
      ); -- i_keyboard

end architecture synthesis;

