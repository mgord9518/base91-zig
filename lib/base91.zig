// Idiomatic re-implementation of basE91 in Zig
// Ported from <https://base91.sourceforge.net/> (Java and C implementations)

const std = @import("std");
const expect = std.testing.expect;

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
    pub fn calcSize(encoder: *const Encoder, src_len: usize) usize {
        const ret = @floatToInt(usize, @intToFloat(f32, src_len) * 1.2308) + 1;

        if (encoder.terminator) |_| {
            return ret + 1;
        }

        return ret;
    }

    /// Takes a u8 slice and returns the basE91 converted slice
    /// This should be used on small strings (anything that can completely fit
    /// into a single buffer, so anything larger than a few MB is probably best
    /// broken up and used with `encodeChunk`)
    pub fn encode(encoder: *Encoder, buf: []u8, in: []const u8) ![]u8 {
        // This function is made to operate on its own, so clear any previous
        // data
        encoder.buf_pos = 0;
        encoder.nbits = 0;
        encoder.queue = 0;

        // Throw away this slice because it's just our array with a length
        // attached
        _ = try encoder.encodeChunk(buf, in);

        // The end of our data is a combination of the current offset and
        // however long the end bytes are (0 to 2)
        const end_len = encoder.buf_pos + encoder.end(buf).len;

        // Only return the counted bytes in case the allocated buffer is bigger
        // than the output. If the entire buffer was returned, it could give random
        // bytes after the output
        return buf[0..end_len];
    }

    /// This is so that a large amount of information (bigger than mem buffer)
    /// can be encoded. Call `end` to get any bytes that might be left over
    pub fn encodeChunk(encoder: *Encoder, buf: []u8, in: []const u8) ![]u8 {
        // Resets the buffer offset, the only reason this is a shared variable
        // at all is because `encoder.end` needs it to finish writing to the
        // same buffer
        encoder.buf_pos = 0;

        for (in) |byte| {
            encoder.queue |= @intCast(u32, byte) << encoder.nbits;

            encoder.nbits += 8;
            if (encoder.nbits > 13) {
                var ev: usize = @truncate(u13, encoder.queue);

                if (ev > 88) {
                    encoder.queue >>= 13;
                    encoder.nbits -= 13;
                } else {
                    ev = @truncate(u14, encoder.queue);
                    encoder.queue >>= 14;
                    encoder.nbits -= 14;
                }

                buf[encoder.buf_pos] = encoder.alphabet[ev % 91];
                encoder.buf_pos += 1;

                buf[encoder.buf_pos] = encoder.alphabet[ev / 91];
                encoder.buf_pos += 1;
            }
        }

        // Only return the counted bytes in case the allocated buffer is bigger
        // than the output. If the entire buffer was returned, it could give random
        // bytes after the output
        return buf[0..encoder.buf_pos];
    }

    /// This function is to clean up after any calls to `encodeChunk`
    /// Using `encode` calls this automatically
    pub inline fn end(encoder: *Encoder, buf: []u8) []u8 {
        const offset: usize = encoder.buf_pos;

        // Finish processing remaining bits, write at most 3 bytes (or 2 if no termination char)
        if (encoder.nbits > 0) {
            buf[encoder.buf_pos] = encoder.alphabet[encoder.queue % 91];
            encoder.buf_pos += 1;

            if (encoder.nbits > 7 or encoder.queue > 90) {
                buf[encoder.buf_pos] = encoder.alphabet[encoder.queue / 91];
                encoder.buf_pos += 1;
            }
        }

        if (encoder.terminator) |terminator| {
            buf[encoder.buf_pos] = terminator;
            encoder.buf_pos += 1;
        }

        // Clear the encoder's fields (encoder.n must be cleared with defer as
        // it's used in the return value)
        defer encoder.buf_pos = 0;
        encoder.nbits = 0;
        encoder.queue = 0;

        return buf[offset..encoder.buf_pos];
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
            decoder.table[byte] = @truncate(u8, idx);
        }

        return decoder;
    }

    /// Estimate how big of a buffer is needed in a worst-case scenario
    /// 1.1429 is used as it's the worst possible decoding size
    pub fn calcSize(decoder: *const Decoder, src_len: usize) usize {
        const ret = @floatToInt(usize, @intToFloat(f128, src_len) / 1.1429);

        if (decoder.terminator) |_| {
            return ret - 1;
        }

        return ret;
    }

    pub fn decode(decoder: *Decoder, buf: []u8, in: []const u8) ![]u8 {
        // Clear previous data if any
        decoder.buf_pos = 0;
        decoder.nbits = 0;
        decoder.queue = 0;

        // Throw away this slice because this function is just being called to
        // fill our array
        _ = try decoder.decodeChunk(buf, in);

        // The end of our data is a combination of the current offset and
        // however long the end bytes are (either 0 or 1)
        const end_pos = decoder.buf_pos + decoder.end(buf).len;

        // Only return the counted bytes in case the allocated buffer is bigger
        // than the output (likely).
        return buf[0..end_pos];
    }

    pub fn decodeChunk(decoder: *Decoder, buf: []u8, in: []const u8) ![]u8 {
        decoder.buf_pos = 0;

        for (in) |byte| {
            var d: u32 = decoder.table[byte];

            // If the byte we get is the terminator, finish writing the queue
            // and act as if starting from a new stream
            if (decoder.terminator) |terminator| {
                if (terminator == byte) _ = decoder.finishWriting(buf);
            }

            // Ignore invalid bytes (anything not given in the alphabet provided)
            if (d == 255) continue;

            if (decoder.val_wrote) {
                decoder.val = d;
                decoder.val_wrote = false;
                continue;
            }

            decoder.val += d * 91;
            const dv = @truncate(u13, decoder.val);

            decoder.queue |= decoder.val << decoder.nbits;

            if (dv > 88) {
                decoder.nbits += 13;
            } else {
                decoder.nbits += 14;
            }

            while (decoder.nbits > 7) {
                buf[decoder.buf_pos] = @truncate(u8, decoder.queue);
                decoder.buf_pos += 1;

                decoder.queue >>= 8;
                decoder.nbits -= 8;
            }

            decoder.val_wrote = true;
        }

        return buf[0..decoder.buf_pos];
    }

    /// Finish processing remaining bits, write at most 1 bytes
    pub inline fn end(decoder: *Decoder, buf: []u8) []u8 {
        const offset = decoder.buf_pos;

        decoder.finishWriting(buf);
        defer decoder.buf_pos = 0;

        return buf[offset..decoder.buf_pos];
    }

    // Write last bytes without clearing the buffer location
    inline fn finishWriting(decoder: *Decoder, buf: []u8) void {
        if (!decoder.val_wrote) {
            buf[decoder.buf_pos] = @truncate(u8, decoder.queue | (decoder.val << decoder.nbits));
            decoder.buf_pos += 1;
        }

        decoder.nbits = 0;
        decoder.queue = 0;
        decoder.val_wrote = true;
    }
};
