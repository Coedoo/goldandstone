package renderer_d3d11

import dm "../../dmcore"

import d3d11 "vendor:directx/d3d11"
import dxgi "vendor:directx/dxgi"
import d3d "vendor:directx/d3d_compiler"

import sdl "vendor:sdl2"

import "core:fmt"
import "core:c/libc"
import "core:mem"

// @NOTE @TODO: Move it to render Context...?
textures: dm.ResourcePool(Texture_d3d)
batches: dm.ResourcePool(RectBatch_D3D)
shaders: dm.ResourcePool(Shader_d3d)


//////////////////////
/// RENDER CONTEXT
//////////////////////

RenderContext_d3d :: struct {
    using base: dm.RenderContext,

    device: ^d3d11.IDevice,
    deviceContext: ^d3d11.IDeviceContext,
    swapchain: ^dxgi.ISwapChain1,

    rasterizerState: ^d3d11.IRasterizerState,

    framebuffer: ^d3d11.ITexture2D,
    framebufferView: ^d3d11.IRenderTargetView,

    blendState: ^d3d11.IBlendState,

    cameraConstBuff: ^d3d11.IBuffer,
}

CreateRenderContext :: proc(window: ^sdl.Window) -> ^dm.RenderContext {

    window_system_info: sdl.SysWMinfo

    // @TODO:
    // Probably don't want using sdl here
    sdl.GetVersion(&window_system_info.version)
    sdl.GetWindowWMInfo(window, &window_system_info)
    assert(window_system_info.subsystem == .WINDOWS)

    nativeWnd := dxgi.HWND(window_system_info.info.win.window)

    featureLevels := [?]d3d11.FEATURE_LEVEL{._11_0}

    device: ^d3d11.IDevice
    deviceContext: ^d3d11.IDeviceContext
    swapchain: ^dxgi.ISwapChain1

    d3d11.CreateDevice(nil, .HARDWARE, nil, {.BGRA_SUPPORT}, &featureLevels[0], len(featureLevels),
                       d3d11.SDK_VERSION, &device, nil, &deviceContext)
    
    // device: ^d3d11.IDevice
    // baseDevice->QueryInterface(d3d11.IDevice_UUID, (^rawptr)(&device))

    // deviceContext: ^d3d11.IDeviceContext
    // baseDeviceContext->QueryInterface(d3d11.IDeviceContext_UUID, (^rawptr)(&deviceContext))

    dxgiDevice: ^dxgi.IDevice
    device->QueryInterface(dxgi.IDevice_UUID, (^rawptr)(&dxgiDevice))

    dxgiAdapter: ^dxgi.IAdapter
    dxgiDevice->GetAdapter(&dxgiAdapter)

    dxgiFactory: ^dxgi.IFactory2
    dxgiAdapter->GetParent(dxgi.IFactory2_UUID, (^rawptr)(&dxgiFactory))

    defer dxgiFactory->Release();
    defer dxgiAdapter->Release();
    defer dxgiDevice->Release();

    /////

    swapchainDesc := dxgi.SWAP_CHAIN_DESC1{
        Width  = 0,
        Height = 0,
        Format = .B8G8R8A8_UNORM_SRGB,
        Stereo = false,
        SampleDesc = {
            Count   = 1,
            Quality = 0,
        },
        BufferUsage = {.RENDER_TARGET_OUTPUT},
        BufferCount = 2,
        Scaling     = .STRETCH,
        SwapEffect  = .DISCARD,
        AlphaMode   = .UNSPECIFIED,
        Flags       = 0,
    }

    dxgiFactory->CreateSwapChainForHwnd(device, nativeWnd, &swapchainDesc, nil, nil, &swapchain)

    rasterizerDesc := d3d11.RASTERIZER_DESC{
        FillMode = .SOLID,
        CullMode = .NONE,
        // ScissorEnable = true,
        DepthClipEnable = true,
        // MultisampleEnable = true,
        // AntialiasedLineEnable = true,
    }

    rasterizerState: ^d3d11.IRasterizerState
    device->CreateRasterizerState(&rasterizerDesc, &rasterizerState)

    ////
    framebuffer: ^d3d11.ITexture2D
    swapchain->GetBuffer(0, d3d11.ITexture2D_UUID, (^rawptr)(&framebuffer))

    framebufferView: ^d3d11.IRenderTargetView
    device->CreateRenderTargetView(framebuffer, nil, &framebufferView)

    framebuffer->Release()

    /////
    blendDesc: d3d11.BLEND_DESC
    blendDesc.RenderTarget[0] = {
        BlendEnable = true,
        SrcBlend = .SRC_ALPHA,
        DestBlend = .INV_SRC_ALPHA,
        BlendOp = .ADD,
        SrcBlendAlpha = .SRC_ALPHA,
        DestBlendAlpha = .INV_SRC_ALPHA,
        BlendOpAlpha = .ADD,
        RenderTargetWriteMask = 0b1111,
    }

    blendState: ^d3d11.IBlendState
    device->CreateBlendState(&blendDesc, &blendState)

    ////

    // @TODO: allocation
    ctx := new(RenderContext_d3d)

    ctx.device = device
    ctx.deviceContext = deviceContext
    ctx.swapchain = swapchain

    ctx.rasterizerState = rasterizerState

    ctx.framebuffer = framebuffer
    ctx.framebufferView = framebufferView

    ctx.blendState = blendState

    //@TODO: How many textures do I need? Maybe make it dynamic?
    dm.InitResourcePool(&textures, 128)
    dm.InitResourcePool(&shaders, 64)
    dm.InitResourcePool(&batches, 8)

    texData := []u8{255, 255, 255, 255}
    ctx.whiteTexture = CreateTexture(texData, 1, 1, 4, ctx)

    // ctx.defaultBatch = CreateRectBatch(&ctx, 8);

    ctx.CreateTexture   = CreateTexture
    // ctx.CreateTexHandle = CreateTexHandle
    ctx.GetTextureInfo  = GetTextureInfo

    ctx.CreateRectBatch = CreateRectBatch
    ctx.DrawBatch = DrawBatch

    CreateRectBatch(ctx, &ctx.defaultBatch, 4086)
    CreatePrimitiveBatch(ctx, 1024)

    constBuffDesc := d3d11.BUFFER_DESC {
        ByteWidth = size_of(dm.mat4),
        Usage = .DYNAMIC,
        BindFlags = { .CONSTANT_BUFFER },
        CPUAccessFlags = { .WRITE },
    }

    ctx.device->CreateBuffer(&constBuffDesc, nil, &ctx.cameraConstBuff)

    ctx.defaultShaders[.ScreenSpaceRect] = CompileShaderSource(ctx, screenSpaceRect_HLSL)
    ctx.defaultShaders[.Sprite] = CompileShaderSource(ctx, sprite_HLSL)
    ctx.defaultShaders[.SDFFont] = CompileShaderSource(ctx, sdfFont_HLSL)

    return ctx
}

// BeginRenderFrame :: proc(ctx: ^dm.RenderContext) {
//     ctx := cast(^RenderContext_d3d) ctx

//     viewport := d3d11.VIEWPORT {
//         0, 0,
//         dm.windowWidth, dm.windowHeight,
//         0, 1,
//     }

//     // @TODO: move clearing render target to another function?
//     ctx.deviceContext->ClearRenderTargetView(ctx.framebufferView, &[4]f32{0.25, 0.5, 1.0, 1.0})

//     ctx.deviceContext->RSSetViewports(1, &viewport)
//     ctx.deviceContext->RSSetState(ctx.rasterizerState)

//     ctx.deviceContext->OMSetRenderTargets(1, &ctx.framebufferView, nil)
//     ctx.deviceContext->OMSetBlendState(ctx.blendState, nil, ~u32(0))
// }

EndFrame :: proc(ctx: ^RenderContext_d3d) {
    ctx.swapchain->Present(1, 0)
}

FlushCommands :: proc(using ctx: ^RenderContext_d3d) {

    viewport := d3d11.VIEWPORT {
        0, 0,
        f32(frameSize.x), f32(frameSize.y),
        0, 1,
    }

    // @TODO: make this settable
    ctx.deviceContext->RSSetViewports(1, &viewport)
    ctx.deviceContext->RSSetState(ctx.rasterizerState)

    ctx.deviceContext->OMSetRenderTargets(1, &ctx.framebufferView, nil)
    ctx.deviceContext->OMSetBlendState(ctx.blendState, nil, ~u32(0))


    for c in &commandBuffer.commands {
        switch cmd in &c {
        case dm.ClearColorCommand:
            deviceContext->ClearRenderTargetView(framebufferView, transmute(^[4]f32) &cmd.clearColor)

        case dm.CameraCommand:
            view := dm.GetViewMatrix(cmd.camera)
            proj := dm.GetProjectionMatrixZTO(cmd.camera)

            mapped: d3d11.MAPPED_SUBRESOURCE
            res := ctx.deviceContext->Map(ctx.cameraConstBuff, 0, .WRITE_DISCARD, nil, &mapped);
            c := cast(^dm.mat4) mapped.pData
            c^ = proj * view

            ctx.deviceContext->Unmap(ctx.cameraConstBuff, 0)
            ctx.deviceContext->VSSetConstantBuffers(0, 1, &ctx.cameraConstBuff)

        case dm.DrawRectCommand:
            if ctx.defaultBatch.count >= ctx.defaultBatch.maxCount {
                DrawBatch(ctx, &ctx.defaultBatch)
            }

            if ctx.defaultBatch.shader.gen != 0 && 
               ctx.defaultBatch.shader != cmd.shader {
                DrawBatch(ctx, &ctx.defaultBatch)
            }

            if ctx.defaultBatch.texture.gen != 0 && 
               ctx.defaultBatch.texture != cmd.texture {
                DrawBatch(ctx, &ctx.defaultBatch)
            }

            ctx.defaultBatch.shader = cmd.shader
            ctx.defaultBatch.texture = cmd.texture

            entry := dm.RectBatchEntry {
                position = cmd.position,
                size = cmd.size,
                rotation = cmd.rotation,

                texPos  = {cmd.source.x, cmd.source.y},
                texSize = {cmd.source.width, cmd.source.height},
                pivot = cmd.pivot,
                color = cmd.tint,
            }

            dm.AddBatchEntry(ctx, &ctx.defaultBatch, entry)
        }
    }

    DrawBatch(ctx, &ctx.defaultBatch)

    clear(&commandBuffer.commands)
}

ResizeFrambuffer :: proc(renderCtx: ^dm.RenderContext, width, height: int) {
    ctx := cast(^RenderContext_d3d) renderCtx

    ctx.deviceContext->OMSetRenderTargets(0, nil, nil)
    ctx.framebufferView->Release()

    ctx.swapchain->ResizeBuffers(0, 0, 0, .UNKNOWN, 0)

    framebuffer: ^d3d11.ITexture2D
    ctx.swapchain->GetBuffer(0, d3d11.ITexture2D_UUID, (^rawptr)(&framebuffer))

    ctx.device->CreateRenderTargetView(framebuffer, nil, &ctx.framebufferView)

    framebuffer->Release()
}

//////////////////
/// TEXTURES
//////////////////
Texture_d3d :: struct {
    using info: dm.TextureInfo,

    texture: ^d3d11.ITexture2D,
    textureView: ^d3d11.IShaderResourceView,
    samplerState: ^d3d11.ISamplerState,
}

CreateTexture :: proc(rawData: []u8, width, height, channels: i32, renderCtx: ^dm.RenderContext) -> dm.TexHandle {
    ctx := cast(^RenderContext_d3d) renderCtx

    handle := cast (dm.TexHandle) dm.CreateHandle(textures)

    tex := &textures.elements[handle.index]

    texDesc := d3d11.TEXTURE2D_DESC {
        Width      = u32(width),
        Height     = u32(height),
        MipLevels  = 1,
        ArraySize  = 1,
        Format     = .R8G8B8A8_UNORM_SRGB,
        SampleDesc = {Count = 1},
        Usage      = .IMMUTABLE,
        BindFlags  = {.SHADER_RESOURCE},
    }

    texData := d3d11.SUBRESOURCE_DATA{
        pSysMem     = &rawData[0],
        SysMemPitch = u32(width * channels),
    }


    ctx.device->CreateTexture2D(&texDesc, &texData, &tex.texture)

    ctx.device->CreateShaderResourceView(tex.texture, nil, &tex.textureView)

    samplerDesc := d3d11.SAMPLER_DESC{
        Filter         = .MIN_MAG_MIP_POINT,
        AddressU       = .WRAP,
        AddressV       = .WRAP,
        AddressW       = .WRAP,
        ComparisonFunc = .NEVER,
    }

    samplerState: ^d3d11.ISamplerState
    ctx.device->CreateSamplerState(&samplerDesc, &tex.samplerState)

    tex.width = width
    tex.height = height

    // @TODO: invalidate texture in case of errors

    return handle
}

GetTextureInfo :: proc(handle: dm.TexHandle) -> (dm.TextureInfo, bool) {
    assert(int(handle.index) < len(textures.slots))

    // info := textures.elements[handle.index].info
    slot := textures.slots[handle.index]

    // @TODO: should this check be only in debug builds?
    if slot.gen != handle.gen ||
       slot.inUse == false
    {
        // texture was already replaced or destroyed
        return {}, false
    }

    return textures.elements[handle.index], true
}


////////////////////////////
//// SHADERS
///////////////////////////

Shader_d3d :: struct {
    using base: dm.Shader,

    vertexShader: ^d3d11.IVertexShader,
    pixelShader: ^d3d11.IPixelShader,
}

CreateShaderHandle :: proc() -> dm.ShaderHandle {
    return cast(dm.ShaderHandle) dm.CreateHandle(shaders)
}

CompileShaderSource :: proc(renderCtx: ^dm.RenderContext, source: string) -> dm.ShaderHandle {
    ctx := cast(^RenderContext_d3d) renderCtx

    handle := CreateShaderHandle()
    if dm.IsHandleValid(shaders, dm.Handle(handle)) == false {
        // @TODO: logger
        return {}
    }

    shader := &shaders.elements[handle.index]

    error: ^d3d11.IBlob

    vsBlob: ^d3d11.IBlob
    defer vsBlob->Release()

    hr := d3d.Compile(raw_data(source), len(source), "shaders.hlsl", nil, nil, 
                      "vs_main", "vs_5_0", 0, 0, &vsBlob, &error)

    if hr < 0 {
        fmt.println(transmute(cstring) error->GetBufferPointer())
        error->Release()

        return {}
    }

    ctx.device->CreateVertexShader(vsBlob->GetBufferPointer(), vsBlob->GetBufferSize(), 
                                         nil, &shader.vertexShader)

    psBlob: ^d3d11.IBlob
    defer psBlob->Release()

    hr = d3d.Compile(raw_data(source), len(source), "shaders.hlsl", nil, nil,
                     "ps_main", "ps_5_0", 0, 0, &psBlob, &error)

    if hr < 0 {
        fmt.println(transmute(cstring) error->GetBufferPointer())
        error->Release()

        return {}
    }

    ctx.device->CreatePixelShader(psBlob->GetBufferPointer(), psBlob->GetBufferSize(), 
                                        nil, &shader.pixelShader)

    return handle
}


/////////////////
/// BATCH
////////////////

RectBatch_D3D :: struct {
    handle: dm.BatchHandle,

    // TODO: can probably abstract it to GPU buffer
    d3dBuffer: ^d3d11.IBuffer, // rect buffer
    SRV:       ^d3d11.IShaderResourceView, // 

    constBuffer: ^d3d11.IBuffer,
}

CreateBatchHandle :: proc() -> dm.BatchHandle {
    return cast(dm.BatchHandle) dm.CreateHandle(batches)
}

CreateRectBatch :: proc(renderCtx: ^dm.RenderContext, batch: ^dm.RectBatch, count: int) {
    ctx := cast(^RenderContext_d3d) renderCtx

    handle := CreateBatchHandle()

    // @TODO: add handle validation
    renderData := &batches.elements[handle.index]
    renderData.handle = handle

    rectBufferDesc := d3d11.BUFFER_DESC {
        ByteWidth = u32(count) * size_of(dm.RectBatchEntry),
        Usage     = .DYNAMIC,
        BindFlags = { .SHADER_RESOURCE },
        CPUAccessFlags = { .WRITE },
        MiscFlags = {.BUFFER_STRUCTURED},
        StructureByteStride = size_of(dm.RectBatchEntry),
    }

    ctx.device->CreateBuffer(&rectBufferDesc, nil, &renderData.d3dBuffer)

    rectSRVDesc := d3d11.SHADER_RESOURCE_VIEW_DESC {
        Format = .UNKNOWN,
        ViewDimension = .BUFFER,
    }

    rectSRVDesc.Buffer.NumElements = u32(count)

    ctx.device->CreateShaderResourceView(renderData.d3dBuffer, &rectSRVDesc, &renderData.SRV)

    constBuffDesc := d3d11.BUFFER_DESC {
        ByteWidth = size_of(dm.BatchConstants),
        Usage = .DYNAMIC,
        BindFlags = { .CONSTANT_BUFFER },
        CPUAccessFlags = { .WRITE },
    }

    ctx.device->CreateBuffer(&constBuffDesc, nil, &renderData.constBuffer)

    batch.renderData = handle
    batch.buffer = make([]dm.RectBatchEntry, count)
    batch.maxCount = count
}

DrawBatch :: proc(ctx: ^dm.RenderContext, batch: ^dm.RectBatch) {
    if batch.count == 0 {
        return
    }

    ctx := cast(^RenderContext_d3d) ctx

    // @TODO: batch validation
    batchRenderData := batches.elements[batch.renderData.index]

    screenSize := [2]f32 {
         2 / f32(ctx.frameSize.x),
        -2 / f32(ctx.frameSize.y),
    }

    // @TODO: better texture validation:
    assert(batch.shader.gen != 0)
    assert(batch.texture.gen != 0, "Rendered batch doesn't have texture set")
    texture := textures.elements[batch.texture.index]

    oneOverAtlasSize := [2]f32 {
        1 / f32(texture.width),
        1 / f32(texture.height),
    }

    ////

    ctx.deviceContext->IASetPrimitiveTopology(.TRIANGLESTRIP)

    //@TODO: shader validation
    shader := shaders.elements[batch.shader.index]

    ctx.deviceContext->VSSetShader(shader.vertexShader, nil, 0)

    mapped: d3d11.MAPPED_SUBRESOURCE
    res := ctx.deviceContext->Map(batchRenderData.constBuffer, 0, .WRITE_DISCARD, nil, &mapped)

    val := cast(^dm.BatchConstants) mapped.pData
    val.screenSize = screenSize
    val.oneOverAtlasSize = oneOverAtlasSize

    // if batch.camera != nil {
        // val.VP = dm.GetVPMatrix(&ctx.camera)
    // }

    ctx.deviceContext->Unmap(batchRenderData.constBuffer, 0)

    ctx.deviceContext->VSSetShaderResources(0, 1, &batchRenderData.SRV)
    ctx.deviceContext->VSSetConstantBuffers(1, 1, &batchRenderData.constBuffer)


    ctx.deviceContext->PSSetShader(shader.pixelShader, nil, 0)
    ctx.deviceContext->PSSetShaderResources(1, 1, &texture.textureView)
    ctx.deviceContext->PSSetSamplers(0, 1, &texture.samplerState)

    msr : d3d11.MAPPED_SUBRESOURCE
    ctx.deviceContext->Map(batchRenderData.d3dBuffer, 0, .WRITE_DISCARD, nil, &msr)

    libc.memcpy(msr.pData, &batch.buffer[0], uint(size_of(dm.RectBatchEntry) * batch.count))

    ctx.deviceContext->Unmap(batchRenderData.d3dBuffer, 0)

    ctx.deviceContext->DrawInstanced(4, u32(batch.count), 0, 0);

    batch.count = 0
}

////////////////////
// Primitive Buffer
///////////////

PrimitiveVertexShaderSource := `
cbuffer constants: register(b0) {
    float4x4 VPMat;
}

struct vs_in {
    float3 position: POSITION;
    float4 color: COLOR;
};

struct vs_out {
    float4 position: SV_POSITION;
    float4 color: COLOR;
};

vs_out vs_main(vs_in input) {
    vs_out output;

    output.position = mul(VPMat, float4(input.position, 1));
    output.color = input.color;

    return output;
}

float4 ps_main(vs_out input) : SV_TARGET {
    return input.color;
}
`

primitiveVertexShader: dm.ShaderHandle

CreatePrimitiveBatch :: proc(ctx: ^RenderContext_d3d, maxCount: int) {

    ctx.debugBatch.buffer = make([]dm.PrimitiveVertex, maxCount)

    // vert buffer
    desc := d3d11.BUFFER_DESC {
        ByteWidth = u32(maxCount) * size_of(dm.PrimitiveVertex),
        Usage     = .DYNAMIC,
        BindFlags = { .VERTEX_BUFFER },
        CPUAccessFlags = { .WRITE },
    }

    res := ctx.device->CreateBuffer(&desc, nil, &ctx.debugBatch.gpuVertBuffer)

    if primitiveVertexShader.index == 0 {
        primitiveVertexShader = CompileShaderSource(ctx, PrimitiveVertexShaderSource);
    }

    // @HACK: I need to somehow have shader byte code in order to create input layout
    // But my current implementation doesn't store shader bytecode so I need to compile it 
    // again to create the layout.
    // Maybe with precompiled shaders I could get away with
    vsBlob: ^d3d11.IBlob
    defer vsBlob->Release()

    error: ^d3d11.IBlob
    hr := d3d.Compile(raw_data(PrimitiveVertexShaderSource), len(PrimitiveVertexShaderSource), 
                      "shaders.hlsl", nil, nil, 
                      "vs_main", "vs_5_0", 0, 0, &vsBlob, &error)

    inputDescs: []d3d11.INPUT_ELEMENT_DESC = {
        {"POSITION", 0, .R32G32B32_FLOAT,    0,                            0, .VERTEX_DATA, 0 },
        {"COLOR",    0, .R32G32B32A32_FLOAT, 0, d3d11.APPEND_ALIGNED_ELEMENT, .VERTEX_DATA, 0 },
    }

    res = ctx.device->CreateInputLayout(&inputDescs[0], cast(u32) len(inputDescs), 
                          vsBlob->GetBufferPointer(), vsBlob->GetBufferSize(),
                          &ctx.debugBatch.inputLayout)
}

DrawPrimitiveBatch :: proc(ctx: ^RenderContext_d3d) {
    batch := &ctx.debugBatch
    if batch.index == 0 {
        return
    }


    mapped: d3d11.MAPPED_SUBRESOURCE

    ctx.deviceContext->Map(batch.gpuVertBuffer, 0, .WRITE_DISCARD, nil, &mapped)
    mem.copy(mapped.pData, &batch.buffer[0], (batch.index) * size_of(dm.PrimitiveVertex))
    ctx.deviceContext->Unmap(batch.gpuVertBuffer, 0)

    shader := shaders.elements[primitiveVertexShader.index]

    stride: u32 = size_of(dm.PrimitiveVertex)
    offset: u32 = 0

    ctx.deviceContext->IASetPrimitiveTopology(.LINELIST)
    ctx.deviceContext->IASetInputLayout(batch.inputLayout)
    ctx.deviceContext->IASetVertexBuffers(0, 1, &batch.gpuVertBuffer, &stride, &offset)

    ctx.deviceContext->VSSetShader(shader.vertexShader, nil, 0)

    ctx.deviceContext->PSSetShader(shader.pixelShader, nil, 0)

    ctx.deviceContext->Draw(u32(batch.index), 0)

    batch.index = 0
}