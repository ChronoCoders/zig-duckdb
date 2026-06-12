# strduck

A DuckDB extension that adds string helper functions, written in Zig.

## What it is

strduck is a loadable DuckDB extension that exposes three scalar functions for working with VARCHAR values: `str_reverse`, `str_count`, and `str_truncate`. The function implementations are written in Zig and registered through the DuckDB C extension API, with a small C entry point that wires them into the database.

## Functions

| Function | Signature | Description |
| --- | --- | --- |
| `str_reverse` | `str_reverse(s VARCHAR) -> VARCHAR` | Reverses a string, preserving UTF-8 codepoints. |
| `str_count` | `str_count(s VARCHAR, needle VARCHAR) -> INTEGER` | Counts non-overlapping occurrences of `needle` in `s`. |
| `str_truncate` | `str_truncate(s VARCHAR, max_len INTEGER, ellipsis VARCHAR) -> VARCHAR` | Truncates `s` to `max_len` characters, appending `ellipsis` when truncation happens. |

Each function returns NULL when any of its arguments is NULL.

## Requirements

- Zig 0.13
- DuckDB 1.2 or newer
- Python 3 with the `duckdb` and `duckdb_sqllogictest` packages (only required to run the tests)

## Building

The DuckDB headers and prebuilt library are downloaded automatically by the Zig build system.

```shell
zig build -Dduckdb-version=1.2.0
```

By default the extension is built for the host platform. Pass `-Dplatform` to select a different one, for example `-Dplatform=osx_arm64`. Optimized builds are available through the standard Zig release flags:

```shell
zig build -Dduckdb-version=1.2.0 --release=fast
zig build -Dduckdb-version=1.2.0 --release=small
```

The extension is written to `zig-out/v<version>/<platform>/strduck.duckdb_extension`.

## Testing

```shell
zig build test -Dduckdb-version=1.2.0
```

This runs the SQL logic tests in `test/sql/strduck.test` against the freshly built extension.

## Usage

Load the extension into a DuckDB session started with `-unsigned` and call the functions:

```
$ duckdb -unsigned
v1.2.0
D LOAD 'zig-out/v1.2.0/linux_amd64_gcc4/strduck.duckdb_extension';
D SELECT str_reverse('hello');
┌──────────────────────┐
│ str_reverse('hello') │
│       varchar        │
├──────────────────────┤
│ olleh                │
└──────────────────────┘
D SELECT str_count('abcabc', 'bc');
┌─────────────────────────────┐
│ str_count('abcabc', 'bc')   │
│            int32            │
├─────────────────────────────┤
│                           2 │
└─────────────────────────────┘
D SELECT str_truncate('hello world', 5, '...');
┌─────────────────────────────────────────┐
│ str_truncate('hello world', 5, '...')   │
│                 varchar                 │
├─────────────────────────────────────────┤
│ hello...                                │
└─────────────────────────────────────────┘
```

## License

MIT
