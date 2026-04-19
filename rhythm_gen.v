// =============================================================================
// rhythm_gen.v  —  Metronome / rhythm click generator
// =============================================================================
// Generates a short percussive click at a fixed BPM (default 120 BPM).
// KEY[1] toggles ON/OFF (handled in top_level).
//
// BPM = 120 → beat every 0.5 s → 0.5 × 48828 = 24414 samples per beat
// Click shape: decaying square burst (simple, no SRAM needed)
//
// The click audio is mixed with the instrument audio in top_level at 50% each.
// Set BEAT_SAMPLES to change tempo:
//   BPM = 60  → 48828 samples/beat
//   BPM = 120 → 24414 samples/beat
//   BPM = 90  → 32552 samples/beat
// =============================================================================

module rhythm_gen (
    input         clk,
    input         rst,
    input         en,           // rhythm enable (toggle from KEY[1])
    input         audio_tick,   // 48828 Hz sample clock
    output [15:0] audio_out,    // click sample output
    output        beat          // high for 1 audio_tick on each beat
);

localparam BEAT_SAMPLES = 24414;  // 120 BPM at 48828 Hz
localparam BEAT_CNT_W   = 15;     // ceil(log2(24414)) = 15 bits

// ---------------------------------------------------------------------------
// Beat counter
// ---------------------------------------------------------------------------
reg [BEAT_CNT_W-1:0] beat_cnt;
reg                  beat_r;

always @(posedge clk or posedge rst) begin
    if (rst) begin
        beat_cnt <= 0;
        beat_r   <= 1'b0;
    end else if (audio_tick && en) begin
        if (beat_cnt == BEAT_SAMPLES - 1) begin
            beat_cnt <= 0;
            beat_r   <= 1'b1;
        end else begin
            beat_cnt <= beat_cnt + 1'b1;
            beat_r   <= 1'b0;
        end
    end else begin
        beat_r <= 1'b0;
    end
end

assign beat = beat_r;

// ---------------------------------------------------------------------------
// Click sound: decaying burst
// Short burst of 50 samples at full amplitude, then silence
// ---------------------------------------------------------------------------
localparam CLICK_LEN = 6'd50;

reg [5:0]  click_cnt;
reg        clicking;

always @(posedge clk or posedge rst) begin
    if (rst) begin
        click_cnt <= 6'd0;
        clicking  <= 1'b0;
    end else if (audio_tick) begin
        if (beat_r && en) begin
            click_cnt <= 6'd0;
            clicking  <= 1'b1;
        end else if (clicking) begin
            if (click_cnt == CLICK_LEN - 1)
                clicking <= 1'b0;
            else
                click_cnt <= click_cnt + 1'b1;
        end
    end
end

// Click amplitude decays linearly: full at count 0, zero at count CLICK_LEN
// Use alternating polarity for a click sound (square wave burst)
wire signed [15:0] click_amp  = {1'b0, {9{1'b1}}, 6'd0}; // ~16352 ≈ half scale
wire signed [15:0] click_sample = (click_cnt[0]) ? click_amp : -click_amp;

assign audio_out = (clicking && en) ? click_sample : 16'd0;

endmodule
