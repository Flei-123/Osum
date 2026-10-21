#include <dlfcn.h>
#include <stdio.h>
#include <stdint.h>
#include <string.h>

typedef int (*ver_fn)(uint32_t *);
typedef int (*ext_fn)(uint64_t, uint32_t *, uint64_t);
typedef int (*create_fn)(uint64_t, uint64_t, uint64_t *);
typedef void (*destroy_fn)(uint64_t, uint64_t);
typedef int (*enum_fn)(uint64_t, uint32_t *, uint64_t *);
typedef void (*qcount_fn)(uint64_t, uint32_t *);
typedef int (*neg_fn)(uint32_t *);
typedef uint64_t (*pa_fn)(uint64_t, uint64_t);
typedef uint64_t (*calls_fn)(void);
typedef uint64_t (*add_fn)(uint64_t, uint64_t);

static int bad;
static void check(const char *what, int ok)
{
    printf("GPU3 %s %s\n", ok ? "ok" : "FAIL", what);
    if (!ok) bad++;
}

int main(int argc, char **argv)
{
    const char *path = argc > 1 ? argv[1] : "./libicd.so";
    void *h = dlopen(path, RTLD_NOW | RTLD_LOCAL);
    check("dlopen", h != 0);
    if (!h) { printf("GPU3 dlerror %s\n", dlerror()); printf("GPU3 DONE bad=%d\n", bad + 1); return 1; }
    const char *names[] = {"vkEnumerateInstanceVersion", "vkEnumerateInstanceExtensionProperties", "vkCreateInstance", "vkDestroyInstance",
        "vkEnumeratePhysicalDevices", "vkGetPhysicalDeviceQueueFamilyPropertyCount", "vk_icdNegotiateLoaderICDInterfaceVersion",
        "vk_icdGetInstanceProcAddr", "icd_calls", "icd_add"};
    void *sym[10];
    for (int i = 0; i < 10; i++) {
        sym[i] = dlsym(h, names[i]);
        char buf[96];
        snprintf(buf, sizeof buf, "dlsym %s", names[i]);
        check(buf, sym[i] != 0);
    }
    if (bad) { printf("GPU3 DONE bad=%d\n", bad); return 1; }
    uint32_t v = 0;
    check("vkEnumerateInstanceVersion = 1.2", ((ver_fn)sym[0])(&v) == 0 && v == 0x00402000);
    uint32_t n = 99;
    check("extension count 0", ((ext_fn)sym[1])(0, &n, 0) == 0 && n == 0);
    uint64_t inst = 0;
    check("vkCreateInstance", ((create_fn)sym[2])(0, 0, &inst) == 0 && inst == 0xC0DE0001);
    uint32_t dc = 0;
    uint64_t dev = 0;
    check("vkEnumeratePhysicalDevices count", ((enum_fn)sym[4])(inst, &dc, 0) == 0 && dc == 1);
    check("vkEnumeratePhysicalDevices handle", ((enum_fn)sym[4])(inst, &dc, &dev) == 0 && dev == 0xD0D00001);
    check("wrong instance rejected", ((enum_fn)sym[4])(inst + 1, &dc, &dev) == -3);
    uint32_t q = 0;
    ((qcount_fn)sym[5])(dev, &q);
    check("queue family count 1", q == 1);
    uint32_t iv = 7;
    check("negotiate clamps to 5", ((neg_fn)sym[6])(&iv) == 0 && iv == 5);
    check("GetInstanceProcAddr returns 0", ((pa_fn)sym[7])(inst, 0) == 0);
    check("icd_add", ((add_fn)sym[9])(40, 2) == 42);
    ((destroy_fn)sym[3])(inst, 0);
    check("static counter kept state (11 calls)", ((calls_fn)sym[8])() == 11);
    check("dlclose", dlclose(h) == 0);
    printf("GPU3 DONE bad=%d\n", bad);
    return bad ? 1 : 0;
}
