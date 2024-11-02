const std = @import("std");

/// `Location` stores line+col locations in source
/// line and col are 0-indexed
pub const Location = struct {
    line: usize = 0,
    col: usize = 0,

    const Self = @This();
    pub fn format(self: Self, fmt: []const u8, opts: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = opts;
        try writer.print("Line {}, col {}", .{ self.line, self.col });
    }
};

/// `Span` stores [start..end)
pub const Span = struct {
    start: usize,
    end: usize,

    const Self = @This();
    pub inline fn contains(self: Self, idx: usize) bool {
        return self.start <= idx and self.end > idx;
    }
    pub inline fn len(self: Self) usize {
        return self.end - self.start;
    }
};

/// `Source` is a type to conveniently read from some text buffer.
pub const Source = struct {
    buf: []const u8,
    /// Index of the **next** character to be read
    i: usize = 0,
    /// Location of the **next** character
    loc: Location = .{},
    /// Stores line location infromation:
    /// start[0] start[1] ... start[n] end[n]
    line_offsets: std.ArrayList(usize),
    /// Location of the EOF
    end_loc: Location = .{},

    pub const Error = error{
        UnexpectedEnd,
        Mismatch,
    };

    const Self = @This();
    /// Initializes `Source` and determines all line locations
    pub fn init(buf: []const u8, allocator: std.mem.Allocator) !Self {
        var self = Self{
            .buf = buf,
            .line_offsets = std.ArrayList(usize).init(allocator),
        };
        errdefer self.deinit();
        try self.line_offsets.append(0);
        for (buf, 0..) |c, i| {
            if (c == '\n') {
                try self.line_offsets.append(i + 1);
                self.end_loc.line += 1;
                self.end_loc.col = 0;
            } else {
                self.end_loc.col += 1;
            }
        }
        try self.line_offsets.append(buf.len);

        return self;
    }

    /// Deinitializes `Source`
    pub fn deinit(self: *Self) void {
        self.line_offsets.deinit();
    }

    pub inline fn finished(self: *const Self) bool {
        return self.i >= self.buf.len;
    }

    pub inline fn reset(self: *Self) void {
        self.i = 0;
    }
    /// Read one character from `buf` and move to the right
    pub fn read(self: *Self) Error!u8 {
        if (self.finished()) return Error.UnexpectedEnd;
        const c = self.buf[self.i];
        if (c == '\n') {
            self.loc.line += 1;
            self.loc.col = 0;
        } else {
            self.loc.col += 1;
        }
        self.i += 1;

        return c;
    }
    /// Peek the next character, null if the string ends.
    pub inline fn peek(self: *const Self) ?u8 {
        if (!self.finished()) return self.buf[self.i];
        return null;
    }
    /// Skip the next character, returns false if end reached
    pub inline fn skip(self: *Self) bool {
        _ = self.read() catch return false;
        return true;
    }
    /// Skip up to n characters, returns how many were actually skipped
    pub fn skipN(self: *Self, n: usize) usize {
        for (0..n) |i| {
            if (!self.skip()) return i;
        }
        return n;
    }
    /// Move one to the left
    pub fn unread(self: *Self) void {
        if (self.i == 0) return;
        self.i -= 1;
        const c = self.buf[self.i];
        if (c == '\n') {
            self.loc.line -= 1;
            const span = self.getLineSpan(self.loc.line, true);
            self.loc.col = span.end - span.start - 1;
        } else {
            self.loc.col -= 1;
        }
    }

    /// Read one of the expected characters.
    /// Expected may be an Int, a ComptimeInt (i.e. char literal) or a tuple-struct of possible values
    /// If the read character does not match, an error is returned,
    /// the read character is optionally placed into the 'got' variable.
    pub fn readExpect(
        self: *Self,
        expected: anytype,
        got: ?*u8,
    ) Error!u8 {
        const t = @typeInfo(@TypeOf(expected));
        const c = self.read() catch |e| {
            if (got) |x| x.* = 0;
            return e;
        };
        if (got) |x| x.* = c;
        switch (t) {
            .Int, .ComptimeInt => {
                if (@as(u8, expected) != c) return Error.Mismatch;
                return c;
            },
            .Struct => |*s| {
                if (!s.is_tuple) {
                    @compileError("'expected' argument in 'readExpect' should be an int or a tuple struct");
                }
                inline for (s.fields, 0..) |f, i| {
                    switch (@typeInfo(f.type)) {
                        .Int, .ComptimeInt => {
                            if (@as(u8, expected[i]) == c) return c;
                        },
                        else => @compileError("elements of tuple struct in 'readExpect' should be ints"),
                    }
                }
                return Error.Mismatch;
            },
            else => @compileError("'expected' argument of 'readExpect' should be an int or a tuple struct"),
        }
    }

    /// Skips until a non-whitespace symbol is reached
    /// Whitespace is according to std.ascii.isWhitespace
    pub fn skipWhitespace(self: *Self) void {
        while (self.peek()) |c| {
            if (!std.ascii.isWhitespace(c)) {
                break;
            }
            _ = self.skip();
        }
    }

    pub inline fn getLineCount(self: *const Self) usize {
        return self.line_offsets.items.len - 1;
    }
    /// Returns a `Span` of 0-indexed line.
    pub inline fn getLineSpan(self: *const Self, line_num: usize, keep_endline: bool) Span {
        var res = Span{
            .start = self.line_offsets.items[line_num],
            .end = self.line_offsets.items[line_num + 1],
        };

        if (keep_endline) return res;
        if (self.buf[res.end - 1] == '\n') {
            res.end -= 1;
        }

        return res;
    }
    /// Return a view into `buf`, from start (included) to end (excluded)
    pub inline fn getSpan(self: *const Self, span: Span) []const u8 {
        return self.buf[span.start..span.end];
    }
    /// Returns a 0-indexed line
    pub inline fn getLine(self: *const Self, line_num: usize, keep_endline: bool) []const u8 {
        const span = self.getLineSpan(line_num, keep_endline);
        return self.getSpan(span);
    }
    /// Returns a `Location` corresponding to buffer index `idx`
    pub fn indexLocation(self: *const Self, idx: usize) Location {
        var left: usize = 0;
        var right = self.getLineCount() - 1;
        std.debug.assert(idx <= self.buf.len);
        if (idx == self.buf.len) return self.end_loc;

        const line = while (left + 1 != right) {
            const mid = left + (right - left) / 2;
            const span = self.getLineSpan(mid, true);
            if (span.contains(idx)) {
                break mid;
            } else if (span.start > idx) {
                right = mid;
            } else {
                left = mid;
            }
        } else if (self.getLineSpan(right, true).contains(idx)) right else left;

        const span = self.getLineSpan(line, true);
        std.debug.assert(span.contains(idx));
        return Location{ .line = line, .col = idx - span.start };
    }
    /// Returns the buffer index corresponding to `loc`
    pub inline fn locationIndex(self: *const Self, loc: Location) usize {
        const span = self.getLineSpan(loc.line, true);
        return span.start + loc.col;
    }

    /// Reports a couple of lines around `loc`, highlighting `loc`.
    /// Usage example: std.debug.print("{}", .{mysrc.reportLocation(myloc, .{})});
    pub inline fn reportLocation(self: *const Self, loc: Location, cfg: ReportConfig) Report {
        return Report{ .src = self, .kind = Report.Kind{ .Location = loc }, .cfg = cfg };
    }

    /// Reports a couple of lines around `span` highlighting the span contents
    /// Usage example: std.debug.print("{}", .{mysrc.reportLocation(myspan, .{})});
    pub inline fn reportSpan(self: *const Self, span: Span, cfg: ReportConfig) Report {
        return Report{ .src = self, .kind = Report.Kind{ .Span = span }, .cfg = cfg };
    }
};

pub const ReportConfig = struct {
    /// How many spaces does a '\t' character take
    tab_width: u8 = 4,
    /// How many extra lines on top and bottom to report
    context_lines: u8 = 0,
};

/// A `Report` of a place of interest that can be formatted
pub const Report = struct {
    src: *const Source,
    kind: Kind,
    cfg: ReportConfig,

    const Self = @This();
    const Kind = union(enum) {
        Location: Location,
        Span: Span,
    };

    pub fn format(
        self: *const Self,
        fmt: []const u8,
        opts: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = opts;

        const interest = switch (self.kind) {
            .Location => |loc| blk: {
                const i = self.src.locationIndex(loc);
                break :blk Span{ .start = i, .end = i + 1 };
            },
            .Span => |span| span,
        };

        const interest_start_line = self.src.indexLocation(interest.start).line;
        var start_line = interest_start_line;
        if (start_line >= self.cfg.context_lines) {
            start_line -= self.cfg.context_lines;
        } else {
            start_line = 0;
        }
        const interest_end_line = self.src.indexLocation(interest.end - 1).line;
        var end_line = interest_end_line;
        if (end_line + self.cfg.context_lines < self.src.getLineCount()) {
            end_line += self.cfg.context_lines;
        } else {
            end_line = self.src.getLineCount() - 1;
        }

        const num_width = std.math.log10_int(end_line + 1) + 1;
        for (start_line..interest_start_line) |line_num| {
            try self.printLineNum(num_width, line_num, writer, false);
            try self.printLine(line_num, writer);
        }

        if (interest_start_line == interest_end_line) {
            try self.printLineNum(num_width, interest_start_line, writer, false);
            try self.printLine(interest_start_line, writer);
            try self.printLineNum(num_width, interest_end_line, writer, false);
            try self.printLineHighlight(interest_start_line, interest, '^', writer);
        } else {
            try self.printLineNum(num_width, interest_start_line, writer, false);
            try self.printLineHighlight(interest_start_line, interest, 'v', writer);
            try self.printLineNum(num_width, interest_start_line, writer, false);
            try self.printLine(interest_start_line, writer);

            for (interest_start_line + 1..interest_end_line) |line_num| {
                try self.printLineNum(num_width, line_num, writer, true);
                try self.printLine(line_num, writer);
            }

            try self.printLineNum(num_width, interest_end_line, writer, true);
            try self.printLine(interest_end_line, writer);
            try self.printLineNum(num_width, interest_end_line, writer, true);
            try self.printLineHighlight(interest_end_line, interest, '^', writer);
        }

        for (interest_end_line + 1..end_line + 1) |line_num| {
            try self.printLineNum(num_width, line_num, writer, false);
            try self.printLine(line_num, writer);
        }
    }

    fn printLineNum(
        self: *const Self,
        num_width: usize,
        line_num: usize,
        writer: anytype,
        is_marked: bool,
    ) !void {
        _ = self;
        try std.fmt.formatInt(
            line_num + 1,
            10,
            .lower,
            .{ .width = num_width, .alignment = .right },
            writer,
        );
        if (is_marked) {
            try writer.print("|>", .{});
        } else {
            try writer.print("| ", .{});
        }
    }

    fn printLine(self: *const Self, line_num: usize, writer: anytype) !void {
        for (self.src.getLine(line_num, false)) |c| {
            switch (c) {
                '\t' => for (0..self.cfg.tab_width) |_| try writer.print(" ", .{}),
                '\n' => unreachable,
                else => try writer.print("{c}", .{c}),
            }
        }
        try writer.print("\n", .{});
    }

    fn printLineHighlight(
        self: *const Self,
        line_num: usize,
        span: Span,
        highlight: u8,
        writer: anytype,
    ) !void {
        const line_span = self.src.getLineSpan(line_num, false);
        for (self.src.getLine(line_num, false), line_span.start..) |c, i| {
            var fill: u8 = ' ';
            if (span.contains(i)) fill = highlight;

            if (c == '\t') {
                for (0..self.cfg.tab_width) |_| try writer.print("{c}", .{fill});
            } else {
                try writer.print("{c}", .{fill});
            }
        }
        if (span.contains(line_span.end)) {
            try writer.print("{c}\n", .{highlight});
        } else {
            try writer.print(" \n", .{});
        }
    }
};
