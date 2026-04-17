`include "tinker.sv"

module test_all;
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

    integer cycle_count, pass_count, fail_count;

    task run_test(input [255:0] name);
        begin
            reset = 1;
            #20;
            reset = 0;
            cycle_count = 0;
            while (!hlt && cycle_count < 100) begin
                @(posedge clk);
                cycle_count = cycle_count + 1;
            end
        end
    endtask

    task check(input [255:0] name, input [4:0] reg_num, input [63:0] expected);
        begin
            if (cycle_count >= 100) begin
                $display("FAIL %-20s TIMEOUT", name);
                fail_count = fail_count + 1;
            end else if (dut.reg_file.registers[reg_num] === expected) begin
                $display("PASS %-20s cycles=%0d r%0d=%0d", name, cycle_count, reg_num, expected);
                pass_count = pass_count + 1;
            end else begin
                $display("FAIL %-20s cycles=%0d r%0d=%0d (expected %0d)",
                    name, cycle_count, reg_num, dut.reg_file.registers[reg_num], expected);
                fail_count = fail_count + 1;
            end
        end
    endtask

    initial begin
        clk = 0;
        pass_count = 0;
        fail_count = 0;

        // === ADD ===
        reset = 1; #2;
        dut.reg_file.registers[1] = 64'd10;
        dut.reg_file.registers[2] = 64'd20;
        store_instr(64'h2000, mk_instr(5'h18, 5'd3, 5'd1, 5'd2, 12'd0));
        store_instr(64'h2004, mk_instr(5'h0f, 5'd0, 5'd0, 5'd0, 12'd0));
        run_test("add");
        check("add", 3, 64'd30);

        // === ADDI ===
        reset = 1; #2;
        dut.reg_file.registers[1] = 64'd10;
        store_instr(64'h2000, mk_instr(5'h19, 5'd1, 5'd0, 5'd0, 12'd5));
        store_instr(64'h2004, mk_instr(5'h0f, 5'd0, 5'd0, 5'd0, 12'd0));
        run_test("addi");
        check("addi", 1, 64'd15);

        // === SUB ===
        reset = 1; #2;
        dut.reg_file.registers[1] = 64'd30;
        dut.reg_file.registers[2] = 64'd10;
        store_instr(64'h2000, mk_instr(5'h1a, 5'd3, 5'd1, 5'd2, 12'd0));
        store_instr(64'h2004, mk_instr(5'h0f, 5'd0, 5'd0, 5'd0, 12'd0));
        run_test("sub");
        check("sub", 3, 64'd20);

        // === SUBI ===
        reset = 1; #2;
        dut.reg_file.registers[1] = 64'd30;
        store_instr(64'h2000, mk_instr(5'h1b, 5'd1, 5'd0, 5'd0, 12'd5));
        store_instr(64'h2004, mk_instr(5'h0f, 5'd0, 5'd0, 5'd0, 12'd0));
        run_test("subi");
        check("subi", 1, 64'd25);

        // === MUL ===
        reset = 1; #2;
        dut.reg_file.registers[1] = 64'd6;
        dut.reg_file.registers[2] = 64'd7;
        store_instr(64'h2000, mk_instr(5'h1c, 5'd3, 5'd1, 5'd2, 12'd0));
        store_instr(64'h2004, mk_instr(5'h0f, 5'd0, 5'd0, 5'd0, 12'd0));
        run_test("mul");
        check("mul", 3, 64'd42);

        // === DIV ===
        reset = 1; #2;
        dut.reg_file.registers[1] = 64'd42;
        dut.reg_file.registers[2] = 64'd6;
        store_instr(64'h2000, mk_instr(5'h1d, 5'd3, 5'd1, 5'd2, 12'd0));
        store_instr(64'h2004, mk_instr(5'h0f, 5'd0, 5'd0, 5'd0, 12'd0));
        run_test("div");
        check("div", 3, 64'd7);

        // === AND ===
        reset = 1; #2;
        dut.reg_file.registers[1] = 64'hFF00;
        dut.reg_file.registers[2] = 64'hF0F0;
        store_instr(64'h2000, mk_instr(5'h00, 5'd3, 5'd1, 5'd2, 12'd0));
        store_instr(64'h2004, mk_instr(5'h0f, 5'd0, 5'd0, 5'd0, 12'd0));
        run_test("and");
        check("and", 3, 64'hF000);

        // === OR ===
        reset = 1; #2;
        dut.reg_file.registers[1] = 64'hFF00;
        dut.reg_file.registers[2] = 64'h00FF;
        store_instr(64'h2000, mk_instr(5'h01, 5'd3, 5'd1, 5'd2, 12'd0));
        store_instr(64'h2004, mk_instr(5'h0f, 5'd0, 5'd0, 5'd0, 12'd0));
        run_test("or");
        check("or", 3, 64'hFFFF);

        // === XOR ===
        reset = 1; #2;
        dut.reg_file.registers[1] = 64'hFF00;
        dut.reg_file.registers[2] = 64'hF0F0;
        store_instr(64'h2000, mk_instr(5'h02, 5'd3, 5'd1, 5'd2, 12'd0));
        store_instr(64'h2004, mk_instr(5'h0f, 5'd0, 5'd0, 5'd0, 12'd0));
        run_test("xor");
        check("xor", 3, 64'h0FF0);

        // === NOT ===
        reset = 1; #2;
        dut.reg_file.registers[1] = 64'h0;
        store_instr(64'h2000, mk_instr(5'h03, 5'd3, 5'd1, 5'd0, 12'd0));
        store_instr(64'h2004, mk_instr(5'h0f, 5'd0, 5'd0, 5'd0, 12'd0));
        run_test("not");
        check("not", 3, 64'hFFFFFFFFFFFFFFFF);

        // === SHFTR ===
        reset = 1; #2;
        dut.reg_file.registers[1] = 64'd16;
        dut.reg_file.registers[2] = 64'd2;
        store_instr(64'h2000, mk_instr(5'h04, 5'd3, 5'd1, 5'd2, 12'd0));
        store_instr(64'h2004, mk_instr(5'h0f, 5'd0, 5'd0, 5'd0, 12'd0));
        run_test("shftr");
        check("shftr", 3, 64'd4);

        // === SHFTRI ===
        reset = 1; #2;
        dut.reg_file.registers[1] = 64'd16;
        store_instr(64'h2000, mk_instr(5'h05, 5'd1, 5'd0, 5'd0, 12'd2));
        store_instr(64'h2004, mk_instr(5'h0f, 5'd0, 5'd0, 5'd0, 12'd0));
        run_test("shftri");
        check("shftri", 1, 64'd4);

        // === SHFTL ===
        reset = 1; #2;
        dut.reg_file.registers[1] = 64'd4;
        dut.reg_file.registers[2] = 64'd2;
        store_instr(64'h2000, mk_instr(5'h06, 5'd3, 5'd1, 5'd2, 12'd0));
        store_instr(64'h2004, mk_instr(5'h0f, 5'd0, 5'd0, 5'd0, 12'd0));
        run_test("shftl");
        check("shftl", 3, 64'd16);

        // === SHFTLI ===
        reset = 1; #2;
        dut.reg_file.registers[1] = 64'd4;
        store_instr(64'h2000, mk_instr(5'h07, 5'd1, 5'd0, 5'd0, 12'd2));
        store_instr(64'h2004, mk_instr(5'h0f, 5'd0, 5'd0, 5'd0, 12'd0));
        run_test("shftli");
        check("shftli", 1, 64'd16);

        // === MOV reg to reg ===
        reset = 1; #2;
        dut.reg_file.registers[1] = 64'd42;
        store_instr(64'h2000, mk_instr(5'h11, 5'd3, 5'd1, 5'd0, 12'd0));
        store_instr(64'h2004, mk_instr(5'h0f, 5'd0, 5'd0, 5'd0, 12'd0));
        run_test("mov_reg_to_reg");
        check("mov_reg_to_reg", 3, 64'd42);

        // === MOV L to reg (MOVI) ===
        reset = 1; #2;
        dut.reg_file.registers[1] = 64'd0;
        store_instr(64'h2000, mk_instr(5'h12, 5'd1, 5'd0, 5'd0, 12'd5));
        store_instr(64'h2004, mk_instr(5'h0f, 5'd0, 5'd0, 5'd0, 12'd0));
        run_test("mov_L_to_reg");
        // MOVI: result = {imm[11:0], src1[51:0]} = {5, 0[51:0]} = 5 << 52
        check("mov_L_to_reg", 1, {12'd5, 52'd0});

        $display("\n=== Results: %0d PASS, %0d FAIL ===", pass_count, fail_count);
        $finish;
    end
endmodule
