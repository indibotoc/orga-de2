// =============================================================================
// dds_oscillator.v  —  Direct Digital Synthesis oscillator (one per note)
// =============================================================================
// Each instance maintains a 32-bit phase accumulator.
// On every audio_tick (48828 Hz) the accumulator is incremented by freq_word.
// The top 8 bits address the waveform ROM (256 samples per period).
// Output is gated to 0 when note is off; phase is preserved for legato playing.
// =============================================================================

module dds_oscillator (
    input         clk,
    input         rst,
    input         en,           // note gate: 1=playing, 0=silent
    input         audio_tick,   // 1-cycle pulse at sample rate (~48828 Hz)
    input  [31:0] freq_word,    // phase increment = freq * 2^32 / sample_rate
    input   [1:0] instrument,   // waveform select (to waveform_rom)
    output [15:0] audio_out     // signed 16-bit sample (0 when note off)
);

// ---------------------------------------------------------------------------
// Phase accumulator
// ---------------------------------------------------------------------------
reg [31:0] phase_acc;

always @(posedge clk or posedge rst) begin
    if (rst)
        phase_acc <= 32'd0;
    else if (audio_tick)
        phase_acc <= en ? phase_acc + freq_word : 32'd0;
        // Reset phase on note-off gives a clean restart next note-on.
        // Change to just phase_acc + freq_word (remove : 32'd0) for legato.
end

// ---------------------------------------------------------------------------
// Waveform ROM lookup
// ---------------------------------------------------------------------------
wire [7:0]  rom_addr = phase_acc[31:24];  // top 8 bits = table index
wire [15:0] wave_sample;

waveform_rom u_rom (
    .instrument (instrument),
    .addr       (rom_addr),
    .data       (wave_sample)
);

// ---------------------------------------------------------------------------
// Gate: output zero when note is not active
// ---------------------------------------------------------------------------
assign audio_out = en ? wave_sample : 16'd0;

endmodule
