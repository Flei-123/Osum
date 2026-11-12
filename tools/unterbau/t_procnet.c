#define TNAME "procnet"
#include "t.h"
#include <arpa/inet.h>
#include <fcntl.h>
#include <netinet/in.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <unistd.h>

#define TCP_HEADER "  sl  local_address rem_address   st tx_queue rx_queue tr tm->when retrnsmt   uid  timeout inode\n"
#define UDP_HEADER "   sl  local_address rem_address   st tx_queue rx_queue tr tm->when retrnsmt   uid  timeout inode ref pointer drops\n"
#define ARP_HEADER "IP address       HW type     Flags       HW address            Mask     Device\n"
#define ROUTE_HEADER "Iface\tDestination\tGateway \tFlags\tRefCnt\tUse\tMetric\tMask\t\tMTU\tWindow\tIRTT\n"

static int read_text(const char *path, char *out, size_t cap)
{
    int fd = open(path, O_RDONLY);
    if (fd < 0)
        return -1;
    ssize_t n = read(fd, out, cap - 1);
    close(fd);
    if (n < 0)
        return -1;
    out[n] = 0;
    return (int)n;
}

static int starts_with(const char *s, const char *prefix)
{
    return strncmp(s, prefix, strlen(prefix)) == 0;
}

static void test_headers(void)
{
    char buf[4096];
    CHECK("tcp_header", read_text("/proc/net/tcp", buf, sizeof buf) > 0 && starts_with(buf, TCP_HEADER), "buf=%.60s", buf);
    CHECK("udp_header", read_text("/proc/net/udp", buf, sizeof buf) > 0 && starts_with(buf, UDP_HEADER), "buf=%.60s", buf);
    CHECK("arp_header", read_text("/proc/net/arp", buf, sizeof buf) > 0 && starts_with(buf, ARP_HEADER), "buf=%.60s", buf);
    CHECK("route_header", read_text("/proc/net/route", buf, sizeof buf) > 0 && starts_with(buf, ROUTE_HEADER), "buf=%.60s", buf);
}

struct row {
    unsigned laddr, lport, raddr, rport, state;
};

static int find_row_by(const char *text, unsigned lport, unsigned rport, struct row *out)
{
    const char *line = strchr(text, '\n');
    while (line && *++line) {
        unsigned slot;
        struct row r;
        if (sscanf(line, "%u: %x:%x %x:%x %x", &slot, &r.laddr, &r.lport, &r.raddr, &r.rport, &r.state) == 6
            && (lport == 0 || r.lport == lport) && (rport == 0 || r.rport == rport)) {
            *out = r;
            return 1;
        }
        line = strchr(line, '\n');
    }
    return 0;
}

static int find_row(const char *text, unsigned port, unsigned *state_out)
{
    struct row r;
    if (!find_row_by(text, port, 0, &r))
        return 0;
    *state_out = r.state;
    return 1;
}

static void test_tcp_listen_row(void)
{
    int s = socket(AF_INET, SOCK_STREAM, 0);
    struct sockaddr_in a;
    char buf[4096];
    unsigned st = 0;
    memset(&a, 0, sizeof a);
    a.sin_family = AF_INET;
    a.sin_port = htons(34567);
    int ok = s >= 0 && bind(s, (struct sockaddr *)&a, sizeof a) == 0 && listen(s, 4) == 0;
    CHECKC("tcp_listen_setup", ok, "");
    if (!ok)
        return;
    int n = read_text("/proc/net/tcp", buf, sizeof buf);
    CHECK("tcp_listen_row", n > 0 && find_row(buf, 34567, &st), "buf=%s", buf);
    CHECK("tcp_listen_state_0A", st == 0x0A, "st=%02X", st);
    close(s);
    n = read_text("/proc/net/tcp", buf, sizeof buf);
    CHECK("tcp_row_gone_after_close", n > 0 && !find_row(buf, 34567, &st), "buf=%s", buf);
}

static void test_udp_row(void)
{
    int s = socket(AF_INET, SOCK_DGRAM, 0);
    struct sockaddr_in a;
    char buf[4096];
    unsigned st = 0;
    memset(&a, 0, sizeof a);
    a.sin_family = AF_INET;
    a.sin_port = htons(34568);
    int ok = s >= 0 && bind(s, (struct sockaddr *)&a, sizeof a) == 0;
    CHECKC("udp_bind_setup", ok, "");
    if (!ok)
        return;
    int n = read_text("/proc/net/udp", buf, sizeof buf);
    CHECK("udp_row", n > 0 && find_row(buf, 34568, &st), "buf=%s", buf);
    CHECK("udp_state_07", st == 0x07, "st=%02X", st);
    close(s);
    n = read_text("/proc/net/udp", buf, sizeof buf);
    CHECK("udp_row_gone_after_close", n > 0 && !find_row(buf, 34568, &st), "buf=%s", buf);
}

static void test_tcp_connected_row(void)
{
    int s = socket(AF_INET, SOCK_STREAM, 0);
    struct sockaddr_in a;
    struct row r;
    char buf[4096];
    memset(&a, 0, sizeof a);
    a.sin_family = AF_INET;
    a.sin_port = htons(7777);
    inet_pton(AF_INET, "10.0.2.100", &a.sin_addr);
    int ok = s >= 0 && connect(s, (struct sockaddr *)&a, sizeof a) == 0;
    CHECKC("tcp_connect_setup", ok, "");
    if (!ok)
        return;
    int n = read_text("/proc/net/tcp", buf, sizeof buf);
    CHECK("tcp_connected_row", n > 0 && find_row_by(buf, 0, 7777, &r), "buf=%s", buf);
    CHECK("tcp_connected_state_01", r.state == 0x01, "st=%02X", r.state);
    CHECK("tcp_connected_remote_addr", r.raddr == 0x6402000Au, "raddr=%08X", r.raddr);
    CHECK("tcp_connected_local_addr", r.laddr == 0x0F02000Au, "laddr=%08X", r.laddr);
    CHECK("tcp_connected_local_port_ephemeral", r.lport >= 1024, "lport=%u", r.lport);
    close(s);
}

static void test_route_rows(void)
{
    char buf[4096];
    int n = read_text("/proc/net/route", buf, sizeof buf);
    const char *row = strchr(buf, '\n');
    if (n <= 0 || !row || !*(row + 1)) {
        GAP("route_row_format", "no route rows (no address configured)");
        return;
    }
    char iface[32];
    unsigned dest, gw, flags, refcnt, use, metric, mask, mtu, window, irtt;
    int fields = sscanf(row + 1, "%31s %x %x %x %u %u %u %x %u %u %u", iface, &dest, &gw, &flags, &refcnt, &use, &metric, &mask, &mtu, &window, &irtt);
    CHECK("route_row_format", fields == 11, "fields=%d row=%.80s", fields, row + 1);
    CHECK("route_row_up_flag", (flags & 1) != 0, "flags=%04X", flags);
    CHECK("route_default_via_gateway", flags == 3 && dest == 0 && gw == 0x0202000Au && mask == 0, "dest=%08X gw=%08X flags=%04X mask=%08X", dest, gw, flags, mask);
    CHECK("route_iface_name", strncmp(iface, "eth", 3) == 0 || strncmp(iface, "wlan", 4) == 0 || strncmp(iface, "usb", 3) == 0, "iface=%s", iface);
}

static void test_arp_rows(void)
{
    char buf[4096];
    int n = read_text("/proc/net/arp", buf, sizeof buf);
    const char *row = strchr(buf, '\n');
    if (n <= 0 || !row || !*(row + 1)) {
        GAP("arp_row_format", "no arp entries yet");
        return;
    }
    char ip[32], mac[32], dev[32], mask[8];
    unsigned hw, flags;
    int fields = sscanf(row + 1, "%31s 0x%x 0x%x %31s %7s %31s", ip, &hw, &flags, mac, mask, dev);
    CHECK("arp_row_format", fields == 6 && hw == 1 && flags == 2 && strcmp(mask, "*") == 0 && strlen(mac) == 17, "fields=%d row=%.80s", fields, row + 1);
}

int main(void)
{
    alarm(60);
    test_headers();
    test_tcp_listen_row();
    test_udp_row();
    test_tcp_connected_row();
    test_route_rows();
    test_arp_rows();
    return 0;
}
