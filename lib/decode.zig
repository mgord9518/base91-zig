const std = @import("std");
const base91 = @import("base91.zig");

pub const DecodeOptions = struct {};

pub fn StreamDecoder(comptime ReaderType: type) type {
    return struct {
        table: [256]?u8,

        in_stream: ReaderType,

        bit_queue: u32 = 0,
        nbits: u5 = 0,
        val: ?u32 = null,
        finished: bool = false,

        const Self = @This();
        pub const Error = ReaderType.Error || ReadByteError || error{NoSpaceLeft};
        pub const Reader = std.io.Reader(*Self, Error, read);

        pub const Options = struct {
            source: ReaderType,
            alphabet: [91]u8 = base91.standard_alphabet_chars,
        };

        pub fn init(opts: Options) Self {
            var table: [256]?u8 = .{null} ** 256;

            // Populate the array with all valid alphabet chars
            for (opts.alphabet, 0..) |byte, idx| {
                table[byte] = @truncate(idx);
            }

            return .{
                .in_stream = opts.source,
                .table = table,
            };
        }

        fn finish(self: *Self) error{EndOfStream}!u8 {
            if (self.val) |val| {
                self.bit_queue |= val << self.nbits;

                self.val = null;

                return @truncate(self.bit_queue);
            }

            return error.EndOfStream;
        }

        pub const ReadByteError = ReaderType.Error || error{EndOfStream};

        pub fn readByte(self: *Self) ReadByteError!u8 {
            // Load the bit buffer
            // After each iteration, it may contain between 0-2 bytes, which
            // is why we have to do it in a loop
            while (self.nbits < 8) {
                const byte = self.in_stream.readByte() catch |err| {
                    if (err != error.EndOfStream) {
                        return err;
                    }

                    return self.finish();
                };

                const d = self.table[byte] orelse continue;

                if (self.val) |v| {
                    const val = v + @as(u32, d) * 91;

                    self.bit_queue |= val << self.nbits;

                    if ((val & 0x1fff) > 88) {
                        self.nbits += 13;
                    } else {
                        self.nbits += 14;
                    }

                    self.val = null;
                } else {
                    self.val = d;
                }
            }

            defer {
                self.bit_queue >>= 8;
                self.nbits -= 8;
            }

            return @truncate(self.bit_queue);
        }

        pub fn reader(self: *Self) Reader {
            return .{ .context = self };
        }

        pub fn read(self: *Self, buffer: []u8) !usize {
            if (self.finished) {
                return error.EndOfStream;
            }

            if (buffer.len == 0) {
                self.finished = true;
                return 0;
            }

            buffer[0] = self.readByte() catch |err| {
                if (err == error.EndOfStream) {
                    self.finished = true;
                    return 0;
                }

                return err;
            };

            return 1;
        }
    };
}
