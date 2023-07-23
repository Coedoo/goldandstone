package dmcore

InputState :: enum {
    Up,
    Down,
    JustPressed,
    JustReleased,
}

MouseButton :: enum {
    Left,
    Middle,
    Right,
}

// @NOTE: it's not completed
Key :: enum {
    UNKNOWN,
    A, B, C, D, E, F, G, H, I, J, K, L, M, N, O, P, R, S, T, U, V, W, X, Y, Z,
    Num0, Num1, Num2, Num3, Num4, Num5, Num6, Num7, Num8, Num9,
    F1, F2, F3, F4, F5, F6, F7, F8, F9, F10, F11, F12,
    Space, Backspace, Return, Tab, Esc,
    LShift, RShift, LCtrl, RCtrl, LAlt, RAlt,
    Left, Right, Up, Down,
}


Input :: struct {
    prev: map[Key]InputState,
    curr: map[Key]InputState,

    mousePos:   iv2,
    mouseDelta: iv2,

    scroll: int,
    scrollX: int,

    mousePrev: [len(MouseButton)]InputState,
    mouseCurr: [len(MouseButton)]InputState,

    runesCount: int,
    runesBuffer: [16]rune,
}

GetKeyState :: proc(input: ^Input, key: Key) -> InputState {
    curr := input.curr[key]
    prev := input.prev[key]
    
    if curr == prev {
        return curr
    }
    else if curr == .Down && prev == .Up {
        return .JustPressed
    }
    else {
        return .JustReleased
    }
}

GetMouseButton :: proc(input: ^Input, btn: MouseButton) -> InputState {
    curr := input.mouseCurr[btn]
    prev := input.mousePrev[btn]
    
    if curr == prev {
        return curr
    }
    else if curr == .Down && prev == .Up {
        return .JustPressed
    }
    else {
        return .JustReleased
    }
}

GetAxis :: proc(input: ^Input, left: Key, right: Key) -> f32 {
    if GetKeyState(input, left) == .Down {
        return -1
    }
    else if GetKeyState(input, right) == .Down {
        return 1
    }

    return 0
}

GetAxisInt :: proc(input: ^Input, left: Key, right: Key, state: InputState = .Down) -> i32 {
    if GetKeyState(input, left) == state {
        return -1
    }
    else if GetKeyState(input, right) == state {
        return 1
    }

    return 0
}


InputDebugWindow :: proc(input: ^Input, mui: ^Mui) {
    if muiBeginWindow(mui, "Input", {0, 0, 100, 200}, nil) {

        for key, state in input.curr {
            muiLabel(mui, key, state)
        }

        muiEndWindow(mui)
    }
}