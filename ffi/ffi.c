#include <lean/lean.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <unistd.h>
#include <string.h>
#include <signal.h>
#include <errno.h>

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
