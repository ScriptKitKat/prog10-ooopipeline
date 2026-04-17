`include "tinker.sv"

module test_add3;
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
        clk = 0; reset = 1;
        #2;

        // addi r1, #10
        store_instr(64'h2000, mk_instr(5'h19, 5'd1, 5'd0, 5'd0, 12'd10));
        // addi r2, #20
        store_instr(64'h2004, mk_instr(5'h19, 5'd2, 5'd0, 5'd0, 12'd20));
        // add r3, r1, r2
        store_instr(64'h2008, mk_instr(5'h18, 5'd3, 5'd1, 5'd2, 12'd0));
        // halt
        store_instr(64'h200c, mk_instr(5'h0f, 5'd0, 5'd0, 5'd0, 12'd0));

        #8 reset = 0;

        cycle_count = 0;
        while (!hlt && cycle_count < 200) begin
            @(posedge clk);
            cycle_count = cycle_count + 1;
            if (cycle_count <= 15) begin
                $display("Cycle %0d: hlt=%b", cycle_count, hlt);
                $display("  r1=%0d r2=%0d r3=%0d",
                    dut.reg_file.registers[1],
                    dut.reg_file.registers[2],
                    dut.reg_file.registers[3]);
                $display("  commit_en1=%b commit_en2=%b",
                    dut.rob_commit_en1, dut.rob_commit_en2);
                if (dut.rob_commit_en1)
                    $display("  commit1: arch_rd=%0d val=%0d new_phys=%0d",
                        dut.rob_commit_arch_rd1, dut.rob_commit_value1, dut.rob_commit_new_phys1);
                if (dut.rob_commit_en2)
                    $display("  commit2: arch_rd=%0d val=%0d new_phys=%0d",
                        dut.rob_commit_arch_rd2, dut.rob_commit_value2, dut.rob_commit_new_phys2);
            end
        end

        $display("\nFinal: r1=%0d r2=%0d r3=%0d (expect 10, 20, 30)",
            dut.reg_file.registers[1],
            dut.reg_file.registers[2],
            dut.reg_file.registers[3]);
        if (dut.reg_file.registers[3] === 64'd30)
            $display("PASS");
        else
            $display("FAIL");

        $finish;
    end
endmodule
