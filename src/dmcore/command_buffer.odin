package dmcore

CommandBuffer :: struct {
    commands: [dynamic]Command
}

Command :: union {
    ClearColorCommand,
    CameraCommand,
    DrawRectCommand,
}

ClearColorCommand :: struct {
    clearColor: color
}

CameraCommand :: struct {
    camera: Camera
}

DrawRectCommand :: struct {
    position: v2,
    size: v2,

    rotation: f32,

    pivot: v2,

    source: RectInt,
    tint: color,

    texture: TexHandle,
    shader: ShaderHandle,
}

ClearColor :: proc(ctx: ^RenderContext, color: color) {
    append(&ctx.commandBuffer.commands, ClearColorCommand{
        color
    })
}

DrawSprite :: proc(ctx: ^RenderContext, sprite: Sprite, position: v2, 
                   rotation: f32 = 0, color := WHITE) {
    cmd: DrawRectCommand

    texPos := sprite.atlasPos
    texPos += sprite.pixelSize * sprite.currentFrame * ({1, 0} if sprite.animDirection == .Horizontal else {0, 1})

    size := GetSpriteSize(sprite)

    cmd.position = position
    cmd.pivot = sprite.origin
    cmd.size = size
    cmd.source = {texPos.x, texPos.y, sprite.pixelSize.x, sprite.pixelSize.y}
    cmd.rotation = rotation
    cmd.tint = color
    cmd.texture = sprite.texture
    cmd.shader  = ctx.defaultShaders[.Sprite]

    append(&ctx.commandBuffer.commands, cmd)
}

DrawRect :: proc(ctx: ^RenderContext, texture: TexHandle, 
                 source: RectInt, dest: Rect, shader: ShaderHandle, 
                 color: color = WHITE)
{
    cmd: DrawRectCommand

    cmd.position = {dest.x, dest.y}
    cmd.size = {dest.width, dest.height}
    cmd.source = source
    cmd.tint = color

    cmd.texture = texture
    cmd.shader =  shader

    append(&ctx.commandBuffer.commands, cmd)
}

DrawRectSimple :: proc(ctx: ^RenderContext, texture: TexHandle, position: v2, color: color = WHITE) {
    cmd: DrawRectCommand

    texSize :=  GetTextureSize(ctx, texture)

    cmd.position = position
    cmd.size = v2Conv(texSize)
    cmd.source = {0, 0, texSize.x, texSize.y}
    cmd.tint = color

    cmd.texture = texture
    cmd.shader =  ctx.defaultShaders[.ScreenSpaceRect]

    append(&ctx.commandBuffer.commands, cmd)
}

DrawRectSize :: proc(ctx: ^RenderContext, texture: TexHandle, position: v2, size: v2, color: color = WHITE) {
    cmd: DrawRectCommand

    texSize :=  GetTextureSize(ctx, texture)

    cmd.position = position
    cmd.size = size
    cmd.source = {0, 0, texSize.x, texSize.y}
    cmd.tint = color

    cmd.texture = texture
    cmd.shader =  ctx.defaultShaders[.ScreenSpaceRect]

    append(&ctx.commandBuffer.commands, cmd)
}
SetCamera :: proc(ctx: ^RenderContext, camera: Camera) {
    append(&ctx.commandBuffer.commands, CameraCommand{
        camera
    })
}