package dmcore

import math "core:math/linalg/glsl"
import mem "core:mem/virtual"

import "../renderer"
// Math types
v2  :: math.vec2
iv2 :: math.ivec2

v3 :: math.vec3
iv3 :: math.ivec3

v4 :: math.vec4

mat4 :: math.mat4

color :: math.vec4

WHITE   : color : {1, 1, 1, 1}
BLACK   : color : {0, 0, 0, 1}
RED     : color : {1, 0, 0, 1}
GREEN   : color : {0, 1, 0, 1}
BLUE    : color : {0, 0, 1, 1}
SKYBLUE : color : {0.4, 0.75, 1, 1}
LIME    : color : {0, 0.62, 0.18, 1}
DARKGREEN : color : {0, 0.46, 0.17, 1}

Rect :: struct {
    x, y: f32,
    width, height: f32,
}

RectInt :: struct {
    x, y: i32,
    width, height: i32,
}

Bounds2D :: struct {
    left, right: f32,
    bot, top: f32,
}

CreateBounds :: proc(pos: v2, size: v2, anchor: v2 = {0.5, 0.5}) -> Bounds2D {
    anchor := math.saturate(anchor)

    return {
        left  = pos.x - size.x * anchor.x,
        right = pos.x + size.x * (1 - anchor.x),
        bot   = pos.y - size.y * anchor.y,
        top   = pos.y + size.y * (1 - anchor.y),
    }
}

///////////

TimeData :: struct {
    deltaTime: f32,

    ticks: u32,
    lastTicks: u32,

    gameTicks: u32,

    frame: uint,

    gameTime: f64,
    time: f64, // time as if game was never paused
}

///////////////

Platform :: struct {
    mui:       ^Mui,
    input:     Input,
    time:      TimeData,
    renderCtx: ^RenderContext,
    audio:     Audio,

    gameState: rawptr,

    debugState: bool,
    pauseGame: bool,
    moveOneFrame: bool,

    SetWindowSize: proc(width, height: int),
}

AlocateGameData :: proc(platform: ^Platform, $type: typeid) -> ^type {
    platform.gameState = new(type)

    return cast(^type) platform.gameState
}

Audio :: struct {
    PlayMusic: proc(path: string, loop: bool = false),
    PlaySound: proc(path: string)
}

///////

GameLoad   :: proc(platform: ^Platform)
GameUpdate :: proc(gameState: rawptr)
GameRender :: proc(gameState: rawptr)
GameReload :: proc(gameState: rawptr)
GameUpdateDebug :: proc(gameState: rawptr, debug: bool)
UpdateStatePointerFunc :: proc(platformPtr: ^Platform)
