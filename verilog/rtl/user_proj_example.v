// SPDX-FileCopyrightText: 2020 Efabless Corporation
// SPDX-License-Identifier: Apache-2.0

`default_nettype none

// --------------------------------------------------------
// 1. TOP LEVEL WRAPPER (Caravel Interface)
// --------------------------------------------------------
module user_proj_example #(
    parameter BITS = 32
)(
`ifdef USE_POWER_PINS
    inout vccd1,    // User area 1 1.8V supply
    inout vssd1,    // User area 1 digital ground
`endif

    input wb_clk_i,
    input wb_rst_i,
    input wbs_stb_i,
    input wbs_cyc_i,
    input wbs_we_i,
    input [3:0] wbs_sel_i,
    input [31:0] wbs_dat_i,
    input [31:0] wbs_adr_i,
    output wbs_ack_o,
    output [31:0] wbs_dat_o,

    input  [127:0] la_data_in,
    output [127:0] la_data_out,
    input  [127:0] la_oenb,

    input  [15:0] io_in, 
    output [15:0] io_out,
    output [15:0] io_oeb,

    output [2:0] irq
);
    wire clk = (~la_oenb[64]) ? la_data_in[64]: wb_clk_i;
    wire rst = (~la_oenb[65]) ? la_data_in[65]: wb_rst_i;
    wire [31:0] rdata; 
    wire sensor_pin = io_in[0]; 
    wire valid = wbs_cyc_i && wbs_stb_i; 
    
    assign wbs_dat_o = rdata;
    assign io_out = 16'b0;
    assign io_oeb = 16'hFFFF; 
    assign la_data_out = 128'b0;

    sentry_manager manager_inst (
        .clk(clk),
        .reset(rst),
        .valid(valid),
        .we(wbs_we_i),
        .address(wbs_adr_i),
        .wdata(wbs_dat_i),
        .sensor_pin(sensor_pin),
        .ready(wbs_ack_o),
        .rdata(rdata),
        .irq(irq)
    );
endmodule

// --------------------------------------------------------
// 2. SENTRY-AI MANAGER (Wishbone & System Controller)
// --------------------------------------------------------
module sentry_manager (
    input clk, reset, valid, we,
    input [31:0] address, wdata,
    input sensor_pin,
    output reg ready,
    output reg [31:0] rdata,
    output reg [2:0] irq
);
    // --- Firmware-Programmable Registers ---
    reg [31:0] threshold;
    reg [31:0] leak_rate;
    reg [7:0]  enable_mask;
    reg [31:0] tick_limit; // NEW: Temporal Integration Window
    reg [31:0] weight_reg [0:7]; 
    
    // --- Internal Wires ---
    wire fifo_not_empty;
    wire [15:0] fifo_read_data;
    wire [7:0] array_spikes;
    reg  [2:0] inference_result;
    reg  [7:0] status_reg;
    
    // --- FSM & Delta Encoder Registers ---
    parameter IDLE = 1'b0, CAPTURING = 1'b1;
    parameter NOISE_FLOOR = 16'd5;
    reg state;
    reg [3:0] bit_count; 
    reg [15:0] shift_reg;
    reg [15:0] last_sensor_value;
    reg fifo_write_enable;

    // --- NEW: Global Tick Generator ---
    reg [31:0] tick_counter;
    wire global_tick = (tick_counter >= tick_limit);

    always @(posedge clk) begin
        if (reset) tick_counter <= 32'b0;
        else if (global_tick) tick_counter <= 32'b0;
        else tick_counter <= tick_counter + 1;
    end

    // FSM: Direct I/O Sensor Capture + Delta Event Encoder
    wire [15:0] delta = (shift_reg > last_sensor_value) ? (shift_reg - last_sensor_value) : (last_sensor_value - shift_reg);

    always @(posedge clk) begin
        if(reset) begin
            state <= IDLE;
            fifo_write_enable <= 1'b0;
            bit_count <= 4'b0;
            shift_reg <= 16'b0;
            last_sensor_value <= 16'b0;
        end else begin
            case(state) 
                IDLE: begin
                    fifo_write_enable <= 1'b0;
                    if (sensor_pin == 1'b0) state <= CAPTURING;
                end
                CAPTURING: begin
                    shift_reg <= {shift_reg[14:0], sensor_pin};
                    if (bit_count == 15) begin
                        state <= IDLE;
                        bit_count <= 4'b0;
                        // EVENT ENCODER: Only push to FIFO if change exceeds noise floor!
                        if (delta > NOISE_FLOOR) begin
                            fifo_write_enable <= 1'b1;
                            last_sensor_value <= shift_reg; // Update baseline
                        end else begin
                            fifo_write_enable <= 1'b0; // Ignore boring noise
                        end
                    end else begin
                        bit_count <= bit_count + 1'b1;
                        fifo_write_enable <= 1'b0;
                    end
                end
            endcase
        end
    end

    fifo my_fifo (
        .clk(clk), .reset(reset), .write_enable(fifo_write_enable),
        .write_data(shift_reg), .read_enable(fifo_not_empty), 
        .not_empty(fifo_not_empty), .read_data(fifo_read_data)
    );

    wire [255:0] flat_weights = {weight_reg[7], weight_reg[6], weight_reg[5], weight_reg[4], 
                                 weight_reg[3], weight_reg[2], weight_reg[1], weight_reg[0]};

    neuron_array #(.NEURON_COUNT(8)) brain_array (
        .clk(clk), .reset(reset), .data_in(fifo_read_data), .data_valid(fifo_not_empty),
        .global_tick(global_tick), // NEW: Pass the tick down to the neurons
        .threshold(threshold), .leak_rate(leak_rate), .enable_mask(enable_mask),
        .flat_weights(flat_weights), .spikes(array_spikes)
    );

    // ----------------------------------------
    // WINNER-TAKE-ALL (Reads the Sticky Register!)
    // ----------------------------------------
    always @(*) begin
        if      (status_reg[7]) inference_result = 3'd7; 
        else if (status_reg[6]) inference_result = 3'd6;
        else if (status_reg[5]) inference_result = 3'd5;
        else if (status_reg[4]) inference_result = 3'd4;
        else if (status_reg[3]) inference_result = 3'd3;
        else if (status_reg[2]) inference_result = 3'd2;
        else if (status_reg[1]) inference_result = 3'd1;
        else if (status_reg[0]) inference_result = 3'd0;
        else                    inference_result = 3'd0;
    end

    // ----------------------------------------
    // ALARM LOGIC (Sticky Interrupts!)
    // ----------------------------------------
    always @(posedge clk) begin
        if (reset) begin
            status_reg <= 8'b0;
            irq <= 3'b000;
        end else begin
            if (|array_spikes) begin
                // Latch the spikes using bitwise OR (don't lose previous unread spikes)
                status_reg <= status_reg | array_spikes; 
                irq <= 3'b001; // Ring the alarm and HOLD IT!
            end 
            // Clear the alarm ONLY when the CPU reads the SPIKE_STATUS register (0x34)
            else if (valid && !we && address[7:0] == 8'h34) begin
                status_reg <= 8'b0;
                irq <= 3'b000;
            end
        end
    end

    integer j;
    always @(posedge clk) begin
        if (reset) begin
            ready <= 1'b0; rdata <= 32'b0;
            threshold <= 32'd5000; leak_rate <= 32'd1; enable_mask <= 8'hFF; 
            tick_limit <= 32'd100000; // NEW: Default leak every 1ms at 100MHz
            for (j=0; j<8; j=j+1) weight_reg[j] <= 32'd0; // Default shift = 0
        end else begin
            ready <= 1'b0;
            if (valid && !ready) begin
                ready <= 1'b1; 
                if (we) begin
                    case (address[7:0])
                        8'h00: threshold <= wdata;
                        8'h04: leak_rate <= wdata;
                        8'h08: enable_mask <= wdata[7:0];
                        8'h0C: tick_limit <= wdata; // NEW: Write to tick limit
                        8'h10: weight_reg[0] <= wdata;
                        8'h14: weight_reg[1] <= wdata;
                        8'h18: weight_reg[2] <= wdata;
                        8'h1C: weight_reg[3] <= wdata;
                        8'h20: weight_reg[4] <= wdata;
                        8'h24: weight_reg[5] <= wdata;
                        8'h28: weight_reg[6] <= wdata;
                        8'h2C: weight_reg[7] <= wdata;
                        default: ; 
                    endcase
                end else begin
                    case (address[7:0])
                        8'h30: rdata <= {29'b0, inference_result}; 
                        8'h34: rdata <= {24'b0, status_reg};       
                        default: rdata <= 32'b0;
                    endcase
                end
            end
        end
    end
endmodule

// --------------------------------------------------------
// 3. FIFO STUB (Memory)
// --------------------------------------------------------
module fifo (
    input clk, reset, write_enable, read_enable,
    input [15:0] write_data,
    output wire not_empty,
    output wire [15:0] read_data
);
    reg [15:0] memory [0:15]; 
    reg [3:0]  wr_ptr, rd_ptr;        

    always @(posedge clk) begin
        if (reset) wr_ptr <= 4'b0;
        else if (write_enable) begin
            memory[wr_ptr] <= write_data;
            wr_ptr <= wr_ptr + 1'b1;
        end
    end

    always @(posedge clk) begin
        if (reset) rd_ptr <= 4'b0;
        else if (read_enable && not_empty) rd_ptr <= rd_ptr + 1'b1;
    end

    assign not_empty = (wr_ptr != rd_ptr);
    assign read_data = memory[rd_ptr];
endmodule

// --------------------------------------------------------
// 4. NEUROMORPHIC CORE: 8-Neuron Array (Shift-Add approach)
// --------------------------------------------------------
module neuron_array #(
    parameter NEURON_COUNT = 8
)(
    input clk, reset, data_valid, global_tick, // NEW: added global_tick
    input [15:0] data_in,
    input [31:0] threshold, leak_rate,
    input [7:0]  enable_mask,
    input [255:0] flat_weights,
    output wire [NEURON_COUNT-1:0] spikes
);
    genvar i;
    generate
        for (i = 0; i < NEURON_COUNT; i = i + 1) begin : neuron_cores
            reg [31:0] membrane_potential;
            reg spike_reg;
            
            // Extract the 4-bit shift amount (0 to 15) for this neuron
            wire [3:0] my_shift = flat_weights[(i*32) + 3 : (i*32)];
            
            // AREA SAVINGS: Bit-shift instead of multiplication! 
            wire [31:0] weighted_data = data_in << my_shift; 

            always @(posedge clk) begin
                if (reset || !enable_mask[i]) begin 
                    membrane_potential <= 32'b0;
                    spike_reg <= 1'b0;
                end else begin
                    if (data_valid && (membrane_potential + weighted_data >= threshold)) begin
                        spike_reg <= 1'b1;
                        membrane_potential <= 32'b0;
                    end else if (data_valid) begin
                        membrane_potential <= (membrane_potential + weighted_data > leak_rate) ? 
                                              (membrane_potential + weighted_data - leak_rate) : 32'b0;
                        spike_reg <= 1'b0;
                    end 
                    // NEW: Only leak when the temporal tick fires!
                    else if (global_tick && membrane_potential > leak_rate) begin
                        membrane_potential <= membrane_potential - leak_rate;
                        spike_reg <= 1'b0;
                    end else if (global_tick) begin
                        membrane_potential <= 32'b0;
                        spike_reg <= 1'b0;
                    end else begin
                        spike_reg <= 1'b0; // Maintain potential between ticks
                    end
                end
            end
            assign spikes[i] = spike_reg;
        end
    endgenerate
endmodule
`default_nettype wire