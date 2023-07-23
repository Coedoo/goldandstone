package game

import "core:fmt"
import rand "core:math/rand"
import math "core:math/linalg/glsl"

import dm "../dmcore"

import "core:mem"

import globals "../dmcore/globals"

import "core:math/linalg/glsl"

ColorGround : dm.color : { 71./255., 45./255., 60./255., 1 }
PlayerColor : dm.color : dm.WHITE
EnemyColor  : dm.color : {0.98, 0.04, 0.04 , 1}
WallColor   : dm.color : { 207./255., 198./255., 184./255., 1 }
GoldColor   : dm.color : { 244./255., 180./255., 27./255., 1 }

gameState: ^GameState

State :: enum {
    TitleScreen,
    Game,
    Dead,
    Won,
}

GameState :: struct {
    world: World,
    entities: dm.ResourcePool(Entity),

    playerHandle: EntityHandle,

    camera: dm.Camera,

    /// Assets
    atlas: dm.TexHandle,
    targetSprite: dm.Sprite,

    topWallSprite:      dm.Sprite,
    botWallSprite:      dm.Sprite,
    leftWallSprite:     dm.Sprite,
    rightWallSprite:    dm.Sprite,
    topLeftWallSprite:  dm.Sprite,
    topRightWallSprite: dm.Sprite,
    botLeftWallSprite:  dm.Sprite,
    botRightWallSprite: dm.Sprite,
    filledWallSprite:   dm.Sprite,

    font: dm.Font,

    /////////
    state: State,

    playerMovedThisFrame: bool,
    playerMovedLastFrame: bool,

    messageBuffer: [1024]byte,
    messageTimer: f32,
    messageText: string,

    finalChunkCenter: dm.iv2,

    ////////

    gold: int,
    pickaxeLevel: int,
}


PickaxeDamageTable := [?]int {
    10, 15, 20, 30, 40
}


PickaxeUpgradeCostTable := [?]int {
    150, 170, 230, 270, 350,
}

PickaxeDamage :: proc() -> int {
    idx := clamp(0, len(PickaxeDamageTable) - 1, gameState.pickaxeLevel)
    return PickaxeDamageTable[idx]
}

PickaxeUpgradeCost :: proc() -> int {
    idx := clamp(0, len(PickaxeUpgradeCostTable) - 1, gameState.pickaxeLevel)
    return PickaxeUpgradeCostTable[idx]
}

RestartGame :: proc() {
    DestroyWorld(&gameState.world)
    dm.ClearPool(gameState.entities)

    StartGame()
}

StartGame :: proc() {
    gameState.world = CreateWorld()
    gameState.state = .TitleScreen


    player := CreatePlayerEntity(gameState.world)
    gameState.playerHandle = player.handle
}

GetPlayer :: proc() -> ^Entity {
    return dm.GetElement(gameState.entities, auto_cast gameState.playerHandle)
}

ShowMessage :: proc(objs: ..any) {
    gameState.messageText = fmt.bprint(gameState.messageBuffer[:], ..objs)
    gameState.messageTimer = 5
}

RemoveGold :: proc(gold: int) -> bool {
    if gameState.gold >= gold {
        gameState.gold -= gold
        return true
    }
    else {
        ShowMessage("Not enough gold!")
        return false
    } 
}

SqrDist :: proc(a, b: dm.iv2) -> i32 {
    d := a - b
    return d.x * d.x + d.y * d.y 
}

@(export)
GameLoad : dm.GameLoad : proc(platform: ^dm.Platform) {
    gameState = dm.AlocateGameData(platform, GameState)
    dm.InitResourcePool(&gameState.entities, 1024)

    gameState.camera = dm.CreateCamera(7, 4./3., 0.0001, 1000)
    gameState.camera.position.z = 1

    gameState.atlas = dm.LoadTextureFromFile("assets/atlas.png", globals.renderCtx)
    gameState.targetSprite = dm.CreateSprite(gameState.atlas, {16, 0, 16, 16})

    wallSprite := dm.CreateSprite(gameState.atlas, {16 * 6, 16, 16, 16})

    gameState.filledWallSprite = wallSprite

    wallSprite.atlasPos.y -= 16
    gameState.topWallSprite = wallSprite

    wallSprite.atlasPos.x -= 16
    gameState.topLeftWallSprite = wallSprite

    wallSprite.atlasPos.y += 16
    gameState.leftWallSprite = wallSprite

    wallSprite.atlasPos.y += 16
    gameState.botLeftWallSprite = wallSprite

    wallSprite.atlasPos.x += 16
    gameState.botWallSprite = wallSprite

    wallSprite.atlasPos.x += 16
    gameState.botRightWallSprite = wallSprite

    wallSprite.atlasPos.y -= 16
    gameState.rightWallSprite = wallSprite

    wallSprite.atlasPos.y -= 16
    gameState.topRightWallSprite = wallSprite

    gameState.font = dm.LoadFontSDF(globals.renderCtx, "assets/Kenney Pixel.ttf", 64)


    ////////////////////////////

    StartGame()
}

@(export)
GameUpdate : dm.GameUpdate : proc(state: rawptr) {
    gameState = cast(^GameState) state
    player := dm.GetElement(gameState.entities, auto_cast gameState.playerHandle)

    if gameState.state == .TitleScreen {
        if dm.GetKeyState(globals.input, .Space) == .JustPressed {
            gameState.state = .Game
        }
    }

    if gameState.state == .Game {
        gameState.playerMovedThisFrame = false
        for &e in gameState.entities.elements {
            if dm.IsHandleValid(gameState.entities, auto_cast e.handle) == false {
                continue
            }

            ControlEntity(&e)

            if .Lifetime in e.flags {
                e.lifetime -= globals.time.deltaTime

                if e.lifetime < 0 {
                    DestroyEntity(e.handle)
                }
            }
        }

        gameState.playerMovedLastFrame = gameState.playerMovedThisFrame

        delta := dm.v2Conv(player.position - gameState.finalChunkCenter)
        if  glsl.length(delta) < 10 {
            gameState.state = .Won
        } 
    }

    if gameState.state == .Dead || gameState.state == .Won {
        if dm.GetKeyState(globals.input, .Space) == .JustPressed {
            RestartGame()
        }
    }


    // assert(dm.IsHandleValid(gameState.entities, auto_cast gameState.playerHandle))


    if player != nil {
        gameState.camera.position.x = cast(f32) player.position.x
        gameState.camera.position.y = cast(f32) player.position.y


        //// INPUT /////

        if dm.GetKeyState(globals.input, .X) == .JustPressed {
            dir := gameState.finalChunkCenter - player.position

            if abs(dir.x) > abs(dir.y) {
                dir.x = glsl.sign(dir.x)
                dir.y = 0
            }
            else {
                dir.x = 0
                dir.y = glsl.sign(dir.y)
            }

            heading := HeadingFromDir(dir)

            ShowMessage("Treasure Room is\nsomewhere", heading)
        }

        if dm.GetKeyState(globals.input, .Num1) == .JustPressed {
            if RemoveGold(PickaxeUpgradeCost()) {
                gameState.pickaxeLevel += 1
            }
        }
    }

    if gameState.messageTimer > 0 {
        gameState.messageTimer -= globals.time.deltaTime
    }
}

@(export)
GameUpdateDebug : dm.GameUpdateDebug : proc(state: rawptr, debug: bool) {
    gameState = cast(^GameState) state

    player := dm.GetElement(gameState.entities, auto_cast gameState.playerHandle)

    @static selectedTile: ^Tile
    if dm.GetMouseButton(globals.input, .Left) == .JustPressed {
        mousePos := globals.input.mousePos
        normPos := dm.v2{f32(mousePos.x) / f32(globals.renderCtx.frameSize.x), 
                         f32(mousePos.y) / f32(globals.renderCtx.frameSize.y)} * 2 - 1

        camPos := gameState.camera.position
        camHeight := gameState.camera.orthoSize
        camWidth  := gameState.camera.aspect * camHeight

        worldPos := dm.v2{camPos.x, camPos.y} + normPos * {camWidth, -camHeight}
        worldPos = math.round(worldPos)

        selectedTile = GetWorldTile(gameState.world, {i32(worldPos.x), i32(worldPos.y)})
    }

    
    if dm.muiBeginWindow(globals.mui, "Game Debug", {globals.renderCtx.frameSize.x - 160, 0, 150, 120}, nil) {
        if dm.muiButton(globals.mui, "Refresh") {
            RestartGame()
        }

        if selectedTile != nil {
            dm.muiLabel(globals.mui, selectedTile.holdedEntity)
            dm.muiLabel(globals.mui, selectedTile.traversableEntity)
            dm.muiLabel(globals.mui, selectedTile.indestructible)
            dm.muiLabel(globals.mui, selectedTile.haveVisual)
        }

        dm.muiLabel(globals.mui, "State:", gameState.state)

        dm.muiEndWindow(globals.mui)
    }

    if debug {
        gameState.camera.orthoSize -= f32(globals.input.scroll)

        if dm.GetMouseButton(globals.input, .Right) == .Down {
            gameState.camera.position.xy -= cast([2]f32) dm.v2Conv(globals.input.mouseDelta) * 0.1
        }
    }
}


GetWallColor :: proc(tile: Tile) -> dm.color {
    if tile.indestructible {
        return dm.BLACK
    }
    else if tile.containsGold {
        return GoldColor
    }
    else {
        c := WallColor / f32(tile.level + 1)
        c.a = 1
        return c
    }
}

DrawTextWithBackground :: proc(text: string, pos: dm.iv2, fontSize: int, centered: bool) {
    pos := pos
    size := dm.MeasureText(text, gameState.font, fontSize)
    
    if centered {
        pos -= size / 2
    }

    ctx := globals.renderCtx
    dm.DrawRectSize(ctx, ctx.whiteTexture, dm.v2Conv(pos - {2, -2}), dm.v2Conv(size + {4, 4}), {0, 0, 0, 0.75})
    dm.DrawText(ctx, text, gameState.font, pos, fontSize)
}

DrawTitleScreen :: proc() {
    ctx := globals.renderCtx

    windowSize := globals.renderCtx.frameSize

    rectSize := dm.iv2{windowSize.x - 50, windowSize.y - 100}
    rectPos := windowSize / 2 - rectSize / 2

    dm.DrawRectSize(ctx, ctx.whiteTexture, dm.v2Conv(rectPos), dm.v2Conv(rectSize), {0, 0, 0, .86})

    title := "GOLD and STONE"
    dm.DrawTextCentered(ctx, title, gameState.font, {windowSize.x / 2, rectPos.y + 30}, 55)

    draft := `
The legend says, somewhere in this caverns lays 
The Treasure of The Mad King.
Many have tried to find it but no one returned.
You, The Brave Dwarf, took the challange and with 
help of the Magic Compass,you WILL find
The Treasure!
`
    dm.DrawTextCentered(ctx, draft, gameState.font, {windowSize.x / 2, rectPos.y + 170}, 30)

    dm.DrawTextCentered(ctx, "Controls:", gameState.font, {windowSize.x / 2, rectPos.y + 300}, 35)

    controlsText :=`
Arrows - Move
Space - Attack/Dig
X - Use Magic Compass
`
    dm.DrawTextCentered(ctx, controlsText, gameState.font, {windowSize.x / 2, rectPos.y + 370}, 30)
}


DrawGameUI :: proc() {
    ctx := globals.renderCtx

    player := dm.GetElement(gameState.entities, auto_cast gameState.playerHandle)
    DrawTextWithBackground(
        fmt.tprint("Health:", player.HP if player != nil else 0,
            "\nGold:", gameState.gold), 
        {0, 0},
        32, false,
    )

    dm.DrawRectSize(ctx, ctx.whiteTexture, {0, 74}, {220, 90}, {0, 0, 0, 0.75})
    dm.DrawText(globals.renderCtx, 
            fmt.tprint("Pickaxe level:", gameState.pickaxeLevel), 
            gameState.font,
            {0, 64 + 10}, 32)

    dm.DrawText(globals.renderCtx, 
            fmt.tprintf("Damage: %v \nPress '1' to upgrade (%v)", PickaxeDamage(), PickaxeUpgradeCost()), 
            gameState.font,
            {0, 64 + 32 + 10}, 20)

    if gameState.messageTimer > 0 {
        DrawTextWithBackground(gameState.messageText, {400, 500}, 20, true)
    }
}

DrawDeadScreen :: proc() {
    ctx := globals.renderCtx

    windowSize := globals.renderCtx.frameSize

    rectSize := dm.iv2{windowSize.x - 50, windowSize.y - 100}
    rectPos := windowSize / 2 - rectSize / 2

    dm.DrawRectSize(ctx, ctx.whiteTexture, dm.v2Conv(rectPos), dm.v2Conv(rectSize), {0, 0, 0, .86})

    title := "You have been slain"
    dm.DrawTextCentered(ctx, title, gameState.font, {windowSize.x / 2, rectPos.y + 30}, 64)

    draft := `
Your journey ends here Brave Dwarf.
`
    dm.DrawTextCentered(ctx, draft, gameState.font, {windowSize.x / 2, rectPos.y + rectSize.y / 2 - 30}, 45)

    dm.DrawTextCentered(ctx, "Press space to restart", gameState.font, {windowSize.x / 2, rectPos.y + rectSize.y / 2 + 100}, 30)
}

DrawWinScreen :: proc() {
    ctx := globals.renderCtx

    windowSize := globals.renderCtx.frameSize

    rectSize := dm.iv2{windowSize.x - 50, windowSize.y - 100}
    rectPos := windowSize / 2 - rectSize / 2

    dm.DrawRectSize(ctx, ctx.whiteTexture, dm.v2Conv(rectPos), dm.v2Conv(rectSize), {0, 0, 0, .86})

    // title := "GOLD and STONE"
    // dm.DrawTextCentered(ctx, title, gameState.font, {windowSize.x / 2, rectPos.y + 30}, 55)

    draft := `
Brave Dwarf!
You found The Mad King's Treasure!

With all the richness you can buy
infinite supply of the finest dwarf Ale!
`
    dm.DrawTextCentered(ctx, draft, gameState.font, {windowSize.x / 2, rectPos.y + 170}, 30)
    
    dm.DrawTextCentered(ctx, "Press space to restart", gameState.font, {windowSize.x / 2, rectPos.y + rectSize.y / 2 + 200}, 30)
}

IsInView :: proc(cameraBounds: dm.Bounds2D, pos, size: dm.iv2) -> bool {
    bounds := dm.CreateBounds(dm.v2Conv(pos), dm.v2Conv(size))
    return dm.CheckCollisionBounds(cameraBounds, bounds)
}

@(export)
GameRender : dm.GameRender : proc(state: rawptr) {
    dm.SetCamera(globals.renderCtx, gameState.camera)
    dm.ClearColor(globals.renderCtx, ColorGround)

    ctx := globals.renderCtx

    camPos := gameState.camera.position
    camHeight := gameState.camera.orthoSize
    camWidth  := gameState.camera.aspect * camHeight
    cameraBounds := dm.Bounds2D{
        camPos.x - camWidth, camPos.x + camWidth,
        camPos.y - camHeight, camPos.y + camHeight,
    }

    /// Walls
    for chunk in gameState.world.chunks {
        for tile in chunk.tiles {
            if IsInView(cameraBounds, tile.position, {1, 1}) == false {
                continue
            }

            if tile.neighbours == NotVisible {
                continue
            }

            if tile.isWall || tile.haveVisual {
                assert(tile.sprite.texture.index != 0)
                color := chunk.isFinal ? GoldColor : GetWallColor(tile)
                dm.DrawSprite(ctx, tile.sprite, dm.v2Conv(tile.position), color = color)
            }
        }
    }

    /// Entities
    for &e in gameState.entities.elements {
        if dm.IsHandleValid(gameState.entities, auto_cast e.handle) == false {
            continue
        }

        if IsInView(cameraBounds, e.position, {1, 1}) == false {
            continue
        }

        dm.DrawSprite(ctx, e.sprite, dm.v2Conv(e.position), color = e.tint)

        if .CanAttack in e.flags {
            c := e.tint
            c.a = 0.5
            dm.DrawSprite(ctx, gameState.targetSprite, dm.v2Conv(e.position + Dir(e.direction)), color = c)
        }

        if globals.platform.debugState && e.controler == .Enemy {
            dm.DrawCircle(globals.renderCtx, dm.v2Conv(e.position), cast(f32) e.detectionRadius, dm.RED)
        }
    }

    /// UI
    switch gameState.state {
        case .TitleScreen: DrawTitleScreen()
        case .Game:        DrawGameUI()
        case .Dead:        DrawDeadScreen()
        case .Won:         DrawWinScreen()
    }
}