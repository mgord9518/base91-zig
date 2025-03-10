// TODO: refactor (like done with the decoder)

const std = @import("std");
const decode = @import("decode.zig");
const base91 = @import("base91.zig");

pub const Codecs = struct {
    alphabet_chars: [91]u8,
    Encoder: Encoder,
};

pub const standard = Codecs{
    .alphabet_chars = base91.standard_alphabet_chars,
    .Encoder = Encoder.init(base91.standard_alphabet_chars),
};

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
        pub const Reader = std.io.Reader(*Self, Error, read);

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
            const read_to = buffer.len;
            const read_bytes = try self.in_reader.read(self.buf);

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

pub const Encoder = struct {
    alphabet: [91]u8,

    queue: usize = 0,
    nbits: u5 = 0,
    buf_pos: usize = 0,

    pub fn init(alphabet_chars: [91]u8) Encoder {
        return Encoder{ .alphabet = alphabet_chars };
    }

    /// Estimate the buffer size needed in a worst-case scenario
    /// 1.2308 is used as it's the worst possible encoding size
    pub fn calcSize(self: *const Encoder, src_len: usize) usize {
        _ = self;

        const ret = @as(usize, @intFromFloat(@as(f32, @floatFromInt(src_len)) * 1.5308)) + 1;

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
                return error.InsufficientBuffer;
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

        // Clear the encoder's other fields
        self.nbits = 0;
        self.queue = 0;

        return buf[0..self.buf_pos];
    }
};
