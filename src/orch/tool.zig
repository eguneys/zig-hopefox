const std = @import("std");

pub const ReadNumber = struct {
    digits: [30]u8 = undefined,
    inext: usize = 0,

    pub fn appendDigit(self: *ReadNumber, digit: u8) void {
        if (self.inext >= self.digits.len) return;
        self.digits[self.inext] = digit;
        self.inext += 1;
    }

    pub fn toOwnedNumber(self: *ReadNumber) usize {
        var result: usize = 0;
        var base: usize = 1;

        for (0..self.inext) |i| {
            result += self.digits[self.inext - 1 - i] * base;
            base *= 10;
        }
        return result;
    }
};
