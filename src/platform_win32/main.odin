package main

import d3d11 "vendor:directx/d3d11"
import dxgi "vendor:directx/dxgi"
import d3d "vendor:directx/d3d_compiler"
import sdl "vendor:sdl2"
import stbi "vendor:stb/image"

import "core:c/libc"

import "core:os"
import "core:fmt"
import math "core:math/linalg/glsl"

import "core:unicode/utf8"

import dm "../dmcore"

import renderer "../renderer/renderer_d3d11"

import "core:dynlib"

import mem "core:mem/virtual"

window: ^sdl.Window

engineData: dm.Platform

SetWindowSize :: proc(width, height: int) {
    engineData.renderCtx.frameSize.x = i32(width)
    engineData.renderCtx.frameSize.y = i32(height)

    oldSize: dm.iv2
    sdl.GetWindowSize(window, &oldSize.x, &oldSize.y)

    delta := dm.iv2{i32(width), i32(height)} - oldSize
    delta /= 2

    pos: dm.iv2
    sdl.GetWindowPosition(window, &pos.x, &pos.y)
    sdl.SetWindowPosition(window, pos.x - delta.x, pos.y - delta.y)

    sdl.SetWindowSize(window, i32(width), i32(height))
    renderer.ResizeFrambuffer(engineData.renderCtx, width, height)
}

defaultWindowWidth  :: 800
defaultWindowHeight :: 600

main :: proc() {
    sdl.Init({.VIDEO, .AUDIO})
    defer sdl.Quit()

    sdl.SetHintWithPriority(sdl.HINT_RENDER_DRIVER, "direct3d11", .OVERRIDE)

    window = sdl.CreateWindow("Gold and Stone", sdl.WINDOWPOS_CENTERED, sdl.WINDOWPOS_CENTERED, 
                               defaultWindowWidth, defaultWindowHeight,
                               {.ALLOW_HIGHDPI, .HIDDEN})

    defer sdl.DestroyWindow(window);

    engineData.SetWindowSize = SetWindowSize

    engineData.renderCtx = renderer.CreateRenderContext(window)
    engineData.renderCtx.frameSize = {defaultWindowWidth, defaultWindowHeight}

    engineData.mui = dm.muiInit(engineData.renderCtx)

    engineData.audio = InitAudio()

    gameCode: GameCode
    if LoadGameCode(&gameCode, "Game.dll") == false {
        return
    }

    gameCode.setStatePointers(&engineData)
    gameCode.gameLoad(&engineData)

    sdl.ShowWindow(window)

    for shouldClose := false; !shouldClose; {
        free_all(context.temp_allocator)

        newTime, err2 := os.last_write_time_by_name("Game.dll")
        if newTime > gameCode.lastWriteTime {
            res := ReloadGameCode(&gameCode, "Game.dll")
            // gameCode.gameLoad(&engineData)
            if res {
                gameCode.setStatePointers(&engineData)
            }
        }

        // !!!!!
        using engineData
        // !!!!!

        // Frame Begin
        time.lastTicks = time.ticks
        time.ticks = sdl.GetTicks()

        deltaTicks := time.ticks - time.lastTicks

        if pauseGame == false || moveOneFrame {
            time.gameTicks += deltaTicks
            time.frame += 1
        }

        time.deltaTime = f32(deltaTicks) / 1000

        time.time = f64(time.ticks) / 1000
        time.gameTime = f64(time.gameTicks) / 1000

        // Input
        for key, state in input.curr {
            input.prev[key] = state
        }

        for mouseBtn, i in input.mouseCurr {
            input.mousePrev[i] = input.mouseCurr[i]
        }

        input.runesCount = 0
        input.scrollX = 0;
        input.scroll = 0;
        input.mouseDelta = {0, 0}

        for e: sdl.Event; sdl.PollEvent(&e); {
            #partial switch e.type {

            case .QUIT:
                shouldClose = true

            case .KEYDOWN: 
                key := SDLKeyToKey[e.key.keysym.scancode]

                if key == .Esc {
                    shouldClose = true
                }

                input.curr[key] = .Down

            case .KEYUP:
                key := SDLKeyToKey[e.key.keysym.scancode]
                input.curr[key] = .Up

            case .MOUSEMOTION:
                input.mousePos.x = e.motion.x
                input.mousePos.y = e.motion.y

                input.mouseDelta.x = e.motion.xrel
                input.mouseDelta.y = -e.motion.yrel

                // fmt.println("mousePos: ", input.mousePos)

            case .MOUSEWHEEL:
                input.scroll  = int(e.wheel.y)
                input.scrollX = int(e.wheel.x)

            case .MOUSEBUTTONDOWN:
                // NOTE: SDL mouse button indices starts at 1
                input.mouseCurr[e.button.button - 1] = .Down

            case .MOUSEBUTTONUP:
                input.mouseCurr[e.button.button - 1] = .Up

            case .TEXTINPUT:
                // @TODO: I'm not sure here, I should probably scan entire buffer
                r, i := utf8.decode_rune(e.text.text[:])
                input.runesBuffer[input.runesCount] = r
                input.runesCount += 1
            }
        }

        moveOneFrame = false

        dm.muiProcessInput(engineData.mui, &input)
        dm.muiBegin(engineData.mui)

        when ODIN_DEBUG {
            if dm.GetKeyState(&input, .U) == .JustPressed {
                debugState = !debugState
                pauseGame = debugState

                if debugState {
                    dm.muiShowWindow(mui, "Debug")
                }
            }

            if debugState && dm.muiBeginWindow(mui, "Debug", {0, 0, 100, 240}, nil) {
                dm.muiLabel(mui, "Time:", time.time)
                dm.muiLabel(mui, "GameTime:", time.gameTime)

                dm.muiLabel(mui, "Frame:", time.frame)

                if dm.muiButton(mui, "Play" if pauseGame else "Pause") {
                    pauseGame = !pauseGame
                }

                if dm.muiButton(mui, ">") {
                    moveOneFrame = true
                }

                dm.muiEndWindow(mui)
            }
        }

        if gameCode.lib != nil {
            if pauseGame == false || moveOneFrame {
                gameCode.gameUpdate(gameState)
            }

            when ODIN_DEBUG {
                if gameCode.gameUpdateDebug != nil {
                    gameCode.gameUpdateDebug(gameState, debugState)
                }
            }

            gameCode.gameRender(gameState)
        }

        renderer.FlushCommands(cast(^renderer.RenderContext_d3d) renderCtx)
        renderer.DrawPrimitiveBatch(cast(^renderer.RenderContext_d3d) renderCtx)

        dm.muiEnd(engineData.mui)
        dm.muiRender(engineData.mui, renderCtx)

        renderer.EndFrame(cast(^renderer.RenderContext_d3d) renderCtx)
    }
}