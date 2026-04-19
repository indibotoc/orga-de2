// =============================================================================
// wm8731_i2c_ctrl.v  —  WM8731 codec initialization via I2C
// =============================================================================
// Sends a fixed sequence of register writes to WM8731 on power-up.
// WM8731 I2C address: 0x1A (CSB=GND on DE2) → write byte = 0x34
// Register format: 16 bits = {reg_addr[6:0], reg_data[8:0]}
//
// Configuration:
//   R0  Left  Line In  : Mute
//   R1  Right Line In  : Mute
//   R2  Left  HP Out   : 0 dB
//   R3  Right HP Out   : 0 dB
//   R4  Analog Path    : DAC selected, mic muted
//   R5  Digital Path   : no de-emphasis, no mute
//   R6  Power Down     : DAC on, ADC/MIC/LINE powered down
//   R7  Interface Fmt  : I2S, 16-bit, slave mode
//   R8  Sampling Ctrl  : Normal, BOSR=0, SR=0000 (48k with 12.288 MHz)
//                        (actual MCLK=12.5 MHz ≈ 256*48828 Hz, close enough)
//   R9  Active Ctrl    : activate
// =============================================================================

module wm8731_i2c_ctrl (
    input       clk,        // 50 MHz
    input       rst,
    output reg  i2c_scl,
    inout       i2c_sda
);

// ---------------------------------------------------------------------------
// I2C clock: ~100 kHz  →  divide 50 MHz by 500
// ---------------------------------------------------------------------------
localparam I2C_CLK_DIV = 500;
reg [8:0]  clk_div_cnt;
reg        i2c_clk;     // 100 kHz internal clock enable

always @(posedge clk or posedge rst) begin
    if (rst) begin
        clk_div_cnt <= 9'd0;
        i2c_clk     <= 1'b0;
    end else begin
        if (clk_div_cnt == I2C_CLK_DIV - 1) begin
            clk_div_cnt <= 9'd0;
            i2c_clk     <= ~i2c_clk;
        end else begin
            clk_div_cnt <= clk_div_cnt + 1'b1;
        end
    end
end

// Clock edge detects (based on divided clock)
wire i2c_clk_rise = (clk_div_cnt == I2C_CLK_DIV/2 - 1);
wire i2c_clk_fall = (clk_div_cnt == I2C_CLK_DIV   - 1);

// ---------------------------------------------------------------------------
// Register init table: 10 registers × 16 bits
// ---------------------------------------------------------------------------
reg [15:0] init_regs [0:9];

initial begin
    // {reg_addr[6:0], reg_data[8:0]}
    init_regs[0] = {7'd0,  9'b1_0001_0111};  // Left  Line In:  mute, LINVOL=10111 (0dB)
    init_regs[1] = {7'd1,  9'b1_0001_0111};  // Right Line In:  mute
    init_regs[2] = {7'd2,  9'b0_0111_1001};  // Left  HP Out:   LHPVOL=1111001 (0dB)
    init_regs[3] = {7'd3,  9'b0_0111_1001};  // Right HP Out:   RHPVOL=1111001 (0dB)
    init_regs[4] = {7'd4,  9'b0_0001_0010};  // Analog Path:    DACSEL=1, MUTEMIC=1
    init_regs[5] = {7'd5,  9'b0_0000_0000};  // Digital Path:   clear
    init_regs[6] = {7'd6,  9'b0_0000_0111};  // Power Down:     ADC/MIC/LINE off, rest on
    init_regs[7] = {7'd7,  9'b0_0000_0010};  // Interface Fmt:  I2S, 16-bit, slave
    init_regs[8] = {7'd8,  9'b0_0000_0000};  // Sampling:       Normal, SR=0000, BOSR=0
    init_regs[9] = {7'd9,  9'b0_0000_0001};  // Active Control: activate
end

// ---------------------------------------------------------------------------
// I2C state machine
// ---------------------------------------------------------------------------
localparam  IDLE      = 4'd0,
            START     = 4'd1,
            SEND_ADDR = 4'd2,
            ACK_ADDR  = 4'd3,
            SEND_MSB  = 4'd4,
            ACK_MSB   = 4'd5,
            SEND_LSB  = 4'd6,
            ACK_LSB   = 4'd7,
            STOP      = 4'd8,
            DONE      = 4'd9;

localparam WM8731_ADDR = 8'h34;  // 7-bit addr 0x1A + write bit

reg [3:0]  state;
reg [3:0]  reg_idx;      // which init register we're sending (0..9)
reg [3:0]  bit_idx;      // bit position within byte (7..0)
reg [7:0]  tx_byte;      // byte being shifted out
reg        sda_out;
reg        sda_oe;       // output enable for SDA

assign i2c_sda = sda_oe ? sda_out : 1'bz;

// Start delay counter (wait ~10ms after reset for WM8731 power-up)
reg [19:0] start_dly;
wire       start_ok = (start_dly == 20'hFFFFF);

always @(posedge clk or posedge rst) begin
    if (rst) start_dly <= 20'd0;
    else if (!start_ok) start_dly <= start_dly + 1'b1;
end

always @(posedge clk or posedge rst) begin
    if (rst) begin
        state   <= IDLE;
        reg_idx <= 4'd0;
        bit_idx <= 4'd7;
        i2c_scl <= 1'b1;
        sda_out <= 1'b1;
        sda_oe  <= 1'b1;
        tx_byte <= 8'd0;
    end else begin
        case (state)
        //------------------------------------------------------------------
        IDLE: begin
            i2c_scl <= 1'b1;
            sda_out <= 1'b1;
            sda_oe  <= 1'b1;
            if (start_ok && reg_idx < 4'd10)
                state <= START;
        end
        //------------------------------------------------------------------
        START: begin
            // SDA falls while SCL high → START condition
            if (i2c_clk_fall) begin
                sda_out <= 1'b0;   // SDA low
                sda_oe  <= 1'b1;
            end
            if (i2c_clk_rise) begin
                i2c_scl <= 1'b0;   // SCL low after SDA settled
                tx_byte <= WM8731_ADDR;
                bit_idx <= 4'd7;
                state   <= SEND_ADDR;
            end
        end
        //------------------------------------------------------------------
        SEND_ADDR: begin
            if (i2c_clk_fall) begin
                sda_out <= tx_byte[bit_idx];
                sda_oe  <= 1'b1;
            end
            if (i2c_clk_rise) begin
                i2c_scl <= ~i2c_scl;
                if (i2c_scl) begin     // after SCL high
                    if (bit_idx == 4'd0) begin
                        i2c_scl <= 1'b0;
                        state   <= ACK_ADDR;
                    end else
                        bit_idx <= bit_idx - 1'b1;
                end
            end
        end
        //------------------------------------------------------------------
        ACK_ADDR: begin
            // Release SDA, pulse SCL high for ACK
            if (i2c_clk_fall) begin
                sda_oe  <= 1'b0;  // release SDA (WM8731 pulls low = ACK)
            end
            if (i2c_clk_rise) begin
                i2c_scl <= ~i2c_scl;
                if (i2c_scl) begin
                    // After SCL high: ACK sampled, move to MSB
                    i2c_scl <= 1'b0;
                    tx_byte <= init_regs[reg_idx][15:8];
                    bit_idx <= 4'd7;
                    state   <= SEND_MSB;
                end
            end
        end
        //------------------------------------------------------------------
        SEND_MSB: begin
            if (i2c_clk_fall) begin
                sda_out <= tx_byte[bit_idx];
                sda_oe  <= 1'b1;
            end
            if (i2c_clk_rise) begin
                i2c_scl <= ~i2c_scl;
                if (i2c_scl) begin
                    if (bit_idx == 4'd0) begin
                        i2c_scl <= 1'b0;
                        state   <= ACK_MSB;
                    end else
                        bit_idx <= bit_idx - 1'b1;
                end
            end
        end
        //------------------------------------------------------------------
        ACK_MSB: begin
            if (i2c_clk_fall) sda_oe <= 1'b0;
            if (i2c_clk_rise) begin
                i2c_scl <= ~i2c_scl;
                if (i2c_scl) begin
                    i2c_scl <= 1'b0;
                    tx_byte <= init_regs[reg_idx][7:0];
                    bit_idx <= 4'd7;
                    state   <= SEND_LSB;
                end
            end
        end
        //------------------------------------------------------------------
        SEND_LSB: begin
            if (i2c_clk_fall) begin
                sda_out <= tx_byte[bit_idx];
                sda_oe  <= 1'b1;
            end
            if (i2c_clk_rise) begin
                i2c_scl <= ~i2c_scl;
                if (i2c_scl) begin
                    if (bit_idx == 4'd0) begin
                        i2c_scl <= 1'b0;
                        state   <= ACK_LSB;
                    end else
                        bit_idx <= bit_idx - 1'b1;
                end
            end
        end
        //------------------------------------------------------------------
        ACK_LSB: begin
            if (i2c_clk_fall) sda_oe <= 1'b0;
            if (i2c_clk_rise) begin
                i2c_scl <= ~i2c_scl;
                if (i2c_scl) begin
                    i2c_scl <= 1'b0;
                    state   <= STOP;
                end
            end
        end
        //------------------------------------------------------------------
        STOP: begin
            // SDA rises while SCL high → STOP condition
            if (i2c_clk_fall) begin
                sda_out <= 1'b0;
                sda_oe  <= 1'b1;
            end
            if (i2c_clk_rise) begin
                i2c_scl <= 1'b1;
                sda_out <= 1'b1;  // SDA rises after SCL
                // Move to next register
                if (reg_idx == 4'd9) begin
                    state <= DONE;
                end else begin
                    reg_idx <= reg_idx + 1'b1;
                    state   <= IDLE;
                end
            end
        end
        //------------------------------------------------------------------
        DONE: begin
            // All registers written — hold bus idle
            i2c_scl <= 1'b1;
            sda_out <= 1'b1;
            sda_oe  <= 1'b1;
        end
        endcase
    end
end

endmodule
