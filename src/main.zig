const std = @import("std");

const cmdsize = u64;
const prog = [1024]cmdsize;

pub fn main() !void {
    var program = init_memory(&.{});
    try load_program(&program);
    program[1] = 12;
    program[2] = 2;
    run_program(&program);
    try print_result(&program);
}

fn init_memory(init: []const cmdsize) prog {
    var program: prog = std.mem.zeroes(prog);
    std.mem.copyForwards(cmdsize, &program, init);
    return program;
}

fn print_result(program: *prog) !void {
    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();
    try stdout.print("{d}", .{program[0]});
    try bw.flush(); // don't forget to flush!
}

fn load_program(program: *prog) !void {
    const stdin_file = std.io.getStdIn();
    const stdin = stdin_file.reader();
    var number: u32 = 0;
    var index: u64 = 0;
    while (true) {
        const byte: u8 = stdin.readByte() catch |err| {
            if (err == error.EndOfStream) {
                program.*[index] = number;
                return;
            } else {
                return err;
            }
        };
        switch (byte) {
            ',' => {
                program.*[index] = number;
                index += 1;
                number = 0;
            },
            '0'...'9' => {
                number = number * 10 + (byte - '0');
            },
            '\n' => {},
            else => {
                std.debug.print("parser encountered unexpected byte: {d}\n", .{byte});
                @panic("parser encountered unexpected byte");
            },
        }
    }
}

fn run_program(program: *prog) void {
    var index: u64 = 0;
    while (true) {
        const opcode = program.*[index];
        switch (opcode) {
            1 => {
                const param1 = program.*[index + 1];
                const param2 = program.*[index + 2];
                const param3 = program.*[index + 3];
                program.*[param3] = program.*[param1] + program.*[param2];
                index += 4;
            },
            2 => {
                const param1 = program.*[index + 1];
                const param2 = program.*[index + 2];
                const param3 = program.*[index + 3];
                program.*[param3] = program.*[param1] * program.*[param2];
                index += 4;
            },
            99 => {
                return;
            },
            else => {
                std.debug.print("program encountered unknown opcode: {d}\n", .{opcode});
                @panic("program encountered unknown opcode");
            },
        }
    }
}

test "simple program 1" {
    var program = init_memory(&.{ 1, 0, 0, 0, 99 });
    run_program(&program);
    try std.testing.expectEqual(program, init_memory(&.{ 2, 0, 0, 0, 99 }));
}

test "simple program 2" {
    var program = init_memory(&.{ 2, 3, 0, 3, 99 });
    run_program(&program);
    try std.testing.expectEqual(program, init_memory(&.{ 2, 3, 0, 6, 99 }));
}

test "simple program 3" {
    var program = init_memory(&.{ 2, 4, 4, 5, 99, 0 });
    run_program(&program);
    try std.testing.expectEqual(program, init_memory(&.{ 2, 4, 4, 5, 99, 9801 }));
}

test "simple program 4" {
    var program = init_memory(&.{ 1, 1, 1, 4, 99, 5, 6, 0, 99 });
    run_program(&program);
    try std.testing.expectEqual(program, init_memory(&.{ 30, 1, 1, 4, 2, 5, 6, 0, 99 }));
}
