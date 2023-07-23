package dmcore

import mu "vendor:microui"

import "core:reflect"
import "core:strings"
import "core:fmt"

import "core:unicode/utf8"

import "../dmcore"

Mui :: struct {
    muiCtx: mu.Context,
    muiTextAtlas: TexHandle,

    muiBatch: RectBatch,
}

/// Wrappers
muiInit :: proc(renderCtx: ^dmcore.RenderContext) -> ^Mui {
    mui := new(Mui)

    mu.init(&mui.muiCtx)

    mui.muiCtx.text_width = mu.default_atlas_text_width
    mui.muiCtx.text_height = mu.default_atlas_text_height

    rgba8 := make([]u8, mu.DEFAULT_ATLAS_WIDTH * mu.DEFAULT_ATLAS_HEIGHT * 4, context.temp_allocator);

    for y in 0..<mu.DEFAULT_ATLAS_HEIGHT {
        #no_bounds_check for x in 0..<mu.DEFAULT_ATLAS_WIDTH {
            index := y * mu.DEFAULT_ATLAS_WIDTH + x;

            rgba8[(index * 4) + 0] = 255;
            rgba8[(index * 4) + 1] = 255;
            rgba8[(index * 4) + 2] = 255;
            rgba8[(index * 4) + 3] = mu.default_atlas_alpha[index];
        }
    }

    mui.muiTextAtlas = renderCtx.CreateTexture(rgba8, mu.DEFAULT_ATLAS_WIDTH, mu.DEFAULT_ATLAS_HEIGHT, 4, renderCtx)

    renderCtx.CreateRectBatch(renderCtx, &mui.muiBatch, 2048)
    mui.muiBatch.shader = renderCtx.defaultShaders[.ScreenSpaceRect]
    mui.muiBatch.texture = mui.muiTextAtlas

    // to initialize pool allocators, so we can make some
    // setup before actual work
    mu.begin(&mui.muiCtx)
    mu.end(&mui.muiCtx)

    return mui
}

muiBegin :: proc(using mui: ^Mui) {
    mu.begin(&muiCtx)
}

muiEnd :: proc(using mui: ^Mui) {
    mu.end(&muiCtx)
}

muiBeginWindow :: proc(using mui: ^Mui, label: string, rect: mu.Rect, options: mu.Options) -> bool {
    return mu.begin_window(&muiCtx, label, rect, options)
}

muiEndWindow :: proc(using mui: ^Mui) {
    mu.end_window(&muiCtx)
}

muiShowWindow :: proc(mui: ^Mui, label: string) {
    container := mu.get_container(&mui.muiCtx, label)
    assert(container != nil)

    container.open = true
}

muiLabel :: proc(using mui: ^Mui, params: ..any) {
    mu.text(&muiCtx, fmt.tprint(..params))
}

muiSlider :: proc(using mui: ^Mui, value: ^f32, low, high: f32, step: f32 = 0) {
    mu.slider(&muiCtx, value, low, high, step)
}

muiSliderInt :: proc(using mui: ^Mui, value: ^int, low, high: int, step: int = 0) {
    v := cast(f32) value^
    mu.slider(&muiCtx, &v, f32(low), f32(high), f32(step))
    value^ = cast(int) v
}

muiButton :: proc(mui:^Mui, label: string, icon: mu.Icon = .NONE, opt: mu.Options = {.ALIGN_CENTER}) -> bool {
    return mu.button(&mui.muiCtx, label, icon, opt) == {.SUBMIT}
}

/// Input/Render
muiRender :: proc(mui: ^Mui, renderCtx: ^dmcore.RenderContext) {
    ToColor :: proc(c: mu.Color) -> color {
        r := f32(c.r) / 255
        g := f32(c.g) / 255
        b := f32(c.b) / 255
        a := f32(c.a) / 255

        return {r, g, b, a}
    }

    if len(mui.muiCtx.command_list.items) == 0 do return

    clipRect := mu.unclipped_rect

    assert(mui.muiBatch.count == 0)

    cmd: ^mu.Command;
    for mu.next_command(&mui.muiCtx, &cmd) {
        switch c in cmd.variant {
            case ^mu.Command_Rect:
                rect := c.rect

                whiteRect := mu.default_atlas[mu.DEFAULT_ATLAS_WHITE]
                entry := RectBatchEntry {
                    position = {f32(rect.x), f32(rect.y)},
                    size = {f32(rect.w), f32(rect.h)},

                    texPos  = { whiteRect.x, whiteRect.y },
                    texSize = { whiteRect.w, whiteRect.h },

                    color = ToColor(c.color),
                }

                AddBatchEntry(renderCtx, &mui.muiBatch, entry)

            case ^mu.Command_Text:
                posX := c.pos.x
                posY := c.pos.y
                for ch in c.str {
                    src := mu.default_atlas[mu.DEFAULT_ATLAS_FONT + int(ch)]

                    left   := max(posX, clipRect.x)
                    right  := min(posX + src.w, clipRect.x + clipRect.w)
                    top    := max(posY, clipRect.y)
                    bottom := min(posY + src.h, clipRect.y + clipRect.h)

                    size := iv2 {right - left, bottom - top}

                    clipDelta := iv2 {posX - left, posY - top }
                    texPos := iv2 {src.x, src.y} - clipDelta

                    if size.x <= 0 || size.y <= 0 {
                        // Rect was clipped
                        continue
                    }

                    entry := RectBatchEntry {
                        position = {f32(left), f32(top)},
                        size = ToVec2(size),

                        texPos = texPos,
                        texSize = size,

                        color = ToColor(c.color),
                    }

                    posX += src.w

                    AddBatchEntry(renderCtx, &mui.muiBatch, entry)
                }

            case ^mu.Command_Icon:
                src := mu.default_atlas[c.id]

                size := iv2 { src.w, src.h }
                pos := iv2 {c.rect.x + (c.rect.w - src.w) / 2,
                            c.rect.y + (c.rect.h - src.h) / 2}

                left   := max(pos.x, clipRect.x)
                right  := min(pos.x + src.w, clipRect.x + clipRect.w)
                top    := max(pos.y, clipRect.y)
                bottom := min(pos.y + src.h, clipRect.y + clipRect.h)


                clipDelta := iv2 {pos.x - left, pos.y - top }
                texPos    := iv2 {src.x, src.y} - clipDelta

                size = iv2 {right - left, bottom - top}
                pos  = {left, top}

                if size.x <= 0 || size.y <= 0 {
                    // Rect was clipped
                    continue
                }

                entry := RectBatchEntry {
                    position = ToVec2(pos),
                    size = ToVec2(size),

                    texPos = texPos,
                    texSize = size,

                    color = ToColor(c.color),
                }

                AddBatchEntry(renderCtx, &mui.muiBatch, entry)

            case ^mu.Command_Clip:
                // clipRect = c.rect

            case ^mu.Command_Jump: // Ignored
        }
    }

    renderCtx.DrawBatch(renderCtx, &mui.muiBatch)
}

SCROLL_SPEED :: 20
muiProcessInput :: proc(mui: ^Mui, input: ^dmcore.Input) {
    // mouse
    posX := input.mousePos.x
    posY := input.mousePos.y
    mu.input_mouse_move(&mui.muiCtx, posX, posY)

    mu.input_scroll(&mui.muiCtx, SCROLL_SPEED * i32(input.scrollX), SCROLL_SPEED * -i32(input.scroll))

    // keys
    if      GetMouseButton(input, .Left) == .JustPressed  do mu.input_mouse_down(&mui.muiCtx, posX, posY, .LEFT)
    else if GetMouseButton(input, .Left) == .JustReleased do mu.input_mouse_up(&mui.muiCtx, posX, posY, .LEFT)

    if      GetMouseButton(input, .Right) == .JustPressed  do mu.input_mouse_down(&mui.muiCtx, posX, posY, .RIGHT)
    else if GetMouseButton(input, .Right) == .JustReleased do mu.input_mouse_up(&mui.muiCtx, posX, posY, .RIGHT)

    if      GetMouseButton(input, .Middle) == .JustPressed  do mu.input_mouse_down(&mui.muiCtx, posX, posY, .MIDDLE)
    else if GetMouseButton(input, .Middle) == .JustReleased do mu.input_mouse_up(&mui.muiCtx, posX, posY, .MIDDLE)

    if      GetKeyState(input, .LShift) == .JustPressed  do mu.input_key_down(&mui.muiCtx, .SHIFT)
    else if GetKeyState(input, .LShift) == .JustReleased do mu.input_key_up(&mui.muiCtx, .SHIFT)

    if      GetKeyState(input, .LCtrl) == .JustPressed  do mu.input_key_down(&mui.muiCtx, .CTRL)
    else if GetKeyState(input, .LCtrl) == .JustReleased do mu.input_key_up(&mui.muiCtx, .CTRL)

    if      GetKeyState(input, .LAlt) == .JustPressed  do mu.input_key_down(&mui.muiCtx, .ALT)
    else if GetKeyState(input, .LAlt) == .JustReleased do mu.input_key_up(&mui.muiCtx, .ALT)

    if      GetKeyState(input, .Backspace) == .JustPressed  do mu.input_key_down(&mui.muiCtx, .BACKSPACE)
    else if GetKeyState(input, .Backspace) == .JustReleased do mu.input_key_up(&mui.muiCtx, .BACKSPACE)

    if      GetKeyState(input, .Return) == .JustPressed  do mu.input_key_down(&mui.muiCtx, .RETURN)
    else if GetKeyState(input, .Return) == .JustReleased do mu.input_key_up(&mui.muiCtx, .RETURN)

    str := utf8.runes_to_string(input.runesBuffer[:], context.temp_allocator)
    mu.input_text(&mui.muiCtx, str)
}


/// Test windows

uint8_slider :: proc(ctx: ^mu.Context, value: ^u8, low, high: int) -> (res: mu.Result_Set) {
    using mu;

    @static tmp: Real;

    push_id(ctx, uintptr(value));
    tmp = Real(value^);
    res = slider(ctx, &tmp, Real(low), Real(high), 0, "%.0f", {.ALIGN_CENTER});
    value^ = u8(tmp);
    pop_id(ctx);

    return;
}

style_window :: proc(using mui: ^Mui) {
    using mu;

    if begin_window(&muiCtx, "Style Editor", Rect{350,250,300,240}) {
        sw := i32(Real(get_current_container(&muiCtx).body.w) * 0.14);
        layout_row(&muiCtx, { 95, sw, sw, sw, sw, -1 }, 0);
        for c in Color_Type {
            label(&muiCtx, fmt.tprintf("%s:", reflect.enum_string(c)));
            uint8_slider(&muiCtx, &muiCtx.style.colors[c].r, 0, 255);
            uint8_slider(&muiCtx, &muiCtx.style.colors[c].g, 0, 255);
            uint8_slider(&muiCtx, &muiCtx.style.colors[c].b, 0, 255);
            uint8_slider(&muiCtx, &muiCtx.style.colors[c].a, 0, 255);
            draw_rect(&muiCtx, layout_next(&muiCtx), muiCtx.style.colors[c]);
        }
        end_window(&muiCtx);
    }
}

test_window :: proc(using mui: ^Mui) {
    @static opts: mu.Options;

    // NOTE(oskar): mu.button() returns Res_Bits and not bool (should fix this)
    button :: #force_inline proc(muiCtx: ^mu.Context, label: string) -> bool {
        return mu.button(muiCtx, label) == {.SUBMIT}
    }

    /* do window */
    if mu.begin_window(&muiCtx, "Demo Window", {40,40,300,450}, opts) {
        if mu.header(&muiCtx, "Window Options") != {} {
            win := mu.get_current_container(&muiCtx);
            mu.layout_row(&muiCtx, {120, 120, 120}, 0);
            for opt in mu.Opt {
                state: bool = opt in opts;
                if mu.checkbox(&muiCtx, fmt.tprintf("%v", opt), &state) != {} {
                    if state {
                        opts |= {opt};
                    }
                    else {
                        opts &~= {opt};
                    }
                }
            }
        }

        /* window info */
        if mu.header(&muiCtx, "Window Info") != {} {
            win := mu.get_current_container(&muiCtx);
            mu.layout_row(&muiCtx, { 54, -1 }, 0);
            mu.label(&muiCtx, "Position:");
            mu.label(&muiCtx, fmt.tprintf("%d, %d", win.rect.x, win.rect.y));
            mu.label(&muiCtx, "Size:");
            mu.label(&muiCtx, fmt.tprintf("%d, %d", win.rect.w, win.rect.h));
        }

        /* labels + buttons */
        if mu.header(&muiCtx, "Test Buttons", {.EXPANDED}) != {} {
            mu.layout_row(&muiCtx, { 86, -110, -1 }, 0);
            mu.label(&muiCtx, "Test buttons 1:");
            if button(&muiCtx, "Button 1") do fmt.println("Pressed button 1");
            if button(&muiCtx, "Button 2") do fmt.println("Pressed button 2");
            mu.label(&muiCtx, "Test buttons 2:");
            if button(&muiCtx, "Button 3") do fmt.println("Pressed button 3");
            if button(&muiCtx, "Button 4") do fmt.println("Pressed button 4");
        }

        /* tree */
        if mu.header(&muiCtx, "Tree and Text", {.EXPANDED}) != {} {
            mu.layout_row(&muiCtx, { 140, -1 }, 0);
            mu.layout_begin_column(&muiCtx);
            if mu.begin_treenode(&muiCtx, "Test 1") != {} {
                if mu.begin_treenode(&muiCtx, "Test 1a") != {} {
                    mu.label(&muiCtx, "Hello");
                    mu.label(&muiCtx, "world");
                    mu.end_treenode(&muiCtx);
                }
                if mu.begin_treenode(&muiCtx, "Test 1b") != {} {
                    if button(&muiCtx, "Button 1") do fmt.println("Pressed button 1");
                    if button(&muiCtx, "Button 2") do fmt.println("Pressed button 2");
                    mu.end_treenode(&muiCtx);
                }
                mu.end_treenode(&muiCtx);
            }
            if mu.begin_treenode(&muiCtx, "Test 2") != {} {
                mu.layout_row(&muiCtx, { 54, 54 }, 0);
                if button(&muiCtx, "Button 3") do fmt.println("Pressed button 3");
                if button(&muiCtx, "Button 4") do fmt.println("Pressed button 4");
                if button(&muiCtx, "Button 5") do fmt.println("Pressed button 5");
                if button(&muiCtx, "Button 6") do fmt.println("Pressed button 6");
                mu.end_treenode(&muiCtx);
            }
            if mu.begin_treenode(&muiCtx, "Test 3") != {} {
                @static checks := [3]bool{ true, false, true };
                mu.checkbox(&muiCtx, "Checkbox 1", &checks[0]);
                mu.checkbox(&muiCtx, "Checkbox 2", &checks[1]);
                mu.checkbox(&muiCtx, "Checkbox 3", &checks[2]);
                mu.end_treenode(&muiCtx);
            }
            mu.layout_end_column(&muiCtx);

            mu.layout_begin_column(&muiCtx);
            mu.layout_row(&muiCtx, { -1 }, 0);
            mu.text(&muiCtx, "Lorem ipsum\n dolor sit amet, consectetur adipiscing elit. Maecenas lacinia, sem eu lacinia molestie, mi risus faucibus ipsum, eu varius magna felis a nulla.");
            mu.layout_end_column(&muiCtx);
        }

        mu.end_window(&muiCtx);
    }
}