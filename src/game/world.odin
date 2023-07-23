package game

import dm "../dmcore"

import "core:math/rand"
import "core:math/linalg/glsl"
import "core:fmt"

import "core:container/queue"

import globals "../dmcore/globals"

WorldSize :: dm.iv2{5,  5}
ChunkSize :: dm.iv2{32, 32}

StartChunk :: dm.iv2{2, 2}

GenSteps :: 4

GoldPerRoom :: 60
GoldPerPickup :: 20
EnemiesPerRoom :: 8

FinalChunkLevel :: 6

HealthValue :: 10

World :: struct {
    chunks: []Chunk,

    nextRegion: int,
}

Chunk :: struct {
    offset: dm.iv2,
    tiles: []Tile,

    isFinal: bool,
}

Tile :: struct {
    chunk: ^Chunk,

    position: dm.iv2,
    localPos: dm.iv2,

    neighbours: HeadingsSet,

    isWall: bool,
    indestructible: bool,

    haveVisual: bool,
    sprite: dm.Sprite,

    containsGold: bool,

    traversableEntity: EntityHandle,
    holdedEntity: EntityHandle,

    level: int,

    regionNumber: int,
}

HeadingsSet :: bit_set[Heading]
Top      :: HeadingsSet{ .South, .West, .East }
Bot      :: HeadingsSet{ .North, .West, .East }
Left     :: HeadingsSet{ .South, .North, .East }
Right    :: HeadingsSet{ .South, .North, .West }
BotRight :: HeadingsSet{ .North, .West }
BotLeft  :: HeadingsSet{ .North, .East }
TopRight :: HeadingsSet{ .South, .West }
TopLeft  :: HeadingsSet{ .South, .East }
NotVisible :: HeadingsSet{ .South, .East, .North, .West }

RandRange :: proc(min, max: u32) -> u32 {
    delta := max - min
    return min + (rand.uint32() % delta)
}

InitChunk :: proc(chunk: ^Chunk) {
    chunk.tiles = make([]Tile, ChunkSize.x * ChunkSize.y)

    delta := chunk.offset - StartChunk
    level := abs(delta.x) + abs(delta.y)

    for y in 0..<ChunkSize.y {
        for x in 0..<ChunkSize.x {
            idx := y * ChunkSize.x + x

            chunk.tiles[idx].isWall = (rand.uint32() % 2) == 1

            // chunk.tiles[idx].sprite    = dm.CreateSprite(gameState.atlas, {0, 32, 16, 16})
            chunk.tiles[idx].localPos  = {x, y}
            chunk.tiles[idx].position  = chunk.offset * ChunkSize + {x, y}

            chunk.tiles[idx].level = cast(int) level

            chunk.tiles[idx].chunk = chunk
        }
    }
}

GetChunk :: proc(world: World, x, y: i32) -> ^Chunk {
    idx := y * WorldSize.x + x
    return &world.chunks[idx]
} 

GetChunkFromWorldPos :: proc(world: World, x, y: i32) -> ^Chunk  {
    offset := dm.iv2{x, y} / ChunkSize
    return GetChunk(world, offset.x, offset.y)
}

CreateWorld :: proc() -> (world: World) {
    world.chunks = make([]Chunk, WorldSize.x * WorldSize.y)

    // rand.set_global_seed(0)

    for &chunk, i in world.chunks {
        chunk.offset = {
            i32(i) % WorldSize.x,
            i32(i) / WorldSize.x
        }

        InitChunk(&chunk)
    }

    // Create free space around player spawn
    chunk := GetChunk(world, StartChunk.x, StartChunk.y)
    startPos := ChunkSize / 2

    for y in startPos.y-5..=startPos.y+5 {
        for x in startPos.x-5..=startPos.x+5 {
            idx := y * ChunkSize.x + x
            chunk.tiles[idx].isWall = false
        }
    }

    // Cellural Automata step
    for step in 0..<GenSteps {
        GenStep(&world)
    }

    // Create wall around world
    worldSize := WorldSize * ChunkSize
    for x in 0..<worldSize.x {
        tileA := GetWorldTile(world, {x, 0})
        tileB := GetWorldTile(world, {x, worldSize.y - 1})

        tileA.isWall = true
        tileB.isWall = true

        tileA.indestructible = true
        tileB.indestructible = true
    }

    for y in 0..<worldSize.y {
        tileA := GetWorldTile(world, {0, y})
        tileB := GetWorldTile(world, {worldSize.x - 1, y})

        tileA.isWall = true
        tileB.isWall = true

        tileA.indestructible = true
        tileB.indestructible = true
    }

    // Find final chunk
    {
        x := cast(i32) RandRange(0, u32(WorldSize.x))
        y := i32(RandRange(0, 2)) * (WorldSize.y - 1)

        fmt.println(x, y)

        chunk := GetChunk(world, x, y)
        chunk.isFinal = true

        startPosX:int = int(ChunkSize.x) / 2
        startPosY:int = int(ChunkSize.y) / 2
        radius := 14

        startPos := dm.v2{f32(startPosX), f32(startPosY)}

        gameState.finalChunkCenter = chunk.offset * ChunkSize + ChunkSize / 2

        for &t in chunk.tiles {
            t.level = FinalChunkLevel
        }

        for y in startPosY-radius..=startPosY+radius {
            for x in startPosX-radius..=startPosX+radius {

                if glsl.length(dm.v2{f32(x), f32(y)} - startPos) <= f32(radius) {
                    tile := GetTile(chunk^, dm.iv2{i32(x), i32(y)})
                    tile.isWall = false

                    tile.haveVisual = true
                    idx := RandRange(0, 5)
                    tile.sprite = dm.CreateSprite(gameState.atlas, {i32(idx) * 16, 3 * 16, 16, 16})
                }
            }
        }
    }

    // Create gold, enemies and foliage
    for chunk in world.chunks {
        if chunk.isFinal {
            continue
        }

        for i in 0..<GoldPerRoom {
            idx := RandRange(0, cast(u32) len(chunk.tiles))
            tile := &chunk.tiles[idx]

            if tile.isWall {
                tile.containsGold = true
            }
            else {
                CreateGoldPickup(world, tile.position, GoldPerPickup)
            }
        }

        startPos := StartChunk * ChunkSize + ChunkSize / 2
        emptyTiles := FindEmptyTiles(chunk)
        for i in 0..<EnemiesPerRoom {
            idx := RandRange(0, cast(u32) len(emptyTiles))
            tilePos := emptyTiles[idx]

            if SqrDist(tilePos, startPos) < 10 {
                continue
            }

            tile := GetWorldTile(world, tilePos)
            CreateEnemy(world, tilePos, tile.level)

            unordered_remove(&emptyTiles, cast(int) idx)
        }

        for &t in chunk.tiles {
            if t.isWall == false && t.haveVisual == false {
                t.haveVisual = RandRange(0, 100) < 1
                if t.haveVisual {
                    t.sprite = dm.CreateSprite(gameState.atlas, {0, 2 * 16, 16, 16})
                }
            }
        }
    }


    for chunk in world.chunks {
        UpdateChunk(world, chunk)
    }

    return
}

FindEmptyTiles :: proc(chunk: Chunk) -> [dynamic]dm.iv2 {
    tiles := make([dynamic]dm.iv2, 0, (ChunkSize.x * ChunkSize.y) / 2, context.temp_allocator)

    for t in chunk.tiles {
        if t.isWall == false {
            append(&tiles, t.position)
        }
    }

    return tiles
}

DestroyWorld :: proc(world: ^World) {
    for chunk in world.chunks {
        delete(chunk.tiles)
    }

    delete(world.chunks)
}


IsInsideChunk :: proc(pos: dm.iv2) -> bool {
    return pos.x >= 0 && pos.x < ChunkSize.x &&
           pos.y >= 0 && pos.y < ChunkSize.y
}

IsInsideWorld :: proc(pos: dm.iv2) -> bool {
    return pos.x >= 0 && pos.x < ChunkSize.x * WorldSize.x &&
           pos.y >= 0 && pos.y < ChunkSize.y * WorldSize.y
}

GetWorldTile :: proc(world: World, pos: dm.iv2) -> ^Tile {
    chunkPos := pos / ChunkSize
    idx := chunkPos.y * WorldSize.x + chunkPos.x

    localPos := pos - chunkPos * ChunkSize

    return GetTile(world.chunks[idx], localPos)
}

GetTile :: proc(chunk: Chunk, pos: dm.iv2) -> ^Tile {
    idx := pos.y * ChunkSize.x + pos.x
    return &chunk.tiles[idx]
}

IsTileOccupied :: proc(world: World, worldPos: dm.iv2) -> bool {
    tile := GetWorldTile(world, worldPos)
    validHandle := dm.IsHandleValid(gameState.entities, auto_cast tile.holdedEntity)

    return tile.isWall || validHandle
}

DestroyWallAt :: proc(world: World, worldPos: dm.iv2) -> bool {
    tile := GetWorldTile(world, worldPos)
    assert(tile != nil)

    globals.audio.PlaySound("assets/soundMine.mp3")

    if tile.indestructible == false {
        tile.isWall = false
        if tile.containsGold {
            CreateGoldPickup(world, tile.position, GoldPerPickup)
        }
        else if RandRange(0, 100) < 4 {
            CreateHealthPickup(world, tile.position, HealthValue)
        }

        UpdateChunk(world, tile.chunk^)

        updateOtherChunk := false
        otherPos: dm.iv2

        if tile.localPos.x == 0 {
            otherPos = dm.iv2{worldPos.x - 1, worldPos.y}
            updateOtherChunk = true
        }
        
        if tile.localPos.x == ChunkSize.x - 1 {
            otherPos = dm.iv2{worldPos.x + 1, worldPos.y}
            updateOtherChunk = true
        }

        if tile.localPos.y == 0 {
            otherPos = dm.iv2{worldPos.x, worldPos.y - 1}
            updateOtherChunk = true
        }

        if tile.localPos.y == ChunkSize.y - 1 {
            otherPos = dm.iv2{worldPos.x, worldPos.y + 1}
            updateOtherChunk = true
        }

        if updateOtherChunk && IsInsideWorld(otherPos) {
            chunk := GetChunkFromWorldPos(world, otherPos.x, otherPos.y)
            UpdateChunk(world, chunk^)
        }

        return true
    }
    else {
        return false
    }
}

GetNeighboursCount :: proc(pos: dm.iv2, chunk: Chunk) -> (count: u32) {
    for y in pos.y - 1 ..= pos.y + 1 {
        for x in pos.x - 1 ..= pos.x + 1 {
            neighbour := dm.iv2{x, y}

            if neighbour == pos {
                continue
            }

            if IsInsideChunk(neighbour) {
                count += GetTile(chunk, neighbour).isWall ? 1 : 0
            }
            else {
                count += 1
            }
        }
    }

    return
}

GenStep :: proc(world: ^World) {
    for chunk in world.chunks {

        for y in 0..<ChunkSize.y {
            for x in 0..<ChunkSize.x {
                idx := y * ChunkSize.x + x

                tile := GetTile(chunk, {x, y})
                count := GetNeighboursCount({x, y}, chunk)

                if count < 4 {
                    tile.isWall = false
                }
                else if count > 4 {
                    tile.isWall = true
                }
            }
        }
    }
}

UpdateChunk :: proc(world: World, chunk: Chunk) {
    for &t in chunk.tiles {
        if t.isWall == false {
            continue
        }

        @static checkedDirections:= [?]dm.iv2{
            {1, 0},
            {-1, 0},
            {0, 1},
            {0, -1},
        }

        t.neighbours = nil
        for dir in checkedDirections {
            pos :=  t.position + dir
            // @TODO: probably wont to treat world edge as a wall
            if IsInsideWorld(pos) == false {
                t.neighbours += { HeadingFromDir(dir) }
                continue
            }

            tile := GetWorldTile(world, pos)

            if tile.isWall {
                t.neighbours += { HeadingFromDir(dir) }
            }
        }

        // fmt.println(t.neighbours)
        switch t.neighbours {
            case Top:      t.sprite = gameState.topWallSprite
            case Bot:      t.sprite = gameState.botWallSprite
            case Left:     t.sprite = gameState.leftWallSprite
            case Right:    t.sprite = gameState.rightWallSprite
            case BotRight: t.sprite = gameState.botRightWallSprite
            case BotLeft:  t.sprite = gameState.botLeftWallSprite
            case TopRight: t.sprite = gameState.topRightWallSprite
            case TopLeft:  t.sprite = gameState.topLeftWallSprite
            case:          t.sprite = gameState.filledWallSprite
        }
    }
}

//////////////

PutEntityInWorld :: proc(world: World, entity: ^Entity) {
    tile := GetWorldTile(world, entity.position)

    if .Traversable in entity.flags {
        tile.traversableEntity = entity.handle
    }
    else {
        tile.holdedEntity = entity.handle
    }

}

MoveEntityIfPossible :: proc(world: World, entity: ^Entity, targetPos: dm.iv2) -> (moved: bool, targetTile: ^Tile) {
    if IsTileOccupied(world, targetPos) == false {
        currentTile := GetWorldTile(world, entity.position)
        targetTile = GetWorldTile(world, targetPos)

        currentTile.holdedEntity = {0, 0}
        targetTile.holdedEntity = entity.handle

        entity.position = targetPos

        moved = true
        return
    }

    return
}

// FindPath :: proc(start: dm.iv2, end: dm.iv2) -> []dm.iv2 {
    
// }