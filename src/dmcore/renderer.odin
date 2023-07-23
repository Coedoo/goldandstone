package dmcore

import stbi "vendor:stb/image"

import math "core:math/linalg/glsl"

import coreMath "core:math"

import sdl "vendor:sdl2"

import "core:fmt"

import "core:os"
import "core:c/libc"

import "core:mem"

// LOL
import d3d11 "vendor:directx/d3d11"

TexHandle :: distinct Handle
ShaderHandle :: distinct Handle
BatchHandle :: distinct Handle

ToVec2 :: proc(v: math.ivec2) -> math.vec2 {
    return {
        f32(v.x),
        f32(v.y),
    }
}

Toivec2 :: proc(v: math.vec2) -> math.ivec2 {
    return {
        i32(v.x),
        i32(v.y),
    }
}

/////////////////////////////////////
//// Render Context
////////////////////////////////////

RenderContext :: struct {
    whiteTexture: TexHandle,

    frameSize: iv2,

    defaultBatch: RectBatch,
    debugBatch:   PrimitiveBatch,

    commandBuffer: CommandBuffer,

    defaultShaders: [DefaultShaderType]ShaderHandle,

    CreateTexture: proc(rawData: []u8, width, height, channels: i32, renderCtx: ^RenderContext) -> TexHandle,
    GetTextureInfo: proc(handle: TexHandle) -> (TextureInfo, bool),

    CreateRectBatch: proc(renderCtx: ^RenderContext, bathc: ^RectBatch, count: int),
    DrawBatch: proc(ctx: ^RenderContext, batch: ^RectBatch),
}

/////////////////////////////////////
/// Shaders
/////////////////////////////////////

DefaultShaderType :: enum {
    Sprite,
    ScreenSpaceRect,
    SDFFont,
}

Shader :: struct {
    handle: ShaderHandle,
}


/////////////////////////////////////
// Textures
/////////////////////////////////////


TextureInfo :: struct {
    handle: TexHandle,
    width: i32,
    height: i32,
}

// DestroyTexHandle :: proc(handle: TexHandle) {
//     //@TODO: renderer destroy
//     textures[handle.index].handle.index = 0
// }

GetTextureSize :: proc(renderCtx: ^RenderContext, handle: TexHandle) -> iv2 {
    info, _ := renderCtx.GetTextureInfo(handle)
    return {info.width, info.height}
}

LoadTextureFromFile :: proc(filePath: string, renderCtx: ^RenderContext) -> TexHandle {
    data, ok := os.read_entire_file(filePath, context.temp_allocator)

    if ok == false {
        // @TODO: error texture
        fmt.eprintf("Failed to open file: %v\n", filePath)
        return {}
    }

    return LoadTextureFromMemory(data, renderCtx)
}

LoadTextureFromMemory :: proc(data: []u8, renderCtx: ^RenderContext) -> TexHandle {
    width, height, channels: i32
    imageData := stbi.load_from_memory(
        &data[0],
        cast(i32) len(data),
        &width,
        &height,
        &channels,
        4,
    )

    defer stbi.image_free(imageData)
    
    len := width * height * channels
    return renderCtx.CreateTexture(imageData[:len], width, height, channels, renderCtx)
}


////////////////////////////////////
/// Sprites
///////////////////////////////////
Axis :: enum {
    Horizontal,
    Vertical,
}

Sprite :: struct {
    texture: TexHandle,

    origin: v2,

    //@TODO: change to source rectangle
    atlasPos: iv2,
    pixelSize: iv2,

    // tint: color,

    scale: f32,

    frames: i32,
    currentFrame: i32,
    animDirection: Axis,
}

CreateSprite :: proc {
    // CreateSpriteFromTexture,
    CreateSpriteFromTextureRect,
    CreateSpriteFromTexturePosSize,
}

// CreateSpriteFromTexture :: proc(texture: TexHandle) -> Sprite {
//     return {
//         texture = texture,

//         atlasPos = {0, 0},
//         pixelSize = GetTextureSize(texture),

//         // @TODO: Color constants
//         tint = {1, 1, 1, 1},

//         scale = 1,
//     }
// }

CreateSpriteFromTextureRect :: proc(texture: TexHandle, rect: RectInt) -> Sprite {
    return {
        texture = texture,

        atlasPos = {rect.x, rect.y},
        pixelSize = {rect.width, rect.height},

        origin = {0.5, 0.5},

        // tint = {1, 1, 1, 1},

        scale = 1,
    }
}

CreateSpriteFromTexturePosSize :: proc(texture: TexHandle, atlasPos: iv2, atlasSize: iv2) -> Sprite {
    return {
        texture = texture,

        atlasPos = atlasPos,
        pixelSize = atlasSize,

        origin = {0.5, 0.5},

        // tint = {1, 1, 1, 1},

        scale = 1,
    }
}

AnimateSprite :: proc(sprite: ^Sprite, time: f32, frameTime: f32) {
    t := cast(i32) (time / frameTime)
    t = t%sprite.frames

    sprite.currentFrame = t
}

GetSpriteSize :: proc(sprite: Sprite) -> v2 {
    sizeX := sprite.scale
    sizeY := f32(sprite.pixelSize.y) / f32(sprite.pixelSize.x) * sizeX

    return {sizeX, sizeY}
}

///////////////////////////////
/// Rect rendering
//////////////////////////////

BatchConstants :: struct #align 16 {
    screenSize: [2]f32,
    oneOverAtlasSize: [2]f32,
}

RectBatchEntry :: struct {
    position: v2,
    size:     v2,
    rotation: f32,

    texPos:   iv2,
    texSize:  iv2,

    pivot: v2,

    color: color,
}

RectBatch :: struct {
    count: int,
    maxCount: int,
    buffer: []RectBatchEntry,

    texture: TexHandle,
    shader:  ShaderHandle,

    renderData: BatchHandle,
}

AddBatchEntry :: proc(ctx: ^RenderContext, batch: ^RectBatch, entry: RectBatchEntry) {
    assert(batch.buffer != nil)
    assert(batch.count < len(batch.buffer))

    batch.buffer[batch.count] = entry
    batch.count += 1
}

//////////////
// Debug drawing
/////////////

PrimitiveVertex :: struct {
    pos: v3,
    color: color,
}

PrimitiveBatch :: struct {
    buffer: []PrimitiveVertex,
    index: int,

    gpuVertBuffer: ^d3d11.IBuffer,
    inputLayout: ^d3d11.IInputLayout,
}

DrawLine :: proc(ctx: ^RenderContext, a, b: v3, color: color = RED) {
    using ctx.debugBatch

    buffer[index + 0] = {a, color}
    buffer[index + 1] = {b, color}

    index += 2
}

DrawBox2D :: proc(ctx: ^RenderContext, pos, size: v2, color: color = GREEN) {
    using ctx.debugBatch

    left  := pos.x - size.x / 2
    right := pos.x + size.x / 2
    top   := pos.y + size.y / 2
    bot   := pos.y - size.y / 2

    a := v3{left, bot, 0}
    b := v3{right, bot, 0}
    c := v3{right, top, 0}
    d := v3{left, top, 0}


    buffer[index + 0] = {a, color}
    buffer[index + 1] = {b, color}
    buffer[index + 2] = {b, color}
    buffer[index + 3] = {c, color}
    buffer[index + 4] = {c, color}
    buffer[index + 5] = {d, color}
    buffer[index + 6] = {d, color}
    buffer[index + 7] = {a, color}

    index += 8
}

DrawCircle :: proc(ctx: ^RenderContext, pos: v2, radius: f32, color: color = GREEN) {
    using ctx.debugBatch

    resolution :: 32

    GetPosition :: proc(i: int, pos: v2, radius: f32) -> v3 {
        angle := f32(i) / f32(resolution) * coreMath.PI * 2
        pos := v3{
            coreMath.cos(angle),
            coreMath.sin(angle),
            0
        } * radius + {pos.x, pos.y, 0}

        return pos
    }

    for i in 0..<resolution {
        posA := GetPosition(i, pos, radius)
        posB := GetPosition(i + 1, pos, radius)

        // @TODO: handle resise or early flush
        if index >= len(buffer) {
            return
        }

        buffer[index]     = {posA, color}
        buffer[index + 1] = {posB, color}
        index += 2
    }

}