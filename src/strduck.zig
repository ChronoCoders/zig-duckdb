const std = @import("std");

const c = @cImport({
    @cInclude("duckdb.h");
});

fn stringBytes(value: *c.duckdb_string_t) []const u8 {
    const ptr: [*]const u8 = @ptrCast(c.duckdb_string_t_data(value));
    const len: usize = c.duckdb_string_t_length(value.*);
    return ptr[0..len];
}

fn assign(output: c.duckdb_vector, row: u64, bytes: []const u8) void {
    const ptr: [*c]const u8 = @ptrCast(bytes.ptr);
    c.duckdb_vector_assign_string_element_len(output, row, ptr, bytes.len);
}

fn writeReversed(out: []u8, bytes: []const u8) void {
    if (std.unicode.Utf8View.init(bytes)) |view| {
        var it = view.iterator();
        var pos: usize = out.len;
        while (it.nextCodepointSlice()) |cp| {
            pos -= cp.len;
            @memcpy(out[pos..][0..cp.len], cp);
        }
    } else |_| {
        var i: usize = 0;
        while (i < bytes.len) : (i += 1) {
            out[i] = bytes[bytes.len - 1 - i];
        }
    }
}

fn countOccurrences(haystack: []const u8, needle: []const u8) i32 {
    if (needle.len == 0 or needle.len > haystack.len) return 0;
    var count: i32 = 0;
    var pos: usize = 0;
    while (std.mem.indexOfPos(u8, haystack, pos, needle)) |found| {
        count += 1;
        pos = found + needle.len;
    }
    return count;
}

fn truncatedByteLen(bytes: []const u8, max_chars: usize) ?usize {
    if (max_chars == 0) {
        return if (bytes.len == 0) null else 0;
    }
    if (std.unicode.Utf8View.init(bytes)) |view| {
        var it = view.iterator();
        var chars: usize = 0;
        var cut: usize = 0;
        while (it.nextCodepointSlice()) |cp| {
            if (chars == max_chars) return cut;
            chars += 1;
            cut += cp.len;
        }
        return null;
    } else |_| {
        return if (bytes.len <= max_chars) null else max_chars;
    }
}

export fn strduck_reverse_fn(info: c.duckdb_function_info, input: c.duckdb_data_chunk, output: c.duckdb_vector) void {
    const in_vec = c.duckdb_data_chunk_get_vector(input, 0);
    const in_data: [*]c.duckdb_string_t = @ptrCast(@alignCast(c.duckdb_vector_get_data(in_vec)));
    const in_validity = c.duckdb_vector_get_validity(in_vec);

    c.duckdb_vector_ensure_validity_writable(output);
    const out_validity = c.duckdb_vector_get_validity(output);

    const rows = c.duckdb_data_chunk_get_size(input);
    var row: u64 = 0;
    while (row < rows) : (row += 1) {
        if (!c.duckdb_validity_row_is_valid(in_validity, row)) {
            c.duckdb_validity_set_row_invalid(out_validity, row);
            continue;
        }

        const bytes = stringBytes(&in_data[row]);
        if (bytes.len == 0) {
            assign(output, row, bytes);
            continue;
        }

        const buf: [*]u8 = @ptrCast(c.duckdb_malloc(bytes.len) orelse {
            c.duckdb_scalar_function_set_error(info, "str_reverse: out of memory");
            return;
        });
        const out = buf[0..bytes.len];
        writeReversed(out, bytes);
        assign(output, row, out);
        c.duckdb_free(buf);
    }
}

export fn strduck_count_fn(info: c.duckdb_function_info, input: c.duckdb_data_chunk, output: c.duckdb_vector) void {
    _ = info;
    const haystack_vec = c.duckdb_data_chunk_get_vector(input, 0);
    const needle_vec = c.duckdb_data_chunk_get_vector(input, 1);
    const haystack_data: [*]c.duckdb_string_t = @ptrCast(@alignCast(c.duckdb_vector_get_data(haystack_vec)));
    const needle_data: [*]c.duckdb_string_t = @ptrCast(@alignCast(c.duckdb_vector_get_data(needle_vec)));
    const haystack_validity = c.duckdb_vector_get_validity(haystack_vec);
    const needle_validity = c.duckdb_vector_get_validity(needle_vec);

    const out_data: [*]i32 = @ptrCast(@alignCast(c.duckdb_vector_get_data(output)));
    c.duckdb_vector_ensure_validity_writable(output);
    const out_validity = c.duckdb_vector_get_validity(output);

    const rows = c.duckdb_data_chunk_get_size(input);
    var row: u64 = 0;
    while (row < rows) : (row += 1) {
        if (!c.duckdb_validity_row_is_valid(haystack_validity, row) or
            !c.duckdb_validity_row_is_valid(needle_validity, row))
        {
            c.duckdb_validity_set_row_invalid(out_validity, row);
            continue;
        }

        const haystack = stringBytes(&haystack_data[row]);
        const needle = stringBytes(&needle_data[row]);
        out_data[row] = countOccurrences(haystack, needle);
    }
}

export fn strduck_truncate_fn(info: c.duckdb_function_info, input: c.duckdb_data_chunk, output: c.duckdb_vector) void {
    const source_vec = c.duckdb_data_chunk_get_vector(input, 0);
    const max_vec = c.duckdb_data_chunk_get_vector(input, 1);
    const ellipsis_vec = c.duckdb_data_chunk_get_vector(input, 2);
    const source_data: [*]c.duckdb_string_t = @ptrCast(@alignCast(c.duckdb_vector_get_data(source_vec)));
    const max_data: [*]i32 = @ptrCast(@alignCast(c.duckdb_vector_get_data(max_vec)));
    const ellipsis_data: [*]c.duckdb_string_t = @ptrCast(@alignCast(c.duckdb_vector_get_data(ellipsis_vec)));
    const source_validity = c.duckdb_vector_get_validity(source_vec);
    const max_validity = c.duckdb_vector_get_validity(max_vec);
    const ellipsis_validity = c.duckdb_vector_get_validity(ellipsis_vec);

    c.duckdb_vector_ensure_validity_writable(output);
    const out_validity = c.duckdb_vector_get_validity(output);

    const rows = c.duckdb_data_chunk_get_size(input);
    var row: u64 = 0;
    while (row < rows) : (row += 1) {
        if (!c.duckdb_validity_row_is_valid(source_validity, row) or
            !c.duckdb_validity_row_is_valid(max_validity, row) or
            !c.duckdb_validity_row_is_valid(ellipsis_validity, row))
        {
            c.duckdb_validity_set_row_invalid(out_validity, row);
            continue;
        }

        const source = stringBytes(&source_data[row]);
        const ellipsis = stringBytes(&ellipsis_data[row]);
        const raw_max = max_data[row];
        const max_chars: usize = if (raw_max < 0) 0 else @intCast(raw_max);

        const cut = truncatedByteLen(source, max_chars) orelse {
            assign(output, row, source);
            continue;
        };

        const total = cut + ellipsis.len;
        if (total == 0) {
            assign(output, row, source[0..0]);
            continue;
        }

        const buf: [*]u8 = @ptrCast(c.duckdb_malloc(total) orelse {
            c.duckdb_scalar_function_set_error(info, "str_truncate: out of memory");
            return;
        });
        @memcpy(buf[0..cut], source[0..cut]);
        @memcpy(buf[cut..total], ellipsis);
        assign(output, row, buf[0..total]);
        c.duckdb_free(buf);
    }
}
