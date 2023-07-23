package game

import dm "../dmcore"
import "../dmcore/globals"
import "core:fmt"

import "core:math/ease"

import "core:math/linalg/glsl"

EntityHandle :: distinct dm.Handle

EntityFlag :: enum {
    HP,
    Pickup,
    Traversable,
    CanAttack,

    Lifetime,
}

ControlerType :: enum {
    None,
    Player,
    Enemy,
}

Heading :: enum {
    None,
    North,
    South,
    West,
    East,
}

DirectionFromHeading := [Heading]dm.iv2 {
    .None  = {0,  0},
    .North = {0,  1},
    .South = {0, -1},
    .West  = {-1, 0},
    .East  = { 1, 0},
}

PickupType :: enum {
    Gold, 
    Health,
}

Entity :: struct {
    handle: EntityHandle, // @TODO: do I need it..?
    flags: bit_set[EntityFlag],

    controler: ControlerType,

    damage: int,
    HP: int,
    detectionRadius: int,

    pickupType: PickupType,
    pickupValue: int,

    position: dm.iv2,
    direction: Heading,

    sprite: dm.Sprite,
    tint: dm.color,

    lifetime: f32,
}

Dir :: #force_inline proc(h: Heading) -> dm.iv2 {
    return DirectionFromHeading[h]
}

HeadingFromDir :: proc(dir: dm.iv2) -> Heading {
    if dir == {0,  1} do return .North
    if dir == {0, -1} do return .South
    if dir == {1,  0} do return .East
    if dir == {-1, 0} do return .West

    return .None
}


CreateEntityHandle :: proc() -> EntityHandle {
    return cast(EntityHandle) dm.CreateHandle(gameState.entities)
}

CreateEntity :: proc() -> ^Entity {
    handle := CreateEntityHandle()
    assert(handle.index != 0)

    entity := dm.GetElement(gameState.entities, dm.Handle(handle))

    entity.handle = handle
    entity.tint = dm.WHITE

    entity.direction = .North

    return entity
}

DestroyEntity :: proc(handle: EntityHandle) {
    dm.FreeSlot(gameState.entities, auto_cast handle)
}

DamageEntity :: proc(entity: ^Entity, damage: int) {
    entity.HP -= damage

    if entity.HP <= 0 {
        HandleEntityDeath(entity)
        DestroyEntity(entity.handle)
    }
}

////////////

ControlEntity :: proc(entity: ^Entity) {
    switch entity.controler {
        case .Player: ControlPlayer(entity)
        case .Enemy:  ControlEnemy(entity)
        case .None: // ignore
    }
}

HandleEntityDeath :: proc(entity: ^Entity) {
    switch entity.controler {
        case .Player: HandlePlayerDeath(entity)
        case .Enemy:  HandleEnemyDeath(entity)
        case .None: // ignore
    }   
}

GetFacingEntity :: proc(self: ^Entity) -> ^Entity {
    pos := self.position + Dir(self.direction)
    tile := GetWorldTile(gameState.world, pos)

    return dm.GetElement(gameState.entities, auto_cast tile.holdedEntity)
}

GetFacingEntityHandle :: proc(self: ^Entity) -> EntityHandle {
    pos := self.position + Dir(self.direction)
    tile := GetWorldTile(gameState.world, pos)

    return tile.holdedEntity
}

////////////

CreatePlayerEntity :: proc(world: World) -> ^Entity {
    player := CreateEntity()

    player.controler = .Player
    player.sprite = dm.CreateSprite(gameState.atlas, {0, 0, 16, 16})
    player.tint = PlayerColor

    player.position = ChunkSize * StartChunk + ChunkSize / 2

    player.flags = {.HP, .CanAttack, }

    player.HP = 100

    PutEntityInWorld(world, player)

    return player
}

ControlPlayer :: proc(player: ^Entity) {
    deltaMove: dm.iv2

    deltaMove.x = dm.GetAxisInt(globals.input, .Left, .Right, .JustPressed)

    // Prioritize horizontal movement
    if deltaMove.x == 0 {
        deltaMove.y = dm.GetAxisInt(globals.input, .Down, .Up, .JustPressed)
    }

    if deltaMove != {0, 0} {
        targetPos := player.position + deltaMove
        player.direction = HeadingFromDir(deltaMove)

        moved, movedTile := MoveEntityIfPossible(gameState.world, player, targetPos)
        if moved {
            targetEntity := dm.GetElement(gameState.entities, auto_cast movedTile.traversableEntity)

            if targetEntity != nil && (.Pickup in targetEntity.flags) {

                switch targetEntity.pickupType {
                    case .Gold: gameState.gold  += targetEntity.pickupValue
                    case .Health: player.HP += targetEntity.pickupValue 
                }
                
                
                DestroyEntity(targetEntity.handle)
            }
        }

        gameState.playerMovedThisFrame = true
    }

    if dm.GetKeyState(globals.input, .Space) == .JustPressed {
        tile := GetWorldTile(gameState.world, player.position + Dir(player.direction))

        if tile.isWall {
            if tile.level <= gameState.pickaxeLevel {
                pos := player.position + Dir(player.direction)
                DestroyWallAt(gameState.world, pos)
                SpawnHitEffect(pos, 2, WallColor)
            }
            else {
                ShowMessage("Your pickaxe level is to low!");
            }
        }

        entity := dm.GetElement(gameState.entities, auto_cast tile.holdedEntity)
        if entity != nil && .HP in entity.flags {
            SpawnHitEffect(entity.position, 1, PlayerColor)
            DamageEntity(entity, PickaxeDamage())

            globals.audio.PlaySound("assets/soundHit.mp3")
        }

        gameState.playerMovedThisFrame = true
    }
}

HandlePlayerDeath :: proc(entity: ^Entity) {
    gameState.state = .Dead
}

////////////////

CreateGoldPickup :: proc(world: World, position: dm.iv2, value: int) -> ^Entity {
    gold := CreateEntity()

    gold.position = position

    gold.sprite = dm.CreateSprite(gameState.atlas, {2 * 16, 0, 16, 16})
    gold.tint = GoldColor

    gold.pickupValue = value
    gold.pickupType = .Gold

    gold.flags = { .Pickup, .Traversable }

    PutEntityInWorld(world, gold)

    return gold
}

CreateHealthPickup :: proc(world: World, position: dm.iv2, value: int) -> ^Entity {
    health := CreateEntity()

    health.position = position

    health.sprite = dm.CreateSprite(gameState.atlas, {0, 16, 16, 16})
    health.tint = WallColor

    health.pickupValue = value
    health.pickupType = .Health

    health.flags = { .Pickup, .Traversable }

    PutEntityInWorld(world, health)

    return health
}


/////////////////

EnemyPreset :: struct {
    HP, Dmg: int,
    detectionRadius: int,
}

EnemyPresets := [?]EnemyPreset {
    {
        HP = 10,
        Dmg = 5,
        detectionRadius = 5,
    },
    {
        HP = 15,
        Dmg = 6,
        detectionRadius = 5,
    },
    {
        HP = 20,
        Dmg = 8,
        detectionRadius = 6,
    },
    {
        HP = 30,
        Dmg = 10,
        detectionRadius = 7,
    },
    {
        HP = 40,
        Dmg = 10,
        detectionRadius = 7,
    },
        {
        HP = 45,
        Dmg = 10,
        detectionRadius = 7,
    },
}

GetEnemyPreset :: proc(level: int) -> EnemyPreset {
    level := clamp(0, len(EnemyPresets) - 1, level)
    return EnemyPresets[level]
}

CreateEnemy :: proc(world: World, position: dm.iv2, level: int) -> ^Entity {
    enemy := CreateEntity()

    enemy.position = position

    enemy.sprite = dm.CreateSprite(gameState.atlas, {16 * i32(level), 5 * 16, 16, 16})
    enemy.tint = EnemyColor

    enemy.controler = .Enemy

    preset := GetEnemyPreset(level)
    enemy.damage = preset.Dmg
    enemy.detectionRadius = preset.detectionRadius
    enemy.HP = preset.HP

    enemy.flags = { .HP, .CanAttack }

    PutEntityInWorld(world, enemy)

    return enemy
}

ControlEnemy :: proc(enemy: ^Entity) {
    if gameState.playerMovedLastFrame == false {
        return
    }

    player := GetPlayer() 
    if player == nil {
        return
    }

    playerDir := player.position - enemy.position
    dist := playerDir.x * playerDir.x + playerDir.y * playerDir.y

    if dist != 1 && int(dist) < enemy.detectionRadius * enemy.detectionRadius {
        dir: dm.iv2
        if abs(playerDir.x) > abs(playerDir.y) {
            dir.x = glsl.sign(playerDir.x)
        }
        else {
            dir.y = glsl.sign(playerDir.y)
        }

        MoveEntityIfPossible(gameState.world, enemy, enemy.position + dir)
        enemy.direction = HeadingFromDir(dir)
    }

    if dist == 1 {
        otherHandle := GetFacingEntityHandle(enemy)
        if otherHandle == player.handle {
            SpawnHitEffect(player.position, 0, EnemyColor)
            DamageEntity(player, 10)

            globals.audio.PlaySound("assets/soundHitPlayer.mp3")
        }
    }
}

HandleEnemyDeath :: proc(enemy: ^Entity) {

}

////////////////////////

SpawnHitEffect :: proc(pos: dm.iv2, effectNumber: i32, color: dm.color) {
    effect := CreateEntity()

    effect.position = pos

    effect.sprite = dm.CreateSprite(gameState.atlas, {effectNumber * 16, 4 * 16, 16, 16})
    effect.tint = color

    effect.flags = { .Lifetime }
    effect.lifetime = 0.1

    effect.sprite.scale = 1.2
}