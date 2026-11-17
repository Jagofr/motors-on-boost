package graphics;

import ash.Future;
import graphics.Primitives.PrimitiveDesc;
import graphics.SceneGraph;
import graphics.shaders.SceneLitShader;
import graphics.shaders.SkyShader;
import graphics.shaders.SmaaShader;
import graphics.shaders.TaaResolveShader;
import graphics.shaders.TrackComputeShader;
import haxe.Int64;
import haxe.io.Bytes;
import math.Mat4;
import math.SoABuffer;
import math.Vec3;
import window.Window;
import window.WindowAttributes;
import gpu.*;

private typedef GpuPrimEntry = {
    var vb:GpuBuffer;
    var ib:GpuBuffer;
    var indexCount:Int;
};

private typedef RenderBatch = {
    var prim:PrimitiveDesc;
    var cullNone:Bool;
    var firstInstance:Int;
    var instanceCount:Int;
};

/**
 * Stateless, command-driven WebGPU renderer backed by `hlwgpu` 0.2.0 (`xgpu`) and `hlwindow` 0.3.2.
 * Features async pipeline pre-compilation, WGSL compute track spline tessellation with
 * `renderDrawIndexedIndirect`, SoA instanced forward rendering, and radial velocity blur post-FX.
 */
class WebGpuRenderer {
    public static inline var MAX_INSTANCES:Int = 4096;

    public var win:Window;
    public var instance:GpuInstance;
    public var adapter:GpuAdapter;
    public var device:GpuDevice;
    public var queue:GpuQueue;
    public var surface:GpuSurface;
    public var surfaceFormat:TextureFormat = TextureFormat.Bgra8unorm;

    public var initialized:Bool = false;
    public var deviceLost:Bool = false;
    public var physicalWidth:Int = 1280;
    public var physicalHeight:Int = 720;
    public var renderScale:Float = 1.0;

    // Anti-aliasing & shader quality uniform state
    public var aaModeCode:Float = 1.0; // 0=None, 1=FXAA, 2=TSAA, 3=SMAA, 4=MSAA
    public var aaStrength:Float = 0.5;
    private var reflScaleParam:Float = 0.78;
    private var shadowStrengthParam:Float = 0.55;
    private var surfaceDetailParam:Float = 1.0;
    private var lightScaleParam:Float = 1.0;

    // Pipelines
    private var trackComputePipeline:GpuPipeline;
    private var skyPipeline:GpuPipeline;
    private var skyMsaaPipeline:GpuPipeline;
    private var skyTaaPipeline:GpuPipeline;
    private var sceneLitBackPipeline:GpuPipeline;
    private var sceneLitNonePipeline:GpuPipeline;
    private var sceneLitBackMsaaPipeline:GpuPipeline;
    private var sceneLitNoneMsaaPipeline:GpuPipeline;
    private var sceneLitBackTaaPipeline:GpuPipeline;
    private var sceneLitNoneTaaPipeline:GpuPipeline;
    private var radialBlurPipeline:GpuPipeline;
    private var smaaEdgePipeline:GpuPipeline;
    private var smaaWeightPipeline:GpuPipeline;
    private var smaaResolvePipeline:GpuPipeline;
    private var taaResolvePipeline:GpuPipeline;

    // Shared frame buffers & bind groups
    private var skyUniformBuf:GpuBuffer;
    private var skyBindGroup:GpuBindGroup;
    private var skyMsaaBindGroup:GpuBindGroup;
    private var skyTaaBindGroup:GpuBindGroup;

    private var sceneUniformBuf:GpuBuffer;
    private var instanceStorageBuf:GpuBuffer;
    private var sceneBindGroupBack:GpuBindGroup;
    private var sceneBindGroupNone:GpuBindGroup;
    private var sceneMsaaBindGroupBack:GpuBindGroup;
    private var sceneMsaaBindGroupNone:GpuBindGroup;
    private var sceneTaaBindGroupBack:GpuBindGroup;
    private var sceneTaaBindGroupNone:GpuBindGroup;

    private var blurUniformBuf:GpuBuffer;
    private var taaUniformBuf:GpuBuffer;
    private var blurSampler:GpuSampler;
    private var blurBindGroup:GpuBindGroup;
    private var smaaEdgeBindGroup:GpuBindGroup;
    private var smaaWeightBindGroup:GpuBindGroup;
    private var smaaResolveBindGroup:GpuBindGroup;
    private var taaResolveBindGroup0:GpuBindGroup;
    private var taaResolveBindGroup1:GpuBindGroup;
    private var taaPostBindGroup0:GpuBindGroup;
    private var taaPostBindGroup1:GpuBindGroup;

    // Offscreen, MSAA, SMAA, and TAA history/velocity textures (resized with viewport or renderScale)
    private var offscreenColorTex:GpuTexture;
    private var offscreenColorView:GpuTextureView;
    private var depthTex:GpuTexture;
    private var depthView:GpuTextureView;
    private var msaaColorTex:GpuTexture;
    private var msaaColorView:GpuTextureView;
    private var msaaDepthTex:GpuTexture;
    private var msaaDepthView:GpuTextureView;
    private var smaaEdgeTex:GpuTexture;
    private var smaaEdgeView:GpuTextureView;
    private var smaaBlendTex:GpuTexture;
    private var smaaBlendView:GpuTextureView;
    private var taaVelocityTex:GpuTexture;
    private var taaVelocityView:GpuTextureView;
    private var taaHistoryTex0:GpuTexture;
    private var taaHistoryView0:GpuTextureView;
    private var taaHistoryTex1:GpuTexture;
    private var taaHistoryView1:GpuTextureView;
    private var targetWidth:Int = 0;
    private var targetHeight:Int = 0;

    // Temporal AA state
    private var taaFrameIndex:Int = 0;
    private var taaWriteIdx:Int = 0;
    private var taaHistoryValid:Bool = false;
    private var taaNeedsReset:Bool = true;

    // GPU-computed Track buffers (Roadbed, Asphalt, Left Rail, Right Rail)
    private var trackParamBuf:GpuBuffer;
    private var trackSplineBuf:GpuBuffer;
    private var trackVertBuf:GpuBuffer;
    private var trackIdxBuf:GpuBuffer;
    private var trackIndirectBuf:GpuBuffer;
    private var trackComputeBG:GpuBindGroup;
    private var trackCapacityPts:Int = 0;
    private var trackPointCount:Int = 0;
    private var trackDispatched:Bool = false;

    // Primitive GPU buffer cache keyed by PrimitiveDesc.gpuId
    private var primCache:Map<Int, GpuPrimEntry> = new Map();

    // CPU staging buffers (zero per-frame heap allocation)
    private var skyBytes:Bytes;
    private var sceneBytes:Bytes;
    private var blurBytes:Bytes;
    private var taaBytes:Bytes;
    private var soa:SoABuffer;

    public function new() {
        skyBytes = Bytes.alloc(SkyShader.UNIFORM_BYTES);
        sceneBytes = Bytes.alloc(SceneLitShader.SCENE_UNIFORM_BYTES);
        blurBytes = Bytes.alloc(RadialBlurShader.UNIFORM_BYTES);
        taaBytes = Bytes.alloc(TaaResolveShader.UNIFORM_BYTES);
        soa = new SoABuffer(512);
    }

    /**
     * Opens the host window, acquires WebGPU adapter/device, configures the swapchain surface,
     * and asynchronously compiles all compute and render pipelines.
     */
    public function initAsync(width:Int, height:Int, title:String = "M.O.B. // Motors on Boost"):Bool {
        try {
            var attrs = new WindowAttributes();
            attrs.title(title);
            attrs.width(width);
            attrs.height(height);
            attrs.resizable(true);
            win = Window.open(attrs);
            if (!win.valid()) return false;

            physicalWidth = win.width() > 0 ? win.width() : width;
            physicalHeight = win.height() > 0 ? win.height() : height;

            instance = new GpuInstance();
            if (!instance.valid()) return false;

            surface = instance.surface(win.platform(), win.raw(0), win.raw(1), win.raw(2), win.raw(3));
            if (!surface.valid()) return false;

            adapter = instance.requestAdapter(Power.HighPerformance).await();
            if (!adapter.valid()) return false;

            device = adapter.requestDevice().await();
            if (!device.valid()) return false;

            queue = device.queue();
            surfaceFormat = surface.preferredFormat(adapter);
            if ((surfaceFormat : Int) == 0) {
                surfaceFormat = TextureFormat.Bgra8unorm;
            }

            configureSurface(physicalWidth, physicalHeight);
            createSharedBuffers();
            compilePipelinesAsync();
            ensureRenderTargets();

            initialized = true;
            return true;
        } catch (e:Dynamic) {
            trace("WebGpuRenderer init failed: " + Std.string(e));
            initialized = false;
            return false;
        }
    }

    public function resize(w:Int, h:Int):Void {
        if (!initialized || w <= 0 || h <= 0) return;
        var cw = w > 4096 ? 4096 : w;
        var ch = h > 4096 ? 4096 : h;
        if (cw == physicalWidth && ch == physicalHeight) return;
        physicalWidth = cw;
        physicalHeight = ch;
        configureSurface(cw, ch);
        ensureRenderTargets();
    }

    public function setRenderScale(scale:Float):Void {
        var clamped = Math.max(0.25, Math.min(4.0, scale));
        if (Math.abs(clamped - renderScale) < 0.005) return;
        renderScale = clamped;
        if (initialized) ensureRenderTargets();
    }

    public function setAntiAliasing(aaType:String, aaLevel:Int):Void {
        var nextCode = switch (aaType) {
            case "None": 0.0;
            case "FXAA": 1.0;
            case "TSAA": 2.0;
            case "SMAA": 3.0;
            case "MSAA": 4.0;
            default: 1.0;
        };
        var nextStr = switch (aaLevel) {
            case 2: 0.45;
            case 4: 0.72;
            case 8: 1.0;
            default: 0.65;
        };
        if (Math.abs(nextCode - aaModeCode) > 0.1 || (nextCode == 2.0 && Math.abs(nextStr - aaStrength) > 0.01)) {
            taaNeedsReset = true;
            taaHistoryValid = false;
            taaFrameIndex = 0;
        }
        aaModeCode = nextCode;
        aaStrength = nextStr;
    }

    public function setQualityParams(reflScale:Float, shadowStr:Float, detailScale:Float, lightScale:Float):Void {
        reflScaleParam = reflScale;
        shadowStrengthParam = shadowStr;
        surfaceDetailParam = detailScale;
        lightScaleParam = lightScale;
    }

    /** Clears swapchain purely to black without rendering any 3D geometry (boot intro / pause gate). */
    public function renderBlackFrame():Void {
        if (!initialized || deviceLost) return;
        var swapView = surface.acquire();
        if (!swapView.valid()) return;
        var enc = device.encoder();
        enc.passReset();
        enc.passColour(swapView, 0.0, 0.0, 0.0, 1.0);
        enc.passBegin();
        enc.renderEnd();
        enc.submit(queue);
        enc.destroy();
        queue.presentSurface(surface);
    }

    private function configureSurface(w:Int, h:Int):Void {
        var cfg = new GpuSurfaceConfiguration(surfaceFormat, w, h);
        cfg.usage(TextureUsage.RENDER_ATTACHMENT);
        cfg.alphaMode(AlphaMode.Opaque);
        cfg.presentMode(PresentMode.Fifo);
        device.configureSurfaceWith(surface, cfg);
    }

    private function createBufferWithUsage(byteSize:Int, usage:Int, label:String):GpuBuffer {
        var aligned = (byteSize + 15) & ~15;
        var desc = new GpuBufferDescriptor(Int64.ofInt(aligned < 16 ? 16 : aligned), usage);
        desc.label(label);
        return device.createBuffer(desc);
    }

    private function createSharedBuffers():Void {
        skyUniformBuf = createBufferWithUsage(
            SkyShader.UNIFORM_BYTES,
            BufferUsage.UNIFORM | BufferUsage.COPY_DST,
            "SkyUniforms"
        );
        sceneUniformBuf = createBufferWithUsage(
            SceneLitShader.SCENE_UNIFORM_BYTES,
            BufferUsage.UNIFORM | BufferUsage.COPY_DST,
            "SceneUniforms"
        );
        instanceStorageBuf = createBufferWithUsage(
            MAX_INSTANCES * SoABuffer.INSTANCE_STRIDE_BYTES,
            BufferUsage.STORAGE | BufferUsage.COPY_DST,
            "InstanceStorage"
        );
        blurUniformBuf = createBufferWithUsage(
            RadialBlurShader.UNIFORM_BYTES,
            BufferUsage.UNIFORM | BufferUsage.COPY_DST,
            "BlurUniforms"
        );
        taaUniformBuf = createBufferWithUsage(
            TaaResolveShader.UNIFORM_BYTES,
            BufferUsage.UNIFORM | BufferUsage.COPY_DST,
            "TaaUniforms"
        );

        var sd = new GpuSamplerDescriptor();
        sd.label("LinearClampSampler");
        sd.magFilter(FilterMode.Linear);
        sd.minFilter(FilterMode.Linear);
        sd.addressModeU(AddressMode.ClampToEdge);
        sd.addressModeV(AddressMode.ClampToEdge);
        blurSampler = device.sampler(sd);
    }

    private function compilePipelinesAsync():Void {
        // 1. Track geometry compute pipeline
        var trackMod = device.createShader(TrackComputeShader.WGSL);
        var csStage = new GpuProgrammableStage(trackMod);
        csStage.entryPoint("cs_main");
        var csDesc = new GpuComputePipelineDescriptor(csStage);
        csDesc.label("TrackComputePipeline");
        trackComputePipeline = device.createComputePipelineAsync(csDesc).await();

        // 2. Sky fullscreen pipelines (1x, 4x hardware MSAA, and MRT velocity TAA)
        var skyMod = device.createShader(SkyShader.WGSL);
        var skyTaaMod = device.createShader(SkyShader.WGSL_TAA);
        skyPipeline = buildFullscreenPipelineAsync(skyMod, true, CompareFunction.LessEqual, false, "SkyPipeline");
        skyMsaaPipeline = buildFullscreenPipelineAsync(skyMod, true, CompareFunction.LessEqual, false, "SkyMsaaPipeline", null, 4);
        skyTaaPipeline = buildFullscreenPipelineAsync(skyTaaMod, true, CompareFunction.LessEqual, false, "SkyTaaPipeline", null, 1, true);

        var skyBg = new GpuBindings();
        skyBg.buffer(skyUniformBuf);
        skyBindGroup = device.bindGroup(skyPipeline, 0, skyBg);

        var skyMsaaBg = new GpuBindings();
        skyMsaaBg.buffer(skyUniformBuf);
        skyMsaaBindGroup = device.bindGroup(skyMsaaPipeline, 0, skyMsaaBg);

        var skyTaaBg = new GpuBindings();
        skyTaaBg.buffer(skyUniformBuf);
        skyTaaBindGroup = device.bindGroup(skyTaaPipeline, 0, skyTaaBg);

        // 3. Scene forward lit pipelines (Back-face culled + double-sided None: 1x, 4x MSAA, MRT velocity TAA)
        var litMod = device.createShader(SceneLitShader.WGSL);
        var litTaaMod = device.createShader(SceneLitShader.WGSL_TAA);
        sceneLitBackPipeline = buildLitPipelineAsync(litMod, CullMode.Back, "SceneLitBack");
        sceneLitNonePipeline = buildLitPipelineAsync(litMod, CullMode.None, "SceneLitNone");
        sceneLitBackMsaaPipeline = buildLitPipelineAsync(litMod, CullMode.Back, "SceneLitBackMsaa", 4);
        sceneLitNoneMsaaPipeline = buildLitPipelineAsync(litMod, CullMode.None, "SceneLitNoneMsaa", 4);
        sceneLitBackTaaPipeline = buildLitPipelineAsync(litTaaMod, CullMode.Back, "SceneLitBackTaa", 1, true);
        sceneLitNoneTaaPipeline = buildLitPipelineAsync(litTaaMod, CullMode.None, "SceneLitNoneTaa", 1, true);

        var litBgB = new GpuBindings();
        litBgB.buffer(sceneUniformBuf);
        litBgB.buffer(instanceStorageBuf);
        sceneBindGroupBack = device.bindGroup(sceneLitBackPipeline, 0, litBgB);

        var litMsaaBgB = new GpuBindings();
        litMsaaBgB.buffer(sceneUniformBuf);
        litMsaaBgB.buffer(instanceStorageBuf);
        sceneMsaaBindGroupBack = device.bindGroup(sceneLitBackMsaaPipeline, 0, litMsaaBgB);

        var litTaaBgB = new GpuBindings();
        litTaaBgB.buffer(sceneUniformBuf);
        litTaaBgB.buffer(instanceStorageBuf);
        sceneTaaBindGroupBack = device.bindGroup(sceneLitBackTaaPipeline, 0, litTaaBgB);

        var litBgN = new GpuBindings();
        litBgN.buffer(sceneUniformBuf);
        litBgN.buffer(instanceStorageBuf);
        sceneBindGroupNone = device.bindGroup(sceneLitNonePipeline, 0, litBgN);

        var litMsaaBgN = new GpuBindings();
        litMsaaBgN.buffer(sceneUniformBuf);
        litMsaaBgN.buffer(instanceStorageBuf);
        sceneMsaaBindGroupNone = device.bindGroup(sceneLitNoneMsaaPipeline, 0, litMsaaBgN);

        var litTaaBgN = new GpuBindings();
        litTaaBgN.buffer(sceneUniformBuf);
        litTaaBgN.buffer(instanceStorageBuf);
        sceneTaaBindGroupNone = device.bindGroup(sceneLitNoneTaaPipeline, 0, litTaaBgN);

        // 4. Radial blur, SMAA 1x, and TSAA resolve post-process pipelines
        var blurMod = device.createShader(RadialBlurShader.WGSL);
        radialBlurPipeline = buildFullscreenPipelineAsync(blurMod, false, CompareFunction.Always, false, "RadialBlurPipeline");

        var smaaEdgeMod = device.createShader(SmaaShader.EDGE_WGSL);
        smaaEdgePipeline = buildFullscreenPipelineAsync(smaaEdgeMod, false, CompareFunction.Always, false, "SmaaEdgePipeline", TextureFormat.Rgba8unorm);

        var smaaWeightMod = device.createShader(SmaaShader.WEIGHT_WGSL);
        smaaWeightPipeline = buildFullscreenPipelineAsync(smaaWeightMod, false, CompareFunction.Always, false, "SmaaWeightPipeline", TextureFormat.Rgba8unorm);

        var smaaResolveMod = device.createShader(SmaaShader.RESOLVE_WGSL);
        smaaResolvePipeline = buildFullscreenPipelineAsync(smaaResolveMod, false, CompareFunction.Always, false, "SmaaResolvePipeline");

        var taaMod = device.createShader(TaaResolveShader.WGSL);
        taaResolvePipeline = buildFullscreenPipelineAsync(taaMod, false, CompareFunction.Always, false, "TaaResolvePipeline", TextureFormat.Rgba16float);
    }

    private function buildFullscreenPipelineAsync(
        mod:GpuShader,
        hasDepth:Bool,
        depthCompare:CompareFunction,
        depthWrite:Bool,
        label:String,
        ?targetFormat:TextureFormat,
        sampleCount:Int = 1,
        mrtVelocity:Bool = false
    ):GpuPipeline {
        var fmt = targetFormat != null ? targetFormat : surfaceFormat;
        var vs = new GpuVertexState(mod);
        vs.entryPoint("vs_main");

        var fs = new GpuFragmentState(mod);
        fs.entryPoint("fs_main");
        var ct = new GpuColorTargetState(fmt);
        ct.writeMask(ColorWrite.ALL);
        fs.addTargets(ct);
        if (mrtVelocity) {
            var ctVel = new GpuColorTargetState(TextureFormat.Rg16float);
            ctVel.writeMask(ColorWrite.ALL);
            fs.addTargets(ctVel);
        }

        var prim = new GpuPrimitiveState();
        prim.topology(PrimitiveTopology.TriangleList);
        prim.frontFace(FrontFace.Ccw);
        prim.cullMode(CullMode.None);

        var rpd = new GpuRenderPipelineDescriptor(vs);
        rpd.label(label);
        rpd.fragment(fs);
        rpd.primitive(prim);

        if (sampleCount > 1) {
            var ms = new GpuMultisampleState();
            ms.count(sampleCount);
            rpd.multisample(ms);
        }

        if (hasDepth) {
            var ds = new GpuDepthStencilState(TextureFormat.Depth24plusStencil8);
            ds.depthWriteEnabled(depthWrite);
            ds.depthCompare(depthCompare);
            rpd.depthStencil(ds);
        }

        return device.createRenderPipelineAsync(rpd).await();
    }

    private function buildLitPipelineAsync(mod:GpuShader, cull:CullMode, label:String, sampleCount:Int = 1, mrtVelocity:Bool = false):GpuPipeline {
        var vs = new GpuVertexState(mod);
        vs.entryPoint("vs_main");

        var vbl = new GpuVertexBufferLayout(Int64.ofInt(PrimitiveDesc.VERTEX_STRIDE_BYTES));
        vbl.stepMode(VertexStepMode.Vertex);
        vbl.addAttributes(new GpuVertexAttribute(VertexFormat.Float32x3, Int64.ofInt(0), 0));
        vbl.addAttributes(new GpuVertexAttribute(VertexFormat.Float32x3, Int64.ofInt(12), 1));
        vbl.addAttributes(new GpuVertexAttribute(VertexFormat.Float32x2, Int64.ofInt(24), 2));
        vs.addBuffers(vbl);

        var fs = new GpuFragmentState(mod);
        fs.entryPoint("fs_main");
        var ct = new GpuColorTargetState(surfaceFormat);
        ct.writeMask(ColorWrite.ALL);
        fs.addTargets(ct);
        if (mrtVelocity) {
            var ctVel = new GpuColorTargetState(TextureFormat.Rg16float);
            ctVel.writeMask(ColorWrite.ALL);
            fs.addTargets(ctVel);
        }

        var prim = new GpuPrimitiveState();
        prim.topology(PrimitiveTopology.TriangleList);
        prim.frontFace(FrontFace.Ccw);
        prim.cullMode(cull);

        var ds = new GpuDepthStencilState(TextureFormat.Depth24plusStencil8);
        ds.depthWriteEnabled(true);
        ds.depthCompare(CompareFunction.Less);

        var rpd = new GpuRenderPipelineDescriptor(vs);
        rpd.label(label);
        rpd.fragment(fs);
        rpd.primitive(prim);
        rpd.depthStencil(ds);

        if (sampleCount > 1) {
            var ms = new GpuMultisampleState();
            ms.count(sampleCount);
            rpd.multisample(ms);
        }

        return device.createRenderPipelineAsync(rpd).await();
    }

    private function ensureRenderTargets():Void {
        var sw = Std.int(Math.max(1.0, Math.min(4096.0, Math.round(physicalWidth * renderScale))));
        var sh = Std.int(Math.max(1.0, Math.min(4096.0, Math.round(physicalHeight * renderScale))));
        if (sw == targetWidth && sh == targetHeight && offscreenColorTex.valid() && depthTex.valid()
            && msaaColorTex.valid() && msaaDepthTex.valid()
            && smaaEdgeTex.valid() && smaaBlendTex.valid()
            && taaVelocityTex.valid() && taaHistoryTex0.valid() && taaHistoryTex1.valid()) {
            return;
        }

        if (offscreenColorTex.valid()) offscreenColorTex.destroy();
        if (depthTex.valid()) depthTex.destroy();
        if (msaaColorTex.valid()) msaaColorTex.destroy();
        if (msaaDepthTex.valid()) msaaDepthTex.destroy();
        if (smaaEdgeTex.valid()) smaaEdgeTex.destroy();
        if (smaaBlendTex.valid()) smaaBlendTex.destroy();
        if (taaVelocityTex.valid()) taaVelocityTex.destroy();
        if (taaHistoryTex0.valid()) taaHistoryTex0.destroy();
        if (taaHistoryTex1.valid()) taaHistoryTex1.destroy();

        taaNeedsReset = true;
        taaHistoryValid = false;
        targetWidth = sw;
        targetHeight = sh;

        var cExt = new GpuExtent3D(sw);
        cExt.height(sh);
        cExt.depthOrArrayLayers(1);

        var cDesc = new GpuTextureDescriptor(cExt, surfaceFormat, TextureUsage.RENDER_ATTACHMENT | TextureUsage.TEXTURE_BINDING);
        cDesc.label("OffscreenSceneColor");
        offscreenColorTex = device.texture(cDesc);
        offscreenColorView = offscreenColorTex.createView(new GpuTextureViewDescriptor());

        var msaaCDesc = new GpuTextureDescriptor(cExt, surfaceFormat, TextureUsage.RENDER_ATTACHMENT);
        msaaCDesc.label("MsaaSceneColor4x");
        msaaCDesc.sampleCount(4);
        msaaColorTex = device.texture(msaaCDesc);
        msaaColorView = msaaColorTex.createView(new GpuTextureViewDescriptor());

        var texUsage = TextureUsage.RENDER_ATTACHMENT | TextureUsage.TEXTURE_BINDING;
        var edgeDesc = new GpuTextureDescriptor(cExt, TextureFormat.Rgba8unorm, texUsage);
        edgeDesc.label("SmaaEdges");
        smaaEdgeTex = device.texture(edgeDesc);
        smaaEdgeView = smaaEdgeTex.createView(new GpuTextureViewDescriptor());

        var blendDesc = new GpuTextureDescriptor(cExt, TextureFormat.Rgba8unorm, texUsage);
        blendDesc.label("SmaaBlendWeights");
        smaaBlendTex = device.texture(blendDesc);
        smaaBlendView = smaaBlendTex.createView(new GpuTextureViewDescriptor());

        var velDesc = new GpuTextureDescriptor(cExt, TextureFormat.Rg16float, texUsage);
        velDesc.label("TaaVelocity");
        taaVelocityTex = device.texture(velDesc);
        taaVelocityView = taaVelocityTex.createView(new GpuTextureViewDescriptor());

        var hist0Desc = new GpuTextureDescriptor(cExt, TextureFormat.Rgba16float, texUsage);
        hist0Desc.label("TaaHistory0");
        taaHistoryTex0 = device.texture(hist0Desc);
        taaHistoryView0 = taaHistoryTex0.createView(new GpuTextureViewDescriptor());

        var hist1Desc = new GpuTextureDescriptor(cExt, TextureFormat.Rgba16float, texUsage);
        hist1Desc.label("TaaHistory1");
        taaHistoryTex1 = device.texture(hist1Desc);
        taaHistoryView1 = taaHistoryTex1.createView(new GpuTextureViewDescriptor());

        var dExt = new GpuExtent3D(sw);
        dExt.height(sh);
        dExt.depthOrArrayLayers(1);
        var dDesc = new GpuTextureDescriptor(dExt, TextureFormat.Depth24plusStencil8, TextureUsage.RENDER_ATTACHMENT);
        dDesc.label("SceneDepth");
        depthTex = device.texture(dDesc);
        depthView = depthTex.createView(new GpuTextureViewDescriptor());

        var msaaDDesc = new GpuTextureDescriptor(dExt, TextureFormat.Depth24plusStencil8, TextureUsage.RENDER_ATTACHMENT);
        msaaDDesc.label("MsaaSceneDepth4x");
        msaaDDesc.sampleCount(4);
        msaaDepthTex = device.texture(msaaDDesc);
        msaaDepthView = msaaDepthTex.createView(new GpuTextureViewDescriptor());

        var bBg = new GpuBindings();
        bBg.buffer(blurUniformBuf);
        bBg.texture(offscreenColorView);
        bBg.sampler(blurSampler);
        blurBindGroup = device.bindGroup(radialBlurPipeline, 0, bBg);

        var eBg = new GpuBindings();
        eBg.buffer(blurUniformBuf);
        eBg.texture(offscreenColorView);
        eBg.sampler(blurSampler);
        smaaEdgeBindGroup = device.bindGroup(smaaEdgePipeline, 0, eBg);

        var wBg = new GpuBindings();
        wBg.buffer(blurUniformBuf);
        wBg.texture(smaaEdgeView);
        smaaWeightBindGroup = device.bindGroup(smaaWeightPipeline, 0, wBg);

        var rBg = new GpuBindings();
        rBg.buffer(blurUniformBuf);
        rBg.texture(offscreenColorView);
        rBg.texture(smaaBlendView);
        rBg.sampler(blurSampler);
        smaaResolveBindGroup = device.bindGroup(smaaResolvePipeline, 0, rBg);

        var tBg0 = new GpuBindings();
        tBg0.buffer(taaUniformBuf);
        tBg0.texture(offscreenColorView);
        tBg0.texture(taaHistoryView1);
        tBg0.texture(taaVelocityView);
        tBg0.sampler(blurSampler);
        taaResolveBindGroup0 = device.bindGroup(taaResolvePipeline, 0, tBg0);

        var tBg1 = new GpuBindings();
        tBg1.buffer(taaUniformBuf);
        tBg1.texture(offscreenColorView);
        tBg1.texture(taaHistoryView0);
        tBg1.texture(taaVelocityView);
        tBg1.sampler(blurSampler);
        taaResolveBindGroup1 = device.bindGroup(taaResolvePipeline, 0, tBg1);

        var tpBg0 = new GpuBindings();
        tpBg0.buffer(blurUniformBuf);
        tpBg0.texture(taaHistoryView0);
        tpBg0.sampler(blurSampler);
        taaPostBindGroup0 = device.bindGroup(radialBlurPipeline, 0, tpBg0);

        var tpBg1 = new GpuBindings();
        tpBg1.buffer(blurUniformBuf);
        tpBg1.texture(taaHistoryView1);
        tpBg1.sampler(blurSampler);
        taaPostBindGroup1 = device.bindGroup(radialBlurPipeline, 0, tpBg1);
    }

    /**
     * Uploads spline waypoints and dispatches TrackComputeShader to build roadbed,
     * asphalt, and guardrails directly into GPU vertex, index, and indirect buffers.
     */
    public function dispatchTrackCompute(
        waypoints:Array<Vec3>,
        roadHalfWidth:Float,
        bedExtraWidth:Float,
        roadLift:Float,
        railHeight:Float
    ):Void {
        if (!initialized || waypoints == null || waypoints.length < 3) return;
        var n = waypoints.length;
        trackPointCount = n;

        if (n > trackCapacityPts || !trackVertBuf.valid()) {
            if (trackParamBuf.valid()) trackParamBuf.destroy();
            if (trackSplineBuf.valid()) trackSplineBuf.destroy();
            if (trackVertBuf.valid()) trackVertBuf.destroy();
            if (trackIdxBuf.valid()) trackIdxBuf.destroy();
            if (trackIndirectBuf.valid()) trackIndirectBuf.destroy();

            trackCapacityPts = n;
            trackParamBuf = createBufferWithUsage(32, BufferUsage.UNIFORM | BufferUsage.COPY_DST, "TrackParams");
            trackSplineBuf = createBufferWithUsage(n * 16, BufferUsage.STORAGE | BufferUsage.COPY_DST, "TrackSplines");
            trackVertBuf = createBufferWithUsage(n * 8 * 32, BufferUsage.STORAGE | BufferUsage.VERTEX | BufferUsage.COPY_DST, "TrackVertices");
            trackIdxBuf = createBufferWithUsage(n * 36 * 4, BufferUsage.STORAGE | BufferUsage.INDEX | BufferUsage.COPY_DST, "TrackIndices");
            trackIndirectBuf = createBufferWithUsage(4 * 20, BufferUsage.STORAGE | BufferUsage.INDIRECT | BufferUsage.COPY_DST, "TrackIndirectArgs");

            var bg = new GpuBindings();
            bg.buffer(trackParamBuf);
            bg.buffer(trackSplineBuf);
            bg.buffer(trackVertBuf);
            bg.buffer(trackIdxBuf);
            bg.buffer(trackIndirectBuf);
            trackComputeBG = device.bindGroup(trackComputePipeline, 0, bg);
        }

        // Pack TrackParams (32 bytes)
        var pBytes = Bytes.alloc(32);
        pBytes.setInt32(0, n);
        pBytes.setInt32(4, 0);
        pBytes.setFloat(8, roadHalfWidth);
        pBytes.setFloat(12, roadHalfWidth + bedExtraWidth);
        pBytes.setFloat(16, roadLift);
        pBytes.setFloat(20, 0.30);
        pBytes.setFloat(24, railHeight);
        pBytes.setFloat(28, 0.05);
        queue.writeBuffer(trackParamBuf, Int64.ofInt(0), pBytes, 32);

        // Pack splines with cumulative arc length in .w
        var sBytes = Bytes.alloc(n * 16);
        var arcLen = 0.0;
        for (i in 0...n) {
            var p = waypoints[i];
            if (i > 0) {
                arcLen += p.distance(waypoints[i - 1]);
            }
            var off = i * 16;
            sBytes.setFloat(off,      p.x);
            sBytes.setFloat(off + 4,  p.y);
            sBytes.setFloat(off + 8,  p.z);
            sBytes.setFloat(off + 12, arcLen);
        }
        queue.writeBuffer(trackSplineBuf, Int64.ofInt(0), sBytes, n * 16);

        var enc = device.encoder();
        var groups = Std.int((n + 63) / 64);
        enc.compute(trackComputePipeline, trackComputeBG, groups, 1, 1);
        enc.submit(queue);
        enc.destroy();
        trackDispatched = true;
    }

    public function clearTrack():Void {
        trackDispatched = false;
        trackPointCount = 0;
    }

    private function getOrUploadPrimitive(prim:PrimitiveDesc):GpuPrimEntry {
        var existing = primCache.get(prim.gpuId);
        if (existing != null && !prim.dirty) return existing;

        prim.packGpuData();
        if (existing != null) {
            existing.vb.destroy();
            existing.ib.destroy();
        }

        var vLen = prim.vertexBytes != null ? prim.vertexBytes.length : 32;
        var iLen = prim.indexBytes != null ? prim.indexBytes.length : 4;
        var vb = createBufferWithUsage(vLen, BufferUsage.VERTEX | BufferUsage.COPY_DST, "PrimVB");
        var ib = createBufferWithUsage(iLen, BufferUsage.INDEX | BufferUsage.COPY_DST, "PrimIB");
        if (prim.vertexBytes != null && vLen > 0) {
            queue.writeBuffer(vb, Int64.ofInt(0), prim.vertexBytes, vLen);
        }
        if (prim.indexBytes != null && iLen > 0) {
            queue.writeBuffer(ib, Int64.ofInt(0), prim.indexBytes, iLen);
        }

        var entry:GpuPrimEntry = { vb: vb, ib: ib, indexCount: prim.indexCount };
        primCache.set(prim.gpuId, entry);
        return entry;
    }

    private function collectMeshes(node:Object3D, out:Array<MeshNode>):Void {
        if (node == null || !node.visible) return;
        if (Std.isOfType(node, MeshNode)) {
            var mesh:MeshNode = cast node;
            if (!mesh.material.isSkybox && mesh.primitive != null && mesh.primitive.points.length > 0) {
                out.push(mesh);
            }
        }
        for (c in node.children) {
            collectMeshes(c, out);
        }
    }

    /**
     * Renders the complete 3D world + post-process radial blur to the swapchain surface.
     */
    public function renderFrame(
        s3d:Scene3D,
        skyTopHex:Int = 0x1052B8,
        skyHorizonHex:Int = 0x7AC2F2,
        skyGroundHex:Int = 0x141A24,
        trackActive:Bool = false,
        post:Null<PostProcessRenderer> = null
    ):Void {
        if (!initialized || deviceLost || s3d == null) return;

        ensureRenderTargets();

        var swapView = surface.acquire();
        if (!swapView.valid()) return;

        var isTaa = aaModeCode > 1.5 && aaModeCode < 2.5;
        var isMsaa = aaModeCode > 3.5;

        var jitterNdcX = 0.0;
        var jitterNdcY = 0.0;
        var taaPeriod = aaStrength < 0.58 ? 8 : (aaStrength >= 0.86 ? 32 : 16);
        if (isTaa && targetWidth > 0 && targetHeight > 0) {
            var phase = (taaFrameIndex % taaPeriod) + 1;
            var jxPx = halton(phase, 2) - 0.5;
            var jyPx = halton(phase, 3) - 0.5;
            jitterNdcX = (jxPx * 2.0) / targetWidth;
            jitterNdcY = -(jyPx * 2.0) / targetHeight;
        }

        var aspect = physicalHeight > 0 ? (physicalWidth / physicalHeight) : (16.0 / 9.0);
        s3d.camera.updateMatrices(aspect, jitterNdcX, jitterNdcY);
        s3d.updateWorldTransform(null);

        // 1. Write SkyUniforms
        var cam = s3d.camera;
        if (!cam.hasPrevFrame || cam.pos.distanceSq(cam.prevCamPos) > 225.0) {
            taaNeedsReset = true;
            cam.prevViewProjMat.load(cam.unjitteredViewProjMat);
        }

        var fwd = cam.target.sub(cam.pos);
        fwd.normalize();
        var right = fwd.cross(cam.up);
        if (right.lengthSq() < 1e-8) right.set(1.0, 0.0, 0.0, 0.0) else right.normalize();
        var camUp = right.cross(fwd);
        var tanHalf = Math.tan((cam.fovY * Math.PI) / 360.0);

        var sunDirToward = new Vec3(-0.4, -0.35, 0.85, 0.0);
        var sunColor = new Vec3(1.0, 0.96, 0.88, 1.0);
        var specStrength = 1.0;
        if (s3d.dirLights.length > 0) {
            var dl = s3d.dirLights[0];
            sunDirToward.set(-dl.direction.x, -dl.direction.y, -dl.direction.z, 0.0);
            sunDirToward.normalize();
            sunColor.load(dl.color);
            specStrength = dl.enableSpecular ? 1.0 : 0.0;
        }

        SoABuffer.writeVec3Std140(skyBytes, 0, fwd.x, fwd.y, fwd.z, tanHalf);
        SoABuffer.writeVec3Std140(skyBytes, 16, right.x, right.y, right.z, aspect);
        SoABuffer.writeVec3Std140(skyBytes, 32, camUp.x, camUp.y, camUp.z, 0.0);
        writeHexColorVec4(skyBytes, 48, skyTopHex, 1.0);
        writeHexColorVec4(skyBytes, 64, skyHorizonHex, 1.0);
        writeHexColorVec4(skyBytes, 80, skyGroundHex, 1.0);
        SoABuffer.writeVec3Std140(skyBytes, 96, sunDirToward.x, sunDirToward.y, sunDirToward.z, 0.0);
        SoABuffer.writeVec4Std140(skyBytes, 112, jitterNdcX, jitterNdcY, isTaa ? 1.0 : 0.0, 0.0);
        cam.unjitteredViewProjMat.writeStd140(skyBytes, 128);
        cam.prevViewProjMat.writeStd140(skyBytes, 192);
        queue.writeBuffer(skyUniformBuf, Int64.ofInt(0), skyBytes, SkyShader.UNIFORM_BYTES);

        // 2. Write SceneUniforms
        cam.viewProjMat.writeStd140(sceneBytes, 0);
        cam.unjitteredViewProjMat.writeStd140(sceneBytes, 64);
        cam.prevViewProjMat.writeStd140(sceneBytes, 128);
        SoABuffer.writeVec3Std140(sceneBytes, 192, cam.pos.x, cam.pos.y, cam.pos.z, 1.0);
        SoABuffer.writeVec3Std140(sceneBytes, 208, sunDirToward.x, sunDirToward.y, sunDirToward.z, specStrength);
        SoABuffer.writeVec4Std140(sceneBytes, 224, sunColor.x, sunColor.y, sunColor.z, 1.0);

        var fillDir = new Vec3(0.45, 0.55, 0.70, 0.0).normalized();
        var fillColor = new Vec3(0.22, 0.28, 0.38, 1.0);
        if (s3d.dirLights.length > 1) {
            var fl = s3d.dirLights[1];
            fillDir.set(-fl.direction.x, -fl.direction.y, -fl.direction.z, 0.0);
            fillDir.normalize();
            fillColor.load(fl.color);
        }
        SoABuffer.writeVec3Std140(sceneBytes, 240, fillDir.x, fillDir.y, fillDir.z, 0.0);
        SoABuffer.writeVec4Std140(sceneBytes, 256, fillColor.x, fillColor.y, fillColor.z, 1.0);

        var amb = s3d.lightSystem.ambientLight;
        SoABuffer.writeVec4Std140(sceneBytes, 272, amb.x, amb.y, amb.z, 1.0);
        writeHexColorVec4(sceneBytes, 288, skyHorizonHex, 0.00055);
        SoABuffer.writeVec4Std140(sceneBytes, 304, reflScaleParam, shadowStrengthParam, surfaceDetailParam, lightScaleParam);
        SoABuffer.writeVec4Std140(sceneBytes, 320, jitterNdcX, jitterNdcY, isTaa ? 1.0 : 0.0, 0.0);
        queue.writeBuffer(sceneUniformBuf, Int64.ofInt(0), sceneBytes, SceneLitShader.SCENE_UNIFORM_BYTES);

        // 3. Populate SoA instances: slot 0 reserved for GPU-computed Track indirect draws (`firstInstance = 0`)
        soa.reset();
        var idMat = new Mat4();
        pushHexInstance(idMat, 0x282D35, 0.0, 0.78, 0.0, 1.0); // slot 0: GPU track ribbons (roadbed/asphalt/rails via uv.x)
        pushHexInstance(idMat, 0x282D35, 0.0, 0.78, 0.0, 1.0); // slot 1: reserved
        pushHexInstance(idMat, 0x9EACB8, 0.0, 0.32, 0.0, 2.0); // slot 2: reserved
        pushHexInstance(idMat, 0x9EACB8, 0.0, 0.32, 0.0, 2.0); // slot 3: reserved

        // Gather scene meshes and group into contiguous instanced draw batches
        var meshes:Array<MeshNode> = [];
        collectMeshes(s3d, meshes);

        var backMap = new Map<Int, Array<MeshNode>>();
        var noneMap = new Map<Int, Array<MeshNode>>();
        var backOrder:Array<Int> = [];
        var noneOrder:Array<Int> = [];

        for (m in meshes) {
            var pid = m.primitive.gpuId;
            if (m.material.culling == CullModeDesc.None) {
                var arr = noneMap.get(pid);
                if (arr == null) {
                    arr = [];
                    noneMap.set(pid, arr);
                    noneOrder.push(pid);
                }
                arr.push(m);
            } else {
                var arr = backMap.get(pid);
                if (arr == null) {
                    arr = [];
                    backMap.set(pid, arr);
                    backOrder.push(pid);
                }
                arr.push(m);
            }
        }

        var batches:Array<RenderBatch> = [];
        for (pid in backOrder) {
            pushMeshGroup(backMap.get(pid), false, batches);
        }
        for (pid in noneOrder) {
            pushMeshGroup(noneMap.get(pid), true, batches);
        }

        var byteLen = soa.packToBytes();
        if (byteLen > 0) {
            queue.writeBuffer(instanceStorageBuf, Int64.ofInt(0), soa.stagingBytes, byteLen);
        }

        // 4. Write BlurUniforms (radial blur + active anti-aliasing pass)
        var blurInt = post != null ? post.blurShader.blurIntensity : 0.0;
        var bx = post != null ? post.blurShader.blurOrigin.x : 0.5;
        var by = post != null ? post.blurShader.blurOrigin.y : 0.5;
        blurBytes.setFloat(0, blurInt);
        blurBytes.setFloat(4, bx);
        blurBytes.setFloat(8, by);
        blurBytes.setFloat(12, aaModeCode);
        blurBytes.setFloat(16, aaStrength);
        blurBytes.setFloat(20, targetWidth > 0 ? (1.0 / targetWidth) : (1.0 / 1280.0));
        blurBytes.setFloat(24, targetHeight > 0 ? (1.0 / targetHeight) : (1.0 / 720.0));
        blurBytes.setFloat(28, 0.0);
        queue.writeBuffer(blurUniformBuf, Int64.ofInt(0), blurBytes, RadialBlurShader.UNIFORM_BYTES);

        if (isTaa) {
            var taaAlpha = aaStrength < 0.58 ? 0.14 : (aaStrength >= 0.86 ? 0.075 : 0.10);
            var taaGamma = aaStrength < 0.58 ? 1.05 : (aaStrength >= 0.86 ? 1.25 : 1.15);
            taaBytes.setFloat(0, targetWidth > 0 ? (1.0 / targetWidth) : (1.0 / 1280.0));
            taaBytes.setFloat(4, targetHeight > 0 ? (1.0 / targetHeight) : (1.0 / 720.0));
            taaBytes.setFloat(8, taaAlpha);
            taaBytes.setFloat(12, taaGamma);
            taaBytes.setFloat(16, (taaNeedsReset || !taaHistoryValid) ? 1.0 : 0.0);
            taaBytes.setFloat(20, 0.0);
            taaBytes.setFloat(24, 0.0);
            taaBytes.setFloat(28, 0.0);
            queue.writeBuffer(taaUniformBuf, Int64.ofInt(0), taaBytes, TaaResolveShader.UNIFORM_BYTES);
        }

        // 5. Encode render passes
        var enc = device.encoder();

        // Pass 1: 3D Scene -> offscreenColorView (1x), MSAA (4x->resolve), or TAA MRT (color + velocity)
        if (isMsaa || isTaa) {
            var passDesc = new GpuRenderPassDescriptor();
            var colorAtt = new GpuRenderPassColorAttachment(LoadOp.Clear, isMsaa ? StoreOp.Discard : StoreOp.Store);
            colorAtt.viewTextureView(isMsaa ? msaaColorView : offscreenColorView);
            if (isMsaa) {
                colorAtt.resolveTargetTextureView(offscreenColorView);
            }
            colorAtt.clearValue(new GpuColor(0.06, 0.09, 0.14, 1.0));
            passDesc.addColorAttachments(colorAtt);

            if (isTaa) {
                var velAtt = new GpuRenderPassColorAttachment(LoadOp.Clear, StoreOp.Store);
                velAtt.viewTextureView(taaVelocityView);
                velAtt.clearValue(new GpuColor(0.0, 0.0, 0.0, 0.0));
                passDesc.addColorAttachments(velAtt);
            }

            var depthAtt = new GpuRenderPassDepthStencilAttachment();
            depthAtt.viewTextureView(isMsaa ? msaaDepthView : depthView);
            depthAtt.depthLoadOp(LoadOp.Clear);
            depthAtt.depthStoreOp(StoreOp.Discard);
            depthAtt.depthClearValue(1.0);
            depthAtt.stencilLoadOp(LoadOp.Clear);
            depthAtt.stencilStoreOp(StoreOp.Discard);
            depthAtt.stencilClearValue(0);
            passDesc.depthStencilAttachment(depthAtt);
            enc.beginRenderPass(passDesc);
        } else {
            enc.passReset();
            enc.passColour(offscreenColorView, 0.06, 0.09, 0.14, 1.0);
            enc.passDepth(depthView, 1.0, 0);
            enc.passBegin();
        }
        enc.renderSetViewport(0, 0, targetWidth, targetHeight, 0.0, 1.0);
        enc.renderSetScissorRect(0, 0, targetWidth, targetHeight);

        var activeSkyPipe = isMsaa ? skyMsaaPipeline : (isTaa ? skyTaaPipeline : skyPipeline);
        var activeSkyBg = isMsaa ? skyMsaaBindGroup : (isTaa ? skyTaaBindGroup : skyBindGroup);
        var activeBackPipe = isMsaa ? sceneLitBackMsaaPipeline : (isTaa ? sceneLitBackTaaPipeline : sceneLitBackPipeline);
        var activeBackBg = isMsaa ? sceneMsaaBindGroupBack : (isTaa ? sceneTaaBindGroupBack : sceneBindGroupBack);
        var activeNonePipe = isMsaa ? sceneLitNoneMsaaPipeline : (isTaa ? sceneLitNoneTaaPipeline : sceneLitNonePipeline);
        var activeNoneBg = isMsaa ? sceneMsaaBindGroupNone : (isTaa ? sceneTaaBindGroupNone : sceneBindGroupNone);

        // Sky dome background
        enc.renderSetPipeline(activeSkyPipe);
        enc.renderSetBindGroup(0, activeSkyBg);
        enc.renderDraw(3, 1);

        // GPU-computed Track ribbons via Indirect draw
        if (trackActive && trackDispatched && trackPointCount >= 3 && trackVertBuf.valid()) {
            enc.renderSetPipeline(activeBackPipe);
            enc.renderSetBindGroup(0, activeBackBg);
            enc.renderSetVertexBuffer(0, trackVertBuf);
            enc.renderSetIndexBuffer(trackIdxBuf, IndexFormat.Uint32);
            enc.renderDrawIndexedIndirect(trackIndirectBuf, Int64.ofInt(0));
            enc.renderDrawIndexedIndirect(trackIndirectBuf, Int64.ofInt(20));

            enc.renderSetPipeline(activeNonePipe);
            enc.renderSetBindGroup(0, activeNoneBg);
            enc.renderSetVertexBuffer(0, trackVertBuf);
            enc.renderSetIndexBuffer(trackIdxBuf, IndexFormat.Uint32);
            enc.renderDrawIndexedIndirect(trackIndirectBuf, Int64.ofInt(40));
            enc.renderDrawIndexedIndirect(trackIndirectBuf, Int64.ofInt(60));
        }

        // Dynamic back-face culled batches
        var curCullNone = false;
        var hasSetPipeline = false;
        for (b in batches) {
            if (!hasSetPipeline || curCullNone != b.cullNone) {
                curCullNone = b.cullNone;
                hasSetPipeline = true;
                if (curCullNone) {
                    enc.renderSetPipeline(activeNonePipe);
                    enc.renderSetBindGroup(0, activeNoneBg);
                } else {
                    enc.renderSetPipeline(activeBackPipe);
                    enc.renderSetBindGroup(0, activeBackBg);
                }
            }
            var entry = getOrUploadPrimitive(b.prim);
            if (entry.indexCount > 0) {
                enc.renderSetVertexBuffer(0, entry.vb);
                enc.renderSetIndexBuffer(entry.ib, IndexFormat.Uint32);
                enc.renderDrawIndexedRange(entry.indexCount, b.instanceCount, 0, 0, b.firstInstance);
            }
        }
        enc.renderEnd();

        // Pass 2: Fullscreen Post-Process (TSAA Ping-Pong, SMAA 3-Pass, or FXAA/RadialBlur -> Swapchain)
        if (isTaa) {
            var histWriteView = taaWriteIdx == 0 ? taaHistoryView0 : taaHistoryView1;
            var taaBg = taaWriteIdx == 0 ? taaResolveBindGroup0 : taaResolveBindGroup1;
            var postBg = taaWriteIdx == 0 ? taaPostBindGroup0 : taaPostBindGroup1;
            encodeFullscreenPass(enc, histWriteView, 0.0, 0.0, 0.0, 1.0, targetWidth, targetHeight, taaResolvePipeline, taaBg);
            encodeFullscreenPass(enc, swapView, 0.0, 0.0, 0.0, 1.0, physicalWidth, physicalHeight, radialBlurPipeline, postBg);
            taaWriteIdx = 1 - taaWriteIdx;
            taaHistoryValid = true;
            taaNeedsReset = false;
            taaFrameIndex++;
        } else if (aaModeCode > 2.5 && aaModeCode < 3.5) {
            encodeFullscreenPass(enc, smaaEdgeView, 0.0, 0.0, 0.0, 0.0, targetWidth, targetHeight, smaaEdgePipeline, smaaEdgeBindGroup);
            encodeFullscreenPass(enc, smaaBlendView, 0.0, 0.0, 0.0, 0.0, targetWidth, targetHeight, smaaWeightPipeline, smaaWeightBindGroup);
            encodeFullscreenPass(enc, swapView, 0.0, 0.0, 0.0, 1.0, physicalWidth, physicalHeight, smaaResolvePipeline, smaaResolveBindGroup);
        } else {
            encodeFullscreenPass(enc, swapView, 0.0, 0.0, 0.0, 1.0, physicalWidth, physicalHeight, radialBlurPipeline, blurBindGroup);
        }

        enc.submit(queue);
        enc.destroy();
        queue.presentSurface(surface);

        // Save camera history matrices for next frame's unjittered temporal motion vectors
        cam.prevViewProjMat.load(cam.unjitteredViewProjMat);
        cam.prevCamPos.load(cam.pos);
        cam.hasPrevFrame = true;
    }

    private static function halton(index:Int, base:Int):Float {
        var f = 1.0;
        var r = 0.0;
        var i = index;
        while (i > 0) {
            f = f / base;
            r = r + f * (i % base);
            i = Std.int(i / base);
        }
        return r;
    }

    private inline function encodeFullscreenPass(
        enc:GpuEncoder,
        colorView:GpuTextureView,
        clearR:Float,
        clearG:Float,
        clearB:Float,
        clearA:Float,
        vpW:Int,
        vpH:Int,
        pipeline:GpuPipeline,
        bindGroup:GpuBindGroup
    ):Void {
        enc.passReset();
        enc.passColour(colorView, clearR, clearG, clearB, clearA);
        enc.passBegin();
        enc.renderSetViewport(0, 0, vpW, vpH, 0.0, 1.0);
        enc.renderSetScissorRect(0, 0, vpW, vpH);
        enc.renderSetPipeline(pipeline);
        enc.renderSetBindGroup(0, bindGroup);
        enc.renderDraw(3, 1);
        enc.renderEnd();
    }

    private function pushMeshGroup(list:Array<MeshNode>, cullNone:Bool, outBatches:Array<RenderBatch>):Void {
        if (list == null || list.length == 0) return;
        var firstIdx = soa.count;
        var pushed = 0;
        for (m in list) {
            if (soa.count >= MAX_INSTANCES) break;
            var mat = m.material;
            var prevMat = (m.hasPrevWorldMatrix && !taaNeedsReset) ? m.prevWorldMatrix : m.worldMatrix;
            soa.pushInstance(
                m.worldMatrix,
                mat.color.x, mat.color.y, mat.color.z, mat.color.w,
                mat.emissive,
                mat.roughness,
                mat.gridScale,
                mat.flags,
                prevMat
            );
            m.prevWorldMatrix.load(m.worldMatrix);
            m.hasPrevWorldMatrix = true;
            pushed++;
        }
        if (pushed > 0) {
            outBatches.push({
                prim: list[0].primitive,
                cullNone: cullNone,
                firstInstance: firstIdx,
                instanceCount: pushed
            });
        }
    }

    private inline function pushHexInstance(mat:Mat4, hex:Int, emissive:Float, roughness:Float, gridScale:Float, flags:Float):Void {
        var r = ((hex >> 16) & 0xFF) / 255.0;
        var g = ((hex >> 8) & 0xFF) / 255.0;
        var b = (hex & 0xFF) / 255.0;
        soa.pushInstance(mat, r, g, b, 1.0, emissive, roughness, gridScale, flags);
    }

    private static inline function writeHexColorVec4(bytes:Bytes, offset:Int, hex:Int, alpha:Float):Void {
        bytes.setFloat(offset,      ((hex >> 16) & 0xFF) / 255.0);
        bytes.setFloat(offset + 4,  ((hex >> 8) & 0xFF) / 255.0);
        bytes.setFloat(offset + 8,  (hex & 0xFF) / 255.0);
        bytes.setFloat(offset + 12, alpha);
    }

    public function dispose():Void {
        for (entry in primCache) {
            entry.vb.destroy();
            entry.ib.destroy();
        }
        primCache.clear();
        if (offscreenColorTex.valid()) offscreenColorTex.destroy();
        if (depthTex.valid()) depthTex.destroy();
        if (msaaColorTex.valid()) msaaColorTex.destroy();
        if (msaaDepthTex.valid()) msaaDepthTex.destroy();
        if (smaaEdgeTex.valid()) smaaEdgeTex.destroy();
        if (smaaBlendTex.valid()) smaaBlendTex.destroy();
        if (taaVelocityTex.valid()) taaVelocityTex.destroy();
        if (taaHistoryTex0.valid()) taaHistoryTex0.destroy();
        if (taaHistoryTex1.valid()) taaHistoryTex1.destroy();
        if (trackParamBuf.valid()) trackParamBuf.destroy();
        if (trackSplineBuf.valid()) trackSplineBuf.destroy();
        if (trackVertBuf.valid()) trackVertBuf.destroy();
        if (trackIdxBuf.valid()) trackIdxBuf.destroy();
        if (trackIndirectBuf.valid()) trackIndirectBuf.destroy();
        if (skyUniformBuf.valid()) skyUniformBuf.destroy();
        if (sceneUniformBuf.valid()) sceneUniformBuf.destroy();
        if (instanceStorageBuf.valid()) instanceStorageBuf.destroy();
        if (blurUniformBuf.valid()) blurUniformBuf.destroy();
        if (taaUniformBuf.valid()) taaUniformBuf.destroy();
        if (surface.valid()) surface.destroy();
        if (device.valid()) device.destroy();
        if (instance.valid()) instance.destroy();
        initialized = false;
    }
}
