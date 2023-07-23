package dmcore

import "core:mem"
import "core:os"
import "core:fmt"

import math "core:math/linalg/glsl"
import coreMath "core:math"

import stbtt "vendor:stb/truetype"
import stbrp "vendor:stb/rect_pack"

GLYPH_RANGE_LOW :: 32
GLYPH_RANGE_HIGH :: 383
GLYPH_COUNT :: GLYPH_RANGE_HIGH - GLYPH_RANGE_LOW

GlyphData :: struct {
    codepoint: rune,

    pixelWidth: int,
    pixelHeight: int,

    atlasPos:  v2,
    atlasSize: v2,

    offset: v2,

    advanceX: int,
}

FontType :: enum {
    Bitmap,
    SDF,
}

Font :: struct {
    size: int,
    type: FontType,

    atlas: TexHandle,
    glyphData: [GLYPH_COUNT]GlyphData,
}


GetCodepointIndex :: proc(codepoint: rune) -> int {
    if codepoint > GLYPH_RANGE_HIGH {
        return -1;
    }

    return int(codepoint) - GLYPH_RANGE_LOW
}

DrawTextCentered :: proc(ctx: ^RenderContext, str: string, font: Font, position: iv2, fontSize: int = 0) {
    size := MeasureText(str, font, fontSize)
    pos := position - size / 2

    DrawText(ctx, str, font, pos, fontSize)
}

DrawText :: proc(ctx: ^RenderContext, str: string, font: Font, position: iv2, fontSize: int = 0) {
    // @TODO: I can cache atlas size
    atlasSize := GetTextureSize(ctx, font.atlas)

    fontSize := fontSize
    if fontSize == 0 do fontSize = font.size

    scale := f32(fontSize) / f32(font.size)

    posX := 0
    posY := fontSize

    fontAtlasSize := v2 {
        cast(f32) atlasSize.x,
        cast(f32) atlasSize.y,
    }

    shader := ctx.defaultShaders[.SDFFont] if font.type == .SDF else ctx.defaultShaders[.ScreenSpaceRect]

    for c, i in str {
        if c == '\n' {
            posY += fontSize
            posX = 0

            continue
        }

        index := GetCodepointIndex(c)
        assert(index != -1)

        glyphData := font.glyphData[index]

        pos  := v2{f32(posX), f32(posY) + glyphData.offset.y * scale} + v2Conv(position)
        size := v2{f32(glyphData.pixelWidth), f32(glyphData.pixelHeight)}
        dest := Rect{pos.x, pos.y, size.x * scale, size.y * scale}

        texPos  := Toivec2(glyphData.atlasPos  * fontAtlasSize)
        texSize := Toivec2(glyphData.atlasSize * fontAtlasSize)
        src := RectInt{texPos.x, texPos.y, texSize.x, texSize.y}

        DrawRect(ctx, font.atlas, src, dest, shader)

        advance := glyphData.pixelWidth if glyphData.pixelWidth != 0 else glyphData.advanceX
        posX += int(f32(advance) * scale)
    }
}

MeasureText :: proc(str: string, font: Font, fontSize: int = 0) -> iv2 {
    fontSize := fontSize
    if fontSize == 0 do fontSize = font.size

    scale := f32(fontSize) / f32(font.size)

    posX := 0
    lines := 1

    width := 0

    for c, i in str {
        if c == '\n' {
            width = max(width, posX)

            posX = 0
            lines += 1

            continue
        }

        index := GetCodepointIndex(c)
        assert(index != -1)

        glyphData := font.glyphData[index]

        advance := glyphData.pixelWidth if glyphData.pixelWidth != 0 else glyphData.advanceX
        posX += int(f32(advance) * scale)
    }

    width = max(width, posX)
    return {i32(width), i32(lines * fontSize)}
}

LoadFontSDF :: proc(renderCtx: ^RenderContext, fileName: string, fontSize: int) -> (font: Font) {
    using stbtt

    padding :: 3
    onEdgeValue :: 128
    distanceScale :f32: 64

    font.size = fontSize
    font.type = .SDF

    fileData, ok := os.read_entire_file(fileName, context.temp_allocator)
    if ok == false {
        fmt.eprintf("Failed To Load File: %v !!\n", fileName)
        return
    }

    fontInfo: fontinfo
    if InitFont(&fontInfo, raw_data(fileData), 0) == false {
        fmt.eprintf("Failed To Init a Font: %v !!\n", fileName)
        return
    }

    scaleFactor := ScaleForPixelHeight(&fontInfo, f32(fontSize))

    bitmaps: [GLYPH_COUNT][^]byte
    defer for b in bitmaps {
        FreeSDF(b, nil)
    }

    area: i32

    for i in GLYPH_RANGE_LOW..<GLYPH_RANGE_HIGH {
        width, height: i32
        xoff, yoff: i32

        bitmaps[i - GLYPH_RANGE_LOW] = GetCodepointSDF(&fontInfo, scaleFactor, i32(i), padding, onEdgeValue, distanceScale, &width, &height, &xoff, &yoff)

        advanceX: i32
        GetCodepointHMetrics(&fontInfo, rune(i), &advanceX, nil)

        glyph := GlyphData {
            codepoint = rune(i),
            pixelWidth  = int(width),
            pixelHeight = int(height),

            offset = {f32(xoff), f32(yoff)},
            advanceX = int(f32(advanceX) * scaleFactor),
        }

        idx := GetCodepointIndex(rune(i))
        font.glyphData[idx] = glyph

        area += (width + 2*padding) * (height + 2*padding)
    }

    sqrSurface := int(math.sqrt(f32(area)) + 1)
    bitmapSize := cast(i32) coreMath.next_power_of_two(sqrSurface)

    ///// !!!!!
    using stbrp
    //// 

    rpCtx := new(Context, context.temp_allocator)
    nodes := make([]Node, GLYPH_COUNT, context.temp_allocator)
    rects := make([]Rect, GLYPH_COUNT, context.temp_allocator)

    init_target(rpCtx, bitmapSize, bitmapSize, raw_data(nodes), i32(len(nodes)))

    for g, i in font.glyphData {
        rects[i].id = i32(g.codepoint)
        rects[i].w = cast(Coord) (g.pixelWidth + 2*padding)
        rects[i].h = cast(Coord) (g.pixelHeight + 2*padding)
    }

    pack_rects(rpCtx, raw_data(rects), i32(len(rects)))

    C :: struct {
        r, g, b, a : u8,
    }
    atlas := make([]C, bitmapSize * bitmapSize, context.temp_allocator)


    for r, i in rects {
        if r.was_packed == false {
            fmt.eprintln("Failed To pack codepoint:", rune(r.id), "(", r.id, ")")
            continue
        }

        if bitmaps[i] == nil {
            continue
        }

        x := i32(r.x) + padding
        y := i32(r.y) + padding
        w := cast(i32) font.glyphData[i].pixelWidth
        h := cast(i32) font.glyphData[i].pixelHeight

        for bitmapX in 0..<w {
            for bitmapY in 0..<h {
                atlasX := x + bitmapX
                atlasY := y + bitmapY

                bitmapIdx := bitmapY * w + bitmapX
                atlasIdx := atlasY * bitmapSize + atlasX

                b := bitmaps[i]
                v := b[bitmapIdx]

                atlas[atlasIdx] = {v, v, v, v}
            }
        }

        font.glyphData[i].atlasPos = {f32(r.x + padding) / f32(bitmapSize), f32(r.y + padding) / f32(bitmapSize)}
        font.glyphData[i].atlasSize = {f32(w) / f32(bitmapSize), f32(h) / f32(bitmapSize)}
    }

    font.atlas = renderCtx.CreateTexture(mem.slice_to_bytes(atlas), bitmapSize, bitmapSize, 4, renderCtx)

    return
}

LoadFontFromFile :: proc(renderCtx: ^RenderContext, fileName: string, fontSize: int) -> (font: Font) {
    using stbtt

    fontInfo: fontinfo
    font.type = .Bitmap

    oversampleX :: 3
    oversampleY :: 1
    padding     :: 1

    fileData, ok := os.read_entire_file(fileName, context.temp_allocator)
    if ok == false {
        fmt.eprintf("Failed To Load File: %v !!\n", fileName)
        return
    }

    if InitFont(&fontInfo, raw_data(fileData), 0) == false {
        fmt.eprintf("Failed To Init a Font: %v !!\n", fileName)
        return
    }

    scaleFactor := ScaleForPixelHeight(&fontInfo, f32(fontSize))

    surface: int

    for i in GLYPH_RANGE_LOW..<GLYPH_RANGE_HIGH {
        x0, y0, x1, y1 : i32

        GetCodepointBitmapBoxSubpixel(
            &fontInfo, 
            rune(i),
            oversampleX * scaleFactor,
            oversampleY * scaleFactor,
            0, 0,
            &x0, &y0, &x1, &y1,
        )

        w := x1 - x0 + padding + oversampleX - 1
        h := y1 - y0 + padding + oversampleY - 1

        surface += int(w * h)
    }

    sqrSurface := int(math.sqrt(f32(surface)) + 1)
    bitmapSize := cast(i32) coreMath.next_power_of_two(sqrSurface)

    dataCount := bitmapSize * bitmapSize

    C :: struct {
        r, g, b, a : u8,
    }

    bitmap      := make([]u8, dataCount, context.temp_allocator)
    colorBitmap := make([]C, dataCount, context.temp_allocator)

    packContext: pack_context
    packedChars: [GLYPH_COUNT]packedchar

    PackBegin(&packContext, raw_data(bitmap), bitmapSize, bitmapSize, 0, padding, nil)
    PackSetOversampling(&packContext, oversampleX, oversampleY)
    PackFontRange(&packContext, raw_data(fileData), 0, f32(fontSize), GLYPH_RANGE_LOW, GLYPH_COUNT, &(packedChars[0]))
    PackEnd(&packContext)

    for i in 0..<dataCount {
        colorBitmap[i] = {
            r = 255,
            g = 255,
            b = 255,
            a = bitmap[i],
        }
    }

    font.size = fontSize

    for i in 0..<GLYPH_COUNT {
        m := packedChars[i]

        tempX, tempY: f32
        quad: aligned_quad

        GetPackedQuad(&(packedChars[0]), bitmapSize, bitmapSize,
                      i32(i), &tempX, &tempY, &quad, false);

        font.glyphData[i].codepoint = rune(i + GLYPH_RANGE_LOW)

        font.glyphData[i].atlasPos  = { quad.s0, quad.t0 }
        font.glyphData[i].atlasSize = { quad.s1 - quad.s0, 
                                        quad.t1 - quad.t0, }

        font.glyphData[i].pixelWidth  = int(quad.x1 - quad.x0)
        font.glyphData[i].pixelHeight = int(quad.y1 - quad.y0)

        font.glyphData[i].offset = { quad.x0, quad.y0 }

        font.glyphData[i].advanceX = int(packedChars[i].xadvance)
    }

    font.atlas = renderCtx.CreateTexture(mem.slice_to_bytes(colorBitmap), bitmapSize, bitmapSize, 4, renderCtx)

    return
}
