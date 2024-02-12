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

pub const StreamEncoder = base91.StreamEncoder;
pub const StreamDecoder = base91.StreamDecoder;

pub const decodeStream = base91.decodeStream;
pub const encodeStream = base91.encodeStream;

test "encode single buffer write (standard encoder)" {
    var encoder = standard.Encoder;

    var buf: [256]u8 = undefined;

    for (unencoded, standard_encoded) |decoded, encoded| {
        try expect(std.mem.eql(
            u8,
            encoded,
            try encoder.encode(&buf, decoded),
        ));
    }
}

test "encode single buffer write (quote-safe encoder)" {
    var encoder = quote_safe.Encoder;

    var buf: [256]u8 = undefined;

    for (unencoded, quote_safe_encoded) |decoded, encoded| {
        try expect(std.mem.eql(
            u8,
            encoded,
            try encoder.encode(&buf, decoded),
        ));
    }
}

test "decode single buffer write (standard decoder)" {
    var decoder = standard.Decoder;

    var buf: [256]u8 = undefined;

    for (unencoded, standard_encoded) |decoded, encoded| {
        try expect(std.mem.eql(
            u8,
            decoded,
            try decoder.decode(&buf, encoded),
        ));
    }
}

test "decode single buffer write (quote-safe decoder)" {
    var decoder = quote_safe.Decoder;

    var buf: [256]u8 = undefined;

    for (unencoded, quote_safe_encoded) |decoded, encoded| {
        try expect(std.mem.eql(
            u8,
            decoded,
            try decoder.decode(&buf, encoded),
        ));
    }
}

const unencoded = &[_][]const u8{
    "test",
    "abcdefghijklmnopqrstuvwxyz",
    "TEST",
    "ABCDEFGHIJKLMNOPQRSTUVWXYZ",
    "Lorem ipsum dolor sit amet, consectetur adipiscing elit",
};

const standard_encoded = &[_][]const u8{
    "fPNKd",
    "#G(Ic,5ph#77&xrmlrjgs@DZ7UB>xQGr",
    "\"OdHV",
    "fG^F%w_o%5qOdwQbFrzd[5eYAP;gMP+f",
    "Drzg`<fz+$Q;/ETj~i/2:WP1qU2uG9_ou\"L^;meP(Ig,!eLU2u8Pwn32Wf7=YC,RY6KF",
};

const quote_safe_encoded = &[_][]const u8{
    "fPNKd",
    "#G(Ic,5ph#77&xrmlrjgs@DZ7UB>xQGr",
    " OdHV",
    "fG^F%w_o%5qOdwQbFrzd[5eYAP;gMP+f",
    "Drzg`<fz+$Q;/ETj~i/2:WP1qU2uG9_ou L^;meP(Ig,!eLU2u8Pwn32Wf7=YC,RY6KF",
};
