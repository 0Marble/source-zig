const std = @import("std");
const source = @import("source.zig");

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectError = std.testing.expectError;
const expectEqualStrings = std.testing.expectEqualStrings;
const SourceError = source.Source.Error;
const Source = source.Source;
const Location = source.Location;
const Span = source.Span;

test "Creation: single-line" {
    var src = Source.init("Hello World!", std.testing.allocator) catch unreachable;
    defer src.deinit();
}
test "Creation: multi-line" {
    var src = Source.init("Hello World!\nFoo Bar", std.testing.allocator) catch unreachable;
    defer src.deinit();
}
test "Creation: ends with newline" {
    var src = Source.init("Hello World!\nFoo Bar\n", std.testing.allocator) catch unreachable;
    defer src.deinit();
}
test "Creation: OOM" {
    var buf: [0]u8 = .{};
    var fba = std.heap.FixedBufferAllocator.init(&buf);
    try expectError(
        std.mem.Allocator.Error.OutOfMemory,
        Source.init("Hello World!\nFoo Bar\n", fba.allocator()),
    );
    try expect(fba.end_index == 0);
}

test "Basic: read to end" {
    const txt = "Hello World!\nFoo Bar\nBaz";
    var src = try Source.init(txt, std.testing.allocator);
    defer src.deinit();

    for (txt) |c| {
        try expectEqual(c, src.read());
    }
    try expectError(SourceError.UnexpectedEnd, src.read());
    try expect(src.finished());
}
test "Basic: skip to end" {
    const txt = "Hello World!\nFoo Bar\nBaz";
    var src = try Source.init(txt, std.testing.allocator);
    defer src.deinit();

    for (txt) |_| {
        try expect(src.skip());
    }
    try expect(!src.skip());
    try expect(src.finished());
}
test "Basic: skipN" {
    const t1 = "Foo";
    const t2 = "Bar";
    var src = try Source.init(t1 ++ t2, std.testing.allocator);
    defer src.deinit();

    try expectEqual(t1.len, src.skipN(t1.len));
    try expectEqual('B', src.peek());
    try expectEqual(t2.len, src.skipN(t2.len));
    try expect(src.finished());

    src.reset();
    const big_text = t1 ++ "-----" ++ t2;
    try expectEqual(t1.len + t2.len, src.skipN(big_text.len));
}
test "Basic: peek" {
    const txt = "Hello World!\nFoo Bar\nBaz";
    var src = try Source.init(txt, std.testing.allocator);
    defer src.deinit();

    for (txt) |c| {
        try expectEqual(c, src.peek());
        _ = src.skip();
    }
    try expect(src.peek() == null);
}
test "Basic: readExpect comptimeInt" {
    const txt = "Hello World!\nFoo Bar\nBaz";
    var src = try Source.init(txt, std.testing.allocator);
    defer src.deinit();
    try expectEqual('H', src.readExpect('H', null));
}
test "Basic: readExpect Int" {
    const txt = "Hello World!\nFoo Bar\nBaz";
    var src = try Source.init(txt, std.testing.allocator);
    defer src.deinit();

    for (txt) |c| {
        try expectEqual(c, src.readExpect(c, null));
    }
    src.reset();
}
test "Basic: readExpect tuple" {
    const txt = "Hello World!\nFoo Bar\nBaz";
    var src = try Source.init(txt, std.testing.allocator);
    defer src.deinit();
    try expectEqual('H', src.readExpect(.{ 'H', 'e', 'l', 'o' }, null));
    try expectEqual('e', src.readExpect(.{ 'H', 'e', 'l', 'o' }, null));
    try expectEqual('l', src.readExpect(.{ 'H', 'e', 'l', 'o' }, null));
    try expectEqual('l', src.readExpect(.{ 'H', 'e', 'l', 'o' }, null));
    try expectEqual('o', src.readExpect(.{ 'H', 'e', 'l', 'o' }, null));
}
test "Basic: readExpect mismatch" {
    const txt = "Hello World!\nFoo Bar\nBaz";
    var src = try Source.init(txt, std.testing.allocator);
    defer src.deinit();

    var got: u8 = 0;
    try expectEqual(SourceError.Mismatch, src.readExpect('W', &got));
    try expectEqual('H', got);
}
test "Basic: readExpect unexpected end" {
    const txt = "";
    var src = try Source.init(txt, std.testing.allocator);
    defer src.deinit();

    var got: u8 = 69;
    try expectEqual(SourceError.UnexpectedEnd, src.readExpect('W', &got));
    try expectEqual(0, got);
}
test "Basic: skip whitespace" {
    const txt = "a b\nc  d\n\n     e  \n \n \t f";
    var src = try Source.init(txt, std.testing.allocator);
    defer src.deinit();

    _ = try src.readExpect('a', null);
    src.skipWhitespace();
    _ = try src.readExpect('b', null);
    src.skipWhitespace();
    _ = try src.readExpect('c', null);
    src.skipWhitespace();
    _ = try src.readExpect('d', null);
    src.skipWhitespace();
    _ = try src.readExpect('e', null);
    src.skipWhitespace();
    _ = try src.readExpect('f', null);
}
test "Basic: read and unread" {
    const txt = "abcde";
    var src = try Source.init(txt, std.testing.allocator);
    defer src.deinit();

    src.unread();
    try expectEqual('a', src.read());
    try expectEqual('b', src.read());
    try expectEqual('c', src.read());
    src.unread();
    try expectEqual('c', src.peek());

    try expectEqual('c', src.read());
    try expectEqual('d', src.read());
    try expectEqual('e', src.read());
    src.unread();
    try expectEqual('e', src.peek());
    src.unread();
    try expectEqual('d', src.peek());

    try expectEqual('d', src.read());
    src.unread();
    try expectEqual('d', src.peek());
    src.unread();
    try expectEqual('c', src.peek());
    src.unread();
    try expectEqual('b', src.peek());
    src.unread();
    try expectEqual('a', src.peek());

    try expectEqual('a', src.read());
}

test "Locations: single line" {
    const txt = "Hello World!";
    var src = try Source.init(txt, std.testing.allocator);
    defer src.deinit();

    for (txt, 0..) |_, i| {
        try expectEqual(Location{ .line = 0, .col = i }, src.loc);
        _ = src.skip();
    }
    try expectEqual(Location{ .line = 0, .col = txt.len }, src.loc);
    try expectEqual(Location{ .line = 0, .col = txt.len }, src.end_loc);
}
test "Locations: line starts" {
    const l1 = "Hello World!\n";
    const l2 = "Foo Bar\n";
    const l3 = "Bazz\n";
    const l4 = "\n";
    const txt = l1 ++ l2 ++ l3 ++ l4;
    var src = try Source.init(txt, std.testing.allocator);
    defer src.deinit();

    try expectEqual('H', src.peek());
    try expectEqual(Location{ .line = 0, .col = 0 }, src.loc);
    _ = src.skipN(l1.len);
    try expectEqual('F', src.peek());
    try expectEqual(Location{ .line = 1, .col = 0 }, src.loc);
    _ = src.skipN(l2.len);
    try expectEqual('B', src.peek());
    try expectEqual(Location{ .line = 2, .col = 0 }, src.loc);
    _ = src.skipN(l3.len);
    try expectEqual('\n', src.peek());
    try expectEqual(Location{ .line = 3, .col = 0 }, src.loc);
    _ = src.skipN(l4.len);
    try expectEqual(null, src.peek());
    try expectEqual(Location{ .line = 4, .col = 0 }, src.loc);
    try expectEqual(Location{ .line = 4, .col = 0 }, src.end_loc);
}
test "Locations: multi line" {
    const l1 = "ab\n";
    const l2 = "cde\n";
    const l3 = "f\n";
    const l4 = "gh\n";
    const txt = l1 ++ l2 ++ l3 ++ l4;
    var src = try Source.init(txt, std.testing.allocator);
    defer src.deinit();

    try expectEqual(Location{ .line = 0, .col = 0 }, src.loc);
    _ = try src.readExpect('a', null);
    try expectEqual(Location{ .line = 0, .col = 1 }, src.loc);
    _ = try src.readExpect('b', null);
    try expectEqual(Location{ .line = 0, .col = 2 }, src.loc);
    _ = try src.readExpect('\n', null);
    try expectEqual(Location{ .line = 1, .col = 0 }, src.loc);
    _ = try src.readExpect('c', null);
    try expectEqual(Location{ .line = 1, .col = 1 }, src.loc);
    _ = try src.readExpect('d', null);
    try expectEqual(Location{ .line = 1, .col = 2 }, src.loc);
    _ = try src.readExpect('e', null);
    try expectEqual(Location{ .line = 1, .col = 3 }, src.loc);
    _ = try src.readExpect('\n', null);
    try expectEqual(Location{ .line = 2, .col = 0 }, src.loc);
    _ = try src.readExpect('f', null);
    try expectEqual(Location{ .line = 2, .col = 1 }, src.loc);
    _ = try src.readExpect('\n', null);
    try expectEqual(Location{ .line = 3, .col = 0 }, src.loc);
    _ = try src.readExpect('g', null);
    try expectEqual(Location{ .line = 3, .col = 1 }, src.loc);
    _ = try src.readExpect('h', null);
    try expectEqual(Location{ .line = 3, .col = 2 }, src.loc);
    _ = try src.readExpect('\n', null);
    try expectEqual(Location{ .line = 4, .col = 0 }, src.loc);
    try expectEqual(Location{ .line = 4, .col = 0 }, src.end_loc);
}
test "Locations: unread" {
    const l1 = "ab\n";
    const l2 = "cde\n";
    const l3 = "f\n";
    const l4 = "gh\n";
    const txt = l1 ++ l2 ++ l3 ++ l4;
    var src = try Source.init(txt, std.testing.allocator);
    defer src.deinit();

    try expectEqual(Location{ .line = 0, .col = 0 }, src.loc);
    src.unread();
    try expectEqual(Location{ .line = 0, .col = 0 }, src.loc);

    _ = src.skipN(l1.len);
    try expectEqual('c', src.peek());
    try expectEqual(Location{ .line = 1, .col = 0 }, src.loc);
    src.unread();
    try expectEqual('\n', src.peek());
    try expectEqual(Location{ .line = 0, .col = 2 }, src.loc);
    src.unread();
    try expectEqual('b', src.peek());
    try expectEqual(Location{ .line = 0, .col = 1 }, src.loc);
    src.unread();
    try expectEqual('a', src.peek());
    try expectEqual(Location{ .line = 0, .col = 0 }, src.loc);

    _ = src.skipN(l1.len + l2.len);
    try expectEqual('f', src.peek());
    try expectEqual(Location{ .line = 2, .col = 0 }, src.loc);
    _ = src.skip();
    try expectEqual('\n', src.peek());
    try expectEqual(Location{ .line = 2, .col = 1 }, src.loc);
    src.unread();
    try expectEqual('f', src.peek());
    try expectEqual(Location{ .line = 2, .col = 0 }, src.loc);
}

test "Indices: getSpan" {
    const txt = "0123456789";
    var src = try Source.init(txt, std.testing.allocator);
    defer src.deinit();

    try expectEqualStrings("012", src.getSpan(.{ .start = 0, .end = 3 }));
    try expectEqualStrings("", src.getSpan(.{ .start = 0, .end = 0 }));
    try expectEqualStrings("123", src.getSpan(.{ .start = 1, .end = 4 }));
    try expectEqualStrings("789", src.getSpan(.{ .start = 7, .end = 10 }));
}
test "Indices: getLine" {
    const l1 = "ab\n";
    const l2 = "cde\n";
    const l3 = "f\n";
    const l4 = "gh\n";
    const txt = l1 ++ l2 ++ l3 ++ l4;
    var src = try Source.init(txt, std.testing.allocator);
    defer src.deinit();

    try expectEqual(5, src.getLineCount());
    try expectEqualStrings(l1, src.getLine(0, true));
    try expectEqualStrings(l2, src.getLine(1, true));
    try expectEqualStrings(l3, src.getLine(2, true));
    try expectEqualStrings(l4, src.getLine(3, true));
    try expectEqualStrings("", src.getLine(4, true));
}
test "Indices: locationIndex single line" {
    const txt = "0123456789";
    var src = try Source.init(txt, std.testing.allocator);
    defer src.deinit();

    for (txt, 0..) |_, i| {
        const loc = Location{ .line = 0, .col = i };
        try expectEqual(i, src.locationIndex(loc));
    }
}
test "Indices: locationIndex multi line" {
    const txt =
        \\01
        \\345
        \\
        \\89
    ;
    var src = try Source.init(txt, std.testing.allocator);
    defer src.deinit();

    try expectEqual(0, src.locationIndex(.{ .line = 0, .col = 0 }));
    try expectEqual(1, src.locationIndex(.{ .line = 0, .col = 1 }));
    try expectEqual(2, src.locationIndex(.{ .line = 0, .col = 2 }));
    try expectEqual(3, src.locationIndex(.{ .line = 1, .col = 0 }));
    try expectEqual(4, src.locationIndex(.{ .line = 1, .col = 1 }));
    try expectEqual(5, src.locationIndex(.{ .line = 1, .col = 2 }));
    try expectEqual(6, src.locationIndex(.{ .line = 1, .col = 3 }));
    try expectEqual(7, src.locationIndex(.{ .line = 2, .col = 0 }));
    try expectEqual(8, src.locationIndex(.{ .line = 3, .col = 0 }));
    try expectEqual(9, src.locationIndex(.{ .line = 3, .col = 1 }));
}
test "Indices: indexLocation single line" {
    const txt = "0123456789";
    var src = try Source.init(txt, std.testing.allocator);
    defer src.deinit();

    for (txt, 0..) |_, i| {
        const loc = Location{ .line = 0, .col = i };
        try expectEqual(loc, src.indexLocation(i));
    }
}
test "Indices: indexLocation multi line" {
    const txt =
        \\01
        \\345
        \\
        \\89
    ;
    var src = try Source.init(txt, std.testing.allocator);
    defer src.deinit();

    try expectEqual(Location{ .line = 0, .col = 0 }, src.indexLocation(0));
    try expectEqual(Location{ .line = 0, .col = 1 }, src.indexLocation(1));
    try expectEqual(Location{ .line = 0, .col = 2 }, src.indexLocation(2));
    try expectEqual(Location{ .line = 1, .col = 0 }, src.indexLocation(3));
    try expectEqual(Location{ .line = 1, .col = 1 }, src.indexLocation(4));
    try expectEqual(Location{ .line = 1, .col = 2 }, src.indexLocation(5));
    try expectEqual(Location{ .line = 1, .col = 3 }, src.indexLocation(6));
    try expectEqual(Location{ .line = 2, .col = 0 }, src.indexLocation(7));
    try expectEqual(Location{ .line = 3, .col = 0 }, src.indexLocation(8));
    try expectEqual(Location{ .line = 3, .col = 1 }, src.indexLocation(9));
}

test "Report: location at the start" {
    const txt = "0123456789";
    var src = try Source.init(txt, std.testing.allocator);
    defer src.deinit();

    const SIZE: comptime_int = 256;
    var buf: [SIZE]u8 = .{0} ** SIZE;
    const report = src.reportLocation(src.indexLocation(0), .{});
    const printed = try std.fmt.bufPrint(&buf, "{}", .{report});
    try expectEqualStrings(
        \\1| 0123456789
        \\1| ^          
        \\
    , printed);
}
test "Report: last location" {
    const txt = "0123456789";
    var src = try Source.init(txt, std.testing.allocator);
    defer src.deinit();

    const SIZE: comptime_int = 256;
    var buf: [SIZE]u8 = .{0} ** SIZE;
    const report = src.reportLocation(src.indexLocation(9), .{});
    const printed = try std.fmt.bufPrint(&buf, "{}", .{report});
    try expectEqualStrings(
        \\1| 0123456789
        \\1|          ^ 
        \\
    , printed);
}
test "Report: end location" {
    const txt = "0123456789";
    var src = try Source.init(txt, std.testing.allocator);
    defer src.deinit();

    const SIZE: comptime_int = 256;
    var buf: [SIZE]u8 = .{0} ** SIZE;
    const report = src.reportLocation(src.indexLocation(10), .{});
    const printed = try std.fmt.bufPrint(&buf, "{}", .{report});
    try expectEqualStrings(
        \\1| 0123456789
        \\1|           ^
        \\
    , printed);
}
test "Report: location in a single line" {
    const txt = "0123456789";
    var src = try Source.init(txt, std.testing.allocator);
    defer src.deinit();

    const SIZE: comptime_int = 256;
    var buf: [SIZE]u8 = .{0} ** SIZE;
    const report = src.reportLocation(src.indexLocation(3), .{});
    const printed = try std.fmt.bufPrint(&buf, "{}", .{report});
    try expectEqualStrings(
        \\1| 0123456789
        \\1|    ^       
        \\
    , printed);
}
test "Report: location in a single line, with context" {
    const txt = "0123456789";
    var src = try Source.init(txt, std.testing.allocator);
    defer src.deinit();

    const SIZE: comptime_int = 256;
    var buf: [SIZE]u8 = .{0} ** SIZE;
    const report = src.reportLocation(src.indexLocation(3), .{ .context_lines = 1 });
    const printed = try std.fmt.bufPrint(&buf, "{}", .{report});
    try expectEqualStrings(
        \\1| 0123456789
        \\1|    ^       
        \\
    , printed);
}
test "Report: location on multi line" {
    const txt =
        \\012
        \\456
        \\89
    ;
    var src = try Source.init(txt, std.testing.allocator);
    defer src.deinit();

    const SIZE: comptime_int = 256;
    var buf: [SIZE]u8 = .{0} ** SIZE;
    const report = src.reportLocation(src.indexLocation(5), .{ .context_lines = 0 });
    const printed = try std.fmt.bufPrint(&buf, "{}", .{report});
    try expectEqualStrings(
        \\2| 456
        \\2|  ^  
        \\
    , printed);
}
test "Report: location on multi line at the start of the line" {
    const txt =
        \\012
        \\456
        \\89
    ;
    var src = try Source.init(txt, std.testing.allocator);
    defer src.deinit();

    const SIZE: comptime_int = 256;
    var buf: [SIZE]u8 = .{0} ** SIZE;
    const report = src.reportLocation(src.indexLocation(4), .{ .context_lines = 0 });
    const printed = try std.fmt.bufPrint(&buf, "{}", .{report});
    try expectEqualStrings(
        \\2| 456
        \\2| ^   
        \\
    , printed);
}
test "Report: location on multi line at the last char of the line" {
    const txt =
        \\012
        \\456
        \\89
    ;
    var src = try Source.init(txt, std.testing.allocator);
    defer src.deinit();

    const SIZE: comptime_int = 256;
    var buf: [SIZE]u8 = .{0} ** SIZE;
    const report = src.reportLocation(src.indexLocation(6), .{ .context_lines = 0 });
    const printed = try std.fmt.bufPrint(&buf, "{}", .{report});
    try expectEqualStrings(
        \\2| 456
        \\2|   ^ 
        \\
    , printed);
}
test "Report: location on multi line at the end of the line" {
    const txt =
        \\012
        \\456
        \\89
    ;
    var src = try Source.init(txt, std.testing.allocator);
    defer src.deinit();

    const SIZE: comptime_int = 256;
    var buf: [SIZE]u8 = .{0} ** SIZE;
    const report = src.reportLocation(src.indexLocation(7), .{ .context_lines = 0 });
    const printed = try std.fmt.bufPrint(&buf, "{}", .{report});
    try expectEqualStrings(
        \\2| 456
        \\2|    ^
        \\
    , printed);
}
test "Report: location on multi line with context" {
    const txt =
        \\012
        \\456
        \\89
    ;
    var src = try Source.init(txt, std.testing.allocator);
    defer src.deinit();

    const SIZE: comptime_int = 256;
    var buf: [SIZE]u8 = .{0} ** SIZE;
    const report = src.reportLocation(src.indexLocation(5), .{ .context_lines = 1 });
    const printed = try std.fmt.bufPrint(&buf, "{}", .{report});
    try expectEqualStrings(
        \\1| 012
        \\2| 456
        \\2|  ^  
        \\3| 89
        \\
    , printed);
}
test "Report: location on multi line with context on top" {
    const txt =
        \\012
        \\456
        \\89
    ;
    var src = try Source.init(txt, std.testing.allocator);
    defer src.deinit();

    const SIZE: comptime_int = 256;
    var buf: [SIZE]u8 = .{0} ** SIZE;
    const report = src.reportLocation(src.indexLocation(1), .{ .context_lines = 1 });
    const printed = try std.fmt.bufPrint(&buf, "{}", .{report});
    try expectEqualStrings(
        \\1| 012
        \\1|  ^  
        \\2| 456
        \\
    , printed);
}
test "Report: location on multi line with context on bot" {
    const txt =
        \\012
        \\456
        \\89
    ;
    var src = try Source.init(txt, std.testing.allocator);
    defer src.deinit();

    const SIZE: comptime_int = 256;
    var buf: [SIZE]u8 = .{0} ** SIZE;
    const report = src.reportLocation(src.indexLocation(9), .{ .context_lines = 1 });
    const printed = try std.fmt.bufPrint(&buf, "{}", .{report});
    try expectEqualStrings(
        \\2| 456
        \\3| 89
        \\3|  ^ 
        \\
    , printed);
}
test "Report: location on multi line with less on top than bottom" {
    const txt =
        \\012
        \\456
        \\89a
        \\cde
    ;
    var src = try Source.init(txt, std.testing.allocator);
    defer src.deinit();

    const SIZE: comptime_int = 256;
    var buf: [SIZE]u8 = .{0} ** SIZE;
    const report = src.reportLocation(src.indexLocation(5), .{ .context_lines = 2 });
    const printed = try std.fmt.bufPrint(&buf, "{}", .{report});
    try expectEqualStrings(
        \\1| 012
        \\2| 456
        \\2|  ^  
        \\3| 89a
        \\4| cde
        \\
    , printed);
}
test "Report: location on multi line with more on top than bottom" {
    const txt =
        \\012
        \\456
        \\89a
        \\cde
    ;
    var src = try Source.init(txt, std.testing.allocator);
    defer src.deinit();

    const SIZE: comptime_int = 256;
    var buf: [SIZE]u8 = .{0} ** SIZE;
    const report = src.reportLocation(src.indexLocation(9), .{ .context_lines = 2 });
    const printed = try std.fmt.bufPrint(&buf, "{}", .{report});
    try expectEqualStrings(
        \\1| 012
        \\2| 456
        \\3| 89a
        \\3|  ^  
        \\4| cde
        \\
    , printed);
}
test "Report: span on a single line" {
    const txt = "0123456789";
    var src = try Source.init(txt, std.testing.allocator);
    defer src.deinit();

    const SIZE: comptime_int = 256;
    var buf: [SIZE]u8 = .{0} ** SIZE;
    const report = src.reportSpan(.{ .start = 1, .end = 7 }, .{});
    const printed = try std.fmt.bufPrint(&buf, "{}", .{report});
    try expectEqualStrings(
        \\1| 0123456789
        \\1|  ^^^^^^    
        \\
    , printed);
}
test "Report: span on a single line at the start" {
    const txt = "0123456789";
    var src = try Source.init(txt, std.testing.allocator);
    defer src.deinit();

    const SIZE: comptime_int = 256;
    var buf: [SIZE]u8 = .{0} ** SIZE;
    const report = src.reportSpan(.{ .start = 0, .end = 7 }, .{});
    const printed = try std.fmt.bufPrint(&buf, "{}", .{report});
    try expectEqualStrings(
        \\1| 0123456789
        \\1| ^^^^^^^    
        \\
    , printed);
}
test "Report: span on a single line at the last sym" {
    const txt = "0123456789";
    var src = try Source.init(txt, std.testing.allocator);
    defer src.deinit();

    const SIZE: comptime_int = 256;
    var buf: [SIZE]u8 = .{0} ** SIZE;
    const report = src.reportSpan(.{ .start = 4, .end = 10 }, .{});
    const printed = try std.fmt.bufPrint(&buf, "{}", .{report});
    try expectEqualStrings(
        \\1| 0123456789
        \\1|     ^^^^^^ 
        \\
    , printed);
}
test "Report: span on a single line at the end" {
    const txt = "0123456789";
    var src = try Source.init(txt, std.testing.allocator);
    defer src.deinit();

    const SIZE: comptime_int = 256;
    var buf: [SIZE]u8 = .{0} ** SIZE;
    const report = src.reportSpan(.{ .start = 4, .end = 11 }, .{});
    const printed = try std.fmt.bufPrint(&buf, "{}", .{report});
    try expectEqualStrings(
        \\1| 0123456789
        \\1|     ^^^^^^^
        \\
    , printed);
}
test "Report: span on a single line full line no endline" {
    const txt = "0123456789";
    var src = try Source.init(txt, std.testing.allocator);
    defer src.deinit();

    const SIZE: comptime_int = 256;
    var buf: [SIZE]u8 = .{0} ** SIZE;
    const report = src.reportSpan(.{ .start = 0, .end = 10 }, .{});
    const printed = try std.fmt.bufPrint(&buf, "{}", .{report});
    try expectEqualStrings(
        \\1| 0123456789
        \\1| ^^^^^^^^^^ 
        \\
    , printed);
}
test "Report: span on a single line full line endline" {
    const txt = "0123456789";
    var src = try Source.init(txt, std.testing.allocator);
    defer src.deinit();

    const SIZE: comptime_int = 256;
    var buf: [SIZE]u8 = .{0} ** SIZE;
    const report = src.reportSpan(.{ .start = 0, .end = 11 }, .{});
    const printed = try std.fmt.bufPrint(&buf, "{}", .{report});
    try expectEqualStrings(
        \\1| 0123456789
        \\1| ^^^^^^^^^^^
        \\
    , printed);
}
test "Report: span on multi line" {
    const txt =
        \\012
        \\456
        \\89a
        \\cde
    ;
    var src = try Source.init(txt, std.testing.allocator);
    defer src.deinit();

    const SIZE: comptime_int = 256;
    var buf: [SIZE]u8 = .{0} ** SIZE;
    const report = src.reportSpan(.{ .start = 5, .end = 10 }, .{});
    const printed = try std.fmt.bufPrint(&buf, "{}", .{report});
    try expectEqualStrings(
        \\2|  vvv
        \\2| 456
        \\3|>89a
        \\3|>^^  
        \\
    , printed);
}
test "Report: span on multi line many lines" {
    const txt =
        \\012
        \\456
        \\89a
        \\cde
    ;
    var src = try Source.init(txt, std.testing.allocator);
    defer src.deinit();

    const SIZE: comptime_int = 256;
    var buf: [SIZE]u8 = .{0} ** SIZE;
    const report = src.reportSpan(.{ .start = 5, .end = 14 }, .{});
    const printed = try std.fmt.bufPrint(&buf, "{}", .{report});
    try expectEqualStrings(
        \\2|  vvv
        \\2| 456
        \\3|>89a
        \\4|>cde
        \\4|>^^  
        \\
    , printed);
}
test "Report: span on multi line at the start" {
    const txt =
        \\012
        \\456
        \\89a
        \\cde
    ;
    var src = try Source.init(txt, std.testing.allocator);
    defer src.deinit();

    const SIZE: comptime_int = 256;
    var buf: [SIZE]u8 = .{0} ** SIZE;
    const report = src.reportSpan(.{ .start = 4, .end = 14 }, .{});
    const printed = try std.fmt.bufPrint(&buf, "{}", .{report});
    try expectEqualStrings(
        \\2| vvvv
        \\2| 456
        \\3|>89a
        \\4|>cde
        \\4|>^^  
        \\
    , printed);
}
test "Report: span on multi line at the last sym" {
    const txt =
        \\012
        \\456
        \\89a
        \\cde
    ;
    var src = try Source.init(txt, std.testing.allocator);
    defer src.deinit();

    const SIZE: comptime_int = 256;
    var buf: [SIZE]u8 = .{0} ** SIZE;
    const report = src.reportSpan(.{ .start = 4, .end = 15 }, .{});
    const printed = try std.fmt.bufPrint(&buf, "{}", .{report});
    try expectEqualStrings(
        \\2| vvvv
        \\2| 456
        \\3|>89a
        \\4|>cde
        \\4|>^^^ 
        \\
    , printed);
}
test "Report: span on multi line at the end" {
    const txt =
        \\012
        \\456
        \\89a
        \\cde
    ;
    var src = try Source.init(txt, std.testing.allocator);
    defer src.deinit();

    const SIZE: comptime_int = 256;
    var buf: [SIZE]u8 = .{0} ** SIZE;
    const report = src.reportSpan(.{ .start = 4, .end = 16 }, .{});
    const printed = try std.fmt.bufPrint(&buf, "{}", .{report});
    try expectEqualStrings(
        \\2| vvvv
        \\2| 456
        \\3|>89a
        \\4|>cde
        \\4|>^^^^
        \\
    , printed);
}
test "Report: span on multi line with context" {
    const txt =
        \\012
        \\456
        \\89a
        \\cde
    ;
    var src = try Source.init(txt, std.testing.allocator);
    defer src.deinit();

    const SIZE: comptime_int = 256;
    var buf: [SIZE]u8 = .{0} ** SIZE;
    const report = src.reportSpan(.{ .start = 5, .end = 10 }, .{ .context_lines = 1 });
    const printed = try std.fmt.bufPrint(&buf, "{}", .{report});
    try expectEqualStrings(
        \\1| 012
        \\2|  vvv
        \\2| 456
        \\3|>89a
        \\3|>^^  
        \\4| cde
        \\
    , printed);
}
test "Report: span on multi line with no context on top" {
    const txt =
        \\012
        \\456
        \\89a
        \\cde
    ;
    var src = try Source.init(txt, std.testing.allocator);
    defer src.deinit();

    const SIZE: comptime_int = 256;
    var buf: [SIZE]u8 = .{0} ** SIZE;
    const report = src.reportSpan(.{ .start = 1, .end = 10 }, .{ .context_lines = 1 });
    const printed = try std.fmt.bufPrint(&buf, "{}", .{report});
    try expectEqualStrings(
        \\1|  vvv
        \\1| 012
        \\2|>456
        \\3|>89a
        \\3|>^^  
        \\4| cde
        \\
    , printed);
}
test "Report: span on multi line with no context on bot" {
    const txt =
        \\012
        \\456
        \\89a
        \\cde
    ;
    var src = try Source.init(txt, std.testing.allocator);
    defer src.deinit();

    const SIZE: comptime_int = 256;
    var buf: [SIZE]u8 = .{0} ** SIZE;
    const report = src.reportSpan(.{ .start = 5, .end = 14 }, .{ .context_lines = 1 });
    const printed = try std.fmt.bufPrint(&buf, "{}", .{report});
    try expectEqualStrings(
        \\1| 012
        \\2|  vvv
        \\2| 456
        \\3|>89a
        \\4|>cde
        \\4|>^^  
        \\
    , printed);
}
