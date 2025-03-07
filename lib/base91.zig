// Idiomatic re-implementation of basE91 in Zig
// Ported from <https://base91.sourceforge.net/> (Java and C implementations)

const std = @import("std");
const expect = std.testing.expect;
const io = std.io;

pub const Codecs = struct {
    alphabet_chars: [91]u8,
    terminator: ?u8,
    Encoder: Encoder,
    Decoder: Decoder,
};

pub const standard_alphabet_chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789!#$%&()*+,./:;<=>?@[]^_`{|}~\"".*;

/// The standard basE91 alphabet as defined in <https://base91.sourceforge.net>
pub const standard = Codecs{
    .alphabet_chars = standard_alphabet_chars,
    .terminator = null,
    .Encoder = Encoder.init(standard_alphabet_chars, null),
    .Decoder = Decoder.init(standard_alphabet_chars, null),
};

pub const standard_terminated = Codecs{
    .alphabet_chars = standard_alphabet_chars,
    .terminator = null,
    .Encoder = Encoder.init(standard_alphabet_chars, '-'),
    .Decoder = Decoder.init(standard_alphabet_chars, '-'),
};

/// This replaces the `"` char with ` ` (space) in order to make it easier to
/// quote encoded data in most programming languages
pub const quote_safe_alphabet_chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789!#$%&()*+,./:;<=>?@[]^_`{|}~ ".*;

pub const quote_safe = Codecs{
    .alphabet_chars = quote_safe_alphabet_chars,
    .terminator = null,
    .Encoder = Encoder.init(quote_safe_alphabet_chars, null),
    .Decoder = Decoder.init(quote_safe_alphabet_chars, null),
};

/// There are only 94 total printable ascii chars and the standard
/// basE91 alphabet takes everything but `-`, `\` and `'`. As the dash
/// is the least-likely to have special meaning while inside of quotes,
/// it is the best candidate for using as a termination character
pub const quote_safe_terminated = Codecs{
    .alphabet_chars = quote_safe_alphabet_chars,
    .terminator = null,
    .Encoder = Encoder.init(quote_safe_alphabet_chars, '-'),
    .Decoder = Decoder.init(quote_safe_alphabet_chars, '-'),
};

pub const Base91Error = error{ InsufficientBuffer, InvalidByte };

pub const EncodeOptions = struct {
    buf_size: usize = 4096,
};

pub fn encodeStream(
    allocator: std.mem.Allocator,
    reader: anytype,
    opts: EncodeOptions,
) !StreamEncoder(@TypeOf(reader)) {
    return try StreamEncoder(@TypeOf(reader)).init(.{
        .allocator = allocator,
        .source = reader,
        .buf_size = opts.buf_size,
    });
}

/// Similar API to Zig stdlib's compression code, intended to simplify
/// processing data streams
pub fn StreamEncoder(comptime ReaderType: type) type {
    return struct {
        allocator: std.mem.Allocator,
        encoder: Encoder,
        buf: []u8,
        in_reader: ReaderType,

        const Self = @This();
        pub const Error = ReaderType.Error || error{InsufficientBuffer};
        pub const Reader = io.Reader(*Self, Error, read);

        pub const Options = struct {
            allocator: std.mem.Allocator,
            encoder: Encoder = standard.Encoder,
            source: ReaderType,

            // The buffer is used for reading from `in_reader`, so it should be
            // set to Decoder.calcSize() of whatever buffer you use to encode
            buf_size: usize,
        };

        pub fn init(options: Options) !Self {
            const buf = try options.allocator.alloc(u8, options.buf_size);

            return .{
                .allocator = options.allocator,
                .encoder = options.encoder,
                .in_reader = options.source,
                .buf = buf,
            };
        }

        pub fn read(self: *Self, buffer: []u8) !usize {
            const read_to = standard.Decoder.calcSize(buffer.len);
            const read_bytes = try self.in_reader.read(self.buf);

            //var encoded: []const u8 = undefined;

            if (read_bytes > 0) {
                const encoded = try self.encoder.encodeChunk(
                    buffer[0..read_to],
                    self.buf[0..read_bytes],
                );

                return encoded.len;
            }

            return self.encoder.end(buffer).len;
        }

        pub fn reader(self: *Self) Reader {
            return .{ .context = self };
        }
    };
}

pub const DecodeOptions = struct {};

pub fn decodeStream(
    reader: anytype,
    opts: DecodeOptions,
) !StreamDecoder(@TypeOf(reader)) {
    _ = opts;
    return try StreamDecoder(@TypeOf(reader)).init(.{
        .source = reader,
    });
}

pub fn StreamDecoder(comptime ReaderType: type) type {
    return struct {
        table: [256]?u8,
        terminator: ?u8,

        in_stream: ReaderType,

        bit_queue: usize = 0,
        nbits: u5 = 0,
        val: ?usize = null,

        const Self = @This();
        pub const Error = ReaderType.Error || error{InsufficientBuffer};
        pub const Reader = io.Reader(*Self, Error, read);

        pub const Options = struct {
            decoder: Decoder = standard.Decoder,
            source: ReaderType,
            alphabet: [91]u8 = standard_alphabet_chars,
            terminator: ?u8 = '-',
        };

        pub fn init(opts: Options) !Self {
            var table: [256]?u8 = .{null} ** 256;

            // Populate the array with all valid alphabet chars
            for (opts.alphabet, 0..) |byte, idx| {
                table[byte] = @as(u8, @truncate(idx));
            }

            return .{
                .in_stream = opts.source,
                .table = table,
                .terminator = opts.terminator,
            };
        }

        fn advanceByte(self: *Self, byte: u8) void {
            const d = self.table[byte] orelse return;

            if (self.val) |*val| {
                val.* += @as(u32, d) * 91;

                self.bit_queue |= val.* << self.nbits;

                if ((val.* & 0x1fff) > 88) {
                    self.nbits += 13;
                } else {
                    self.nbits += 14;
                }

                self.val = null;
            } else {
                self.val = d;
            }
        }

        pub fn readByte(self: *Self) !u8 {
            // Load the bit buffer
            // After each iteration, it may contain between 0-2 bytes, which
            // is why we have to do it in a loop
            while (self.nbits < 8) {
                const byte = self.in_stream.readByte() catch |err| {
                    if (err == error.EndOfStream) {
                        return try self.finishWriting();
                    }

                    return err;
                };

                _ = self.advanceByte(byte);
            }

            defer {
                self.bit_queue >>= 8;
                self.nbits -= 8;
            }

            return @truncate(self.bit_queue);
        }

        pub fn read(self: *Self, buffer: []u8) !usize {
            if (buffer.len >= 1) {
                buffer[0] = try self.readByte();
                return 1;
            }

            return error.NoSpaceLeft;
        }

        fn finishWriting(self: *Self) error{EndOfStream}!u8 {
            if (self.val) |val| {
                self.val = null;
                return @truncate(self.bit_queue | (val << self.nbits));
            }

            return error.EndOfStream;
        }
    };
}

pub const Encoder = struct {
    alphabet: [91]u8,
    terminator: ?u8,

    queue: usize = 0,
    nbits: u5 = 0,
    buf_pos: usize = 0,

    pub fn init(alphabet_chars: [91]u8, terminator: ?u8) Encoder {
        return Encoder{ .alphabet = alphabet_chars, .terminator = terminator };
    }

    /// Estimate the buffer size needed in a worst-case scenario
    /// 1.2308 is used as it's the worst possible encoding size
    pub fn calcSize(self: *const Encoder, src_len: usize) usize {
        //const ret = @as(usize, @intFromFloat(@as(f32, @floatFromInt(src_len)) * 1.2308)) + 1;
        const ret = @as(usize, @intFromFloat(@as(f32, @floatFromInt(src_len)) * 1.5308)) + 1;

        if (self.terminator) |_| {
            return ret + 1;
        }

        return ret;
    }

    /// Takes a u8 slice and returns the basE91 converted slice
    /// This should be used on small strings (anything that can completely fit
    /// into a single buffer, so anything larger than a few MB is probably best
    /// broken up and used with `encodeChunk`)
    pub fn encode(self: *Encoder, buf: []u8, in: []const u8) ![]u8 {
        // This function is made to operate on its own, so clear any previous
        // data
        self.buf_pos = 0;
        self.nbits = 0;
        self.queue = 0;

        // Throw away this slice because it's just our array with a length
        // attached
        const written_bytes = try self.encodeChunk(buf, in);

        // The end of our data is a combination of the current offset and
        // however long the end bytes are (0 to 2)
        const end_len = self.end(buf[written_bytes.len..]).len;

        // Only return the counted bytes in case the allocated buffer is bigger
        // than the output. If the entire buffer was returned, it could give random
        // bytes after the output
        return buf[0 .. written_bytes.len + end_len];
    }

    /// This is so that a large amount of information (bigger than mem buffer)
    /// can be encoded. Call `end` to get any bytes that might be left over
    pub fn encodeChunk(self: *Encoder, buf: []u8, in: []const u8) ![]u8 {
        // Resets the buffer offset, the only reason this is a shared variable
        // at all is because `self.end` needs it to finish writing to the
        // same buffer
        self.buf_pos = 0;

        for (in) |byte| {
            if (self.buf_pos >= buf.len) {
                return Base91Error.InsufficientBuffer;
                //return "";
            }

            self.queue |= @as(u32, @intCast(byte)) << self.nbits;

            self.nbits += 8;
            if (self.nbits > 13) {
                var ev: usize = @as(u13, @truncate(self.queue));

                if (ev > 88) {
                    self.queue >>= 13;
                    self.nbits -= 13;
                } else {
                    ev = @as(u14, @truncate(self.queue));
                    self.queue >>= 14;
                    self.nbits -= 14;
                }

                buf[self.buf_pos] = self.alphabet[ev % 91];
                self.buf_pos += 1;

                buf[self.buf_pos] = self.alphabet[ev / 91];
                self.buf_pos += 1;
            }
        }

        return buf[0..self.buf_pos];
    }

    /// This function is to clean up after any calls to `encodeChunk`
    /// Using `encode` calls this automatically
    pub inline fn end(self: *Encoder, buf: []u8) []u8 {
        self.buf_pos = 0;

        // Finish processing remaining bits, write at most 3 bytes (or 2 if no termination char)
        if (self.nbits > 0) {
            buf[self.buf_pos] = self.alphabet[self.queue % 91];
            self.buf_pos += 1;

            if (self.nbits > 7 or self.queue > 90) {
                buf[self.buf_pos] = self.alphabet[self.queue / 91];
                self.buf_pos += 1;
            }
        }

        if (self.terminator) |terminator| {
            buf[self.buf_pos] = terminator;
            self.buf_pos += 1;
        }

        // Clear the encoder's other fields
        self.nbits = 0;
        self.queue = 0;

        return buf[0..self.buf_pos];
    }
};

pub const Decoder = struct {
    table: [256]u8,
    terminator: ?u8,

    queue: usize = 0,
    nbits: u5 = 0,
    val_wrote: bool = true,
    buf_pos: usize = 0,
    val: usize = 0,

    pub fn init(alphabet_chars: [91]u8, terminator: ?u8) Decoder {
        var decoder = Decoder{ .table = undefined, .terminator = terminator };

        // Create array filled with `255`, this byte is used for any non-valid
        // char when decoding
        for (&decoder.table) |*byte| {
            byte.* = 255;
        }

        // Populate the array with all valid alphabet chars
        for (alphabet_chars, 0..) |byte, idx| {
            decoder.table[byte] = @as(u8, @truncate(idx));
        }

        return decoder;
    }

    /// Estimate how big of a buffer is needed in a worst-case scenario
    /// 1.1429 is used as it's the worst possible decoding size
    pub fn calcSize(self: *const Decoder, src_len: usize) usize {
        const ret = @as(usize, @intFromFloat(@as(f128, @floatFromInt(src_len)) / 1.1429));

        if (self.terminator) |_| {
            return ret - 1;
        }

        return ret;
    }

    pub fn decode(self: *Decoder, buf: []u8, in: []const u8) ![]u8 {
        // Clear previous data if any
        self.buf_pos = 0;
        self.nbits = 0;
        self.queue = 0;

        // Throw away this slice because this function is just being called to
        // fill our array
        const written_bytes = try self.decodeChunk(buf, in);

        // The end of our data is a combination of the current offset and
        // however long the end bytes are (either 0 or 1)
        const end_len = self.end(buf[written_bytes.len..]).len;

        return buf[0 .. written_bytes.len + end_len];
    }

    pub fn decodeChunk(self: *Decoder, buf: []u8, in: []const u8) ![]u8 {
        self.buf_pos = 0;

        for (in) |byte| {
            const d: u32 = self.table[byte];

            // If the byte we get is the terminator, finish writing the queue
            // and act as if starting from a new stream
            if (self.terminator) |terminator| {
                if (terminator == byte) _ = self.finishWriting(buf);
            }

            // Ignore invalid bytes (anything not given in the alphabet provided)
            if (d == 255) continue;

            if (self.val_wrote) {
                self.val = d;
                self.val_wrote = false;
                continue;
            }

            self.val += d * 91;
            const dv = @as(u13, @truncate(self.val));

            self.queue |= self.val << self.nbits;

            if (dv > 88) {
                self.nbits += 13;
            } else {
                self.nbits += 14;
            }

            while (self.nbits > 7) {
                buf[self.buf_pos] = @as(u8, @truncate(self.queue));
                self.buf_pos += 1;

                self.queue >>= 8;
                self.nbits -= 8;
            }

            self.val_wrote = true;
        }

        return buf[0..self.buf_pos];
    }

    /// Finish processing remaining bits, write at most 1 bytes
    pub inline fn end(self: *Decoder, buf: []u8) []u8 {
        self.buf_pos = 0;

        self.finishWriting(buf);

        return buf[0..self.buf_pos];
    }

    // Write last bytes without clearing the buffer location
    inline fn finishWriting(self: *Decoder, buf: []u8) void {
        if (!self.val_wrote) {
            buf[self.buf_pos] = @as(u8, @truncate(self.queue | (self.val << self.nbits)));
            self.buf_pos += 1;
        }

        self.nbits = 0;
        self.queue = 0;
        self.val_wrote = true;
    }
};
