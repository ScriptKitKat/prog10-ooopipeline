`include "tinker.sv"

module test_loop_wide;
    reg clk, reset;
    wire hlt;

    tinker_core dut(.clk(clk), .reset(reset), .hlt(hlt));

    always #5 clk = ~clk;

    function [31:0] mk_instr(input [4:0] op, input [4:0] rd,
                             input [4:0] rs, input [4:0] rt, input [11:0] L);
        mk_instr = {op, rd, rs, rt, L};
    endfunction

    task store_instr(input [63:0] addr, input [31:0] word);
        begin
            dut.memory.bytes[addr + 0] = word[7:0];
            dut.memory.bytes[addr + 1] = word[15:8];
            dut.memory.bytes[addr + 2] = word[23:16];
            dut.memory.bytes[addr + 3] = word[31:24];
        end
    endtask

    integer cycle_count;

    initial begin
        clk = 0;

        // Loop with 4-instruction body (more realistic)
        // r1 = counter, r2 = loop target, r3 = accumulator
        // loop: addi r3, 1       ; 0x2000
        //       addi r3, 1       ; 0x2004
        //       subi r1, 1       ; 0x2008
        //       brnz r2, r1      ; 0x200c
        //       halt              ; 0x2010
        reset = 1; #2;
        dut.reg_file.registers[1] = 64'd50;
        dut.reg_file.registers[2] = 64'h2000;
        dut.reg_file.registers[3] = 64'd0;
        store_instr(64'h2000, mk_instr(5'h19, 5'd3, 5'd0, 5'd0, 12'd1));   // addi r3, 1
        store_instr(64'h2004, mk_instr(5'h19, 5'd3, 5'd0, 5'd0, 12'd1));   // addi r3, 1
        store_instr(64'h2008, mk_instr(5'h1b, 5'd1, 5'd0, 5'd0, 12'd1));   // subi r1, 1
        store_instr(64'h200c, mk_instr(5'h0b, 5'd2, 5'd1, 5'd0, 12'd0));   // brnz r2, r1
        store_instr(64'h2010, mk_instr(5'h0f, 5'd0, 5'd0, 5'd0, 12'd0));   // halt

        #8 reset = 0;
        cycle_count = 0;
        while (!hlt && cycle_count < 50000) begin
            @(posedge clk);
            cycle_count = cycle_count + 1;
        end
        $display("Wide loop (50 iter, 4-instr body): cycles=%0d r1=%0d r3=%0d %s (%.1f cyc/iter)",
                 cycle_count, dut.reg_file.registers[1], dut.reg_file.registers[3],
                 (cycle_count < 50000 && dut.reg_file.registers[1] === 64'd0 && dut.reg_file.registers[3] === 64'd100) ? "PASS" : "FAIL",
                 cycle_count / 50.0);

        $finish;
    end
endmodule
