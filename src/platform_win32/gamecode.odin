package main

import "core:dynlib"
import "core:os"
import "core:fmt"

import dm "../dmcore"

GameCode :: struct {
    lib: dynlib.Library,

    lastWriteTime: os.File_Time,

    setStatePointers: dm.UpdateStatePointerFunc,

    gameLoad:   dm.GameLoad,
    gameUpdate: dm.GameUpdate,
    gameUpdateDebug: dm.GameUpdateDebug,
    gameRender: dm.GameRender,
}

LoadProc :: proc(lib: dynlib.Library, name: string, $type: typeid) -> type {
    ptr, ok := dynlib.symbol_address(lib, name)
    if ok == false {
        fmt.println("Can't find proc with name: ", name)
        return nil
    }

    return cast(type) ptr
}

LoadGameCode :: proc(gameCode: ^GameCode, libName: string) -> bool {
    @static session: int
    tempLibName :: "Temp%v.dll"

    fmt.println("Loading Game Code...")

    data, r := os.read_entire_file(libName, context.temp_allocator)
    if r == false {
        fmt.println("Cannot Open Game.dll")
        return false
    }

    dllName := fmt.tprintf(tempLibName, session)
    r = os.write_entire_file(dllName, data)

    if r == false {
        fmt.println("Cannot Write to Temp.dll")
        return false
    }

    if gameCode.lib != nil {
        UnloadGameCode(gameCode)
    }

    lib, ok := dynlib.load_library(dllName)
    if ok == false {
        fmt.println("Cannot open game code!")
        return false
    }

    session += 1

    writeTime, err := os.last_write_time_by_name(libName)

    gameCode.lib = lib
    gameCode.lastWriteTime = writeTime;

    gameCode.gameLoad   = LoadProc(lib, "GameLoad",   dm.GameLoad)
    gameCode.gameUpdate = LoadProc(lib, "GameUpdate", dm.GameUpdate)
    gameCode.gameRender = LoadProc(lib, "GameRender", dm.GameRender)
    gameCode.gameUpdateDebug = LoadProc(lib, "GameUpdateDebug", dm.GameUpdateDebug)
    gameCode.setStatePointers = LoadProc(lib, "UpdateStatePointer", dm.UpdateStatePointerFunc)

    return true
}

UnloadGameCode :: proc(gameCode: ^GameCode) {
    fmt.println("Unloading Game Code...")
    didUnload := dynlib.unload_library(gameCode.lib)

    if didUnload == false {
        fmt.println("FUUUUUUUUUUUUUUCK.....")
    }

    gameCode^ = {} 
}

ReloadGameCode :: proc(gameCode: ^GameCode, libName: string) -> bool {
    result := LoadGameCode(gameCode, libName)

    // assert(result)

    return result
}
