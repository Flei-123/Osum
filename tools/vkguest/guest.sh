echo "VKG guest start"
/vk/draw /vk/libvulkan.so.1 0 - /vk/spv
echo "VKG rc=$?"
/vk/draw /vk/libvulkan_mut.so 0 - /vk/spv
echo "VKG mut-rc=$?"
/vk/draw /vk/libvulkan_missing.so 0 - /vk/spv
echo "VKG neg-missing rc=$?"
echo FX-END
