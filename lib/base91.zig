// Idiomatic re-implementation of basE91 in Zig
// Ported from <https://base91.sourceforge.net/> (Java and C implementations)

const std = @import("std");
const decode = @import("decode.zig");
const encode = @import("encode.zig");

/// The standard basE91 alphabet as defined in <https://base91.sourceforge.net>
pub const standard_alphabet_chars = [91]u8{
    'A', 'B', 'C', 'D', 'E', 'F', 'G',
    'H', 'I', 'J', 'K', 'L', 'M', 'N',
    'O', 'P', 'Q', 'R', 'S', 'T', 'U',
    'V', 'W', 'X', 'Y', 'Z', 'a', 'b',
    'c', 'd', 'e', 'f', 'g', 'h', 'i',
    'j', 'k', 'l', 'm', 'n', 'o', 'p',
    'q', 'r', 's', 't', 'u', 'v', 'w',
    'x', 'y', 'z', '0', '1', '2', '3',
    '4', '5', '6', '7', '8', '9', '!',
    '#', '$', '%', '&', '(', ')', '*',
    '+', ',', '.', '/', ':', ';', '<',
    '=', '>', '?', '@', '[', ']', '^',
    '_', '`', '{', '|', '}', '~', '"',
};

pub const Base91Error = error{InvalidByte};

pub const EncodeOptions = struct {
    buf_size: usize = 4096,
};

pub fn encodeStream(
    allocator: std.mem.Allocator,
    reader: anytype,
    opts: EncodeOptions,
) !encode.StreamEncoder(@TypeOf(reader)) {
    return try encode.StreamEncoder(@TypeOf(reader)).init(.{
        .allocator = allocator,
        .source = reader,
        .buf_size = opts.buf_size,
    });
}

pub const DecodeOptions = struct {};

pub fn decodeStream(
    reader: anytype,
    opts: DecodeOptions,
) decode.StreamDecoder(@TypeOf(reader)) {
    _ = opts;

    return decode.StreamDecoder(@TypeOf(reader)).init(.{
        .source = reader,
    });
}
