// =============================================================================
// note_freq_table.v  —  Maps note index + octave → DDS phase increment
// =============================================================================
// Sample rate: 50 MHz / 1024 = 48828.125 Hz
// Formula:    freq_word = round(freq_Hz * 2^32 / 48828.125)
//
// Notes (index 0..11):  C, C#, D, D#, E, F, F#, G, G#, A, A#, B
// Octave 1 (SW[16]=1):  one octave below   → divide by 2 (>>1)
// Octave 2 (default):   middle octave 4
// Octave 3 (SW[17]=1):  one octave above   → multiply by 2 (<<1)
// =============================================================================

module note_freq_table (
    input  [3:0]  note,       // 0=C, 1=C#, 2=D, ... 11=B
    input  [1:0]  octave,     // 1=low, 2=middle, 3=high
    output reg [31:0] freq_word
);

// Middle octave (4) phase increments — computed for fs = 48828.125 Hz
localparam C4  = 32'd23012866;   // 261.626 Hz
localparam Cs4 = 32'd24381275;   // 277.183 Hz
localparam D4  = 32'd25831047;   // 293.665 Hz
localparam Ds4 = 32'd27367020;   // 311.127 Hz
localparam E4  = 32'd28994386;   // 329.628 Hz
localparam F4  = 32'd30718420;   // 349.228 Hz
localparam Fs4 = 32'd32545016;   // 369.994 Hz
localparam G4  = 32'd34480245;   // 391.995 Hz
localparam Gs4 = 32'd36530614;   // 415.305 Hz
localparam A4  = 32'd38702809;   // 440.000 Hz
localparam As4 = 32'd41004219;   // 466.164 Hz
localparam B4  = 32'd43442408;   // 493.883 Hz

reg [31:0] base_word;

// Look up middle-octave frequency
always @(*) begin
    case (note)
        4'd0:    base_word = C4;
        4'd1:    base_word = Cs4;
        4'd2:    base_word = D4;
        4'd3:    base_word = Ds4;
        4'd4:    base_word = E4;
        4'd5:    base_word = F4;
        4'd6:    base_word = Fs4;
        4'd7:    base_word = G4;
        4'd8:    base_word = Gs4;
        4'd9:    base_word = A4;
        4'd10:   base_word = As4;
        4'd11:   base_word = B4;
        default: base_word = C4;
    endcase
end

// Apply octave shift
always @(*) begin
    case (octave)
        2'd1:    freq_word = base_word >> 1;   // octave -1  (÷2)
        2'd2:    freq_word = base_word;        // middle octave
        2'd3:    freq_word = base_word << 1;   // octave +1  (×2)
        default: freq_word = base_word;
    endcase
end

endmodule
