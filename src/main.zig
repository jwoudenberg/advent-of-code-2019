const std = @import("std");

const icmdsize = i64;
const ucmdsize = u64;
const Mem = [1024]icmdsize;
const Error = union(enum) {
    unexpected_opcode: ucmdsize,
    unexpected_param_mode: ucmdsize,
    unexpected_negative_number: icmdsize,
};
const StateTag = enum {
    unloaded,
    resumable,
    awaiting_input,
    outputting,
    halted,
    errored,
};
const State = union(StateTag) {
    unloaded: void,
    resumable: void,
    awaiting_input: ucmdsize,
    outputting: icmdsize,
    halted: void,
    errored: Error,
};
const unloaded = State{ .unloaded = {} };
const resumable = State{ .resumable = {} };
const halted = State{ .halted = {} };
const Program = struct {
    state: State,
    index: ucmdsize,
    mem: Mem,
};
const Halt = error{Halt};

pub fn main() !void {
    var stdin_file = std.io.getStdIn();
    defer stdin_file.close();
    var program = try load_program(stdin_file);
    resume_program_debug(&program);
    try dump_memory(&program, "end.dump");
}

fn empty_program() Program {
    return Program{
        .state = unloaded,
        .index = 0,
        .mem = std.mem.zeroes(Mem),
    };
}

fn dump_memory(program: *Program, path: []const u8) !void {
    var file = try std.fs.cwd().createFile(path, .{});
    defer file.close();
    const writer = file.writer();
    for (program.mem, 0..) |val, index| {
        try writer.print("{d}: {d}\n", .{ index, val });
    }
}

fn assert_program_state(program: *Program, expected_state: StateTag) void {
    const actual_state = @as(StateTag, program.state);
    if (expected_state != actual_state) {
        std.debug.print("Expected program in state '{s}', but it was in '{s}\n'", .{ @tagName(expected_state), @tagName(actual_state) });
        @panic("program in unexpected state");
    }
}

fn load_program(file: std.fs.File) !Program {
    var program = empty_program();
    program.state = State{ .resumable = {} };
    const reader = file.reader();
    var number: icmdsize = 0;
    var index: ucmdsize = 0;
    var sign: icmdsize = 1;
    while (true) {
        const byte: u8 = reader.readByte() catch |err| {
            if (err == error.EndOfStream) {
                program.mem[index] = sign * number;
                return program;
            } else {
                return err;
            }
        };
        switch (byte) {
            ',' => {
                program.mem[index] = sign * number;
                index += 1;
                number = 0;
                sign = 1;
            },
            '0'...'9' => {
                number = number * 10 + (byte - '0');
            },
            '-' => {
                sign = -1;
            },
            '\n' => {},
            else => {
                std.debug.print("parser encountered unexpected byte: {d}\n", .{byte});
                @panic("parser encountered unexpected byte");
            },
        }
    }
}

fn read_param(program: *Program, modes: *ucmdsize) Halt!icmdsize {
    const mode = modes.* % 10;
    modes.* /= 10;
    const val = read_next(program);
    switch (mode) {
        0 => {
            return program.mem[try to_ucmdsize(program, val)];
        },
        1 => {
            return val;
        },
        else => {
            return set_error(program, Error{ .unexpected_param_mode = mode });
        },
    }
}

fn read_param_for_write(program: *Program, modes: *ucmdsize) Halt!ucmdsize {
    const mode = modes.* % 10;
    modes.* /= 10;
    const val = read_next(program);
    switch (mode) {
        0 => {
            return to_ucmdsize(program, val);
        },
        else => {
            return set_error(program, Error{ .unexpected_param_mode = mode });
        },
    }
}

fn set_error(program: *Program, err: Error) Halt {
    program.state = State{ .errored = err };
    return Halt.Halt;
}

fn resume_program(program: *Program) void {
    resume_program_with_errors(false, program) catch {
        return;
    };
}

fn resume_program_debug(program: *Program) void {
    resume_program_with_errors(true, program) catch {
        return;
    };
}

fn provide_input(program: *Program, input: icmdsize) void {
    assert_program_state(program, StateTag.awaiting_input);
    program.mem[program.state.awaiting_input] = input;
    program.state = State{ .resumable = {} };
}

fn take_output(program: *Program) icmdsize {
    assert_program_state(program, StateTag.outputting);
    const output = program.state.outputting;
    program.state = State{ .resumable = {} };
    return output;
}

fn read_next(program: *Program) icmdsize {
    const val = program.mem[program.index];
    program.index += 1;
    return val;
}

fn to_ucmdsize(program: *Program, signed: icmdsize) Halt!ucmdsize {
    const val = signed;
    if (val < 0) {
        return set_error(program, Error{ .unexpected_negative_number = val });
    }
    return @intCast(val);
}

fn resume_program_with_errors(comptime debug: bool, program: *Program) Halt!void {
    assert_program_state(program, StateTag.resumable);
    while (true) {
        const instruction_head = try to_ucmdsize(program, read_next(program));
        const opcode = instruction_head % 100;
        var modes = instruction_head / 100;
        switch (opcode) {
            1 => {
                if (debug) {
                    std.debug.print("instruction: {d} {d} {d} {d}\n", .{
                        instruction_head,
                        program.mem[program.index],
                        program.mem[program.index + 1],
                        program.mem[program.index + 2],
                    });
                }
                const param1 = try read_param(program, &modes);
                const param2 = try read_param(program, &modes);
                const param3 = try read_param_for_write(program, &modes);
                program.mem[param3] = param1 + param2;
            },
            2 => {
                if (debug) {
                    std.debug.print("instruction: {d} {d} {d} {d}\n", .{
                        instruction_head,
                        program.mem[program.index],
                        program.mem[program.index + 1],
                        program.mem[program.index + 2],
                    });
                }
                const param1 = try read_param(program, &modes);
                const param2 = try read_param(program, &modes);
                const param3 = try read_param_for_write(program, &modes);
                program.mem[param3] = param1 * param2;
            },
            3 => {
                if (debug) {
                    std.debug.print("instruction: {d} {d}\n", .{
                        instruction_head,
                        program.mem[program.index],
                    });
                }
                const param1 = try read_param_for_write(program, &modes);
                program.state = State{ .awaiting_input = param1 };
                return;
            },
            4 => {
                if (debug) {
                    std.debug.print("instruction: {d} {d}\n", .{
                        instruction_head,
                        program.mem[program.index],
                    });
                }
                const param1 = try read_param(program, &modes);
                program.state = State{ .outputting = param1 };
                return;
            },
            99 => {
                if (debug) {
                    std.debug.print("instruction: {d}\n", .{
                        instruction_head,
                    });
                }
                program.state = halted;
                return;
            },
            else => {
                return set_error(program, Error{ .unexpected_opcode = opcode });
            },
        }
    }
}

fn test_program(mem: []const icmdsize, index: ucmdsize, state: State) Program {
    var program = empty_program();
    std.mem.copyForwards(icmdsize, &program.mem, mem);
    program.state = state;
    program.index = index;
    return program;
}

test "day 2 example 1" {
    var program = test_program(&.{ 1, 0, 0, 0, 99 }, 0, resumable);
    _ = resume_program(&program);
    try std.testing.expectEqualDeep(
        test_program(&.{ 2, 0, 0, 0, 99 }, 5, halted),
        program,
    );
}

test "day 2 example 2" {
    var program = test_program(&.{ 2, 3, 0, 3, 99 }, 0, resumable);
    _ = resume_program(&program);
    try std.testing.expectEqualDeep(
        test_program(&.{ 2, 3, 0, 6, 99 }, 5, halted),
        program,
    );
}

test "day 2 example 3" {
    var program = test_program(&.{ 2, 4, 4, 5, 99, 0 }, 0, resumable);
    _ = resume_program(&program);
    try std.testing.expectEqualDeep(
        test_program(&.{ 2, 4, 4, 5, 99, 9801 }, 5, halted),
        program,
    );
}

test "day 2 example 4" {
    var program = test_program(&.{ 1, 1, 1, 4, 99, 5, 6, 0, 99 }, 0, resumable);
    _ = resume_program(&program);
    try std.testing.expectEqualDeep(
        test_program(&.{ 30, 1, 1, 4, 2, 5, 6, 0, 99 }, 9, halted),
        program,
    );
}

test "day 2 part 1" {
    const input = try std.fs.cwd().openFile("puzzle-inputs/day2.txt", .{});
    defer input.close();
    var program = try load_program(input);
    program.mem[1] = 12;
    program.mem[2] = 2;
    resume_program(&program);
    try std.testing.expectEqual(program.state, halted);
    try std.testing.expectEqual(program.mem[0], 4714701);
}

test "day 2 part 2" {
    const input = try std.fs.cwd().openFile("puzzle-inputs/day2.txt", .{});
    defer input.close();
    const initial_program = try load_program(input);
    for (0..99) |noun| {
        for (0..99) |verb| {
            var program = initial_program;
            program.mem[1] = @intCast(noun);
            program.mem[2] = @intCast(verb);
            resume_program(&program);
            if (std.meta.eql(program.state, halted) and program.mem[0] == 19690720) {
                try std.testing.expectEqual((100 * noun) + verb, 5121);
                return;
            }
        }
    }
    try std.testing.expect(false); // No solution found.
}

test "day 5 example 1" {
    var program = test_program(&.{ 1002, 4, 3, 4, 33 }, 0, resumable);
    _ = resume_program(&program);
    try std.testing.expectEqualDeep(
        test_program(&.{ 1002, 4, 3, 4, 99 }, 5, halted),
        program,
    );
}

test "day 5 part 1" {
    const input = try std.fs.cwd().openFile("puzzle-inputs/day5.txt", .{});
    defer input.close();
    var program = try load_program(input);
    resume_program(&program);
    provide_input(&program, 1);
    while (true) {
        resume_program(&program);
        const output = take_output(&program);
        if (output != 0) {
            try std.testing.expectEqual(program.mem[program.index], 99);
            try std.testing.expectEqual(output, 6731945);
            return;
        }
    }
}
