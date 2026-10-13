# GFX-STACK — Weg E: eigener Grafikstack in Firn (Spezifikation + Prototyp, 13.10.2026)

Prototyp: `lib/gpu/swr/` (raster.fi, shader.fi, scene.fi), Tests/Messung `tools/gfx/run.sh [bench]`. Nur Host, keine VM, kein Dell.
Belegt = gemessen/gelesen. **Schätzung** = nicht gemessen. Messwirt: 20 Threads, Load 14–22 (fremde Läufe) → `min` ist verlässlicher als `med`.

## 1. Minimale Teilmenge (Schritt 1)
| Stufe | Client | Braucht | Status |
|---|---|---|---|
| T0 | Wayland `wl_shm`-Programme, Browser mit Software-Renderer (Firefox SWGL, Chromium `--disable-gpu`, GTK-Cairo, Qt-software) — **Allgemeinwissen, ungeprüft** | KEIN GPU-API, nur Syscalls (LINUX-COMPAT Kap. 1) | geht ohne SWR |
| T1 | Daidalos-RHI (Vulkan 1.3) | Liste Kap. 6 (83 Funktionen, 81 ohne Win32/Xlib), SPIR-V Vert/Frag, Dynamic Rendering, Sync2, Present über `wl_shm` | Prototyp deckt Rasterkern ab, API-Schicht fehlt |
| T2 | wgpu/eframe (Vulkan-Backend) — **ungeprüft** | + Compute-Pipeline/`vkCmdDispatch`, Storage-Buffer, Compute-SPIR-V, mehr Formate/Features, Timestamp/Query | offen |
| T3 | GLES 3.0 / GL 3.3 + EGL (eframe glow, WebRender GL) | + GLSL-ES-Compiler (Frontend → SPIR-V/Bytecode), VAO/VBO/UBO/FBO, Instancing | offen, XL |

Immer nötig: Linux-ABI (dlopen, Fäden, mmap, futex/epoll — LINUX-COMPAT), und die Frage, ob `firnc` eine C-ABI-`.so` mit Exporttabelle erzeugt (r674, **unbekannt**).
Aufbau: `libvulkan`-ICD (Loader-kompatibel) → SWR-Kern (Firn) → Swapchain-Present per `wl_shm` (Daidalos hat schon einen Wayland-Pfad: `rhi_vulkan_window_wayland.cpp`).

## 2. Shader-Kern: Entscheidung (Schritt 2)
Optionen: (a) SPIR-V direkt je Pixel interpretieren — verworfen (Dispatch je Pixel). (b) SPIR-V → Batch-Bytecode (SoA, 64 Pixel pro Befehl) mit Interpreter. (c) x86-64-JIT (W^X/mprotect geht laut LINUX-COMPAT). (d) SIMD im Firn-Compiler (`L16` offen) → Interpreter-Schleifen werden 4–8-fach breiter.
**Entscheidung: (b) jetzt.** Gemessen (Prototyp, `shader.fi` = Stand-in für das SPIR-V-Lowering):
- **1,3–1,4 ns je Operation und Pixel** (MAD-Kette, 1 Kern). Programm A (6 Befehle) bzw. B (13 Befehle) kosten gegenüber nativ kompiliertem Firn nur **1,09× / 1,14×** (34,7 vs 31,8 ms; 38,7 vs 34,1 ms) — bei so kleinen Shadern dominiert Raster/Texturzugriff.
- Bit-identisch zu nativ (Test 6/7), und identisch bei 1 und 4 Fäden (Test 9).
- **Schätzung (ungemessen):** Daidalos `mesh.frag.spv` hat 2087 SPIR-V-Ops (davon ~11 Bildzugriffe, 69 ExtInst, 4 Schleifen, 1 `discard`); bei ~800 ausgeführten Op-Pixeln ≈ 1 µs/Pixel → ~1 s/Bild bei 0,9 Mpx auf 1 Kern, ~0,15 s auf 8. Für Echtzeit-PBR zu langsam → Auslöser für (d)/(c): zuerst **(d) SIMD in Firn** (kleiner Eingriff, hilft allem), dann **(c) JIT** nur wenn nötig. Entscheidung (c) fällt nach Messung des echten `mesh.frag` im Bytecode.
- Lowering-Plan: Module parsen, Aufrufe inlinen, strukturierten Kontrollfluss (`OpSelectionMerge/OpLoopMerge`) als Lane-Masken, `OpKill`/discard → Late-Z (heute nur Early-Z), GLSL.std.450 als Bytecode-Ops, `OpImageSample*` (Dref für Schattenarray nötig), Ableitungen (`dFdx`) brauchen 2×2-Quads — **Risiko R1**, heute nicht gebaut.

## 3. Prototyp-Rasterer (Schritt 3)
`lib/gpu/swr/raster.fi`: Clip-Raum-Vertices → 1/16-Pixel-Festkomma, Randfunktionen ganzzahlig, Top-Left-Regel, x-Intervall je Zeile aus den Randfunktionen (nur gedeckte Pixel), Ebenengleichungen für z, 1/w, u/w, v/w, r/w, g/w, b/w, a/w (perspektivisch korrekt), Early-Z (f32), Texture nearest/repeat 256², Bänder à 16 Zeilen parallel über `jobs.parallel_for` (Spiegel `lib/jobs/jobs.fi`, weil der Pin kein `jobs` hat). Deterministisch: Bänder sind disjunkt, Dreiecke je Band in Reihenfolge.
**Tests (`tools/gfx/run.sh`, 10/0):** Füllregel (Vollbild-Quad + 64 schiefe Fächer-Dreiecke: jedes Pixel genau 1×), Tiefe (beide Zeichenreihenfolgen gleich), Textur 1:1 bit-genau (65536 Texel), VM = nativ (2 Programme, 300 Zufallsdreiecke), 1 Faden = 4 Fäden bit-identisch.

**Messung 1240×720, `--opt-level=release-fast`, `min` in ms je Bild (Setup inklusive, Clear nicht; Clear ≈ 3 ms):**
| Szene (schattierte Pixel) | Shader | 1 Kern | 2 | 4 | 8 |
|---|---|---|---|---|---|
| quad-1x (0,89 Mpx) | nativ A (Tex×Farbe) | 31,8 | 17,2 | 9,7 | 10,3 |
| quad-1x | VM A / VM B (13 Befehle) | 34,7 / 38,7 | 18,5 / 23,3 | 10,7 / 13,6 | 9,1 / 10,5 |
| 3 Quads fern→nah (2,68 Mpx) | nativ A | 85,0 | 47,9 | 28,5 | 19,8 |
| 3 Quads nah→fern (Early-Z, 0,89 Mpx) | nativ A | 32,0 | 18,2 | 12,7 | 5,6 |
| 4000 Zufallsdreiecke (3,10 Mpx) | nativ A / nativ B | 194,8 / 196,7 | 95,8 / 104,3 | 55,3 / 53,2 | 30,7 / 28,5 |
| 4000 Zufallsdreiecke | VM A / VM B | 204,0 / 245,8 | 105,5 / 125,3 | 53,8 / 65,4 | 30,0 / 34,7 |
- Einzelkern: **~36 ns/Pixel** (Textur+Tiefe+Farbe), davon Abdeckung+Tiefe ~5 ns (Zählmodus 4,1/5,5 ms), Rest Attribute (f64-Division) + Texel + Pack. Setup 0,9 µs/Dreieck (3,7 ms für 4000). Skalierung 1→8 Kerne 3,1× (kleine Szene) bis 6,3× (Dreiecke); Grenze: 45 Bänder, Last des Wirts.
- Einfache texturierte Szene: 60 Bilder/s ab ~2–4 Kernen. 3–4× Überdeckung: 33 Bilder/s auf 8 Kernen.
- **Compiler-Lehren (gemessen):** (1) Default-`firnc` (dev-fast) prüft Überlauf: 135 statt 31,8 ms (4,2× langsamer) → Bench/Produktion `--opt-level=release-fast`, Tests mit Prüfung. (2) **Inliner-Klippe:** eine große Funktion mit vielen kleinen Schleifen (alle VM-Ops in `shade_vm`) lief 6–8× langsamer (8,4 ns je Op und Pixel); `#[no_inline]` auf den Ops → 1,3 ns. (3) `math.floor32` ist ein Soft-Float-Ersatz (Bitfummelei); Ganzzahl-Abschneiden + Korrektur ist ~10× schneller. (4) Überlauf-Prüfung: Hashes/LCG brauchen Masken (`*%` gibt es).

## 4. Nicht gebaut (Prototyp-Grenzen)
Clipping (Dreiecke mit w ≤ 0 werden verworfen), Scissor, Blending, Stencil, MSAA (Daidalos nutzt 2×/8×), Mip/Bilinear/Anisotropie, discard (Late-Z), Indexpuffer, Tile-Binning (jedes Band läuft alle Dreiecke ab), Ableitungen/Quads, Float-/16-Bit-Ziele, SIMD.

## 5. Nächste Schritte
1. Clipping + Blending + bilinear/Mip + MSAA-Resolve (Daidalos-Pfade). 2. SPIR-V-Modul-Parser + Lowering nach Bytecode (Test: `ui.frag.spv`, 74 Ops, dann `particle`, `sky`, `post_*`, zuletzt `mesh.frag`). 3. Vulkan-API-Schicht (Kap. 6) als `.so` (r674 klären). 4. Firn-SIMD (`L16`) ODER JIT nach Messung. 5. Binning pro Kachel (Dreiecke je Band vorsortieren).

## 6. Daidalos-RHI als Test-Client: minimale Vulkan-Aufrufe (Schritt 4)
Quelle `rhi_vulkan*.cpp` (4971 Zeilen), 83 verschiedene `vk*`-Namen, apiVersion 1.3. Features: `dynamicRendering`, `synchronization2` (Vulkan13Features), `depthClamp`. Gelesen per `grep`, nicht ausgeführt.
- **Instanz/Gerät:** CreateInstance, DestroyInstance, EnumerateInstanceExtensionProperties, EnumeratePhysicalDevices, GetPhysicalDeviceProperties/Features/MemoryProperties/QueueFamilyProperties, EnumerateDeviceExtensionProperties, CreateDevice, DestroyDevice, GetDeviceQueue, QueueSubmit, QueueWaitIdle, DeviceWaitIdle.
- **WSI:** Create/DestroySurfaceKHR (Wayland; Win32/Xlib entfallen), GetPhysicalDeviceSurfaceSupport/Capabilities/Formats, CreateSwapchainKHR, DestroySwapchainKHR, GetSwapchainImagesKHR, AcquireNextImageKHR, QueuePresentKHR. Present-Mode FIFO. Erweiterungen: `VK_KHR_surface`, `VK_KHR_swapchain`, `VK_KHR_wayland_surface`.
- **Speicher/Ressourcen:** Allocate/FreeMemory, Map/UnmapMemory, Create/DestroyBuffer, Create/DestroyImage, Create/DestroyImageView, Create/DestroySampler, Get{Buffer,Image}MemoryRequirements, Bind{Buffer,Image}Memory, CmdCopyBufferToImage, CmdCopyImageToBuffer, CmdBlitImage.
- **Shader/Pipeline/Deskriptoren:** CreateShaderModule (+Destroy), CreateGraphicsPipelines (**keine** Compute-Pipeline), Create/DestroyPipelineLayout, Create/DestroyDescriptorSetLayout, Create/DestroyDescriptorPool, AllocateDescriptorSets, UpdateDescriptorSets. Deskriptortypen: COMBINED_IMAGE_SAMPLER, STORAGE_BUFFER, UNIFORM_BUFFER_DYNAMIC.
- **Kommandos:** Create/DestroyCommandPool, Allocate/FreeCommandBuffers, Begin/End/ResetCommandBuffer, CmdBeginRendering, CmdEndRendering, CmdBindPipeline, CmdBindDescriptorSets, CmdBindVertexBuffers, CmdBindIndexBuffer, CmdPushConstants, CmdSetViewport, CmdSetScissor, CmdDraw, CmdDrawIndexed, CmdPipelineBarrier2.
- **Sync:** Create/Destroy Fence und Semaphore, WaitForFences, ResetFences.
- **Zustände:** Formate B8G8R8A8_UNORM, R8G8B8A8_{UNORM,SRGB,UINT}, D32_SFLOAT, R32{,G32,G32B32,G32B32A32}_SFLOAT, R32_UINT, R32G32_UINT; Topologie TRIANGLE_LIST, LINE_LIST; Tiefe LESS/LESS_OR_EQUAL + Compare (Schatten); Blend ONE/ONE_MINUS_SRC_ALPHA; Cull NONE/BACK; Fill; Filter LINEAR; Adressierung REPEAT/CLAMP_TO_EDGE; Samples 1/2/8.
- **SPIR-V (Daidalos `shaders/*.spv`, per `spirv-dis`):** nur Capability `Shader`; mesh.frag 2087 Ops/4 Schleifen/1 Kill/11 Bildzugriffe, mesh.vert 519 (instanzierte Attribute, Joints/Weights), particle.frag 183 (2× discard), post_comp 365, sky 244, ui.frag 74. `sampler2DArrayShadow`, SSBO-Lichter (`Lights`), Push-Constants.
- **Reihenfolge der Prüfsteine:** ui (74 Ops) → lines → particle (discard) → sky → post_* → mesh.
