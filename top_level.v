// =============================================================================
// top_level.v  —  DE2 Electronic Organ  (top-level module)
// =============================================================================
//
// INTERFACE SUMMARY
// -----------------
// SW[11:0]  Piano keys : C C# D D# E F F# G G# A A# B  (play chord: hold multiple)
// SW[13:12] Instrument : 00=Organ(sine)  01=Harp(sawtooth)
//                        10=Flute(triangle) 11=PipeOrgan(harmonics)
// SW[14]    Reverb ON/OFF
// SW[15]    Distortion ON/OFF
// SW[16]    Octave DOWN  (one octave below middle)
// SW[17]    Octave UP    (one octave above middle)
//           (both OFF = middle octave 4)
//
// KEY[0]    Reset (active low)
// KEY[1]    Rhythm/Metronome toggle (press to ON, press again to OFF)
// KEY[2]    Sustain pedal (hold to keep notes ringing)
// KEY[3]    (reserved)
//
// LEDR[11:0]  = active note indicators
// LEDR[13:12] = selected instrument
// LEDR[14]    = reverb active
// LEDR[15]    = distortion active
// LEDR[16]    = octave down
// LEDR[17]    = octave up
// LEDG[0]     = rhythm enabled
// LEDG[1]     = beat flash (blinks every beat)
// =============================================================================

module top_level (
    input        CLOCK_50,
    input [17:0] SW,
    input  [3:0] KEY,

    // Red / Green LEDs
    output [17:0] LEDR,
    output  [8:0] LEDG,

    // 7-segment displays (show instrument name)
    output  [6:0] HEX0, HEX1, HEX2, HEX3,

    // WM8731 Audio Codec
    output        AUD_XCK,
    inout         AUD_BCLK,
    output        AUD_DACLRCK,
    output        AUD_DACDAT,
    input         AUD_ADCDAT,
    inout         AUD_ADCLRCK,

    // I2C (codec configuration)
    output        I2C_SCLK,
    inout         I2C_SDAT
);

// ---------------------------------------------------------------------------
// Reset & control signals
// ---------------------------------------------------------------------------
wire rst   = ~KEY[0];   // KEY[0] active-low → rst active-high
wire sustain = ~KEY[2]; // KEY[2] active-low → sustain active-high

// Octave: 1=low, 2=middle(default), 3=high
// SW[17] and SW[16] are mutually prioritised (UP wins over DOWN)
wire [1:0] octave = SW[17] ? 2'd3 :
                   SW[16]  ? 2'd1 : 2'd2;

wire [1:0] instrument = SW[13:12];
wire       reverb_en  = SW[14];
wire       distort_en = SW[15];

// ---------------------------------------------------------------------------
// Rhythm: KEY[1] toggles ON/OFF on falling edge (button press)
// ---------------------------------------------------------------------------
reg [1:0] key1_sync;
reg       rhythm_on;

always @(posedge CLOCK_50 or posedge rst) begin
    if (rst) begin
        key1_sync <= 2'b11;
        rhythm_on <= 1'b0;
    end else begin
        key1_sync <= {key1_sync[0], KEY[1]};
        if (key1_sync == 2'b10)     // falling edge detected
            rhythm_on <= ~rhythm_on;
    end
end

// ---------------------------------------------------------------------------
// Sustain: latch notes that were held when sustain was engaged
// ---------------------------------------------------------------------------
wire [11:0] notes_raw = SW[11:0];
reg  [11:0] notes_held;

always @(posedge CLOCK_50 or posedge rst) begin
    if (rst)
        notes_held <= 12'b0;
    else if (sustain)
        notes_held <= notes_held | notes_raw;  // latch on
    else
        notes_held <= 12'b0;                   // release
end

wire [11:0] notes_active = notes_raw | notes_held;

// ---------------------------------------------------------------------------
// Audio sample-rate tick (from I2S transmitter)
// ---------------------------------------------------------------------------
wire        audio_tick;
wire [15:0] final_audio;

// ---------------------------------------------------------------------------
// 12 DDS oscillators — generated with genvar
// ---------------------------------------------------------------------------
wire [191:0] osc_bus;    // 12 × 16 bits flat
wire [11:0]  osc_valid;

genvar i;
generate
    for (i = 0; i < 12; i = i + 1) begin : osc_gen
        wire [31:0] freq_word;

        note_freq_table u_freq (
            .note      (i[3:0]),
            .octave    (octave),
            .freq_word (freq_word)
        );

        dds_oscillator u_dds (
            .clk        (CLOCK_50),
            .rst        (rst),
            .en         (notes_active[i]),
            .audio_tick (audio_tick),
            .freq_word  (freq_word),
            .instrument (instrument),
            .audio_out  (osc_bus[i*16 +: 16])
        );

        assign osc_valid[i] = notes_active[i];
    end
endgenerate

// ---------------------------------------------------------------------------
// Chord mixer
// ---------------------------------------------------------------------------
wire [15:0] mixed_audio;

chord_mixer u_mixer (
    .osc_bus   (osc_bus),
    .valid     (osc_valid),
    .audio_out (mixed_audio)
);

// ---------------------------------------------------------------------------
// Effects chain (distortion → reverb)
// ---------------------------------------------------------------------------
wire [15:0] fx_audio;

effects u_fx (
    .clk        (CLOCK_50),
    .rst        (rst),
    .audio_tick (audio_tick),
    .audio_in   (mixed_audio),
    .reverb_en  (reverb_en),
    .distort_en (distort_en),
    .audio_out  (fx_audio)
);

// ---------------------------------------------------------------------------
// Rhythm generator
// ---------------------------------------------------------------------------
wire [15:0] rhythm_audio;
wire        beat_pulse;

rhythm_gen u_rhythm (
    .clk        (CLOCK_50),
    .rst        (rst),
    .en         (rhythm_on),
    .audio_tick (audio_tick),
    .audio_out  (rhythm_audio),
    .beat       (beat_pulse)
);

// Mix rhythm with instrument (50%/50% when rhythm on)
wire signed [16:0] mix_sum = {{1{fx_audio[15]}},     fx_audio}
                           + {{1{rhythm_audio[15]}},  rhythm_audio};
wire [15:0] mix_half = mix_sum[16:1];  // divide by 2

assign final_audio = rhythm_on ? mix_half : fx_audio;

// ---------------------------------------------------------------------------
// WM8731 I2C initialisation
// ---------------------------------------------------------------------------
wm8731_i2c_ctrl u_i2c (
    .clk     (CLOCK_50),
    .rst     (rst),
    .i2c_scl (I2C_SCLK),
    .i2c_sda (I2C_SDAT)
);

// ---------------------------------------------------------------------------
// I2S transmitter  (generates AUD_XCK, AUD_BCLK, AUD_DACLRCK, AUD_DACDAT)
// ---------------------------------------------------------------------------
i2s_transmitter u_i2s (
    .clk        (CLOCK_50),
    .rst        (rst),
    .audio_l    (final_audio),
    .audio_r    (final_audio),   // mono: same on both channels
    .aud_xck    (AUD_XCK),
    .aud_bclk   (AUD_BCLK),
    .aud_lrck   (AUD_DACLRCK),
    .aud_dacdat (AUD_DACDAT),
    .audio_tick (audio_tick)
);

assign AUD_ADCLRCK = AUD_DACLRCK;  // tie ADC LR clock to DAC (unused)

// ---------------------------------------------------------------------------
// LED indicators
// ---------------------------------------------------------------------------
assign LEDR[11:0] = notes_active;   // active notes
assign LEDR[13:12] = instrument;    // instrument
assign LEDR[14]    = reverb_en;
assign LEDR[15]    = distort_en;
assign LEDR[16]    = SW[16];        // octave down
assign LEDR[17]    = SW[17];        // octave up

assign LEDG[0]    = rhythm_on;      // rhythm enabled
assign LEDG[1]    = beat_pulse;     // beat flash
assign LEDG[8:2]  = 7'd0;

// ---------------------------------------------------------------------------
// 7-segment display: instrument name (crude single-digit code on HEX0)
// Segments: gfedcba (active low)
// Display:  0=0  1=1  2=2  3=3  on HEX0; blank others
// ---------------------------------------------------------------------------
// seg7 lookup for digits 0..3
function [6:0] seg7;
    input [1:0] d;
    case (d)
        2'd0: seg7 = 7'b1000000;  // "0"
        2'd1: seg7 = 7'b1111001;  // "1"
        2'd2: seg7 = 7'b0100100;  // "2"
        2'd3: seg7 = 7'b0110000;  // "3"
    endcase
endfunction

assign HEX0 = seg7(instrument);  // shows 0/1/2/3
assign HEX1 = 7'b1111111;        // blank
assign HEX2 = 7'b1111111;        // blank
assign HEX3 = 7'b1111111;        // blank

endmodule
