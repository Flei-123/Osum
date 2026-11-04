#define VK_NO_PROTOTYPES
#include <vulkan/vulkan.h>
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>

#define FN(name) static PFN_##name name
FN(vkCreateInstance); FN(vkDestroyInstance); FN(vkEnumeratePhysicalDevices); FN(vkGetPhysicalDeviceProperties);
FN(vkGetPhysicalDeviceMemoryProperties); FN(vkGetPhysicalDeviceQueueFamilyProperties); FN(vkCreateDevice); FN(vkDestroyDevice);
FN(vkGetDeviceQueue); FN(vkAllocateMemory); FN(vkFreeMemory); FN(vkMapMemory); FN(vkUnmapMemory); FN(vkCreateBuffer); FN(vkDestroyBuffer);
FN(vkGetBufferMemoryRequirements); FN(vkBindBufferMemory); FN(vkCreateImage); FN(vkDestroyImage); FN(vkGetImageMemoryRequirements);
FN(vkBindImageMemory); FN(vkCreateCommandPool); FN(vkDestroyCommandPool); FN(vkAllocateCommandBuffers); FN(vkBeginCommandBuffer);
FN(vkEndCommandBuffer); FN(vkCmdClearColorImage); FN(vkCmdCopyBuffer); FN(vkCmdCopyImageToBuffer); FN(vkCmdCopyBufferToImage);
FN(vkCmdFillBuffer); FN(vkCmdPipelineBarrier); FN(vkCreateFence); FN(vkDestroyFence); FN(vkQueueSubmit); FN(vkWaitForFences);
FN(vkResetFences); FN(vkGetFenceStatus); FN(vkGetDeviceProcAddr); FN(vkQueueWaitIdle); FN(vkResetCommandBuffer); FN(vkFreeCommandBuffers);
FN(vkEnumerateInstanceVersion);

static PFN_vkGetInstanceProcAddr gipa;
static VkDevice dev;
static VkQueue queue;
static VkCommandPool pool;
static VkCommandBuffer cb;
static VkPhysicalDeviceMemoryProperties mp;
static int bad;

static void check(const char *what, int ok)
{
    printf("VK %s %s\n", ok ? "ok" : "FAIL", what);
    if (!ok) bad++;
}

static uint64_t fnv(const uint8_t *p, size_t n)
{
    uint64_t h = 1469598103934665603ull;
    for (size_t i = 0; i < n; i++) { h ^= p[i]; h *= 1099511628211ull; }
    return h;
}

static uint32_t mem_type(uint32_t bits)
{
    for (uint32_t i = 0; i < mp.memoryTypeCount; i++)
        if ((bits & (1u << i)) && (mp.memoryTypes[i].propertyFlags & 6) == 6) return i;
    return 0;
}

typedef struct { VkBuffer b; VkDeviceMemory m; uint8_t *p; size_t n; } Buf;
static Buf mkbuf(size_t n)
{
    Buf r = {0};
    r.n = n;
    VkBufferCreateInfo bi = { .sType = VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO, .size = n, .usage = VK_BUFFER_USAGE_TRANSFER_SRC_BIT | VK_BUFFER_USAGE_TRANSFER_DST_BIT, .sharingMode = VK_SHARING_MODE_EXCLUSIVE };
    vkCreateBuffer(dev, &bi, 0, &r.b);
    VkMemoryRequirements rq;
    vkGetBufferMemoryRequirements(dev, r.b, &rq);
    VkMemoryAllocateInfo ai = { .sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO, .allocationSize = rq.size, .memoryTypeIndex = mem_type(rq.memoryTypeBits) };
    vkAllocateMemory(dev, &ai, 0, &r.m);
    vkBindBufferMemory(dev, r.b, r.m, 0);
    vkMapMemory(dev, r.m, 0, VK_WHOLE_SIZE, 0, (void **)&r.p);
    memset(r.p, 0, n);
    return r;
}

typedef struct { VkImage i; VkDeviceMemory m; uint32_t w, h; } Img;
static Img mkimg(VkFormat f, uint32_t w, uint32_t h)
{
    Img r = {0};
    r.w = w; r.h = h;
    VkImageCreateInfo ii = { .sType = VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO, .imageType = VK_IMAGE_TYPE_2D, .format = f, .extent = { w, h, 1 }, .mipLevels = 1, .arrayLayers = 1,
        .samples = VK_SAMPLE_COUNT_1_BIT, .tiling = VK_IMAGE_TILING_OPTIMAL, .usage = VK_IMAGE_USAGE_TRANSFER_SRC_BIT | VK_IMAGE_USAGE_TRANSFER_DST_BIT, .sharingMode = VK_SHARING_MODE_EXCLUSIVE, .initialLayout = VK_IMAGE_LAYOUT_UNDEFINED };
    vkCreateImage(dev, &ii, 0, &r.i);
    VkMemoryRequirements rq;
    vkGetImageMemoryRequirements(dev, r.i, &rq);
    VkMemoryAllocateInfo ai = { .sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO, .allocationSize = rq.size, .memoryTypeIndex = 0 };
    for (uint32_t t = 0; t < mp.memoryTypeCount; t++) if (rq.memoryTypeBits & (1u << t)) { ai.memoryTypeIndex = t; break; }
    vkAllocateMemory(dev, &ai, 0, &r.m);
    vkBindImageMemory(dev, r.i, r.m, 0);
    return r;
}

static void begin(void)
{
    vkResetCommandBuffer(cb, 0);
    VkCommandBufferBeginInfo bi = { .sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO, .flags = VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT };
    vkBeginCommandBuffer(cb, &bi);
}

static void to_general(VkImage im)
{
    VkImageMemoryBarrier b = { .sType = VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER, .dstAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT | VK_ACCESS_TRANSFER_READ_BIT, .oldLayout = VK_IMAGE_LAYOUT_UNDEFINED, .newLayout = VK_IMAGE_LAYOUT_GENERAL,
        .srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED, .dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED, .image = im, .subresourceRange = { VK_IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1 } };
    vkCmdPipelineBarrier(cb, VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT, VK_PIPELINE_STAGE_TRANSFER_BIT, 0, 0, 0, 0, 0, 1, &b);
}

static void barrier_all(void)
{
    VkMemoryBarrier m = { .sType = VK_STRUCTURE_TYPE_MEMORY_BARRIER, .srcAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT, .dstAccessMask = VK_ACCESS_TRANSFER_READ_BIT | VK_ACCESS_TRANSFER_WRITE_BIT | VK_ACCESS_HOST_READ_BIT };
    vkCmdPipelineBarrier(cb, VK_PIPELINE_STAGE_TRANSFER_BIT, VK_PIPELINE_STAGE_TRANSFER_BIT | VK_PIPELINE_STAGE_HOST_BIT, 0, 1, &m, 0, 0, 0, 0);
}

static int submit_wait(VkFence f)
{
    vkEndCommandBuffer(cb);
    VkSubmitInfo si = { .sType = VK_STRUCTURE_TYPE_SUBMIT_INFO, .commandBufferCount = 1, .pCommandBuffers = &cb };
    if (vkQueueSubmit(queue, 1, &si, f) != VK_SUCCESS) return 0;
    return vkWaitForFences(dev, 1, &f, VK_TRUE, 5000000000ull) == VK_SUCCESS;
}

#define LOAD(name) name = (PFN_##name)gipa(inst, #name)

int main(int argc, char **argv)
{
    const char *path = argc > 1 ? argv[1] : "./libvulkan.so.1";
    int mode = argc > 2 ? atoi(argv[2]) : 0;
    void *h = dlopen(path, RTLD_NOW | RTLD_LOCAL);
    check("dlopen", h != 0);
    if (!h) { printf("VK DONE bad=%d\n", bad); return 1; }
    gipa = (PFN_vkGetInstanceProcAddr)dlsym(h, "vkGetInstanceProcAddr");
    check("dlsym vkGetInstanceProcAddr", gipa != 0);
    if (!gipa) { printf("VK DONE bad=%d\n", bad); return 1; }
    VkInstance inst = 0;
    vkCreateInstance = (PFN_vkCreateInstance)gipa(0, "vkCreateInstance");
    vkEnumerateInstanceVersion = (PFN_vkEnumerateInstanceVersion)gipa(0, "vkEnumerateInstanceVersion");
    uint32_t ver = 0;
    check("vkEnumerateInstanceVersion >= 1.1", vkEnumerateInstanceVersion && vkEnumerateInstanceVersion(&ver) == VK_SUCCESS && ver >= VK_MAKE_VERSION(1, 1, 0));
    VkApplicationInfo app = { .sType = VK_STRUCTURE_TYPE_APPLICATION_INFO, .apiVersion = VK_API_VERSION_1_1 };
    VkInstanceCreateInfo ici = { .sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO, .pApplicationInfo = &app };
    check("vkCreateInstance", vkCreateInstance(&ici, 0, &inst) == VK_SUCCESS && inst);
    LOAD(vkDestroyInstance); LOAD(vkEnumeratePhysicalDevices); LOAD(vkGetPhysicalDeviceProperties); LOAD(vkGetPhysicalDeviceMemoryProperties);
    LOAD(vkGetPhysicalDeviceQueueFamilyProperties); LOAD(vkCreateDevice); LOAD(vkGetDeviceProcAddr);
    uint32_t n = 0;
    check("vkEnumeratePhysicalDevices count", vkEnumeratePhysicalDevices(inst, &n, 0) == VK_SUCCESS && n >= 1);
    VkPhysicalDevice pds[8];
    if (n > 8) n = 8;
    vkEnumeratePhysicalDevices(inst, &n, pds);
    VkPhysicalDevice pd = pds[0];
    if (mode == 1) for (uint32_t i = 0; i < n; i++) { VkPhysicalDeviceProperties p; vkGetPhysicalDeviceProperties(pds[i], &p); if (p.deviceType == VK_PHYSICAL_DEVICE_TYPE_CPU) pd = pds[i]; }
    VkPhysicalDeviceProperties props;
    vkGetPhysicalDeviceProperties(pd, &props);
    check("device apiVersion >= 1.1", props.apiVersion >= VK_MAKE_VERSION(1, 1, 0));
    check("device type CPU", props.deviceType == VK_PHYSICAL_DEVICE_TYPE_CPU);
    printf("VK info device=%s\n", mode == 2 ? "hidden" : props.deviceName);
    vkGetPhysicalDeviceMemoryProperties(pd, &mp);
    check("a host visible coherent memory type", mem_type(0xFFFFFFFFu) < mp.memoryTypeCount && (mp.memoryTypes[mem_type(0xFFFFFFFFu)].propertyFlags & 6) == 6);
    uint32_t qn = 0, qf = 0;
    vkGetPhysicalDeviceQueueFamilyProperties(pd, &qn, 0);
    VkQueueFamilyProperties qp[8];
    if (qn > 8) qn = 8;
    vkGetPhysicalDeviceQueueFamilyProperties(pd, &qn, qp);
    for (uint32_t i = 0; i < qn; i++) if (qp[i].queueFlags & VK_QUEUE_TRANSFER_BIT) { qf = i; break; }
    check("queue family with transfer", qn >= 1 && (qp[qf].queueFlags & VK_QUEUE_TRANSFER_BIT));
    float prio = 1.0f;
    VkDeviceQueueCreateInfo dq = { .sType = VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO, .queueFamilyIndex = qf, .queueCount = 1, .pQueuePriorities = &prio };
    VkDeviceCreateInfo dci = { .sType = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO, .queueCreateInfoCount = 1, .pQueueCreateInfos = &dq };
    check("vkCreateDevice", vkCreateDevice(pd, &dci, 0, &dev) == VK_SUCCESS && dev);
#define LD(name) name = (PFN_##name)vkGetDeviceProcAddr(dev, #name)
    LD(vkDestroyDevice); LD(vkGetDeviceQueue); LD(vkAllocateMemory); LD(vkFreeMemory); LD(vkMapMemory); LD(vkUnmapMemory); LD(vkCreateBuffer); LD(vkDestroyBuffer);
    LD(vkGetBufferMemoryRequirements); LD(vkBindBufferMemory); LD(vkCreateImage); LD(vkDestroyImage); LD(vkGetImageMemoryRequirements); LD(vkBindImageMemory);
    LD(vkCreateCommandPool); LD(vkDestroyCommandPool); LD(vkAllocateCommandBuffers); LD(vkBeginCommandBuffer); LD(vkEndCommandBuffer); LD(vkCmdClearColorImage);
    LD(vkCmdCopyBuffer); LD(vkCmdCopyImageToBuffer); LD(vkCmdCopyBufferToImage); LD(vkCmdFillBuffer); LD(vkCmdPipelineBarrier); LD(vkCreateFence); LD(vkDestroyFence);
    LD(vkQueueSubmit); LD(vkWaitForFences); LD(vkResetFences); LD(vkGetFenceStatus); LD(vkQueueWaitIdle); LD(vkResetCommandBuffer); LD(vkFreeCommandBuffers);
    int all = vkDestroyDevice && vkGetDeviceQueue && vkAllocateMemory && vkMapMemory && vkCreateBuffer && vkCreateImage && vkCmdClearColorImage && vkCmdCopyBuffer && vkCmdCopyImageToBuffer &&
        vkCmdCopyBufferToImage && vkCmdFillBuffer && vkCmdPipelineBarrier && vkQueueSubmit && vkWaitForFences && vkCreateFence && vkAllocateCommandBuffers;
    check("all device entry points resolve", all);
    if (!all || bad) { printf("VK DONE bad=%d\n", bad); return 1; }
    vkGetDeviceQueue(dev, qf, 0, &queue);
    VkCommandPoolCreateInfo pci = { .sType = VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO, .flags = VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT, .queueFamilyIndex = qf };
    vkCreateCommandPool(dev, &pci, 0, &pool);
    VkCommandBufferAllocateInfo cai = { .sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO, .commandPool = pool, .level = VK_COMMAND_BUFFER_LEVEL_PRIMARY, .commandBufferCount = 1 };
    check("vkAllocateCommandBuffers", vkAllocateCommandBuffers(dev, &cai, &cb) == VK_SUCCESS && cb);
    VkFenceCreateInfo fci = { .sType = VK_STRUCTURE_TYPE_FENCE_CREATE_INFO };
    VkFence fence;
    vkCreateFence(dev, &fci, 0, &fence);
    check("fence starts unsignaled", vkGetFenceStatus(dev, fence) == VK_NOT_READY);

    const uint32_t W = 64, H = 48;
    const VkFormat fmts[2] = { VK_FORMAT_R8G8B8A8_UNORM, VK_FORMAT_B8G8R8A8_UNORM };
    const char *fname[2] = { "rgba", "bgra" };
    for (int f = 0; f < 2; f++) {
        Img im = mkimg(fmts[f], W, H);
        Buf out = mkbuf(W * H * 4);
        begin();
        to_general(im.i);
        VkClearColorValue cv = { .float32 = { 10.6f / 255.0f, 100.7f / 255.0f, 200.2f / 255.0f, 253.9f / 255.0f } };
        VkImageSubresourceRange rg = { VK_IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1 };
        vkCmdClearColorImage(cb, im.i, VK_IMAGE_LAYOUT_GENERAL, &cv, 1, &rg);
        barrier_all();
        VkBufferImageCopy rc = { .bufferOffset = 0, .imageSubresource = { VK_IMAGE_ASPECT_COLOR_BIT, 0, 0, 1 }, .imageExtent = { W, H, 1 } };
        vkCmdCopyImageToBuffer(cb, im.i, VK_IMAGE_LAYOUT_GENERAL, out.b, 1, &rc);
        barrier_all();
        vkResetFences(dev, 1, &fence);
        char nm[64];
        snprintf(nm, sizeof nm, "clear+readback %s submit", fname[f]);
        check(nm, submit_wait(fence));
        printf("VK case clear-%s hash=%016llx first=%02x%02x%02x%02x\n", fname[f], (unsigned long long)fnv(out.p, out.n), out.p[0], out.p[1], out.p[2], out.p[3]);
        check("fence signaled after wait", vkGetFenceStatus(dev, fence) == VK_SUCCESS);

        Buf src = mkbuf(W * H * 4), back = mkbuf(W * H * 4);
        for (uint32_t i = 0; i < W * H * 4; i++) src.p[i] = (uint8_t)((i * 7 + (i >> 8) * 13) & 0xFF);
        begin();
        VkBufferImageCopy up = { .bufferOffset = 0, .bufferRowLength = W, .imageSubresource = { VK_IMAGE_ASPECT_COLOR_BIT, 0, 0, 1 }, .imageExtent = { W, H, 1 } };
        vkCmdCopyBufferToImage(cb, src.b, im.i, VK_IMAGE_LAYOUT_GENERAL, 1, &up);
        barrier_all();
        VkBufferImageCopy sub = { .bufferOffset = 16, .bufferRowLength = 40, .bufferImageHeight = 30, .imageSubresource = { VK_IMAGE_ASPECT_COLOR_BIT, 0, 0, 1 }, .imageOffset = { 5, 7, 0 }, .imageExtent = { 20, 11, 1 } };
        vkCmdCopyImageToBuffer(cb, im.i, VK_IMAGE_LAYOUT_GENERAL, back.b, 1, &sub);
        barrier_all();
        snprintf(nm, sizeof nm, "upload + sub-rect readback %s submit", fname[f]);
        vkResetFences(dev, 1, &fence);
        check(nm, submit_wait(fence));
        printf("VK case subrect-%s hash=%016llx\n", fname[f], (unsigned long long)fnv(back.p, back.n));
        int match = 1;
        for (uint32_t y = 0; y < 11 && match; y++) for (uint32_t x = 0; x < 20 && match; x++)
            if (memcmp(back.p + 16 + (y * 40 + x) * 4, src.p + ((7 + y) * W + 5 + x) * 4, 4)) match = 0;
        check("sub-rect pixels equal the uploaded pixels", match);
        vkUnmapMemory(dev, src.m);
        vkDestroyBuffer(dev, src.b, 0); vkDestroyBuffer(dev, back.b, 0); vkDestroyBuffer(dev, out.b, 0);
        vkFreeMemory(dev, src.m, 0); vkFreeMemory(dev, back.m, 0); vkFreeMemory(dev, out.m, 0);
        vkDestroyImage(dev, im.i, 0); vkFreeMemory(dev, im.m, 0);
    }

    Buf a = mkbuf(4096), b = mkbuf(4096);
    for (int i = 0; i < 4096; i++) a.p[i] = (uint8_t)(i * 3);
    begin();
    vkCmdFillBuffer(cb, b.b, 0, VK_WHOLE_SIZE, 0xA5A5A5A5u);
    barrier_all();
    VkBufferCopy bc[2] = { { 100, 200, 300 }, { 1000, 2000, 500 } };
    vkCmdCopyBuffer(cb, a.b, b.b, 2, bc);
    barrier_all();
    vkResetFences(dev, 1, &fence);
    check("fill + copy buffer submit", submit_wait(fence));
    printf("VK case buffers hash=%016llx\n", (unsigned long long)fnv(b.p, b.n));
    check("fill value", b.p[0] == 0xA5 && b.p[4095] == 0xA5 && b.p[199] == 0xA5);
    check("copy region 0", memcmp(b.p + 200, a.p + 100, 300) == 0 && b.p[500] == 0xA5);
    check("copy region 1", memcmp(b.p + 2000, a.p + 1000, 500) == 0);
    printf("VK DONE bad=%d\n", bad);
    return bad ? 1 : 0;
}
