/* tools/net/bruecke.c -- round K8: the wire between QEMU and Linux.
 *
 * WHY THIS FILE EXISTS AT ALL, and it is worth writing down because it
 * is the same wall round K3 ran into. The obvious way to give a QEMU
 * guest a real wire is a TAP device. `/dev/net/tun` does not exist in
 * the container this repository is measured in and cannot be created
 * there -- `mknod: Operation not permitted`, and the device cgroup of
 * the LXC container will not have it. `AF_PACKET` needs no device node,
 * and a `veth` pair across two network namespaces gives exactly what a
 * TAP would: on one side the LINUX KERNEL with an address, on the other
 * an interface without one that nobody but this program answers for.
 *
 * So the wire is three hops and every one of them carries whole
 * Ethernet frames and nothing else:
 *
 *   Osum in QEMU  <--virtio-net-->  QEMU  <--UDP on the loopback-->
 *   this program  <--AF_PACKET-->  veth  <-->  the Linux kernel in a
 *   network namespace of its own
 *
 * QEMU's `-netdev socket,udp=...` puts ONE frame in ONE datagram with
 * no header of its own, which is why the translation here is a copy and
 * not a parser.
 *
 * TWO SETTINGS THAT ARE NOT DECORATION:
 *
 *   PACKET_IGNORE_OUTGOING -- without it every frame this program
 *   injects comes straight back out of the same socket, and Osum sees
 *   its own transmissions as receptions. That is not a slowdown, it is
 *   a stack talking to itself.
 *
 *   ethtool -K ... tx off (done by run.sh, not here) -- over a veth the
 *   kernel hands out locally generated frames with CHECKSUM_PARTIAL,
 *   that is, with a checksum field it has NOT filled in because the
 *   hardware was supposed to. A stack that CHECKS the checksum -- and
 *   `lib/net/wire.fi` does -- rightly throws every one of them away.
 *
 *   bruecke <interface> <own udp port> <qemu udp port>
 *
 * On SIGTERM it prints its two counters, which run.sh reads to tell
 * "the bridge saw nothing" from "Osum sent nothing".
 */
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <errno.h>
#include <signal.h>
#include <poll.h>
#include <net/if.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <sys/ioctl.h>
#include <sys/socket.h>
#include <linux/if_packet.h>
#include <linux/if_ether.h>

#ifndef PACKET_IGNORE_OUTGOING
#define PACKET_IGNORE_OUTGOING 23
#endif

static volatile sig_atomic_t stop = 0;
static unsigned long to_qemu = 0, to_wire = 0, drops = 0;

static void on_signal(int s) { (void)s; stop = 1; }

int main(int argc, char **argv)
{
    if (argc < 4) {
        fprintf(stderr, "usage: bruecke <if> <own port> <qemu port>\n");
        return 2;
    }
    const char *ifname = argv[1];
    int myport = atoi(argv[2]);
    int qport = atoi(argv[3]);

    int pk = socket(AF_PACKET, SOCK_RAW, htons(ETH_P_ALL));
    if (pk < 0) { perror("socket(AF_PACKET)"); return 1; }

    struct ifreq ifr;
    memset(&ifr, 0, sizeof ifr);
    strncpy(ifr.ifr_name, ifname, IFNAMSIZ - 1);
    if (ioctl(pk, SIOCGIFINDEX, &ifr) < 0) { perror("SIOCGIFINDEX"); return 1; }
    int ifindex = ifr.ifr_ifindex;

    struct sockaddr_ll sll;
    memset(&sll, 0, sizeof sll);
    sll.sll_family = AF_PACKET;
    sll.sll_protocol = htons(ETH_P_ALL);
    sll.sll_ifindex = ifindex;
    if (bind(pk, (struct sockaddr *)&sll, sizeof sll) < 0) {
        perror("bind(AF_PACKET)"); return 1;
    }
    int one = 1;
    /* Not fatal on an old kernel -- but then the counters below lie, so
     * say so rather than go on in silence. */
    if (setsockopt(pk, SOL_PACKET, PACKET_IGNORE_OUTGOING, &one, sizeof one) < 0)
        fprintf(stderr, "bruecke: PACKET_IGNORE_OUTGOING is not available\n");

    /* Promiscuous: the frames Osum sends carry ITS hardware address as
     * the source and the peer's as the destination; the veth end this
     * program listens on has an address of its own and would otherwise
     * only see broadcasts. */
    struct packet_mreq mr;
    memset(&mr, 0, sizeof mr);
    mr.mr_ifindex = ifindex;
    mr.mr_type = PACKET_MR_PROMISC;
    if (setsockopt(pk, SOL_PACKET, PACKET_ADD_MEMBERSHIP, &mr, sizeof mr) < 0)
        perror("PACKET_MR_PROMISC");

    int us = socket(AF_INET, SOCK_DGRAM, 0);
    if (us < 0) { perror("socket(udp)"); return 1; }
    struct sockaddr_in me, qemu;
    memset(&me, 0, sizeof me);
    me.sin_family = AF_INET;
    me.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    me.sin_port = htons(myport);
    if (bind(us, (struct sockaddr *)&me, sizeof me) < 0) {
        perror("bind(udp)"); return 1;
    }
    memset(&qemu, 0, sizeof qemu);
    qemu.sin_family = AF_INET;
    qemu.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    qemu.sin_port = htons(qport);

    int big = 4 << 20;
    setsockopt(us, SOL_SOCKET, SO_RCVBUF, &big, sizeof big);
    setsockopt(us, SOL_SOCKET, SO_SNDBUF, &big, sizeof big);
    setsockopt(pk, SOL_SOCKET, SO_RCVBUF, &big, sizeof big);

    signal(SIGTERM, on_signal);
    signal(SIGINT, on_signal);

    static unsigned char buf[65536];
    struct pollfd p[2];
    p[0].fd = pk; p[0].events = POLLIN;
    p[1].fd = us; p[1].events = POLLIN;

    while (!stop) {
        int r = poll(p, 2, 200);
        if (r < 0) { if (errno == EINTR) continue; break; }
        if (p[0].revents & POLLIN) {
            for (;;) {
                ssize_t n = recv(pk, buf, sizeof buf, MSG_DONTWAIT);
                if (n <= 0) break;
                if (sendto(us, buf, n, 0, (struct sockaddr *)&qemu,
                           sizeof qemu) < 0) drops++;
                else to_qemu++;
            }
        }
        if (p[1].revents & POLLIN) {
            for (;;) {
                ssize_t n = recv(us, buf, sizeof buf, MSG_DONTWAIT);
                if (n <= 0) break;
                struct sockaddr_ll d;
                memset(&d, 0, sizeof d);
                d.sll_family = AF_PACKET;
                d.sll_ifindex = ifindex;
                d.sll_halen = 6;
                memcpy(d.sll_addr, buf, 6);
                if (sendto(pk, buf, n, 0, (struct sockaddr *)&d, sizeof d) < 0)
                    drops++;
                else to_wire++;
            }
        }
    }
    fprintf(stderr, "bruecke: to_qemu=%lu to_wire=%lu drops=%lu\n",
            to_qemu, to_wire, drops);
    return 0;
}
