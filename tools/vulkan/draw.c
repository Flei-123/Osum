#define VK_NO_PROTOTYPES
#include <vulkan/vulkan.h>
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>

#define FNS(X) X(vkDestroyDevice) X(vkGetDeviceQueue) X(vkAllocateMemory) X(vkMapMemory) X(vkCreateBuffer) X(vkGetBufferMemoryRequirements) X(vkBindBufferMemory) \
    X(vkCreateImage) X(vkGetImageMemoryRequirements) X(vkBindImageMemory) X(vkCreateCommandPool) X(vkAllocateCommandBuffers) X(vkBeginCommandBuffer) X(vkEndCommandBuffer) \
    X(vkCmdCopyBuffer) X(vkCmdCopyImageToBuffer) X(vkCmdCopyBufferToImage) X(vkCmdPipelineBarrier) X(vkCreateFence) X(vkQueueSubmit) X(vkWaitForFences) X(vkResetFences) \
    X(vkResetCommandBuffer) X(vkCreateShaderModule) X(vkCreateGraphicsPipelines) X(vkCreatePipelineLayout) X(vkCreateDescriptorSetLayout) X(vkCreateDescriptorPool) \
    X(vkAllocateDescriptorSets) X(vkUpdateDescriptorSets) X(vkCreateImageView) X(vkCreateSampler) X(vkCmdBeginRendering) X(vkCmdEndRendering) X(vkCmdBindPipeline) \
    X(vkCmdBindVertexBuffers) X(vkCmdBindIndexBuffer) X(vkCmdBindDescriptorSets) X(vkCmdPushConstants) X(vkCmdSetViewport) X(vkCmdSetScissor) X(vkCmdDraw) X(vkCmdDrawIndexed)
#define DECL(n) static PFN_##n n;
FNS(DECL)

static VkDevice dev;
static VkQueue queue;
static VkCommandBuffer cb;
static VkFence fence;
static VkPhysicalDeviceMemoryProperties mp;
static int bad;
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

typedef struct { const char *vs, *fs; VkFormat color, depth; int blend, depth_test, nattr, stride; VkFormat afmt[2]; uint32_t aoff[2]; VkPipelineLayout layout; } PipeDesc;
static VkPipeline mkpipe(const PipeDesc *d)
{
    VkPipelineShaderStageCreateInfo st[2] = {
        { .sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO, .stage = VK_SHADER_STAGE_VERTEX_BIT, .module = load_shader(d->vs), .pName = "main" },
        { .sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO, .stage = VK_SHADER_STAGE_FRAGMENT_BIT, .module = load_shader(d->fs), .pName = "main" } };
    VkVertexInputBindingDescription bd = { 0, (uint32_t)d->stride, VK_VERTEX_INPUT_RATE_VERTEX };
    VkVertexInputAttributeDescription ad[2] = { { 0, 0, d->afmt[0], d->aoff[0] }, { 1, 0, d->afmt[1], d->aoff[1] } };
    VkPipelineVertexInputStateCreateInfo vi = { .sType = VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO, .vertexBindingDescriptionCount = 1, .pVertexBindingDescriptions = &bd, .vertexAttributeDescriptionCount = 2, .pVertexAttributeDescriptions = ad };
    VkPipelineInputAssemblyStateCreateInfo ia = { .sType = VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO, .topology = VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST };
    VkPipelineViewportStateCreateInfo vp = { .sType = VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO, .viewportCount = 1, .scissorCount = 1 };
    VkPipelineRasterizationStateCreateInfo rs = { .sType = VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO, .polygonMode = VK_POLYGON_MODE_FILL, .cullMode = VK_CULL_MODE_NONE, .frontFace = VK_FRONT_FACE_COUNTER_CLOCKWISE, .lineWidth = 1.0f };
    VkPipelineMultisampleStateCreateInfo ms = { .sType = VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO, .rasterizationSamples = VK_SAMPLE_COUNT_1_BIT };
    VkPipelineDepthStencilStateCreateInfo ds = { .sType = VK_STRUCTURE_TYPE_PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO, .depthTestEnable = d->depth_test, .depthWriteEnable = d->depth_test, .depthCompareOp = VK_COMPARE_OP_LESS, .maxDepthBounds = 1.0f };
    VkPipelineColorBlendAttachmentState ba = { .blendEnable = d->blend, .srcColorBlendFactor = VK_BLEND_FACTOR_SRC_ALPHA, .dstColorBlendFactor = VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA, .colorBlendOp = VK_BLEND_OP_ADD,
        .srcAlphaBlendFactor = VK_BLEND_FACTOR_ONE, .dstAlphaBlendFactor = VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA, .alphaBlendOp = VK_BLEND_OP_ADD, .colorWriteMask = 15 };
    VkPipelineColorBlendStateCreateInfo cbs = { .sType = VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO, .attachmentCount = 1, .pAttachments = &ba };
    VkDynamicState dyn[2] = { VK_DYNAMIC_STATE_VIEWPORT, VK_DYNAMIC_STATE_SCISSOR };
    VkPipelineDynamicStateCreateInfo dsi = { .sType = VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO, .dynamicStateCount = 2, .pDynamicStates = dyn };
    VkFormat cf = d->color;
    VkPipelineRenderingCreateInfo ri = { .sType = VK_STRUCTURE_TYPE_PIPELINE_RENDERING_CREATE_INFO, .colorAttachmentCount = 1, .pColorAttachmentFormats = &cf, .depthAttachmentFormat = d->depth };
    VkGraphicsPipelineCreateInfo gi = { .sType = VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO, .pNext = &ri, .stageCount = 2, .pStages = st, .pVertexInputState = &vi, .pInputAssemblyState = &ia,
        .pViewportState = &vp, .pRasterizationState = &rs, .pMultisampleState = &ms, .pDepthStencilState = &ds, .pColorBlendState = &cbs, .pDynamicState = &dsi, .layout = d->layout };
    VkPipeline p = 0;
    VkResult r = vkCreateGraphicsPipelines(dev, 0, 1, &gi, 0, &p);
    if (r != VK_SUCCESS) p = 0;
    return p;
}

static VkPipelineLayout mklayout(int sampler, uint32_t push, VkDescriptorSetLayout *out_dsl)
{
    VkDescriptorSetLayoutBinding b = { .binding = 0, .descriptorType = sampler == 1 ? VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER : VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER, .descriptorCount = 1, .stageFlags = VK_SHADER_STAGE_ALL_GRAPHICS };
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
    VkDescriptorPoolSize ps = { sampler == 1 ? VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER : VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER, 1 };
    VkDescriptorPoolCreateInfo pi = { .sType = VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO, .maxSets = 1, .poolSizeCount = 1, .pPoolSizes = &ps };
    VkDescriptorPool pool = 0;
    vkCreateDescriptorPool(dev, &pi, 0, &pool);
    VkDescriptorSetAllocateInfo ai = { .sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO, .descriptorPool = pool, .descriptorSetCount = 1, .pSetLayouts = &dsl };
    VkDescriptorSet set = 0;
    vkAllocateDescriptorSets(dev, &ai, &set);
    VkDescriptorImageInfo ii = { smp, view, VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL };
    VkDescriptorBufferInfo bi = { ubo, ubo_off, ubo_size };
    VkWriteDescriptorSet w = { .sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET, .dstSet = set, .dstBinding = 0, .descriptorCount = 1,
        .descriptorType = sampler == 1 ? VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER : VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER, .pImageInfo = &ii, .pBufferInfo = &bi };
    vkUpdateDescriptorSets(dev, 1, &w, 0, 0);
    return set;
}

typedef struct { Img color; Img depth; VkFormat fmt; } Target;
static Target mktarget(VkFormat fmt, int with_depth)
{
    Target t = {0};
    t.fmt = fmt;
    t.color = mkimg(fmt, W, H, VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT | VK_IMAGE_USAGE_TRANSFER_SRC_BIT, VK_IMAGE_ASPECT_COLOR_BIT);
    if (with_depth) t.depth = mkimg(VK_FORMAT_D32_SFLOAT, W, H, VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT, VK_IMAGE_ASPECT_DEPTH_BIT);
    return t;
}

static void begin_pass(Target *t, float r, float g, float b, float a)
{
    transition(t->color.i, VK_IMAGE_ASPECT_COLOR_BIT, VK_IMAGE_LAYOUT_UNDEFINED, VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL);
    VkRenderingAttachmentInfo ca = { .sType = VK_STRUCTURE_TYPE_RENDERING_ATTACHMENT_INFO, .imageView = t->color.v, .imageLayout = VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
        .loadOp = VK_ATTACHMENT_LOAD_OP_CLEAR, .storeOp = VK_ATTACHMENT_STORE_OP_STORE, .clearValue = { .color = { .float32 = { r, g, b, a } } } };
    VkRenderingAttachmentInfo da = { .sType = VK_STRUCTURE_TYPE_RENDERING_ATTACHMENT_INFO, .imageView = t->depth.v, .imageLayout = VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL,
        .loadOp = VK_ATTACHMENT_LOAD_OP_CLEAR, .storeOp = VK_ATTACHMENT_STORE_OP_STORE, .clearValue = { .depthStencil = { 1.0f, 0 } } };
    if (t->depth.i) transition(t->depth.i, VK_IMAGE_ASPECT_DEPTH_BIT, VK_IMAGE_LAYOUT_UNDEFINED, VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL);
    VkRenderingInfo ri = { .sType = VK_STRUCTURE_TYPE_RENDERING_INFO, .renderArea = { { 0, 0 }, { W, H } }, .layerCount = 1, .colorAttachmentCount = 1, .pColorAttachments = &ca, .pDepthAttachment = t->depth.i ? &da : 0 };
    vkCmdBeginRendering(cb, &ri);
}

static void set_vp(int x, int y, int w, int h, int sx, int sy, int sw, int sh)
{
    VkViewport v = { (float)x, (float)y, (float)w, (float)h, 0.0f, 1.0f };
    VkRect2D s = { { sx, sy }, { (uint32_t)sw, (uint32_t)sh } };
    vkCmdSetViewport(cb, 0, 1, &v);
    vkCmdSetScissor(cb, 0, 1, &s);
}

static void finish(Target *t, const char *name, Buf *rb)
{
    vkCmdEndRendering(cb);
    transition(t->color.i, VK_IMAGE_ASPECT_COLOR_BIT, VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL);
    VkBufferImageCopy c = { .imageSubresource = { VK_IMAGE_ASPECT_COLOR_BIT, 0, 0, 1 }, .imageExtent = { W, H, 1 } };
    vkCmdCopyImageToBuffer(cb, t->color.i, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, rb->b, 1, &c);
    char label[128];
    snprintf(label, sizeof label, "draw %s submits", name);
    check(label, submit_wait());
    char path[512];
    snprintf(path, sizeof path, "%s/%s.rgba", outdir, name);
    FILE *f = fopen(path, "wb");
    if (f) {
        for (int i = 0; i < W * H; i++) {
            uint8_t *p = rb->p + i * 4;
            uint8_t px[4] = { p[0], p[1], p[2], p[3] };
            if (t->fmt == VK_FORMAT_B8G8R8A8_UNORM) { px[0] = p[2]; px[2] = p[0]; }
            fwrite(px, 1, 4, f);
        }
        fclose(f);
    }
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

static void case_quad(void)
{
    Target t = mktarget(VK_FORMAT_R8G8B8A8_UNORM, 0);
    uint8_t texels[8 * 8 * 4];
    for (int y = 0; y < 8; y++) for (int x = 0; x < 8; x++) {
        uint8_t *p = texels + (y * 8 + x) * 4;
        p[0] = (uint8_t)(x * 36); p[1] = (uint8_t)(y * 36); p[2] = ((x ^ y) & 1) ? 220 : 40; p[3] = 255;
    }
    Img tex = mkimg(VK_FORMAT_R8G8B8A8_UNORM, 8, 8, VK_IMAGE_USAGE_SAMPLED_BIT | VK_IMAGE_USAGE_TRANSFER_DST_BIT, VK_IMAGE_ASPECT_COLOR_BIT);
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
    check("pipeline quad", p != 0);
    static const float quad[] = { -0.75f, -0.75f, 0, 0,   0.75f, -0.75f, 1, 0,   0.75f, 0.75f, 1, 1,   -0.75f, 0.75f, 0, 1 };
    static const uint16_t idx[] = { 7, 7, 0, 1, 2, 0, 2, 3 };
    Buf vb = mkvec(quad, sizeof quad, VK_BUFFER_USAGE_VERTEX_BUFFER_BIT);
    Buf ib = mkvec(idx, sizeof idx, VK_BUFFER_USAGE_INDEX_BUFFER_BIT);
    Buf rb = mkbuf(W * H * 4, VK_BUFFER_USAGE_TRANSFER_DST_BIT);
    begin();
    transition(tex.i, VK_IMAGE_ASPECT_COLOR_BIT, VK_IMAGE_LAYOUT_UNDEFINED, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL);
    VkBufferImageCopy c = { .imageSubresource = { VK_IMAGE_ASPECT_COLOR_BIT, 0, 0, 1 }, .imageExtent = { 8, 8, 1 } };
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
    finish(&t, "quad", &rb);
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

typedef struct { float clipr[4], box[4], c1[4], grad[4], size[4]; } FuiU;
typedef struct { float x, y, r, g, b, a; } FuiV;

static void case_fui(void)
{
    Target t = mktarget(VK_FORMAT_R8G8B8A8_UNORM, 0);
    VkDescriptorSetLayout dsl;
    VkPipelineLayout lay = mklayout(2, 0, &dsl);
    PipeDesc d = { "fui_rect.vert", "fui_rect.frag", t.fmt, VK_FORMAT_UNDEFINED, 1, 0, 2, 24, { VK_FORMAT_R32G32_SFLOAT, VK_FORMAT_R32G32B32A32_SFLOAT }, { 0, 8 }, lay };
    VkPipeline p = mkpipe(&d);
    check("pipeline fui", p != 0);
    struct { float box[4], clip[4], col[4], c1[3], grad[3]; } q[3] = {
        { { 0, 0, 64, 48 }, { 0, 0, 4096, 4096 }, { 30, 34, 48, 255 }, { 0, 0, 0 }, { 0, 0, 0 } },
        { { 5, 4, 58, 30 }, { 0, 0, 4096, 4096 }, { 80, 120, 200, 255 }, { 20, 40, 90 }, { 4, 30, 1 } },
        { { 12.5f, 10.25f, 50.75f, 40.5f }, { 0, 0, 4096, 4096 }, { 255, 200, 0, 160 }, { 0, 0, 0 }, { 0, 0, 0 } } };
    Buf rb = mkbuf(W * H * 4, VK_BUFFER_USAGE_TRANSFER_DST_BIT);
    enum { UB_STRIDE = 256 };
    Buf ubs = mkbuf(UB_STRIDE * 3, VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT);
    memset(ubs.p, 0xA5, UB_STRIDE * 3);
    Buf vb[3];
    VkDescriptorSet sets[3];
    for (int i = 0; i < 3; i++) {
        FuiU u = { { q[i].clip[0], q[i].clip[1], q[i].clip[2], q[i].clip[3] }, { q[i].box[0], q[i].box[1], q[i].box[2], q[i].box[3] },
            { q[i].c1[0], q[i].c1[1], q[i].c1[2], 255 }, { q[i].grad[0], q[i].grad[1], q[i].grad[2], 0 }, { W, H, 0, 0 } };
        memcpy(ubs.p + (2 - i) * UB_STRIDE, &u, sizeof u);
        float x0 = q[i].box[0], y0 = q[i].box[1], x1 = q[i].box[2], y1 = q[i].box[3];
        x0 = (float)(int)x0; y0 = (float)(int)y0; x1 = (float)((int)x1 + (x1 > (int)x1)); y1 = (float)((int)y1 + (y1 > (int)y1));
        FuiV v[6] = { { x0, y0 }, { x1, y0 }, { x1, y1 }, { x0, y0 }, { x1, y1 }, { x0, y1 } };
        for (int k = 0; k < 6; k++) { v[k].r = q[i].col[0]; v[k].g = q[i].col[1]; v[k].b = q[i].col[2]; v[k].a = q[i].col[3]; }
        vb[i] = mkvec(v, sizeof v, VK_BUFFER_USAGE_VERTEX_BUFFER_BIT);
        sets[i] = mkset(dsl, 2, 0, 0, ubs.b, (2 - i) * UB_STRIDE, sizeof(FuiU));
    }
    begin();
    begin_pass(&t, 0.0f, 0.0f, 0.0f, 1.0f);
    vkCmdBindPipeline(cb, VK_PIPELINE_BIND_POINT_GRAPHICS, p);
    set_vp(0, 0, W, H, 0, 0, W, H);
    for (int i = 0; i < 3; i++) {
        if (i == 2) set_vp(0, 0, W, H, 16, 12, 24, 16);
        VkDeviceSize off = 0;
        vkCmdBindDescriptorSets(cb, VK_PIPELINE_BIND_POINT_GRAPHICS, lay, 0, 1, &sets[i], 0, 0);
        vkCmdBindVertexBuffers(cb, 0, 1, &vb[i].b, &off);
        vkCmdDraw(cb, 6, 1, 0, 0);
    }
    finish(&t, "fui", &rb);
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
    VkInstanceCreateInfo ici = { .sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO, .pApplicationInfo = &app };
    VkInstance inst = 0;
    check("vkCreateInstance", ci(&ici, 0, &inst) == VK_SUCCESS && inst);
    PFN_vkEnumeratePhysicalDevices enumpd = (PFN_vkEnumeratePhysicalDevices)gipa(inst, "vkEnumeratePhysicalDevices");
    PFN_vkGetPhysicalDeviceProperties getprops = (PFN_vkGetPhysicalDeviceProperties)gipa(inst, "vkGetPhysicalDeviceProperties");
    PFN_vkGetPhysicalDeviceMemoryProperties getmp = (PFN_vkGetPhysicalDeviceMemoryProperties)gipa(inst, "vkGetPhysicalDeviceMemoryProperties");
    PFN_vkCreateDevice createdev = (PFN_vkCreateDevice)gipa(inst, "vkCreateDevice");
    PFN_vkGetDeviceProcAddr gdpa = (PFN_vkGetDeviceProcAddr)gipa(inst, "vkGetDeviceProcAddr");
    uint32_t n = 8;
    VkPhysicalDevice pds[8];
    enumpd(inst, &n, pds);
    VkPhysicalDevice pd = pds[0];
    if (mode == 1) for (uint32_t i = 0; i < n; i++) { VkPhysicalDeviceProperties p; getprops(pds[i], &p); if (p.deviceType == VK_PHYSICAL_DEVICE_TYPE_CPU) pd = pds[i]; }
    getmp(pd, &mp);
    float prio = 1.0f;
    VkDeviceQueueCreateInfo dq = { .sType = VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO, .queueFamilyIndex = 0, .queueCount = 1, .pQueuePriorities = &prio };
    VkPhysicalDeviceVulkan13Features f13 = { .sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_3_FEATURES, .dynamicRendering = VK_TRUE };
    VkDeviceCreateInfo dci = { .sType = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO, .pNext = &f13, .queueCreateInfoCount = 1, .pQueueCreateInfos = &dq };
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
    case_quad();
    case_depth();
    case_fui();
    printf("VK DONE bad=%d\n", bad);
    return bad ? 1 : 0;
}
