#include <lean/lean.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <unistd.h>
#include <string.h>
#include <signal.h>
#include <errno.h>
#include <stdlib.h>
#include <libpq-fe.h>

static lean_obj_res mk_io_error(const char *msg) {
    return lean_io_result_mk_error(
        lean_mk_io_user_error(lean_mk_string(msg)));
}

LEAN_EXPORT lean_obj_res lean_tcp_listen(uint16_t port, lean_obj_arg world) {
    signal(SIGPIPE, SIG_IGN);

    int fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) return mk_io_error("socket() failed");

    int opt = 1;
    setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));

    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family      = AF_INET;
    addr.sin_addr.s_addr = INADDR_ANY;
    addr.sin_port        = htons(port);

    if (bind(fd, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
        close(fd);
        return mk_io_error("bind() failed");
    }
    if (listen(fd, 128) < 0) {
        close(fd);
        return mk_io_error("listen() failed");
    }
    return lean_io_result_mk_ok(lean_box_uint32((uint32_t)fd));
}

LEAN_EXPORT lean_obj_res lean_tcp_accept(uint32_t server_fd, lean_obj_arg world) {
    int fd = accept((int)server_fd, NULL, NULL);
    if (fd < 0) return mk_io_error("accept() failed");
    return lean_io_result_mk_ok(lean_box_uint32((uint32_t)fd));
}

LEAN_EXPORT lean_obj_res lean_tcp_recv(uint32_t fd, lean_obj_arg world) {
    char buf[65536];
    ssize_t n = read((int)fd, buf, sizeof(buf) - 1);
    if (n < 0) return mk_io_error("read() failed");
    buf[n] = '\0';
    return lean_io_result_mk_ok(lean_mk_string(buf));
}

LEAN_EXPORT lean_obj_res lean_tcp_send(uint32_t fd, b_lean_obj_arg str, lean_obj_arg world) {
    const char *data = lean_string_cstr(str);
    size_t len = strlen(data);
    size_t sent = 0;
    while (sent < len) {
        ssize_t n = write((int)fd, data + sent, len - sent);
        if (n < 0) return mk_io_error("write() failed");
        sent += (size_t)n;
    }
    return lean_io_result_mk_ok(lean_box(0));
}

LEAN_EXPORT lean_obj_res lean_tcp_close(uint32_t fd, lean_obj_arg world) {
    close((int)fd);
    return lean_io_result_mk_ok(lean_box(0));
}

/* ── libpq FFI ─────────────────────────────────────────────── */

static void pg_conn_finalize(void *ptr) {
    PGconn *conn = (PGconn *)ptr;
    if (conn) PQfinish(conn);
}

static void pg_conn_foreach(void *ptr, b_lean_obj_arg fn) {
    (void)ptr; (void)fn;
}

static lean_external_class *g_pg_conn_class = NULL;

static lean_external_class *get_pg_conn_class(void) {
    if (!g_pg_conn_class) {
        g_pg_conn_class = lean_register_external_class(
            pg_conn_finalize, pg_conn_foreach);
    }
    return g_pg_conn_class;
}

static inline PGconn *pg_conn_of(b_lean_obj_arg o) {
    return (PGconn *)lean_get_external_data(o);
}

LEAN_EXPORT lean_obj_res lean_pg_connect(b_lean_obj_arg conn_str, lean_obj_arg world) {
    const char *cs = lean_string_cstr(conn_str);
    PGconn *conn = PQconnectdb(cs);
    if (PQstatus(conn) != CONNECTION_OK) {
        const char *err = PQerrorMessage(conn);
        lean_obj_res msg = lean_mk_string(err);
        PQfinish(conn);
        return lean_io_result_mk_error(lean_mk_io_user_error(msg));
    }
    lean_obj_res obj = lean_alloc_external(get_pg_conn_class(), (void *)conn);
    return lean_io_result_mk_ok(obj);
}

LEAN_EXPORT lean_obj_res lean_pg_exec(b_lean_obj_arg conn_obj, b_lean_obj_arg sql_obj,
                                       b_lean_obj_arg params_obj, lean_obj_arg world) {
    PGconn *conn = pg_conn_of(conn_obj);
    const char *sql = lean_string_cstr(sql_obj);

    size_t nParams = lean_array_size(params_obj);
    const char **paramValues = NULL;
    if (nParams > 0) {
        paramValues = (const char **)malloc(nParams * sizeof(char *));
        for (size_t i = 0; i < nParams; i++) {
            lean_obj_arg elem = lean_array_cptr(params_obj)[i];
            paramValues[i] = lean_string_cstr(elem);
        }
    }

    PGresult *res = PQexecParams(conn, sql, (int)nParams, NULL,
                                  paramValues, NULL, NULL, 0);
    free(paramValues);

    ExecStatusType st = PQresultStatus(res);
    if (st != PGRES_COMMAND_OK && st != PGRES_TUPLES_OK) {
        const char *err = PQresultErrorMessage(res);
        lean_obj_res msg = lean_mk_string(err);
        PQclear(res);
        return lean_io_result_mk_error(lean_mk_io_user_error(msg));
    }

    const char *affected = PQcmdTuples(res);
    size_t n = 0;
    if (affected && affected[0]) n = (size_t)atol(affected);
    PQclear(res);
    return lean_io_result_mk_ok(lean_box(n));
}

LEAN_EXPORT lean_obj_res lean_pg_query(b_lean_obj_arg conn_obj, b_lean_obj_arg sql_obj,
                                        b_lean_obj_arg params_obj, lean_obj_arg world) {
    PGconn *conn = pg_conn_of(conn_obj);
    const char *sql = lean_string_cstr(sql_obj);

    size_t nParams = lean_array_size(params_obj);
    const char **paramValues = NULL;
    if (nParams > 0) {
        paramValues = (const char **)malloc(nParams * sizeof(char *));
        for (size_t i = 0; i < nParams; i++) {
            lean_obj_arg elem = lean_array_cptr(params_obj)[i];
            paramValues[i] = lean_string_cstr(elem);
        }
    }

    PGresult *res = PQexecParams(conn, sql, (int)nParams, NULL,
                                  paramValues, NULL, NULL, 0);
    free(paramValues);

    ExecStatusType st = PQresultStatus(res);
    if (st != PGRES_TUPLES_OK) {
        const char *err = PQresultErrorMessage(res);
        lean_obj_res msg = lean_mk_string(err);
        PQclear(res);
        return lean_io_result_mk_error(lean_mk_io_user_error(msg));
    }

    int nRows = PQntuples(res);
    int nCols = PQnfields(res);
    lean_obj_res outer = lean_mk_empty_array();
    for (int r = 0; r < nRows; r++) {
        lean_obj_res row = lean_mk_empty_array();
        for (int c = 0; c < nCols; c++) {
            const char *val = PQgetvalue(res, r, c);
            row = lean_array_push(row, lean_mk_string(val ? val : ""));
        }
        outer = lean_array_push(outer, row);
    }
    PQclear(res);
    return lean_io_result_mk_ok(outer);
}
