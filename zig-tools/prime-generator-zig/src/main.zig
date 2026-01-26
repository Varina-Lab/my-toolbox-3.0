// You can edit this code!
// Click into the editor and start typing.
const std = @import("std");
const builtin = @import("builtin");

pub fn main() void {
    std.debug.print("Hello, {s}! (using Zig version: {f})", .{ "world", builtin.zig_version });
}
