package main

import mixer "vendor:sdl2/mixer"
import "core:fmt"
import str "core:strings"
import dm "../dmcore"
import "core:math/rand"

SoundData :: struct {
    sound: ^mixer.Chunk,
    channel: i32,
}

musicMap: map[string]^mixer.Music
sounds: map[string]SoundData

InitAudio :: proc() -> dm.Audio {
    mixer.Init({.MP3, .OGG})

    if mixer.OpenAudio(44100, mixer.DEFAULT_FORMAT, 2, 2048) < 0 {
        fmt.println("Can't initialize audio")
    }

    audio: dm.Audio
    audio.PlayMusic = PlayMusic
    audio.PlaySound = PlaySound

    return audio
}

PlayMusic :: proc(path: string, loop: bool = true) {
    if path in musicMap == false {
        cpath := str.clone_to_cstring(path, context.temp_allocator)
        music := mixer.LoadMUS(cpath)

        if music == nil {
            fmt.println("Can't open music at path:", path)
            return
        }

        musicMap[path] = music
    }

    mixer.PlayMusic(musicMap[path], loop ? -1 : 0)
}

PlaySound :: proc(path: string) {
    @static lastChannel: i32
    if path in sounds == false {
        cpath := str.clone_to_cstring(path, context.temp_allocator)
        sound := mixer.LoadWAV(cpath)
 
        if sound == nil {
            fmt.println("Can't open sound at path:", path)
            return
        }

        sounds[path] = SoundData {
            sound, lastChannel
        }

        lastChannel = (lastChannel + 1) % mixer.CHANNELS
    }

    s := sounds[path]
    mixer.PlayChannel(s.channel, s.sound, 0)
}