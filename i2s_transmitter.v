// =============================================================================
// i2s_transmitter.v  —  I2S audio output for WM8731 (slave mode)
// =============================================================================
// Clock: CLOCK_50 = 50 MHz
//   BCLK  = 50 MHz / 16  = 3.125 MHz   (toggle at count=7)
//   LRCK  = BCLK  / 64  = 48828.125 Hz (6-bit BCLK counter)
//   AUD_XCK = 50 MHz / 4 = 12.5 MHz    (close to 256*fs; WM8731 slave mode)
//
// I2S frame: 64 BCLK per sample period (32 left + 32 right)
//   Data changes on BCLK falling edge, sampled on rising edge
//   MSB transmitted 1 BCLK after LRCK edge (standard I2S)
//   16-bit audio data, 16-bit zero padding per channel
// =============================================================================

module i2s_transmitter (
    input         clk,          // 50 MHz
    input         rst,          // synchronous reset, active high
    input  [15:0] audio_l,      // left channel  (registered at audio_tick)
    input  [15:0] audio_r,      // right channel (registered at audio_tick)
    output        aud_xck,      // ~12.5 MHz to WM8731 MCLK
    output reg    aud_bclk,     // 3.125 MHz bit clock
    output reg    aud_lrck,     // 48.828 kHz left/right clock
    output reg    aud_dacdat,   // serial data output
    output        audio_tick    // pulses HIGH for 1 clk at start of new frame
);

// ---------------------------------------------------------------------------
// AUD_XCK : divide 50 MHz by 4  →  12.5 MHz
// ---------------------------------------------------------------------------
reg [1:0] xck_cnt;
reg       xck_r;
always @(posedge clk or posedge rst) begin
    if (rst) begin
        xck_cnt <= 2'd0;
        xck_r   <= 1'b0;
    end else begin
        if (xck_cnt == 2'd1) begin
            xck_cnt <= 2'd0;
            xck_r   <= ~xck_r;
        end else begin
            xck_cnt <= xck_cnt + 1'b1;
        end
    end
end
assign aud_xck = xck_r;

// ---------------------------------------------------------------------------
// BCLK : divide 50 MHz by 16  →  3.125 MHz
// ---------------------------------------------------------------------------
reg [3:0] bclk_cnt;
wire      bclk_rise = (bclk_cnt == 4'd7);
wire      bclk_fall = (bclk_cnt == 4'd15);

always @(posedge clk or posedge rst) begin
    if (rst)
        bclk_cnt <= 4'd0;
    else
        bclk_cnt <= bclk_cnt + 1'b1;
end

always @(posedge clk or posedge rst) begin
    if (rst)
        aud_bclk <= 1'b0;
    else if (bclk_rise)
        aud_bclk <= 1'b1;
    else if (bclk_fall)
        aud_bclk <= 1'b0;
end

// ---------------------------------------------------------------------------
// Bit counter : 6-bit, counts BCLK falling edges (0..63)
//   0..31  = left  channel (LRCK=0)
//   32..63 = right channel (LRCK=1)
// ---------------------------------------------------------------------------
reg [5:0] bit_cnt;

always @(posedge clk or posedge rst) begin
    if (rst)
        bit_cnt <= 6'd0;
    else if (bclk_fall)
        bit_cnt <= bit_cnt + 1'b1;
end

// LRCK: low for bits 0-31, high for bits 32-63
// Standard I2S: LRCK changes at bit_cnt==0 and ==32
always @(posedge clk or posedge rst) begin
    if (rst)
        aud_lrck <= 1'b1;
    else if (bclk_fall) begin
        if (bit_cnt == 6'd0)
            aud_lrck <= 1'b0;   // left channel starts
        else if (bit_cnt == 6'd32)
            aud_lrck <= 1'b1;   // right channel starts
    end
end

// audio_tick: fires at bit_cnt==0 so top level can prepare next sample
// We signal one clock before the BCLK fall so data is ready
assign audio_tick = bclk_fall && (bit_cnt == 6'd63);

// ---------------------------------------------------------------------------
// Shift registers — loaded when audio_tick fires
// ---------------------------------------------------------------------------
reg [31:0] shift_l;  // left:  16 data bits + 16 zero padding
reg [31:0] shift_r;

always @(posedge clk or posedge rst) begin
    if (rst) begin
        shift_l <= 32'd0;
        shift_r <= 32'd0;
    end else if (audio_tick) begin
        // Load: data in upper 16 bits, zeros in lower 16
        shift_l <= {audio_l, 16'd0};
        shift_r <= {audio_r, 16'd0};
    end else if (bclk_fall) begin
        // Shift MSB first on each BCLK fall
        if (!aud_lrck)       // left channel (LRCK=0)
            shift_l <= {shift_l[30:0], 1'b0};
        else                  // right channel (LRCK=1)
            shift_r <= {shift_r[30:0], 1'b0};
    end
end

// Output MSB of the currently active channel
always @(posedge clk or posedge rst) begin
    if (rst)
        aud_dacdat <= 1'b0;
    else if (bclk_fall) begin
        if (bit_cnt < 6'd32)
            aud_dacdat <= shift_l[31];
        else
            aud_dacdat <= shift_r[31];
    end
end

endmodule
