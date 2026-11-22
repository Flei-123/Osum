static long count_cpus_osum(const char *text)
{
    const char *key = "cpus_online=";
    const char *at = strstr(text, key);
    return at ? strtol(at + strlen(key), 0, 10) : -1;
}

static long count_cpus_linux(const char *text)
{
    long n = 0;
    for (const char *at = text; (at = strstr(at, "processor")); at += 9)
        n++;
    return n > 0 ? n : -1;
}

static long read_text(const char *path, char *buf, long cap)
{
    int fd = open(path, O_RDONLY);
    if (fd < 0)
        return -1;
    long len = read(fd, buf, cap - 1);
    close(fd);
    if (len < 0)
        return -1;
    buf[len] = 0;
    return len;
}

static void report_cpus(void)
{
    static char buf[16384];
    long n = -1;
    if (read_text("/proc/cpus", buf, sizeof buf) > 0)
        n = count_cpus_osum(buf);
    if (n < 0 && read_text("/proc/cpuinfo", buf, sizeof buf) > 0)
        n = count_cpus_linux(buf);
    char line[64];
    int len = snprintf(line, sizeof line, "C cpus %ld\n", n);
    (void)!write(1, line, len);
}
