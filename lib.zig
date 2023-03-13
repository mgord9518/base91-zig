// Idiomatic re-implementation of basE91 in Zig
// Ported from <https://base91.sourceforge.net/> (Java and C implementations)

pub const base91 = @import("lib/base91.zig");
pub const std = @import("std");
pub const expect = std.testing.expect;

pub const Codecs = base91.Codecs;

pub const standard_alphabet_chars = base91.standard_alphabet_chars;
pub const standard = base91.standard;
pub const standard_terminated = base91.standard_terminated;

pub const quote_safe_alphabet_chars = base91.quote_safe_alphabet_chars;
pub const quote_safe = base91.quote_safe;
pub const quote_safe_terminated = base91.quote_safe_terminated;

pub const Encoder = base91.Encoder;
pub const Decoder = base91.Decoder;

test "encode single buffer write (standard encoder)" {
    var encoder = standard.Encoder;

    var buf: [256]u8 = undefined;

    try expect(std.mem.eql(u8, "fPNKd", try encoder.encode(&buf, "test")));
    try expect(std.mem.eql(u8, "#G(Ic,5ph#77&xrmlrjgs@DZ7UB>xQGr", try encoder.encode(&buf, "abcdefghijklmnopqrstuvwxyz")));
}

test "decode single buffer write (standard encoder)" {
    var decoder = standard_terminated.Decoder;

    var buf: [256]u8 = undefined;

    try expect(std.mem.eql(u8, "TEST", try decoder.decode(&buf, "\"OdHV")));
    try expect(std.mem.eql(u8, "ABCDEFGHIJKLMNOPQRSTUVWXYZ", try decoder.decode(&buf, "fG^F%w_o%5qOdwQbFrzd[5eYAP;gMP+f")));
}
