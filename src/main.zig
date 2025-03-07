const std = @import("std");
const base91 = @import("base91");
const eql = std.mem.eql;

const Options = struct {
    help: bool = false,
    decode: bool = false,
    memory: usize = 512,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    var opts = Options{};

    var state: enum {
        none,
        expect_memory,
    } = .none;

    // Parse options
    // TODO: allow `chaining` eg `-dm 1024`
    for (args) |arg| {
        if (state == .expect_memory) {
            opts.memory = try std.fmt.parseInt(usize, arg, 0);
            state = .none;
        }

        if (eql(u8, arg, "-h") or eql(u8, arg, "--help")) {
            opts.help = true;
        }

        if (eql(u8, arg, "-d") or eql(u8, arg, "--decode")) {
            opts.decode = true;
        }

        if (eql(u8, arg, "-m") or eql(u8, arg, "--memory")) {
            state = .expect_memory;
        }
    }

    if (opts.help) {
        var reset: []const u8 = "\x1b[0;0m";
        var orange: []const u8 = "\x1b[0;33m";
        var light_blue: []const u8 = "\x1b[0;94m";
        var light_green: []const u8 = "\x1b[0;92m";
        var cyan: []const u8 = "\x1b[0;36m";

        if (std.process.hasEnvVarConstant("NO_COLOR")) {
            //if (false) {
            reset = "";
            orange = "";
            light_blue = "";
            light_green = "";
            cyan = "";
        }

        std.debug.print(
            \\{s}usage{s}: {s}{s} {1s}[{s}option{1s}]...
            \\{0s}description{1s}: read from standard input and en/decode basE91 to standard output.
            \\
            \\{0s}normal options{1s}:
            \\  {4s}-h{1s}, {4s}--help{1s}:    display this help and exit
            \\  {4s}-m{1s}, {4s}--memory{1s}:  change the stdin buffer size (default: 256KiB)
            \\  {4s}-d{1s}, {4s}--decode{1s}:  decode instead of encode
            \\
        , .{
            orange,
            reset,
            light_blue,
            args[0],
            cyan,
        });

        std.debug.print(
            \\
            \\{s}enviornment variables{s}:
            \\  {s}NO_COLOR{1s}: disable color
            \\
            \\
        , .{ orange, reset, cyan });

        return;
    }

    // Buffered stdin and stdout
    const stdin = std.io.getStdIn().reader();
    var buf_reader = std.io.bufferedReader(stdin);
    const buffered_stdin = buf_reader.reader();

    const stdout = std.io.getStdOut().writer();
    var buf_writer = std.io.bufferedWriter(stdout);
    const buffered_stdout = buf_writer.writer();

    if (opts.decode) {
        //const buf = try allocator.alloc(u8, opts.memory);
        const buf = try allocator.alloc(u8, 1);

        var decoder = try base91.decodeStream(
            buffered_stdin,
            .{},
        );

        while (true) {
            const bytes_read = decoder.read(buf) catch |err| {
                switch (err) {
                    error.EndOfStream => break,
                    else => return err,
                }
            };

            if (bytes_read == 0) break;

            _ = try buffered_stdout.write(buf[0..bytes_read]);
        }
    } else {
        const buf = try allocator.alloc(
            u8,
            base91.standard.Encoder.calcSize(opts.memory),
        );

        var encoder = try base91.encodeStream(
            allocator,
            buffered_stdin,
            .{
                .buf_size = opts.memory,
                //.buf_size = base91.standard.Encoder.calcSize(opts.memory),
            },
        );

        while (true) {
            const bytes_read = try encoder.read(buf);

            if (bytes_read == 0) break;

            _ = try buffered_stdout.write(buf[0..bytes_read]);
        }
    }

    try buf_writer.flush();
}
