package dmcore

import math "core:math/linalg/glsl"

import "core:fmt"

Camera :: struct {
    position: v3,

    orthoSize: f32,

    near, far, f32,

    aspect: f32,
}

CreateCamera :: proc(orthoSize, aspect, near, far: f32) -> Camera {
    return Camera {
        orthoSize = orthoSize,
        aspect = aspect,
        near = near,
        far = far,
    }
}


// @TODO: actual view matrix...
GetViewMatrix :: proc(camera: Camera) -> mat4 {
    view := math.mat4Translate(-camera.position)
    return view
}

Mat4OrthoZTO :: proc(left, right, bottom, top, near, far: f32) -> (m: mat4) {
    m[0, 0] = +2 / (right - left)
    m[1, 1] = +2 / (top - bottom)
    m[2, 2] = -1 / (far - near)
    m[0, 3] = -(right + left)   / (right - left)
    m[1, 3] = -(top   + bottom) / (top - bottom)
    m[2, 3] = -near / (far - near)
    m[3, 3] = 1
    return m
}

// @TODO: support perspective projection
GetProjectionMatrixZTO :: proc(camera: Camera) -> mat4 {
    orthoHeight := camera.orthoSize
    orthoWidth  := camera.aspect * orthoHeight

    proj := Mat4OrthoZTO(-orthoWidth, orthoWidth, 
                         -orthoHeight, orthoHeight, 
                          camera.near, camera.far)

    return proj 
}

GetProjectionMatrixNTO :: proc(camera: Camera) -> mat4 {
    orthoHeight := camera.orthoSize
    orthoWidth  := camera.aspect * orthoHeight

    proj := math.mat4Ortho3d(-orthoWidth, orthoWidth, 
                             -orthoHeight, orthoHeight, 
                              camera.near, camera.far)

    return proj
}

GetVPMatrix :: proc(camera: Camera) -> mat4 {
    orthoHeight := camera.orthoSize
    orthoWidth  := camera.aspect * orthoHeight

    proj := math.mat4Ortho3d(-orthoWidth, orthoWidth, 
                             -orthoHeight, orthoHeight, 
                              camera.near, camera.far)

    view := math.mat4Translate(camera.position)

    return proj * view
}

WorldToClipSpace :: proc(camera: Camera, point: v3) -> v3 {
    p := GetVPMatrix(camera) * v4{point.x, point.y, point.z, 1}
    p.xyz /= p.w

    return p.xyz
}

ControlCamera :: proc(camera: ^Camera, input: ^Input, timeDelta: f32) {
    horizontal := GetAxis(input, .A, .D)
    vertical   := GetAxis(input, .W, .S)

    camera.position += {horizontal, vertical, 0} * timeDelta
}

IsPointInCamera :: proc(point: v3) -> bool {
    return (point.x >= -1 && point.x <= 1) &&
           (point.y >= -1 && point.y <= 1) &&
           (point.z >= -1 && point.z <= 1)
}

IsInsideCamera :: proc {
    IsInsideCamera_Rect,
    IsInsideCamera_Sprite,
}

IsInsideCamera_Rect :: proc(camera: Camera, rect: Rect) -> bool {
    a := v2{rect.x,              rect.y}
    b := v2{rect.x,              rect.y + rect.height}
    c := v2{rect.x + rect.width, rect.y}
    d := v2{rect.x + rect.width, rect.y + rect.width}

    ac := WorldToClipSpace(camera, v3Conv(a))
    bc := WorldToClipSpace(camera, v3Conv(b))
    cc := WorldToClipSpace(camera, v3Conv(c))
    dc := WorldToClipSpace(camera, v3Conv(d))

    // fmt.println(ac, bc, cc, dc)

    return IsPointInCamera(ac) ||
           IsPointInCamera(bc) ||
           IsPointInCamera(cc) ||
           IsPointInCamera(dc)
}

IsInsideCamera_Sprite :: proc(camera: Camera, position: v2, sprite: Sprite) -> bool {
    size := GetSpriteSize(sprite)

    return IsInsideCamera_Rect(camera, {position.x, position.y, size.x, size.y})
}