#include "duckdb.h"

extern void strduck_reverse_fn(duckdb_function_info info, duckdb_data_chunk input, duckdb_vector output);
extern void strduck_count_fn(duckdb_function_info info, duckdb_data_chunk input, duckdb_vector output);
extern void strduck_truncate_fn(duckdb_function_info info, duckdb_data_chunk input, duckdb_vector output);

static duckdb_state register_scalar(duckdb_connection con, const char *name, duckdb_logical_type *params,
                                    idx_t param_count, duckdb_logical_type return_type,
                                    duckdb_scalar_function_t fn) {
    duckdb_scalar_function func = duckdb_create_scalar_function();
    duckdb_scalar_function_set_name(func, name);
    for (idx_t i = 0; i < param_count; i++) {
        duckdb_scalar_function_add_parameter(func, params[i]);
    }
    duckdb_scalar_function_set_return_type(func, return_type);
    duckdb_scalar_function_set_function(func, fn);
    duckdb_state state = duckdb_register_scalar_function(con, func);
    duckdb_destroy_scalar_function(&func);
    return state;
}

DUCKDB_EXTENSION_API const char *strduck_version(void) {
    return duckdb_library_version();
}

DUCKDB_EXTENSION_API void strduck_init(duckdb_database db) {
    duckdb_connection con;
    if (duckdb_connect(db, &con) == DuckDBError) {
        return;
    }

    duckdb_logical_type varchar = duckdb_create_logical_type(DUCKDB_TYPE_VARCHAR);
    duckdb_logical_type integer = duckdb_create_logical_type(DUCKDB_TYPE_INTEGER);

    duckdb_logical_type reverse_params[] = {varchar};
    register_scalar(con, "str_reverse", reverse_params, 1, varchar, strduck_reverse_fn);

    duckdb_logical_type count_params[] = {varchar, varchar};
    register_scalar(con, "str_count", count_params, 2, integer, strduck_count_fn);

    duckdb_logical_type truncate_params[] = {varchar, integer, varchar};
    register_scalar(con, "str_truncate", truncate_params, 3, varchar, strduck_truncate_fn);

    duckdb_destroy_logical_type(&varchar);
    duckdb_destroy_logical_type(&integer);
    duckdb_disconnect(&con);
}
