package dmcore

import "core:math"
import "core:math/linalg/glsl"


DirectionFromRotation :: proc(rotation: f32) -> v2 {
    return {
        math.cos(math.to_radians(rotation)),
        math.sin(math.to_radians(rotation)),
    }
}


v2Conv :: proc {
    ToV2FromIV2,
    ToV2FromV3,
}

ToV2FromIV2 :: proc(v: iv2) -> v2 {
    return {f32(v.x), f32(v.y)}
}

ToV2FromV3 :: proc(v: v3) -> v2 {
    return {v.x, v.y}
}

iv2Conv :: proc {
    ToIV2FromV2,
}

ToIV2FromV2 :: proc(v: v2) -> iv2 {
    return {i32(v.x), i32(v.y)}
}

v3Conv :: proc {
    ToV3FromV2
}

ToV3FromV2 :: proc(v: v2) -> v3 {
    return {v.x, v.y, 0}
}

//////////
// Collisions
/////////

CheckCollisionBounds :: proc(a, b: Bounds2D) -> bool {
    return a.left  <= b.right &&
           a.right >= b.left  &&
           a.bot   <= b.top   &&
           a.top   >= b.bot
}

CheckCollisionCircles :: proc(aPos: v2, aRad: f32, bPos: v2, bRad: f32) -> bool {
    delta := aPos - bPos
    sum := aRad + bRad 
    return delta.x * delta.x + delta.y * delta.y <= sum * sum
}

CheckCollisionBoundsCircle :: proc(a: Bounds2D, bPos: v2, bRad: f32) -> bool {
    x := max(a.left, min(bPos.x, a.right))
    y := max(a.bot,  min(bPos.y, a.top))

    dist := (x - bPos.x) * (x - bPos.x) +
            (y - bPos.y) * (y - bPos.y)

    return dist < bRad * bRad
}