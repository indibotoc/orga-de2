// =============================================================================
// chord_mixer.v  —  Mixes up to 12 simultaneous DDS oscillator outputs
// =============================================================================
// Each oscillator outputs a signed 16-bit sample (stored as unsigned 16-bit).
// The mixer sums all active (non-zero) voices in a wider accumulator, then
// scales back to 16 bits to prevent clipping.
//
// Scaling strategy: sum into 20-bit signed, divide by 8 (>>3).
// This gives headroom for up to 8 simultaneous full-scale notes without clip.
// Adjust the right-shift if you want louder single notes.
// =============================================================================

module chord_mixer (
    input  [191:0] osc_bus,    // 12 × 16-bit oscillator outputs (flat bus)
    input  [11:0]  valid,      // which oscillators are active
    output [15:0]  audio_out   // mixed signed 16-bit output
);

// Unpack the flat bus into individual 16-bit words
wire signed [15:0] osc [0:11];
genvar k;
generate
    for (k = 0; k < 12; k = k + 1) begin : unpack
        assign osc[k] = osc_bus[k*16 +: 16];
    end
endgenerate

// Signed accumulation into 22-bit (12 × 16-bit max = 12 × 32767 ≈ 393K < 2^19)
reg signed [21:0] sum;
integer j;

always @(*) begin
    sum = 22'sd0;
    for (j = 0; j < 12; j = j + 1)
        sum = sum + {{6{osc[j][15]}}, osc[j]};  // sign-extend to 22 bits
end

// Scale: divide by 8 (arithmetic right shift 3) to fit back in 16 bits
// If ≤2 notes play simultaneously there is no clipping anyway
wire signed [21:0] scaled = sum >>> 3;

// Saturate to 16-bit range (−32768 .. +32767)
wire overflow_pos = (scaled > 22'sd32767);
wire overflow_neg = (scaled < -22'sd32768);

assign audio_out = overflow_pos ? 16'h7FFF :
                   overflow_neg ? 16'h8000 :
                                  scaled[15:0];

endmodule
