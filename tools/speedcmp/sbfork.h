#define SBF_THREADS 3
#define SBF_BYTES (64UL << 20)
#define SBF_FORKS 20

static volatile int sbf_stop;

static void *sbf_spin(void *arg)
{
    (void)arg;
    while (!sbf_stop)
        __builtin_ia32_pause();
    return 0;
}

static void run_fork_threads(long n)
{
    for (long i = 0; i < n; i++) {
        pid_t pid = fork();
        if (pid == 0)
            _exit(0);
        waitpid(pid, 0, 0);
    }
}

static void sbfork_run_all(void)
{
    char *mem = mmap(0, SBF_BYTES, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (mem == MAP_FAILED)
        return;
    for (size_t off = 0; off < SBF_BYTES; off += 4096)
        mem[off] = 1;
    pthread_t threads[SBF_THREADS];
    int started = 0;
    sbf_stop = 0;
    while (started < SBF_THREADS && pthread_create(&threads[started], 0, sbf_spin, 0) == 0)
        started++;
    measure("fork_threads_exit_wait", run_fork_threads, SBF_FORKS, 1, 1);
    sbf_stop = 1;
    for (int i = 0; i < started; i++)
        pthread_join(threads[i], 0);
    munmap(mem, SBF_BYTES);
}
