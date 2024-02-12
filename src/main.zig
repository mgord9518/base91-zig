const std = @import("std");
const base91 = @import("base91");
const clap = @import("clap");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    // The amount to read from stdin in one chunk.
    // The memory allocated will be more than twice this number as it needs
    // an output buffer as well
    var buf_size: usize = 1024 * 256;

    const params = comptime clap.parseParamsComptime(
        \\-h, --help           display this help and exit
        \\-m, --memory <usize> change the stdin buffer size (default: 256KiB)
        \\-d, --decode         decode instead of encode
        //        \\    --alphabet <str> use a different basE91 alphabet (must be 91 chars long)
    );

    var res = try clap.parse(
        clap.Help,
        &params,
        clap.parsers.default,
        .{ .allocator = allocator },
    );
    defer res.deinit();

    if (res.args.help != 0) {
        // Obtain the longest argument length
        var longest_normal: usize = 0;
        var longest_long_only: usize = 0;
        for (params) |param| {
            if (param.names.long) |long_name| {
                if (param.names.short) |_| {
                    if (long_name.len > longest_normal) longest_normal = long_name.len;
                } else {
                    if (long_name.len > longest_long_only) longest_long_only = long_name.len;
                }
            }
        }

        const args = try std.process.argsAlloc(allocator);

        const env_map = try std.process.getEnvMap(allocator);

        var reset: []const u8 = "\x1b[0;0m";
        var orange: []const u8 = "\x1b[0;33m";
        var light_blue: []const u8 = "\x1b[0;94m";
        var light_green: []const u8 = "\x1b[0;92m";
        var cyan: []const u8 = "\x1b[0;36m";

        if (env_map.get("NO_COLOR")) |_| {
            reset = "";
            orange = "";
            light_blue = "";
            light_green = "";
            cyan = "";
        }

        std.debug.print(
            \\{s}usage{s}: {s}{s} {s}[{s}option{s}]...
            \\{s}description{s}: read from standard input and en/decode basE91 to standard output.
            \\
            \\{s}normal options{s}:
            \\
        , .{ orange, reset, light_blue, args[0], reset, light_green, reset, orange, reset, orange, reset });

        // Print all normal arguments and their descriptions
        for (params) |param| {
            if (param.names.short) |short_name| {
                std.debug.print("  {s}-{c}{s}, ", .{ cyan, short_name, reset });
            } else {
                continue;
            }

            if (param.names.long) |long_name| {
                std.debug.print("{s}--{s}{s}:", .{ cyan, long_name, reset });

                // Pad all equal to the longest GNU-style flag
                for (long_name.len..longest_normal) |_| {
                    std.debug.print(" ", .{});
                }

                std.debug.print("  {s}\n", .{param.id.description()});
            }
        }

        std.debug.print(
            \\
            //            \\{s}long-only options{s}:
            //            \\
        , .{});
        //, .{ orange, reset });

        for (params) |param| {
            if (param.names.long) |long_name| {
                if (param.names.short) |_| continue;

                std.debug.print("  {s}--{s}{s}:", .{ cyan, long_name, reset });

                // Pad all equal to the longest GNU-style flag
                for (long_name.len..longest_long_only) |_| {
                    std.debug.print(" ", .{});
                }

                std.debug.print("  {s}\n", .{param.id.description()});
            }
        }

        std.debug.print(
            \\
            \\{s}enviornment variables{s}:
            \\  {s}NO_COLOR{s}: disable color
            \\
            \\
        , .{ orange, reset, cyan, reset });

        return;
    }

    if (res.args.memory) |n| buf_size = n;

    //    if (res.args.alphabet) |alphabet| {
    //        if (alphabet.len != 91) {}
    //    }

    const buf = try allocator.alloc(u8, buf_size * 2);

    // Buffer stdin and stdout
    const stdin = std.io.getStdIn().reader();
    var buf_reader = std.io.bufferedReader(stdin);
    const buffered_stdin = buf_reader.reader();

    const stdout = std.io.getStdOut().writer();
    var buf_writer = std.io.bufferedWriter(stdout);
    const buffered_stdout = buf_writer.writer();

    //    var fifo = std.fifo.LinearFifo(u8, .Slice).init(buf);
    //        var fifo = std.fifo.LinearFifo(u8, .Dynamic).init(allocator);
    //var fifo = std.fifo.LinearFifo(u8, .{ .Static = 256 }).init();
    var bytes_read: usize = 1;

    if (res.args.decode != 0) {
        var decoder = try base91.decodeStream(allocator, buffered_stdin, .{
            .buf_size = base91.standard.Decoder.calcSize(buf_size),
        });

        while (bytes_read > 0) {
            bytes_read = try decoder.read(buf);

            _ = try buffered_stdout.write(buf[0..bytes_read]);
        }
    } else {
        var encoder = try base91.encodeStream(allocator, buffered_stdin, .{
            .buf_size = base91.standard.Decoder.calcSize(buf_size),
        });

        while (bytes_read > 0) {
            bytes_read = try encoder.read(buf);

            _ = try buffered_stdout.write(buf[0..bytes_read]);
        }
    }

    try buf_writer.flush();
}
