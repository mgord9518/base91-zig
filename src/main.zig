const std = @import("std");
const base91 = @import("base91");
const eql = std.mem.eql;

const Options = struct {
    help: bool = false,
    decode: bool = false,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    var opts = Options{};

    // Parse options
    for (args) |arg| {
        if (eql(u8, arg, "-h") or eql(u8, arg, "--help")) {
            opts.help = true;
        }

        if (eql(u8, arg, "-d") or eql(u8, arg, "--decode")) {
            opts.decode = true;
        }
    }

    if (opts.help) {
        std.debug.print(
            \\usage: {s} [option]...
            \\description: read from standard input and en/decode basE91 to standard output.
            \\
            \\normal options:
            \\  -h, --help:    display this help and exit
            \\  -d, --decode:  decode instead of encode
            \\
        , .{args[0]});

        return;
    }

    const stdin = std.io.getStdIn().reader();
    var buf_reader = std.io.bufferedReader(stdin);
    const buffered_stdin = buf_reader.reader();

    const stdout = std.io.getStdOut();

    const buf = try allocator.alloc(u8, 1024 * 4);
    defer allocator.free(buf);

    if (opts.decode) {
        var decoder = base91.decodeStream(buffered_stdin, .{});

        while (true) {
            const bytes_read = try decoder.reader().readAll(buf);

            _ = try stdout.writer().writeAll(buf[0..bytes_read]);

            if (bytes_read < buf.len) break;
        }
    } else {
        var encoder = try base91.encodeStream(
            allocator,
            buffered_stdin,
            .{
                .buf_size = 4096,
            },
        );

        while (true) {
            const bytes_read = try encoder.read(buf);

            if (bytes_read == 0) break;

            _ = try stdout.write(buf[0..bytes_read]);
        }
    }
}
