// =============================================================================
// reverb.v  —  Simple echo/reverb using on-chip block RAM delay line
// =============================================================================
// Implements a feedback delay line:
//   output = input + feedback × delayed_input
//
// Delay depth: 4096 samples × 16 bits = 8 KB of block RAM
//   At 48828 Hz: 4096 / 48828 ≈ 83.9 ms delay
//
// Feedback gain: 0.5 (shift right by 1) — adjust FEEDBACK_SHIFT as desired
// Wet/dry mix: 50/50 (wet = 50%, dry = 50%)
//
// Block RAM is inferred by Quartus from the synchronous read-write pattern.
// Cyclone II has 105 × M4K (4Kbit) blocks → 4096 samples easily fit.
// =============================================================================

module reverb (
    input         clk,
    input         rst,
    input         en,           // reverb enable
    input         audio_tick,   // 48828 Hz sample clock
    input  [15:0] audio_in,     // signed 16-bit input
    output [15:0] audio_out     // signed 16-bit output
);

localparam DEPTH          = 4096;   // samples in delay line
localparam ADDR_BITS      = 12;
localparam FEEDBACK_SHIFT = 1;      // multiply feedback by 0.5 (>>1)

// ---------------------------------------------------------------------------
// Circular buffer (block RAM)
// ---------------------------------------------------------------------------
reg [15:0] delay_mem [0:DEPTH-1];
reg [ADDR_BITS-1:0] wr_ptr;
reg [ADDR_BITS-1:0] rd_ptr;   // = wr_ptr (read oldest = full delay)

wire [ADDR_BITS-1:0] rd_addr = wr_ptr;  // read before write → DEPTH samples ago

// Read (async; Quartus may use registers here — timing is fine at 48828 Hz)
wire signed [15:0] delayed = delay_mem[rd_addr];

// Write: input + feedback from delayed signal
wire signed [15:0] in_s      = audio_in;
wire signed [16:0] feedback  = {{1{delayed[15]}}, delayed} >>> FEEDBACK_SHIFT;
wire signed [17:0] mixed_wr  = {{2{in_s[15]}},  in_s} + {{1{feedback[16]}}, feedback};
// Saturate to 16 bits
wire signed [15:0] write_val = (mixed_wr > 18'sd32767)  ? 16'h7FFF :
                               (mixed_wr < -18'sd32768)  ? 16'h8000 :
                               mixed_wr[15:0];

always @(posedge clk or posedge rst) begin
    if (rst) begin
        wr_ptr <= {ADDR_BITS{1'b0}};
    end else if (audio_tick) begin
        delay_mem[wr_ptr] <= write_val;
        wr_ptr <= wr_ptr + 1'b1;  // wraps automatically
    end
end

// ---------------------------------------------------------------------------
// Wet/dry mix: output = 0.5×dry + 0.5×wet
// ---------------------------------------------------------------------------
wire signed [15:0] dry = audio_in;
wire signed [15:0] wet = delayed;
wire signed [16:0] mix = {{1{dry[15]}}, dry} + {{1{wet[15]}}, wet}; // sum
wire signed [15:0] mix16 = mix[16:1]; // divide by 2

assign audio_out = en ? mix16 : audio_in;

endmodule
