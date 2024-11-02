const std = @import("std");
const source = @import("source");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const txt = "0123456789";
    var src = try source.Source.init(txt, gpa.allocator());
    defer src.deinit();

    std.debug.print("{}", .{src.reportSpan(.{ .start = 1, .end = 7 }, .{})});
}

