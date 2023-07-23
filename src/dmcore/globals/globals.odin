package globals

import dm ".."

import "core:fmt"

input: ^dm.Input
time: ^dm.TimeData
renderCtx: ^dm.RenderContext
audio: ^dm.Audio
mui: ^dm.Mui

platform: ^dm.Platform

@(export)
UpdateStatePointer : dm.UpdateStatePointerFunc : proc(platformPtr: ^dm.Platform) {
    platform = platformPtr

    input     = &platformPtr.input
    time      = &platformPtr.time
    renderCtx = platformPtr.renderCtx
    audio     = &platformPtr.audio
    mui       = platformPtr.mui
}