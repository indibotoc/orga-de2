// =============================================================================
// effects.v  —  Effects chain: distortion → reverb
// =============================================================================
// SW[14] = reverb_en    (0=off, 1=on)
// SW[15] = distort_en   (0=off, 1=on)
//
// Distortion: hard clip — reduces amplitude by 4 then clips at threshold.
// This adds harmonic saturation similar to an overdriven amplifier.
// =============================================================================

module effects (
    input         clk,
    input         rst,
    input         audio_tick,
    input  [15:0] audio_in,
    input         reverb_en,
    input         distort_en,
    output [15:0] audio_out
);

// ---------------------------------------------------------------------------
// Stage 1: Distortion (hard clipping)
// ---------------------------------------------------------------------------
localparam signed [15:0] CLIP_THRESH = 16'sd8192;  // ±25% of full scale

wire signed [15:0] in_s = audio_in;

// Boost × 4, then hard-clip
wire signed [17:0] boosted = {{2{in_s[15]}}, in_s} <<< 2;
wire signed [15:0] clipped = (boosted >  18'sd8192) ?  CLIP_THRESH :
                             (boosted < -18'sd8192) ? -CLIP_THRESH :
                             boosted[15:0];

wire [15:0] after_dist = distort_en ? clipped : audio_in;

// ---------------------------------------------------------------------------
// Stage 2: Reverb
// ---------------------------------------------------------------------------
wire [15:0] after_reverb;

reverb u_reverb (
    .clk        (clk),
    .rst        (rst),
    .en         (reverb_en),
    .audio_tick (audio_tick),
    .audio_in   (after_dist),
    .audio_out  (after_reverb)
);

assign audio_out = after_reverb;

endmodule
