`include "tinker.sv"

module test_store2;
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

        // Pre-load: r1 = 42 (data), r2 = 0x3000 (address)
        dut.reg_file.registers[1] = 64'd42;
        dut.reg_file.registers[2] = 64'h3000;

        // store [rd+L], rs → mem[r2 + 0] = r1
        // opcode 0x13, rd=2, rs=1, rt=0, L=0
        store_instr(64'h2000, mk_instr(5'h13, 5'd2, 5'd1, 5'd0, 12'd0));
        // halt
        store_instr(64'h2004, mk_instr(5'h0f, 5'd0, 5'd0, 5'd0, 12'd0));

        #8 reset = 0;

        cycle_count = 0;
        while (!hlt && cycle_count < 30) begin
            @(posedge clk);
            cycle_count = cycle_count + 1;
            if (cycle_count <= 20) begin
                $display("=== Cycle %0d ===", cycle_count);
                $display("  dispatch_v1=%b dispatch_v2=%b", dut.dispatch_valid1, dut.dispatch_valid2);
                $display("  sq_dispatch=%b sq_full=%b", dut.sq_dispatch, dut.sq_full);
                $display("  SQ: valid=%b%b%b%b%b%b%b%b",
                    dut.sq_inst.sq_valid[7], dut.sq_inst.sq_valid[6],
                    dut.sq_inst.sq_valid[5], dut.sq_inst.sq_valid[4],
                    dut.sq_inst.sq_valid[3], dut.sq_inst.sq_valid[2],
                    dut.sq_inst.sq_valid[1], dut.sq_inst.sq_valid[0]);
                $display("  SQ[0]: addr_base_rdy=%b data_rdy=%b addr_computed=%b rob=%0d",
                    dut.sq_inst.sq_addr_base_ready[0], dut.sq_inst.sq_data_ready[0],
                    dut.sq_inst.sq_addr_computed[0], dut.sq_inst.sq_rob_idx[0]);
                $display("  ROB: head=%0d tail=%0d count=%0d",
                    dut.rob_inst.head, dut.rob_inst.tail, dut.rob_inst.count);
                if (dut.rob_inst.count > 0)
                    $display("  ROB[head]: valid=%b complete=%b itype=%0d addr_rdy=%b data_rdy=%b",
                        dut.rob_inst.valid[dut.rob_inst.head],
                        dut.rob_inst.complete[dut.rob_inst.head],
                        dut.rob_inst.itype[dut.rob_inst.head],
                        dut.rob_inst.store_addr_rdy[dut.rob_inst.head],
                        dut.rob_inst.store_data_rdy[dut.rob_inst.head]);
                $display("  sq_rob_store_addr_ready=%b sq_rob_store_data_ready=%b",
                    dut.sq_rob_store_addr_ready, dut.sq_rob_store_data_ready);
                $display("  commit_en1=%b commit_en2=%b", dut.rob_commit_en1, dut.rob_commit_en2);
            end
        end

        $display("Cycles: %0d, hlt=%b", cycle_count, hlt);
        $finish;
    end
endmodule
