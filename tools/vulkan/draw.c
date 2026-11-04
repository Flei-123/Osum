#define VK_NO_PROTOTYPES
#include <vulkan/vulkan.h>
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <time.h>
#include <unistd.h>
#include <sys/mman.h>
#include <sys/syscall.h>

typedef VkResult (VKAPI_PTR *PFN_vkOsumSetSurfaceSinkOSUM)(VkSurfaceKHR, void *, uint64_t);
typedef uint64_t (VKAPI_PTR *PFN_vkOsumGetPresentCountOSUM)(VkSurfaceKHR);
#define FNS(X) X(vkDestroyDevice) X(vkGetDeviceQueue) X(vkAllocateMemory) X(vkMapMemory) X(vkCreateBuffer) X(vkGetBufferMemoryRequirements) X(vkBindBufferMemory) \
    X(vkCreateImage) X(vkGetImageMemoryRequirements) X(vkBindImageMemory) X(vkCreateCommandPool) X(vkAllocateCommandBuffers) X(vkBeginCommandBuffer) X(vkEndCommandBuffer) \
    X(vkCmdCopyBuffer) X(vkCmdCopyImageToBuffer) X(vkCmdCopyBufferToImage) X(vkCmdPipelineBarrier) X(vkCreateFence) X(vkQueueSubmit) X(vkWaitForFences) X(vkResetFences) \
    X(vkResetCommandBuffer) X(vkCreateShaderModule) X(vkCreateGraphicsPipelines) X(vkCreatePipelineLayout) X(vkCreateDescriptorSetLayout) X(vkCreateDescriptorPool) \
    X(vkAllocateDescriptorSets) X(vkUpdateDescriptorSets) X(vkCreateImageView) X(vkCreateSampler) X(vkCmdBeginRendering) X(vkCmdEndRendering) X(vkCmdBindPipeline) \
    X(vkCmdBindVertexBuffers) X(vkCmdBindIndexBuffer) X(vkCmdBindDescriptorSets) X(vkCmdPushConstants) X(vkCmdSetViewport) X(vkCmdSetScissor) X(vkCmdDraw) X(vkCmdDrawIndexed) \
    X(vkCreateRenderPass) X(vkCreateFramebuffer) X(vkCmdBeginRenderPass) X(vkCmdEndRenderPass) X(vkCmdClearAttachments) X(vkCmdBlitImage)
#define DECL(n) static PFN_##n n;
FNS(DECL)

static VkDevice dev;
static VkQueue queue;
static VkCommandBuffer cb;
static VkFence fence;
static VkPhysicalDeviceMemoryProperties mp;
static int bad;
static int g_area[4] = { 0, 0, 64, 48 };
static int g_keep;
static const char *outdir = ".";
static const char *spvdir = ".";
enum { W = 64, H = 48 };

static void check(const char *what, int ok) { printf("VK %s %s\n", ok ? "ok" : "FAIL", what); if (!ok) bad++; }

typedef struct { VkBuffer b; VkDeviceMemory m; uint8_t *p; } Buf;
static uint32_t mem_type(uint32_t bits)
{
    for (uint32_t i = 0; i < mp.memoryTypeCount; i++) if ((bits & (1u << i)) && (mp.memoryTypes[i].propertyFlags & 6) == 6) return i;
    return 0;
}
static Buf mkbuf(size_t n, VkBufferUsageFlags usage)
{
    Buf r = {0};
    VkBufferCreateInfo bi = { .sType = VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO, .size = n, .usage = usage, .sharingMode = VK_SHARING_MODE_EXCLUSIVE };
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
static Buf mkvec(const void *d, size_t n, VkBufferUsageFlags usage) { Buf b = mkbuf(n, usage); memcpy(b.p, d, n); return b; }

typedef struct { VkImage i; VkImageView v; } Img;
static Img mkimg(VkFormat f, uint32_t w, uint32_t h, VkImageUsageFlags usage, VkImageAspectFlags aspect)
{
    Img r = {0};
    VkImageCreateInfo ii = { .sType = VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO, .imageType = VK_IMAGE_TYPE_2D, .format = f, .extent = { w, h, 1 }, .mipLevels = 1, .arrayLayers = 1,
        .samples = VK_SAMPLE_COUNT_1_BIT, .tiling = VK_IMAGE_TILING_OPTIMAL, .usage = usage, .sharingMode = VK_SHARING_MODE_EXCLUSIVE, .initialLayout = VK_IMAGE_LAYOUT_UNDEFINED };
    vkCreateImage(dev, &ii, 0, &r.i);
    VkMemoryRequirements rq;
    vkGetImageMemoryRequirements(dev, r.i, &rq);
    VkMemoryAllocateInfo ai = { .sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO, .allocationSize = rq.size, .memoryTypeIndex = 0 };
    for (uint32_t t = 0; t < mp.memoryTypeCount; t++) if (rq.memoryTypeBits & (1u << t)) { ai.memoryTypeIndex = t; break; }
    VkDeviceMemory m;
    vkAllocateMemory(dev, &ai, 0, &m);
    vkBindImageMemory(dev, r.i, m, 0);
    VkImageViewCreateInfo vi = { .sType = VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO, .image = r.i, .viewType = VK_IMAGE_VIEW_TYPE_2D, .format = f, .subresourceRange = { aspect, 0, 1, 0, 1 } };
    vkCreateImageView(dev, &vi, 0, &r.v);
    return r;
}

static void begin(void)
{
    vkResetCommandBuffer(cb, 0);
    VkCommandBufferBeginInfo bi = { .sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO, .flags = VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT };
    vkBeginCommandBuffer(cb, &bi);
}
static void transition(VkImage im, VkImageAspectFlags aspect, VkImageLayout from, VkImageLayout to)
{
    VkImageMemoryBarrier b = { .sType = VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER, .srcAccessMask = VK_ACCESS_MEMORY_WRITE_BIT, .dstAccessMask = VK_ACCESS_MEMORY_READ_BIT | VK_ACCESS_MEMORY_WRITE_BIT,
        .oldLayout = from, .newLayout = to, .srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED, .dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED, .image = im, .subresourceRange = { aspect, 0, 1, 0, 1 } };
    vkCmdPipelineBarrier(cb, VK_PIPELINE_STAGE_ALL_COMMANDS_BIT, VK_PIPELINE_STAGE_ALL_COMMANDS_BIT, 0, 0, 0, 0, 0, 1, &b);
}
static int submit_wait(void)
{
    vkEndCommandBuffer(cb);
    VkSubmitInfo si = { .sType = VK_STRUCTURE_TYPE_SUBMIT_INFO, .commandBufferCount = 1, .pCommandBuffers = &cb };
    vkResetFences(dev, 1, &fence);
    if (vkQueueSubmit(queue, 1, &si, fence) != VK_SUCCESS) return 0;
    return vkWaitForFences(dev, 1, &fence, VK_TRUE, 20000000000ull) == VK_SUCCESS;
}

static VkShaderModule load_shader(const char *name)
{
    char path[512];
    snprintf(path, sizeof path, "%s/%s.opt", spvdir, name);
    FILE *f = fopen(path, "rb");
    if (!f) { printf("VK FAIL open %s\n", path); bad++; return 0; }
    fseek(f, 0, SEEK_END);
    long n = ftell(f);
    fseek(f, 0, SEEK_SET);
    uint32_t *code = malloc(n);
    if (fread(code, 1, n, f) != (size_t)n) bad++;
    fclose(f);
    VkShaderModuleCreateInfo si = { .sType = VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO, .codeSize = n, .pCode = code };
    VkShaderModule m = 0;
    vkCreateShaderModule(dev, &si, 0, &m);
    free(code);
    return m;
}

typedef struct { const char *vs, *fs; VkFormat color, depth; int blend, depth_test, nattr, stride; VkFormat afmt[2]; uint32_t aoff[2]; VkPipelineLayout layout; int cull, cw, dopx, nowrite, stencil, inst; VkStencilOpState sf; } PipeDesc;
static VkFormat g_sfmt = VK_FORMAT_UNDEFINED;
static VkInstance g_inst;
static int g_wsi;
static VkPhysicalDevice g_pd;
static PFN_vkGetInstanceProcAddr g_gipa;
static PFN_vkGetDeviceProcAddr g_gdpa;
static VkRenderPass g_rp;
static VkPipeline mkpipe(const PipeDesc *d)
{
    VkPipelineShaderStageCreateInfo st[2] = {
        { .sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO, .stage = VK_SHADER_STAGE_VERTEX_BIT, .module = load_shader(d->vs), .pName = "main" },
        { .sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO, .stage = VK_SHADER_STAGE_FRAGMENT_BIT, .module = load_shader(d->fs), .pName = "main" } };
    VkVertexInputBindingDescription bd[2] = { { 0, (uint32_t)d->stride, VK_VERTEX_INPUT_RATE_VERTEX }, { 1, 24, VK_VERTEX_INPUT_RATE_INSTANCE } };
    VkVertexInputAttributeDescription ad[3] = { { 0, 0, d->afmt[0], d->aoff[0] }, { 1, 0, d->afmt[1], d->aoff[1] }, { 2, 1, VK_FORMAT_R32G32B32A32_SFLOAT, 8 } };
    if (d->inst) ad[1] = (VkVertexInputAttributeDescription){ 1, 1, VK_FORMAT_R32G32_SFLOAT, 0 };
    VkPipelineVertexInputStateCreateInfo vi = { .sType = VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO, .vertexBindingDescriptionCount = d->inst ? 2 : 1, .pVertexBindingDescriptions = bd, .vertexAttributeDescriptionCount = d->inst ? 3 : 2, .pVertexAttributeDescriptions = ad };
    VkPipelineInputAssemblyStateCreateInfo ia = { .sType = VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO, .topology = VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST };
    VkPipelineViewportStateCreateInfo vp = { .sType = VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO, .viewportCount = 1, .scissorCount = 1 };
    VkPipelineRasterizationStateCreateInfo rs = { .sType = VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO, .polygonMode = VK_POLYGON_MODE_FILL, .cullMode = d->cull, .frontFace = d->cw ? VK_FRONT_FACE_CLOCKWISE : VK_FRONT_FACE_COUNTER_CLOCKWISE, .lineWidth = 1.0f };
    VkPipelineMultisampleStateCreateInfo ms = { .sType = VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO, .rasterizationSamples = VK_SAMPLE_COUNT_1_BIT };
    VkPipelineDepthStencilStateCreateInfo ds = { .sType = VK_STRUCTURE_TYPE_PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO, .depthTestEnable = d->depth_test, .depthWriteEnable = d->depth_test && !d->nowrite, .depthCompareOp = d->dopx ? d->dopx - 1 : VK_COMPARE_OP_LESS, .stencilTestEnable = d->stencil, .front = d->sf, .back = d->sf, .maxDepthBounds = 1.0f };
    VkPipelineColorBlendAttachmentState ba = { .blendEnable = d->blend, .srcColorBlendFactor = VK_BLEND_FACTOR_SRC_ALPHA, .dstColorBlendFactor = VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA, .colorBlendOp = VK_BLEND_OP_ADD,
        .srcAlphaBlendFactor = VK_BLEND_FACTOR_ONE, .dstAlphaBlendFactor = VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA, .alphaBlendOp = VK_BLEND_OP_ADD, .colorWriteMask = 15 };
    VkPipelineColorBlendStateCreateInfo cbs = { .sType = VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO, .attachmentCount = 1, .pAttachments = &ba };
    VkDynamicState dyn[2] = { VK_DYNAMIC_STATE_VIEWPORT, VK_DYNAMIC_STATE_SCISSOR };
    VkPipelineDynamicStateCreateInfo dsi = { .sType = VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO, .dynamicStateCount = 2, .pDynamicStates = dyn };
    VkFormat cf = d->color;
    VkPipelineRenderingCreateInfo ri = { .sType = VK_STRUCTURE_TYPE_PIPELINE_RENDERING_CREATE_INFO, .colorAttachmentCount = 1, .pColorAttachmentFormats = &cf, .depthAttachmentFormat = d->depth, .stencilAttachmentFormat = d->stencil ? g_sfmt : VK_FORMAT_UNDEFINED };
    VkGraphicsPipelineCreateInfo gi = { .sType = VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO, .pNext = g_rp ? 0 : &ri, .renderPass = g_rp, .stageCount = 2, .pStages = st, .pVertexInputState = &vi, .pInputAssemblyState = &ia,
        .pViewportState = &vp, .pRasterizationState = &rs, .pMultisampleState = &ms, .pDepthStencilState = &ds, .pColorBlendState = &cbs, .pDynamicState = &dsi, .layout = d->layout };
    VkPipeline p = 0;
    VkResult r = vkCreateGraphicsPipelines(dev, 0, 1, &gi, 0, &p);
    if (r != VK_SUCCESS) p = 0;
    return p;
}

static VkPipelineLayout mklayout(int sampler, uint32_t push, VkDescriptorSetLayout *out_dsl)
{
    VkDescriptorSetLayoutBinding b = { .binding = 0, .descriptorType = sampler == 1 ? VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER : sampler == 3 ? VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER_DYNAMIC : VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER, .descriptorCount = 1, .stageFlags = VK_SHADER_STAGE_ALL_GRAPHICS };
    VkDescriptorSetLayoutCreateInfo li = { .sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO, .bindingCount = sampler ? 1 : 0, .pBindings = &b };
    VkDescriptorSetLayout dsl = 0;
    vkCreateDescriptorSetLayout(dev, &li, 0, &dsl);
    VkPushConstantRange pr = { VK_SHADER_STAGE_FRAGMENT_BIT, 0, push };
    VkPipelineLayoutCreateInfo pl = { .sType = VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO, .setLayoutCount = sampler ? 1 : 0, .pSetLayouts = &dsl, .pushConstantRangeCount = push ? 1 : 0, .pPushConstantRanges = &pr };
    VkPipelineLayout l = 0;
    vkCreatePipelineLayout(dev, &pl, 0, &l);
    *out_dsl = dsl;
    return l;
}

static VkDescriptorSet mkset(VkDescriptorSetLayout dsl, int sampler, VkImageView view, VkSampler smp, VkBuffer ubo, VkDeviceSize ubo_off, VkDeviceSize ubo_size)
{
    VkDescriptorPoolSize ps = { sampler == 1 ? VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER : sampler == 3 ? VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER_DYNAMIC : VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER, 1 };
    VkDescriptorPoolCreateInfo pi = { .sType = VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO, .maxSets = 1, .poolSizeCount = 1, .pPoolSizes = &ps };
    VkDescriptorPool pool = 0;
    vkCreateDescriptorPool(dev, &pi, 0, &pool);
    VkDescriptorSetAllocateInfo ai = { .sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO, .descriptorPool = pool, .descriptorSetCount = 1, .pSetLayouts = &dsl };
    VkDescriptorSet set = 0;
    vkAllocateDescriptorSets(dev, &ai, &set);
    VkDescriptorImageInfo ii = { smp, view, VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL };
    VkDescriptorBufferInfo bi = { ubo, ubo_off, ubo_size };
    VkWriteDescriptorSet w = { .sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET, .dstSet = set, .dstBinding = 0, .descriptorCount = 1,
        .descriptorType = sampler == 1 ? VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER : sampler == 3 ? VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER_DYNAMIC : VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER, .pImageInfo = &ii, .pBufferInfo = &bi };
    vkUpdateDescriptorSets(dev, 1, &w, 0, 0);
    return set;
}

typedef struct { Img color; Img depth; Img stencil; VkFormat fmt; } Target;
static Target mktarget(VkFormat fmt, int with_depth)
{
    Target t = {0};
    t.fmt = fmt;
    t.color = mkimg(fmt, W, H, VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT | VK_IMAGE_USAGE_TRANSFER_SRC_BIT, VK_IMAGE_ASPECT_COLOR_BIT);
    if (with_depth) t.depth = mkimg(VK_FORMAT_D32_SFLOAT, W, H, VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT, VK_IMAGE_ASPECT_DEPTH_BIT);
    if (g_sfmt) t.stencil = mkimg(g_sfmt, W, H, VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT, VK_IMAGE_ASPECT_STENCIL_BIT);
    return t;
}

static void begin_pass(Target *t, float r, float g, float b, float a)
{
    transition(t->color.i, VK_IMAGE_ASPECT_COLOR_BIT, g_keep ? VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL : VK_IMAGE_LAYOUT_UNDEFINED, VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL);
    VkRenderingAttachmentInfo ca = { .sType = VK_STRUCTURE_TYPE_RENDERING_ATTACHMENT_INFO, .imageView = t->color.v, .imageLayout = VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
        .loadOp = VK_ATTACHMENT_LOAD_OP_CLEAR, .storeOp = VK_ATTACHMENT_STORE_OP_STORE, .clearValue = { .color = { .float32 = { r, g, b, a } } } };
    VkRenderingAttachmentInfo da = { .sType = VK_STRUCTURE_TYPE_RENDERING_ATTACHMENT_INFO, .imageView = t->depth.v, .imageLayout = VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL,
        .loadOp = VK_ATTACHMENT_LOAD_OP_CLEAR, .storeOp = VK_ATTACHMENT_STORE_OP_STORE, .clearValue = { .depthStencil = { 1.0f, 0 } } };
    if (t->depth.i) transition(t->depth.i, VK_IMAGE_ASPECT_DEPTH_BIT, VK_IMAGE_LAYOUT_UNDEFINED, VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL);
    VkRenderingAttachmentInfo sa = da;
    sa.imageView = t->stencil.v;
    sa.clearValue.depthStencil.stencil = 0;
    if (t->stencil.i) transition(t->stencil.i, VK_IMAGE_ASPECT_STENCIL_BIT, VK_IMAGE_LAYOUT_UNDEFINED, VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL);
    VkRenderingInfo ri = { .sType = VK_STRUCTURE_TYPE_RENDERING_INFO, .renderArea = { { g_area[0], g_area[1] }, { (uint32_t)g_area[2], (uint32_t)g_area[3] } }, .layerCount = 1, .colorAttachmentCount = 1, .pColorAttachments = &ca, .pDepthAttachment = t->depth.i ? &da : 0, .pStencilAttachment = t->stencil.i ? &sa : 0 };
    vkCmdBeginRendering(cb, &ri);
}

static void set_vp(int x, int y, int w, int h, int sx, int sy, int sw, int sh)
{
    VkViewport v = { (float)x, (float)y, (float)w, (float)h, 0.0f, 1.0f };
    VkRect2D s = { { sx, sy }, { (uint32_t)sw, (uint32_t)sh } };
    vkCmdSetViewport(cb, 0, 1, &v);
    vkCmdSetScissor(cb, 0, 1, &s);
}

static void readback(Target *t, const char *name, Buf *rb, VkImageLayout from)
{
    transition(t->color.i, VK_IMAGE_ASPECT_COLOR_BIT, from, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL);
    VkBufferImageCopy c = { .imageSubresource = { VK_IMAGE_ASPECT_COLOR_BIT, 0, 0, 1 }, .imageExtent = { W, H, 1 } };
    vkCmdCopyImageToBuffer(cb, t->color.i, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, rb->b, 1, &c);
    char label[128];
    snprintf(label, sizeof label, "draw %s submits", name);
    check(label, submit_wait());
    char path[512];
    snprintf(path, sizeof path, "%s/%s.rgba", outdir, name);
    FILE *f = strcmp(outdir, "-") ? fopen(path, "wb") : 0;
    uint64_t hash = 1469598103934665603ull;
    for (int i = 0; i < W * H; i++) {
        uint8_t *p = rb->p + i * 4;
        uint8_t px[4] = { p[0], p[1], p[2], p[3] };
        if (t->fmt == VK_FORMAT_B8G8R8A8_UNORM) { px[0] = p[2]; px[2] = p[0]; }
        for (int k = 0; k < 4; k++) hash = (hash ^ px[k]) * 1099511628211ull;
        if (f) fwrite(px, 1, 4, f);
    }
    if (f) fclose(f);
    printf("VK img %s %016llx\n", name, (unsigned long long)hash);
}

static void finish(Target *t, const char *name, Buf *rb)
{
    vkCmdEndRendering(cb);
    readback(t, name, rb, VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL);
}

static const float tri_data[] = { -0.8f, -0.7f, 1, 0, 0, 1,   0.9f, -0.5f, 0, 1, 0, 1,   0.1f, 0.8f, 0, 0, 1, 1 };
static const float push_tint[4] = { 1.0f, 0.5f, 0.25f, 1.0f };

static void case_tri(const char *name, VkFormat fmt, int viewport_sub)
{
    Target t = mktarget(fmt, 0);
    VkDescriptorSetLayout dsl;
    VkPipelineLayout lay = mklayout(0, 0, &dsl);
    PipeDesc d = { "tri.vert", "tri.frag", fmt, VK_FORMAT_UNDEFINED, 0, 0, 2, 24, { VK_FORMAT_R32G32_SFLOAT, VK_FORMAT_R32G32B32A32_SFLOAT }, { 0, 8 }, lay };
    VkPipeline p = mkpipe(&d);
    char label[128];
    snprintf(label, sizeof label, "pipeline %s", name);
    check(label, p != 0);
    Buf vb = mkvec(tri_data, sizeof tri_data, VK_BUFFER_USAGE_VERTEX_BUFFER_BIT);
    Buf rb = mkbuf(W * H * 4, VK_BUFFER_USAGE_TRANSFER_DST_BIT);
    begin();
    begin_pass(&t, 0.1f, 0.2f, 0.3f, 1.0f);
    vkCmdBindPipeline(cb, VK_PIPELINE_BIND_POINT_GRAPHICS, p);
    if (viewport_sub) set_vp(8, 6, 40, 30, 0, 0, W, H); else set_vp(0, 0, W, H, 0, 0, W, H);
    VkDeviceSize off = 0;
    vkCmdBindVertexBuffers(cb, 0, 1, &vb.b, &off);
    vkCmdDraw(cb, 3, 1, 0, 0);
    finish(&t, name, &rb);
}

static void case_push(void)
{
    Target t = mktarget(VK_FORMAT_R8G8B8A8_UNORM, 0);
    VkDescriptorSetLayout dsl;
    VkPipelineLayout lay = mklayout(0, 16, &dsl);
    PipeDesc d = { "tri.vert", "push.frag", t.fmt, VK_FORMAT_UNDEFINED, 0, 0, 2, 24, { VK_FORMAT_R32G32_SFLOAT, VK_FORMAT_R32G32B32A32_SFLOAT }, { 0, 8 }, lay };
    VkPipeline p = mkpipe(&d);
    check("pipeline push", p != 0);
    Buf vb = mkvec(tri_data, sizeof tri_data, VK_BUFFER_USAGE_VERTEX_BUFFER_BIT);
    Buf rb = mkbuf(W * H * 4, VK_BUFFER_USAGE_TRANSFER_DST_BIT);
    begin();
    begin_pass(&t, 0.0f, 0.0f, 0.0f, 1.0f);
    vkCmdBindPipeline(cb, VK_PIPELINE_BIND_POINT_GRAPHICS, p);
    set_vp(0, 0, W, H, 0, 0, W, H);
    VkDeviceSize off = 0;
    vkCmdBindVertexBuffers(cb, 0, 1, &vb.b, &off);
    vkCmdPushConstants(cb, lay, VK_SHADER_STAGE_FRAGMENT_BIT, 0, 16, push_tint);
    vkCmdDraw(cb, 3, 1, 0, 0);
    finish(&t, "push", &rb);
}

static void case_quad(const char *name, VkFormat tfmt, int tw, int th, float uvs)
{
    Target t = mktarget(VK_FORMAT_R8G8B8A8_UNORM, 0);
    uint8_t texels[8 * 8 * 4];
    for (int y = 0; y < th; y++) for (int x = 0; x < tw; x++) {
        uint8_t *p = texels + (y * tw + x) * 4;
        p[0] = (uint8_t)(x * 36); p[1] = (uint8_t)(y * 36); p[2] = ((x ^ y) & 1) ? 220 : 40; p[3] = 255;
    }
    Img tex = mkimg(tfmt, tw, th, VK_IMAGE_USAGE_SAMPLED_BIT | VK_IMAGE_USAGE_TRANSFER_DST_BIT, VK_IMAGE_ASPECT_COLOR_BIT);
    Buf tb = mkvec(texels, sizeof texels, VK_BUFFER_USAGE_TRANSFER_SRC_BIT);
    VkSamplerCreateInfo sci = { .sType = VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO, .magFilter = VK_FILTER_NEAREST, .minFilter = VK_FILTER_NEAREST, .mipmapMode = VK_SAMPLER_MIPMAP_MODE_NEAREST,
        .addressModeU = VK_SAMPLER_ADDRESS_MODE_REPEAT, .addressModeV = VK_SAMPLER_ADDRESS_MODE_REPEAT, .addressModeW = VK_SAMPLER_ADDRESS_MODE_REPEAT, .maxLod = 0.0f };
    VkSampler smp = 0;
    vkCreateSampler(dev, &sci, 0, &smp);
    VkDescriptorSetLayout dsl;
    VkPipelineLayout lay = mklayout(1, 0, &dsl);
    VkDescriptorSet set = mkset(dsl, 1, tex.v, smp, 0, 0, 0);
    PipeDesc d = { "quad.vert", "quad.frag", t.fmt, VK_FORMAT_UNDEFINED, 0, 0, 2, 16, { VK_FORMAT_R32G32_SFLOAT, VK_FORMAT_R32G32_SFLOAT }, { 0, 8 }, lay };
    VkPipeline p = mkpipe(&d);
    { char lb[96]; snprintf(lb, sizeof lb, "pipeline %s", name); check(lb, p != 0); }
    const float quad[] = { -0.75f, -0.75f, 0, 0,   0.75f, -0.75f, uvs, 0,   0.75f, 0.75f, uvs, uvs,   -0.75f, 0.75f, 0, uvs };
    static const uint16_t idx[] = { 7, 7, 0, 1, 2, 0, 2, 3 };
    Buf vb = mkvec(quad, sizeof quad, VK_BUFFER_USAGE_VERTEX_BUFFER_BIT);
    Buf ib = mkvec(idx, sizeof idx, VK_BUFFER_USAGE_INDEX_BUFFER_BIT);
    Buf rb = mkbuf(W * H * 4, VK_BUFFER_USAGE_TRANSFER_DST_BIT);
    begin();
    transition(tex.i, VK_IMAGE_ASPECT_COLOR_BIT, VK_IMAGE_LAYOUT_UNDEFINED, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL);
    VkBufferImageCopy c = { .imageSubresource = { VK_IMAGE_ASPECT_COLOR_BIT, 0, 0, 1 }, .imageExtent = { (uint32_t)tw, (uint32_t)th, 1 } };
    vkCmdCopyBufferToImage(cb, tb.b, tex.i, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 1, &c);
    transition(tex.i, VK_IMAGE_ASPECT_COLOR_BIT, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL);
    begin_pass(&t, 0.0f, 0.0f, 0.0f, 1.0f);
    vkCmdBindPipeline(cb, VK_PIPELINE_BIND_POINT_GRAPHICS, p);
    set_vp(0, 0, W, H, 0, 0, W, H);
    vkCmdBindDescriptorSets(cb, VK_PIPELINE_BIND_POINT_GRAPHICS, lay, 0, 1, &set, 0, 0);
    VkDeviceSize off = 0;
    vkCmdBindVertexBuffers(cb, 0, 1, &vb.b, &off);
    vkCmdBindIndexBuffer(cb, ib.b, 4, VK_INDEX_TYPE_UINT16);
    vkCmdDrawIndexed(cb, 6, 1, 0, 0, 0);
    finish(&t, name, &rb);
}

static void case_depth(void)
{
    Target t = mktarget(VK_FORMAT_R8G8B8A8_UNORM, 1);
    VkDescriptorSetLayout dsl;
    VkPipelineLayout lay = mklayout(0, 0, &dsl);
    PipeDesc d = { "depth.vert", "tri.frag", t.fmt, VK_FORMAT_D32_SFLOAT, 0, 1, 2, 28, { VK_FORMAT_R32G32B32_SFLOAT, VK_FORMAT_R32G32B32A32_SFLOAT }, { 0, 12 }, lay };
    VkPipeline p = mkpipe(&d);
    check("pipeline depth", p != 0);
    static const float v[] = {
        -0.9f, -0.8f, 0.3f, 1, 0, 0, 1,   0.7f, -0.8f, 0.3f, 1, 0, 0, 1,   -0.1f, 0.8f, 0.3f, 1, 0, 0, 1,
        -0.7f, -0.8f, 0.7f, 0, 1, 0, 1,   0.9f, -0.8f, 0.7f, 0, 1, 0, 1,   0.1f, 0.8f, 0.7f, 0, 1, 0, 1 };
    Buf vb = mkvec(v, sizeof v, VK_BUFFER_USAGE_VERTEX_BUFFER_BIT);
    Buf rb = mkbuf(W * H * 4, VK_BUFFER_USAGE_TRANSFER_DST_BIT);
    begin();
    begin_pass(&t, 0.0f, 0.0f, 0.0f, 1.0f);
    vkCmdBindPipeline(cb, VK_PIPELINE_BIND_POINT_GRAPHICS, p);
    set_vp(0, 0, W, H, 0, 0, W, H);
    VkDeviceSize off = 0;
    vkCmdBindVertexBuffers(cb, 0, 1, &vb.b, &off);
    vkCmdDraw(cb, 6, 1, 0, 0);
    finish(&t, "depth", &rb);
}

static void case_inst(void)
{
    Target t = mktarget(VK_FORMAT_R8G8B8A8_UNORM, 0);
    VkDescriptorSetLayout dsl;
    VkPipelineLayout lay = mklayout(0, 0, &dsl);
    PipeDesc d = { "inst.vert", "inst.frag", t.fmt, VK_FORMAT_UNDEFINED, 0, 0, 1, 8, { VK_FORMAT_R32G32_SFLOAT, VK_FORMAT_R32G32_SFLOAT }, { 0, 0 }, lay };
    d.inst = 1;
    VkPipeline p = mkpipe(&d);
    check("pipeline inst", p != 0);
    static const float q[] = { -0.2f, -0.2f,  0.2f, -0.2f,  0.2f, 0.2f,  -0.2f, -0.2f,  0.2f, 0.2f,  -0.2f, 0.2f };
    static const float inst[] = { -0.7f, 0.5f, 1, 0, 0, 1,   -0.3f, -0.5f, 0, 1, 0, 1,   0.2f, 0.4f, 0, 0, 1, 1,   0.6f, -0.4f, 1, 1, 0, 1 };
    Buf vb = mkvec(q, sizeof q, VK_BUFFER_USAGE_VERTEX_BUFFER_BIT);
    Buf ib = mkvec(inst, sizeof inst, VK_BUFFER_USAGE_VERTEX_BUFFER_BIT);
    Buf rb = mkbuf(W * H * 4, VK_BUFFER_USAGE_TRANSFER_DST_BIT);
    begin();
    begin_pass(&t, 0.0f, 0.0f, 0.0f, 1.0f);
    vkCmdBindPipeline(cb, VK_PIPELINE_BIND_POINT_GRAPHICS, p);
    set_vp(0, 0, W, H, 0, 0, W, H);
    VkBuffer bufs[2] = { vb.b, ib.b };
    VkDeviceSize offs[2] = { 0, 0 };
    vkCmdBindVertexBuffers(cb, 0, 2, bufs, offs);
    vkCmdDraw(cb, 6, 3, 0, 1);
    finish(&t, "inst", &rb);
}

static void case_dubo(void)
{
    Target t = mktarget(VK_FORMAT_R8G8B8A8_UNORM, 0);
    VkDescriptorSetLayout dsl;
    VkPipelineLayout lay = mklayout(3, 16, &dsl);
    PipeDesc d = { "ubo.vert", "ubo.frag", t.fmt, VK_FORMAT_UNDEFINED, 0, 0, 2, 24, { VK_FORMAT_R32G32_SFLOAT, VK_FORMAT_R32G32B32A32_SFLOAT }, { 0, 8 }, lay };
    VkPipeline p = mkpipe(&d);
    check("pipeline dubo", p != 0);
    enum { STRIDE = 256 };
    Buf ubs = mkbuf(STRIDE * 3, VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT);
    memset(ubs.p, 0xA5, STRIDE * 3);
    static const float tints[3][4] = { { 1, 0.2f, 0.2f, 1 }, { 0.2f, 1, 0.2f, 1 }, { 0.3f, 0.3f, 1, 1 } };
    for (int i = 0; i < 3; i++) memcpy(ubs.p + i * STRIDE, tints[i], 16);
    VkDescriptorSet set = mkset(dsl, 3, 0, 0, ubs.b, 0, 16);
    float v[3][6 * 6];
    for (int i = 0; i < 3; i++) {
        float x0 = -0.9f + 0.6f * i, x1 = x0 + 0.5f, y0 = -0.5f + 0.2f * i, y1 = y0 + 0.9f;
        float q[6][2] = { { x0, y0 }, { x1, y0 }, { x1, y1 }, { x0, y0 }, { x1, y1 }, { x0, y1 } };
        for (int k = 0; k < 6; k++) { float *o = v[i] + k * 6; o[0] = q[k][0]; o[1] = q[k][1]; o[2] = o[3] = o[4] = o[5] = 1; }
    }
    Buf vb = mkvec(v, sizeof v, VK_BUFFER_USAGE_VERTEX_BUFFER_BIT);
    Buf rb = mkbuf(W * H * 4, VK_BUFFER_USAGE_TRANSFER_DST_BIT);
    static const float pushes[3][4] = { { 1, 1, 1, 1 }, { 0.5f, 1, 0.5f, 1 }, { 1, 0.5f, 1, 1 } };
    static const uint32_t order[3] = { 2, 0, 1 };
    begin();
    begin_pass(&t, 0.0f, 0.0f, 0.0f, 1.0f);
    vkCmdBindPipeline(cb, VK_PIPELINE_BIND_POINT_GRAPHICS, p);
    set_vp(0, 0, W, H, 0, 0, W, H);
    for (int i = 0; i < 3; i++) {
        uint32_t dyn = order[i] * STRIDE;
        vkCmdBindDescriptorSets(cb, VK_PIPELINE_BIND_POINT_GRAPHICS, lay, 0, 1, &set, 1, &dyn);
        vkCmdPushConstants(cb, lay, VK_SHADER_STAGE_FRAGMENT_BIT, 0, 16, pushes[i]);
        VkDeviceSize off = (VkDeviceSize)i * sizeof v[0];
        vkCmdBindVertexBuffers(cb, 0, 1, &vb.b, &off);
        vkCmdDraw(cb, 6, 1, 0, 0);
    }
    finish(&t, "dubo", &rb);
}

static void case_area(void)
{
    Target t = mktarget(VK_FORMAT_R8G8B8A8_UNORM, 0);
    VkDescriptorSetLayout dsl;
    VkPipelineLayout lay = mklayout(0, 0, &dsl);
    PipeDesc d = { "tri.vert", "tri.frag", t.fmt, VK_FORMAT_UNDEFINED, 0, 0, 2, 24, { VK_FORMAT_R32G32_SFLOAT, VK_FORMAT_R32G32B32A32_SFLOAT }, { 0, 8 }, lay };
    VkPipeline p = mkpipe(&d);
    check("pipeline area", p != 0);
    Buf vb = mkvec(tri_data, sizeof tri_data, VK_BUFFER_USAGE_VERTEX_BUFFER_BIT);
    Buf rb = mkbuf(W * H * 4, VK_BUFFER_USAGE_TRANSFER_DST_BIT);
    begin();
    begin_pass(&t, 0.8f, 0.1f, 0.1f, 1.0f);
    vkCmdEndRendering(cb);
    g_area[0] = 8; g_area[1] = 6; g_area[2] = 40; g_area[3] = 30;
    g_keep = 1;
    begin_pass(&t, 0.1f, 0.4f, 0.2f, 1.0f);
    g_keep = 0;
    vkCmdBindPipeline(cb, VK_PIPELINE_BIND_POINT_GRAPHICS, p);
    set_vp(8, 6, 40, 30, 8, 6, 40, 30);
    VkDeviceSize off = 0;
    vkCmdBindVertexBuffers(cb, 0, 1, &vb.b, &off);
    vkCmdDraw(cb, 3, 1, 0, 0);
    finish(&t, "area", &rb);
    g_area[0] = 0; g_area[1] = 0; g_area[2] = W; g_area[3] = H;
}

static void case_rpass(void)
{
    Target t = mktarget(VK_FORMAT_R8G8B8A8_UNORM, 0);
    VkAttachmentDescription ad = { .format = t.fmt, .samples = VK_SAMPLE_COUNT_1_BIT, .loadOp = VK_ATTACHMENT_LOAD_OP_CLEAR, .storeOp = VK_ATTACHMENT_STORE_OP_STORE,
        .stencilLoadOp = VK_ATTACHMENT_LOAD_OP_DONT_CARE, .stencilStoreOp = VK_ATTACHMENT_STORE_OP_DONT_CARE, .initialLayout = VK_IMAGE_LAYOUT_UNDEFINED, .finalLayout = VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL };
    VkAttachmentReference ar = { 0, VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL };
    VkSubpassDescription sp = { .pipelineBindPoint = VK_PIPELINE_BIND_POINT_GRAPHICS, .colorAttachmentCount = 1, .pColorAttachments = &ar };
    VkRenderPassCreateInfo rpi = { .sType = VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO, .attachmentCount = 1, .pAttachments = &ad, .subpassCount = 1, .pSubpasses = &sp };
    VkRenderPass rp = 0;
    check("vkCreateRenderPass", vkCreateRenderPass(dev, &rpi, 0, &rp) == VK_SUCCESS && rp);
    VkFramebufferCreateInfo fi = { .sType = VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO, .renderPass = rp, .attachmentCount = 1, .pAttachments = &t.color.v, .width = W, .height = H, .layers = 1 };
    VkFramebuffer fb = 0;
    check("vkCreateFramebuffer", vkCreateFramebuffer(dev, &fi, 0, &fb) == VK_SUCCESS && fb);
    VkDescriptorSetLayout dsl;
    VkPipelineLayout lay = mklayout(0, 0, &dsl);
    PipeDesc d = { "tri.vert", "tri.frag", t.fmt, VK_FORMAT_UNDEFINED, 0, 0, 2, 24, { VK_FORMAT_R32G32_SFLOAT, VK_FORMAT_R32G32B32A32_SFLOAT }, { 0, 8 }, lay };
    g_rp = rp;
    VkPipeline p = mkpipe(&d);
    g_rp = 0;
    check("pipeline rpass", p != 0);
    Buf vb = mkvec(tri_data, sizeof tri_data, VK_BUFFER_USAGE_VERTEX_BUFFER_BIT);
    Buf rb = mkbuf(W * H * 4, VK_BUFFER_USAGE_TRANSFER_DST_BIT);
    begin();
    VkClearValue cv = { .color = { .float32 = { 0.2f, 0.4f, 0.6f, 1.0f } } };
    VkRenderPassBeginInfo bi = { .sType = VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO, .renderPass = rp, .framebuffer = fb, .renderArea = { { 0, 0 }, { W, H } }, .clearValueCount = 1, .pClearValues = &cv };
    vkCmdBeginRenderPass(cb, &bi, VK_SUBPASS_CONTENTS_INLINE);
    VkClearAttachment ca = { .aspectMask = VK_IMAGE_ASPECT_COLOR_BIT, .colorAttachment = 0, .clearValue = { .color = { .float32 = { 0.9f, 0.1f, 0.1f, 1.0f } } } };
    VkClearRect cr = { .rect = { { 4, 3 }, { 20, 14 } }, .baseArrayLayer = 0, .layerCount = 1 };
    vkCmdClearAttachments(cb, 1, &ca, 1, &cr);
    vkCmdBindPipeline(cb, VK_PIPELINE_BIND_POINT_GRAPHICS, p);
    set_vp(0, 0, W, H, 0, 0, W, H);
    VkDeviceSize off = 0;
    vkCmdBindVertexBuffers(cb, 0, 1, &vb.b, &off);
    vkCmdDraw(cb, 3, 1, 0, 0);
    vkCmdEndRenderPass(cb);
    Target t2 = t;
    t2.color = mkimg(t.fmt, W, H, VK_IMAGE_USAGE_TRANSFER_DST_BIT | VK_IMAGE_USAGE_TRANSFER_SRC_BIT, VK_IMAGE_ASPECT_COLOR_BIT);
    transition(t.color.i, VK_IMAGE_ASPECT_COLOR_BIT, VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL);
    transition(t2.color.i, VK_IMAGE_ASPECT_COLOR_BIT, VK_IMAGE_LAYOUT_UNDEFINED, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL);
    VkImageBlit br = { .srcSubresource = { VK_IMAGE_ASPECT_COLOR_BIT, 0, 0, 1 }, .srcOffsets = { { 0, 0, 0 }, { W, H, 1 } },
        .dstSubresource = { VK_IMAGE_ASPECT_COLOR_BIT, 0, 0, 1 }, .dstOffsets = { { W, 0, 0 }, { 0, H, 1 } } };
    vkCmdBlitImage(cb, t.color.i, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, t2.color.i, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 1, &br, VK_FILTER_NEAREST);
    readback(&t2, "blit", &rb, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL);
    Buf rb2 = mkbuf(W * H * 4, VK_BUFFER_USAGE_TRANSFER_DST_BIT);
    begin();
    readback(&t, "rpass", &rb2, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL);
}

typedef struct { float clipr[4], box[4], c1[4], grad[4], size[4]; } FuiU;
typedef struct { float x, y, r, g, b, a; } FuiV;

static void quad3(float *v, float x0, float y0, float x1, float y1, float z, float r, float g, float b)
{
    float q[6][2] = { { x0, y0 }, { x1, y0 }, { x1, y1 }, { x0, y0 }, { x1, y1 }, { x0, y1 } };
    for (int i = 0; i < 6; i++) { float *p = v + i * 7; p[0] = q[i][0]; p[1] = q[i][1]; p[2] = z; p[3] = r; p[4] = g; p[5] = b; p[6] = 1; }
}
static const VkFormat F3[2] = { VK_FORMAT_R32G32B32_SFLOAT, VK_FORMAT_R32G32B32A32_SFLOAT };
static void scene3(const char *name, int kind)
{
    Target t = mktarget(VK_FORMAT_R8G8B8A8_UNORM, kind == 1 || kind == 2);
    VkDescriptorSetLayout dsl;
    VkPipelineLayout lay = mklayout(0, 0, &dsl);
    float v[8][42];
    PipeDesc d[4];
    int nd = 0, ndraw = 0;
    for (int i = 0; i < 4; i++) { PipeDesc e = { "depth.vert", "tri.frag", t.fmt, (kind == 1 || kind == 2) ? VK_FORMAT_D32_SFLOAT : VK_FORMAT_UNDEFINED, 0, kind == 1 || kind == 2, 2, 28, { F3[0], F3[1] }, { 0, 12 }, lay }; d[i] = e; }
    if (kind == 0 || kind == 5) {
        d[0].cull = kind == 0 ? VK_CULL_MODE_BACK_BIT : VK_CULL_MODE_FRONT_BIT; d[0].cw = kind == 5; nd = 1;
        quad3(v[0], -0.9f, -0.8f, -0.1f, 0.8f, 0.5f, 1, 0, 0); quad3(v[1], 0.1f, -0.8f, 0.9f, 0.8f, 0.5f, 0, 1, 0);
        float tmp[7]; for (int k = 0; k < 7; k++) { tmp[k] = v[1][7 + k]; v[1][7 + k] = v[1][14 + k]; v[1][14 + k] = tmp[k]; }
        ndraw = 2;
    }
    if (kind == 1) {
        d[1].dopx = 1 + VK_COMPARE_OP_EQUAL; d[1].nowrite = 1; d[2].dopx = 1 + VK_COMPARE_OP_GREATER; d[2].nowrite = 1; nd = 3;
        quad3(v[0], -0.9f, -0.6f, 0.0f, 0.6f, 0.5f, 1, 0, 0); quad3(v[1], -0.5f, -0.9f, 0.5f, 0.9f, 0.5f, 0, 1, 0); quad3(v[2], -0.2f, -0.7f, 0.9f, 0.7f, 0.8f, 0, 0, 1);
        ndraw = 3;
    }
    if (kind == 2) {
        d[0].nowrite = 1; nd = 2;
        quad3(v[0], -0.9f, -0.6f, 0.2f, 0.6f, 0.6f, 1, 1, 0); quad3(v[1], -0.2f, -0.8f, 0.9f, 0.8f, 0.8f, 0, 1, 1);
        ndraw = 2;
    }
    if (kind == 3) {
        d[0].stencil = 1; d[0].sf = (VkStencilOpState){ VK_STENCIL_OP_KEEP, VK_STENCIL_OP_REPLACE, VK_STENCIL_OP_KEEP, VK_COMPARE_OP_ALWAYS, 255, 255, 1 };
        d[1].stencil = 1; d[1].sf = (VkStencilOpState){ VK_STENCIL_OP_KEEP, VK_STENCIL_OP_INCREMENT_AND_CLAMP, VK_STENCIL_OP_KEEP, VK_COMPARE_OP_ALWAYS, 255, 255, 1 };
        d[2].stencil = 1; d[2].sf = (VkStencilOpState){ VK_STENCIL_OP_KEEP, VK_STENCIL_OP_KEEP, VK_STENCIL_OP_KEEP, VK_COMPARE_OP_EQUAL, 255, 255, 2 };
        d[3].stencil = 1; d[3].sf = (VkStencilOpState){ VK_STENCIL_OP_KEEP, VK_STENCIL_OP_KEEP, VK_STENCIL_OP_KEEP, VK_COMPARE_OP_EQUAL, 255, 255, 1 };
        nd = 4; for (int i = 0; i < 4; i++) d[i].depth_test = 0;
        quad3(v[0], -0.9f, -0.7f, 0.1f, 0.7f, 0.5f, 1, 0, 0); quad3(v[1], -0.2f, -0.5f, 0.8f, 0.5f, 0.5f, 1, 1, 0);
        quad3(v[2], -1, -1, 1, 1, 0.5f, 0, 0, 1); quad3(v[3], -1, -1, 1, 1, 0.5f, 0, 1, 0);
        ndraw = 4;
    }
    VkPipeline p[4];
    for (int i = 0; i < nd; i++) p[i] = mkpipe(&d[i]);
    char label[128];
    snprintf(label, sizeof label, "pipelines %s", name);
    check(label, p[0] != 0);
    Buf vb = mkvec(v, sizeof v, VK_BUFFER_USAGE_VERTEX_BUFFER_BIT);
    Buf rb = mkbuf(W * H * 4, VK_BUFFER_USAGE_TRANSFER_DST_BIT);
    begin();
    begin_pass(&t, 0.0f, 0.0f, 0.0f, 1.0f);
    set_vp(0, 0, W, H, 0, 0, W, H);
    for (int k = 0; k < ndraw; k++) {
        VkPipeline use = (kind == 0 || kind == 5) ? p[0] : p[k];
        vkCmdBindPipeline(cb, VK_PIPELINE_BIND_POINT_GRAPHICS, use);
        VkDeviceSize off = (VkDeviceSize)k * sizeof v[0];
        vkCmdBindVertexBuffers(cb, 0, 1, &vb.b, &off);
        vkCmdDraw(cb, 6, 1, 0, 0);
    }
    finish(&t, name, &rb);
}

typedef struct { VkPipelineLayout lay; VkPipeline pipe; VkDescriptorSet sets[3]; Buf vb[3]; } FuiScene;

static FuiScene fui_prepare(VkFormat fmt)
{
    FuiScene sc = {0};
    VkDescriptorSetLayout dsl;
    sc.lay = mklayout(2, 0, &dsl);
    PipeDesc d = { "fui_rect.vert", "fui_rect.frag", fmt, VK_FORMAT_UNDEFINED, 1, 0, 2, 24, { VK_FORMAT_R32G32_SFLOAT, VK_FORMAT_R32G32B32A32_SFLOAT }, { 0, 8 }, sc.lay };
    sc.pipe = mkpipe(&d);
    check("pipeline fui", sc.pipe != 0);
    struct { float box[4], clip[4], col[4], c1[3], grad[3]; } q[3] = {
        { { 0, 0, 64, 48 }, { 0, 0, 4096, 4096 }, { 30, 34, 48, 255 }, { 0, 0, 0 }, { 0, 0, 0 } },
        { { 5, 4, 58, 30 }, { 0, 0, 4096, 4096 }, { 80, 120, 200, 255 }, { 20, 40, 90 }, { 4, 30, 1 } },
        { { 12.5f, 10.25f, 50.75f, 40.5f }, { 0, 0, 4096, 4096 }, { 255, 200, 0, 160 }, { 0, 0, 0 }, { 0, 0, 0 } } };
    enum { UB_STRIDE = 256 };
    Buf ubs = mkbuf(UB_STRIDE * 3, VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT);
    memset(ubs.p, 0xA5, UB_STRIDE * 3);
    for (int i = 0; i < 3; i++) {
        FuiU u = { { q[i].clip[0], q[i].clip[1], q[i].clip[2], q[i].clip[3] }, { q[i].box[0], q[i].box[1], q[i].box[2], q[i].box[3] },
            { q[i].c1[0], q[i].c1[1], q[i].c1[2], 255 }, { q[i].grad[0], q[i].grad[1], q[i].grad[2], 0 }, { W, H, 0, 0 } };
        memcpy(ubs.p + (2 - i) * UB_STRIDE, &u, sizeof u);
        float x0 = q[i].box[0], y0 = q[i].box[1], x1 = q[i].box[2], y1 = q[i].box[3];
        x0 = (float)(int)x0; y0 = (float)(int)y0; x1 = (float)((int)x1 + (x1 > (int)x1)); y1 = (float)((int)y1 + (y1 > (int)y1));
        FuiV v[6] = { { x0, y0 }, { x1, y0 }, { x1, y1 }, { x0, y0 }, { x1, y1 }, { x0, y1 } };
        for (int k = 0; k < 6; k++) { v[k].r = q[i].col[0]; v[k].g = q[i].col[1]; v[k].b = q[i].col[2]; v[k].a = q[i].col[3]; }
        sc.vb[i] = mkvec(v, sizeof v, VK_BUFFER_USAGE_VERTEX_BUFFER_BIT);
        sc.sets[i] = mkset(dsl, 2, 0, 0, ubs.b, (2 - i) * UB_STRIDE, sizeof(FuiU));
    }
    return sc;
}

static void fui_record(FuiScene *sc, Target *t)
{
    begin();
    begin_pass(t, 0.0f, 0.0f, 0.0f, 1.0f);
    vkCmdBindPipeline(cb, VK_PIPELINE_BIND_POINT_GRAPHICS, sc->pipe);
    set_vp(0, 0, W, H, 0, 0, W, H);
    for (int i = 0; i < 3; i++) {
        if (i == 2) set_vp(0, 0, W, H, 16, 12, 24, 16);
        VkDeviceSize off = 0;
        vkCmdBindDescriptorSets(cb, VK_PIPELINE_BIND_POINT_GRAPHICS, sc->lay, 0, 1, &sc->sets[i], 0, 0);
        vkCmdBindVertexBuffers(cb, 0, 1, &sc->vb[i].b, &off);
        vkCmdDraw(cb, 6, 1, 0, 0);
    }
}

static void case_fui(void)
{
    Target t = mktarget(VK_FORMAT_R8G8B8A8_UNORM, 0);
    FuiScene sc = fui_prepare(t.fmt);
    Buf rb = mkbuf(W * H * 4, VK_BUFFER_USAGE_TRANSFER_DST_BIT);
    fui_record(&sc, &t);
    finish(&t, "fui", &rb);
}


static double now_ms(void)
{
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec * 1000.0 + ts.tv_nsec / 1e6;
}

static uint64_t fnv(const uint8_t *p, size_t n)
{
    uint64_t h = 1469598103934665603ull;
    for (size_t i = 0; i < n; i++) h = (h ^ p[i]) * 1099511628211ull;
    return h;
}

static uint8_t *sink_map(size_t n, uint8_t **view2)
{
    long fd = syscall(SYS_memfd_create, "vksink", 0);
    *view2 = 0;
    if (fd >= 0 && ftruncate((int)fd, (off_t)n) == 0) {
        uint8_t *a = mmap(0, n, PROT_READ | PROT_WRITE, MAP_SHARED, (int)fd, 0);
        uint8_t *b = mmap(0, n, PROT_READ, MAP_SHARED, (int)fd, 0);
        if (a != MAP_FAILED && b != MAP_FAILED) { *view2 = b; return a; }
    }
    uint8_t *m = calloc(1, n);
    *view2 = m;
    return m;
}

#define WSI_FRAMES 60

static void case_wsi(void)
{
    PFN_vkCreateHeadlessSurfaceEXT mksurf = (PFN_vkCreateHeadlessSurfaceEXT)g_gipa(g_inst, "vkCreateHeadlessSurfaceEXT");
    PFN_vkGetPhysicalDeviceSurfaceSupportKHR getsup = (PFN_vkGetPhysicalDeviceSurfaceSupportKHR)g_gipa(g_inst, "vkGetPhysicalDeviceSurfaceSupportKHR");
    PFN_vkGetPhysicalDeviceSurfaceCapabilitiesKHR getcaps = (PFN_vkGetPhysicalDeviceSurfaceCapabilitiesKHR)g_gipa(g_inst, "vkGetPhysicalDeviceSurfaceCapabilitiesKHR");
    PFN_vkGetPhysicalDeviceSurfaceFormatsKHR getfmts = (PFN_vkGetPhysicalDeviceSurfaceFormatsKHR)g_gipa(g_inst, "vkGetPhysicalDeviceSurfaceFormatsKHR");
    PFN_vkGetPhysicalDeviceSurfacePresentModesKHR getmodes = (PFN_vkGetPhysicalDeviceSurfacePresentModesKHR)g_gipa(g_inst, "vkGetPhysicalDeviceSurfacePresentModesKHR");
    PFN_vkDestroySurfaceKHR killsurf = (PFN_vkDestroySurfaceKHR)g_gipa(g_inst, "vkDestroySurfaceKHR");
    PFN_vkCreateSwapchainKHR mksc = (PFN_vkCreateSwapchainKHR)g_gdpa(dev, "vkCreateSwapchainKHR");
    PFN_vkDestroySwapchainKHR killsc = (PFN_vkDestroySwapchainKHR)g_gdpa(dev, "vkDestroySwapchainKHR");
    PFN_vkGetSwapchainImagesKHR getimgs = (PFN_vkGetSwapchainImagesKHR)g_gdpa(dev, "vkGetSwapchainImagesKHR");
    PFN_vkAcquireNextImageKHR acquire = (PFN_vkAcquireNextImageKHR)g_gdpa(dev, "vkAcquireNextImageKHR");
    PFN_vkQueuePresentKHR present = (PFN_vkQueuePresentKHR)g_gdpa(dev, "vkQueuePresentKHR");
    check("wsi entry points", mksurf && getsup && getcaps && getfmts && getmodes && killsurf && mksc && killsc && getimgs && acquire && present);
    if (!(mksurf && mksc && present)) return;
    VkHeadlessSurfaceCreateInfoEXT hi = { .sType = VK_STRUCTURE_TYPE_HEADLESS_SURFACE_CREATE_INFO_EXT };
    VkSurfaceKHR surf = 0;
    check("vkCreateHeadlessSurfaceEXT", mksurf(g_inst, &hi, 0, &surf) == VK_SUCCESS && surf);
    VkBool32 sup = 0;
    check("surface supports queue family 0", getsup(g_pd, 0, surf, &sup) == VK_SUCCESS && sup);
    VkSurfaceCapabilitiesKHR caps;
    check("surface capabilities", getcaps(g_pd, surf, &caps) == VK_SUCCESS && caps.minImageCount >= 1 && (caps.supportedUsageFlags & VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT) && (caps.supportedUsageFlags & VK_IMAGE_USAGE_TRANSFER_SRC_BIT));
    uint32_t nf = 0, nm = 0;
    getfmts(g_pd, surf, &nf, 0);
    VkSurfaceFormatKHR fm[16];
    if (nf > 16) nf = 16;
    getfmts(g_pd, surf, &nf, fm);
    int has_bgra = 0;
    for (uint32_t i = 0; i < nf; i++) if (fm[i].format == VK_FORMAT_B8G8R8A8_UNORM) has_bgra = 1;
    check("surface offers B8G8R8A8_UNORM", has_bgra);
    getmodes(g_pd, surf, &nm, 0);
    VkPresentModeKHR pm[8];
    if (nm > 8) nm = 8;
    getmodes(g_pd, surf, &nm, pm);
    int has_fifo = 0;
    for (uint32_t i = 0; i < nm; i++) if (pm[i] == VK_PRESENT_MODE_FIFO_KHR) has_fifo = 1;
    check("surface offers FIFO", has_fifo);
    VkSwapchainCreateInfoKHR sci = { .sType = VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR, .surface = surf, .minImageCount = 3, .imageFormat = VK_FORMAT_B8G8R8A8_UNORM,
        .imageColorSpace = VK_COLOR_SPACE_SRGB_NONLINEAR_KHR, .imageExtent = { W, H }, .imageArrayLayers = 1, .imageUsage = VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT | VK_IMAGE_USAGE_TRANSFER_SRC_BIT,
        .imageSharingMode = VK_SHARING_MODE_EXCLUSIVE, .preTransform = VK_SURFACE_TRANSFORM_IDENTITY_BIT_KHR, .compositeAlpha = VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR,
        .presentMode = VK_PRESENT_MODE_FIFO_KHR, .clipped = VK_TRUE };
    VkSwapchainKHR sc = 0;
    check("vkCreateSwapchainKHR", mksc(dev, &sci, 0, &sc) == VK_SUCCESS && sc);
    uint32_t ni = 0;
    getimgs(dev, sc, &ni, 0);
    VkImage imgs[16];
    if (ni > 16) ni = 16;
    getimgs(dev, sc, &ni, imgs);
    check("swapchain has >= 3 images", ni >= 3);
    if (ni < 3) return;
    Target tg[16];
    for (uint32_t i = 0; i < ni; i++) {
        memset(&tg[i], 0, sizeof tg[i]);
        tg[i].fmt = VK_FORMAT_B8G8R8A8_UNORM;
        tg[i].color.i = imgs[i];
        VkImageViewCreateInfo vi = { .sType = VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO, .image = imgs[i], .viewType = VK_IMAGE_VIEW_TYPE_2D, .format = tg[i].fmt, .subresourceRange = { VK_IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1 } };
        vkCreateImageView(dev, &vi, 0, &tg[i].color.v);
    }
    FuiScene scn = fui_prepare(VK_FORMAT_B8G8R8A8_UNORM);
    Buf rb = mkbuf(W * H * 4, VK_BUFFER_USAGE_TRANSFER_DST_BIT);
    PFN_vkOsumSetSurfaceSinkOSUM setsink = (PFN_vkOsumSetSurfaceSinkOSUM)g_gipa(g_inst, "vkOsumSetSurfaceSinkOSUM");
    PFN_vkOsumGetPresentCountOSUM getcount = (PFN_vkOsumGetPresentCountOSUM)g_gipa(g_inst, "vkOsumGetPresentCountOSUM");
    enum { SINK_STRIDE = W * 4 + 16 };
    uint8_t *sink_w = 0, *sink_r = 0;
    if (setsink) {
        sink_w = sink_map(SINK_STRIDE * H, &sink_r);
        check("sink registered", setsink(surf, sink_w, SINK_STRIDE) == VK_SUCCESS);
    }
    const char *names[3] = { "wsi", "wsi1", "wsi2" };
    unsigned seen = 0;
    for (int f = 0; f < 3; f++) {
        uint32_t idx = 99;
        VkResult ar = acquire(dev, sc, 1000000000ull, 0, 0, &idx);
        check("vkAcquireNextImageKHR", ar == VK_SUCCESS && idx < ni);
        if (idx >= ni) return;
        seen |= 1u << idx;
        if (sink_w) memset(sink_w, 0xEE, SINK_STRIDE * H);
        fui_record(&scn, &tg[idx]);
        finish(&tg[idx], names[f], &rb);
        begin();
        transition(imgs[idx], VK_IMAGE_ASPECT_COLOR_BIT, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, VK_IMAGE_LAYOUT_PRESENT_SRC_KHR);
        check("present layout transition", submit_wait());
        VkPresentInfoKHR pi = { .sType = VK_STRUCTURE_TYPE_PRESENT_INFO_KHR, .swapchainCount = 1, .pSwapchains = &sc, .pImageIndices = &idx };
        check("vkQueuePresentKHR", present(queue, &pi) == VK_SUCCESS);
        if (sink_w) {
            int same = 1, pad = 1;
            uint8_t flat[W * H * 4];
            for (int y = 0; y < H; y++) {
                if (memcmp(sink_r + y * SINK_STRIDE, rb.p + y * W * 4, W * 4)) same = 0;
                for (int k = W * 4; k < SINK_STRIDE; k++) if (sink_r[y * SINK_STRIDE + k] != 0xEE) pad = 0;
                memcpy(flat + y * W * 4, sink_r + y * SINK_STRIDE, W * 4);
            }
            check("sink rows == swapchain readback", same);
            check("sink padding untouched", pad);
            printf("VK sink %s %016llx\n", names[f], (unsigned long long)fnv(flat, sizeof flat));
        }
    }
    check("acquire cycles 3 distinct images", __builtin_popcount(seen) == 3);
    if (getcount) check("present counter == 3", getcount(surf) == 3);
    double t0 = now_ms();
    for (int f = 0; f < WSI_FRAMES; f++) {
        uint32_t idx = 0;
        acquire(dev, sc, 1000000000ull, 0, 0, &idx);
        fui_record(&scn, &tg[idx]);
        vkCmdEndRendering(cb);
        transition(imgs[idx], VK_IMAGE_ASPECT_COLOR_BIT, VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL, VK_IMAGE_LAYOUT_PRESENT_SRC_KHR);
        submit_wait();
        VkPresentInfoKHR pi = { .sType = VK_STRUCTURE_TYPE_PRESENT_INFO_KHR, .swapchainCount = 1, .pSwapchains = &sc, .pImageIndices = &idx };
        present(queue, &pi);
    }
    printf("VK time wsi_frame_ms %.3f\n", (now_ms() - t0) / WSI_FRAMES);
    killsc(dev, sc, 0);
    killsurf(g_inst, surf, 0);
}

int main(int argc, char **argv)
{
    const char *path = argc > 1 ? argv[1] : "./libvulkan.so.1";
    int mode = argc > 2 ? atoi(argv[2]) : 0;
    if (argc > 3) outdir = argv[3];
    if (argc > 4) spvdir = argv[4];
    void *h = dlopen(path, RTLD_NOW | RTLD_LOCAL);
    check("dlopen", h != 0);
    if (!h) { printf("VK DONE bad=%d\n", bad); return 1; }
    PFN_vkGetInstanceProcAddr gipa = (PFN_vkGetInstanceProcAddr)dlsym(h, "vkGetInstanceProcAddr");
    PFN_vkCreateInstance ci = (PFN_vkCreateInstance)gipa(0, "vkCreateInstance");
    VkApplicationInfo app = { .sType = VK_STRUCTURE_TYPE_APPLICATION_INFO, .apiVersion = VK_API_VERSION_1_3 };
    const char *iexts[2] = { "VK_KHR_surface", "VK_EXT_headless_surface" };
    VkInstanceCreateInfo ici = { .sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO, .pApplicationInfo = &app, .enabledExtensionCount = 2, .ppEnabledExtensionNames = iexts };
    VkInstance inst = 0;
    g_wsi = ci(&ici, 0, &inst) == VK_SUCCESS && inst;
    if (!g_wsi) {
        ici.enabledExtensionCount = 0;
        inst = 0;
        printf("VK note no headless surface support, wsi scene skipped\n");
    }
    check("vkCreateInstance", (g_wsi || ci(&ici, 0, &inst) == VK_SUCCESS) && inst);
    PFN_vkEnumeratePhysicalDevices enumpd = (PFN_vkEnumeratePhysicalDevices)gipa(inst, "vkEnumeratePhysicalDevices");
    PFN_vkGetPhysicalDeviceProperties getprops = (PFN_vkGetPhysicalDeviceProperties)gipa(inst, "vkGetPhysicalDeviceProperties");
    PFN_vkGetPhysicalDeviceMemoryProperties getmp = (PFN_vkGetPhysicalDeviceMemoryProperties)gipa(inst, "vkGetPhysicalDeviceMemoryProperties");
    PFN_vkCreateDevice createdev = (PFN_vkCreateDevice)gipa(inst, "vkCreateDevice");
    PFN_vkGetDeviceProcAddr gdpa = (PFN_vkGetDeviceProcAddr)gipa(inst, "vkGetDeviceProcAddr");
    uint32_t n = 8;
    VkPhysicalDevice pds[8];
    enumpd(inst, &n, pds);
    VkPhysicalDevice pd = pds[0];
    g_gipa = gipa;
    g_gdpa = gdpa;
    g_inst = inst;
    if (mode == 1) for (uint32_t i = 0; i < n; i++) { VkPhysicalDeviceProperties p; getprops(pds[i], &p); if (p.deviceType == VK_PHYSICAL_DEVICE_TYPE_CPU) pd = pds[i]; }
    g_pd = pd;
    getmp(pd, &mp);
    float prio = 1.0f;
    VkDeviceQueueCreateInfo dq = { .sType = VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO, .queueFamilyIndex = 0, .queueCount = 1, .pQueuePriorities = &prio };
    VkPhysicalDeviceVulkan13Features f13 = { .sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_3_FEATURES, .dynamicRendering = VK_TRUE };
    const char *dexts[1] = { "VK_KHR_swapchain" };
    VkDeviceCreateInfo dci = { .sType = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO, .pNext = &f13, .queueCreateInfoCount = 1, .pQueueCreateInfos = &dq, .enabledExtensionCount = g_wsi ? 1 : 0, .ppEnabledExtensionNames = dexts };
    check("vkCreateDevice", createdev(pd, &dci, 0, &dev) == VK_SUCCESS && dev);
#define LOADFN(n) n = (PFN_##n)gdpa(dev, #n); if (!n) { printf("VK FAIL missing " #n "\n"); bad++; }
    FNS(LOADFN)
    if (bad) { printf("VK DONE bad=%d\n", bad); return 1; }
    vkGetDeviceQueue(dev, 0, 0, &queue);
    VkCommandPoolCreateInfo pci = { .sType = VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO, .flags = VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT, .queueFamilyIndex = 0 };
    VkCommandPool pool;
    vkCreateCommandPool(dev, &pci, 0, &pool);
    VkCommandBufferAllocateInfo cai = { .sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO, .commandPool = pool, .level = VK_COMMAND_BUFFER_LEVEL_PRIMARY, .commandBufferCount = 1 };
    vkAllocateCommandBuffers(dev, &cai, &cb);
    VkFenceCreateInfo fci = { .sType = VK_STRUCTURE_TYPE_FENCE_CREATE_INFO };
    vkCreateFence(dev, &fci, 0, &fence);
    case_tri("tri", VK_FORMAT_R8G8B8A8_UNORM, 0);
    case_tri("tri_bgra", VK_FORMAT_B8G8R8A8_UNORM, 0);
    case_tri("tri_view", VK_FORMAT_R8G8B8A8_UNORM, 1);
    case_push();
    case_quad("quad", VK_FORMAT_R8G8B8A8_UNORM, 8, 8, 1.0f);
    case_quad("quad_bgra", VK_FORMAT_B8G8R8A8_UNORM, 8, 8, 1.0f);
    case_quad("quad_npot", VK_FORMAT_R8G8B8A8_UNORM, 5, 7, 2.0f);
    case_inst();
    case_dubo();
    case_area();
    case_rpass();
    case_depth();
    case_fui();
    if (g_wsi) case_wsi();
    scene3("cull", 0);
    scene3("cullfront", 5);
    scene3("dops", 1);
    scene3("dnowrite", 2);
    g_sfmt = VK_FORMAT_S8_UINT;
    scene3("stencil", 3);
    g_sfmt = VK_FORMAT_UNDEFINED;
    printf("VK DONE bad=%d\n", bad);
    return bad ? 1 : 0;
}
