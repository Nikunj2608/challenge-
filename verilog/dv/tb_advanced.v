`timescale 1ns / 1ps

module tb_advanced;
    reg clk = 0, rst = 1, cyc = 0, we = 0;
    reg [31:0] addr = 0, dat = 0; 
    wire [2:0] irq;
    wire ack; // We need to listen to the hardware's ACK signal!
    
    always #5 clk = ~clk; // 10ns clock cycle
    
    user_proj_example uut (
        .wb_clk_i(clk), .wb_rst_i(rst), .wbs_cyc_i(cyc), .wbs_stb_i(cyc), 
        .wbs_we_i(we), .wbs_adr_i(addr), .wbs_dat_i(dat), 
        .wbs_ack_o(ack),   // Grab the ACK from the hardware
        .la_oenb(~128'b0), // Disable logic analyzer hijack
        .irq(irq)
    );
    
    // Robust Wishbone Write Task
    task wb_write(input [31:0] a, input [31:0] d);
        begin
            @(negedge clk); // Drive on falling edge to avoid race conditions!
            cyc = 1; we = 1; addr = a; dat = d;
            
            wait(ack == 1'b1); // Wait for the hardware to say "Got it!"
            
            @(negedge clk); // Release on the next falling edge
            cyc = 0; we = 0;
        end
    endtask

    initial begin
        $dumpfile("advanced.vcd"); $dumpvars(0, tb_advanced);
        
        #20 rst = 0; // Release Reset
        
        // 1. Configure Sentry-AI via Wishbone
        $display("--- CONFIGURING SENTRY-AI ---");
        wb_write(32'h00, 32'd100); // GLOBAL_THRESH = 100
        wb_write(32'h04, 32'd2);   // LEAK_RATE = 2
        wb_write(32'h10, 32'd0);   // WEIGHT_0: Shift by 0 (x1)
        wb_write(32'h2C, 32'd2);   // WEIGHT_7: Shift by 2 (x4)
        wb_write(32'h08, 32'h81);  // MASK: Enable Neurons 0 and 7 only
        
        // 2. Inject Event Data (Create the Staircase!)
        $display("--- INJECTING DATA (Value: 10, multiple times) ---");
        
        // Hit 1: 10 * 4 = 40. Potential = 40.
        @(negedge clk); 
        force uut.manager_inst.my_fifo.write_enable = 1;
        force uut.manager_inst.my_fifo.write_data = 16'd10;
        @(negedge clk); release uut.manager_inst.my_fifo.write_enable;
        #30; 
        
        // Hit 2: 10 * 4 = 40. Potential = 80.
        @(negedge clk); 
        force uut.manager_inst.my_fifo.write_enable = 1;
        force uut.manager_inst.my_fifo.write_data = 16'd10;
        @(negedge clk); release uut.manager_inst.my_fifo.write_enable;
        #30;

        // Hit 3: 10 * 4 = 40. Potential = 120. SPIKE!
        @(negedge clk); 
        force uut.manager_inst.my_fifo.write_enable = 1;
        force uut.manager_inst.my_fifo.write_data = 16'd10;
        @(negedge clk); release uut.manager_inst.my_fifo.write_enable;
        
        // Let it process...
        #100;
        
        // Check results safely on the falling edge
        @(negedge clk);
        if (irq[0]) begin
            $display("✅ PASS: Interrupt Fired!");
            // Verify Winner-Take-All output
            if (uut.manager_inst.inference_result == 3'd7)
                $display("✅ PASS: WTA Classified Anomaly Type 7!");
            else
                $display("❌ FAIL: Wrong classification.");
        end else begin
            $display("❌ FAIL: No Spike detected.");
        end
        
        #20 $finish;
    end
endmodule