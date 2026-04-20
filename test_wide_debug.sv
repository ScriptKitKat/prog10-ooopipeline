`include "tinker.sv"

module test_wide_debug;
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
        clk = 0; reset = 1; #2;

        // 3-iteration loop with 4-instr body
        dut.reg_file.registers[1] = 64'd3;
        dut.reg_file.registers[2] = 64'h2000;
        dut.reg_file.registers[3] = 64'd0;
        store_instr(64'h2000, mk_instr(5'h19, 5'd3, 5'd0, 5'd0, 12'd1));   // addi r3, 1
        store_instr(64'h2004, mk_instr(5'h19, 5'd3, 5'd0, 5'd0, 12'd1));   // addi r3, 1
        store_instr(64'h2008, mk_instr(5'h1b, 5'd1, 5'd0, 5'd0, 12'd1));   // subi r1, 1
        store_instr(64'h200c, mk_instr(5'h0b, 5'd2, 5'd1, 5'd0, 12'd0));   // brnz r2, r1
        store_instr(64'h2010, mk_instr(5'h0f, 5'd0, 5'd0, 5'd0, 12'd0));   // halt

        #8 reset = 0;

        cycle_count = 0;
        while (!hlt && cycle_count < 200) begin
            @(posedge clk);
            cycle_count = cycle_count + 1;
            if (cycle_count <= 60 || cycle_count % 20 == 0)
            $display("C%0d: v1=%b v2=%b op1=%h op2=%h stall=%b tf1=%b flush=%b rob[h=%0d t=%0d c=%0d] rs0full=%b rs1full=%b",
                cycle_count,
                dut.fu_out_valid1, dut.fu_out_valid2,
                dut.opcode1, dut.opcode2,
                dut.decode_stall,
                (dut.fu_out_valid1 && dut.target_full1),
                dut.flush,
                dut.rob_inst.head, dut.rob_inst.tail, dut.rob_inst.count,
                dut.rs_alu0_full, dut.rs_alu1_full);
        end

        $display("Cycles: %0d, r1=%0d, r3=%0d", cycle_count, dut.reg_file.registers[1], dut.reg_file.registers[3]);
        $finish;
    end
endmodule
