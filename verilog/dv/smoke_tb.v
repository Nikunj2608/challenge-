module tb;
    reg clk = 0, rst = 1, cyc = 0, we = 0;
    reg [31:0] addr = 0, dat = 0; 
    wire [2:0] irq;
    
    always #5 clk = ~clk; // 10ns clock cycle
    
    user_proj_example uut (
        .wb_clk_i(clk), 
        .wb_rst_i(rst), 
        .wbs_cyc_i(cyc), 
        .wbs_stb_i(cyc), 
        .wbs_we_i(we), 
        .wbs_adr_i(addr), 
        .wbs_dat_i(dat), 
        .la_oenb(~128'b0), // FIX: Disable the Logic Analyzer hijack!
        .irq(irq)
    );
    
    initial begin
        $dumpfile("smoke.vcd"); $dumpvars(0, tb);
        
        // Print the potential to the terminal every time it changes
        $monitor("Time: %0t | Potential: %0d | IRQ: %b", $time, uut.counter_inst.membrane_potential, irq[0]);
        
        #10 rst = 0; // Release Reset
        
        // 1. Wishbone Write: Set Threshold to 10
        #10 cyc = 1; we = 1; addr = 32'h00; dat = 32'd10;
        #10 cyc = 0; we = 0;
        
        // 2. Force the stubbed FIFO to output increments of 6
        force uut.counter_inst.fifo_not_empty = 1;
        force uut.counter_inst.fifo_read_data = 16'd6;
        
        #10; // Cycle 1: Potential = 0 + 6 = 6
        #10; // Cycle 2: Potential = 6 + 6 = 12 (Crosses Threshold!)
        #10; // Give it one more tick to let the alarm trigger
        
        @(negedge clk); 
        
        if (irq[0]) begin
            $display("✅ PASS: Neuron Fired at Potential %0d!", uut.counter_inst.membrane_potential);
            release uut.counter_inst.fifo_not_empty; // Stop the machine gun!
        end else begin
            $display("❌ FAIL: No Spike detected at time %0t", $time);
        end
        #10 $finish;
    end
endmodule