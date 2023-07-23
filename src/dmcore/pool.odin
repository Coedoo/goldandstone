package dmcore

import "core:mem"
import "core:slice"

Handle :: struct {
    index: i32,
    gen: i32,
}

PoolSlot :: struct {
    inUse: bool,
    gen: i32,
}

ResourcePool :: struct($T:typeid) {
    slots: []PoolSlot,
    elements: []T,
}

InitResourcePool :: proc(pool: ^ResourcePool($T), len: int, allocator := context.allocator) -> bool {
    assert(pool != nil)

    pool.slots    = make([]PoolSlot, len, allocator)
    pool.elements = make([]T, len, allocator)

    return pool.slots != nil && pool.elements != nil
}

CreateHandle :: proc(pool: ResourcePool($T)) -> Handle {
    assert(len(pool.elements) > 0 && len(pool.slots) > 0, "Pool is uninitialized")
    assert(len(pool.elements) == len(pool.slots))

    for &s, i in pool.slots {
        // slot at index 0 is reserved as "invalid resorce" 
        // so never allocate at it

        if s.inUse == false && i != 0 {
            s.inUse = true
            s.gen += 1

            return Handle {
                index = i32(i),
                gen = s.gen,
            }
        }
    }

    return {}
}

IsHandleValid :: proc(pool: ResourcePool($T), handle: Handle) -> bool {
    assert(int(handle.index) < len(pool.slots))

    slot := pool.slots[handle.index]
    return slot.inUse && slot.gen == handle.gen
}

GetElement :: proc(pool: ResourcePool($T), handle: Handle) -> ^T {
    if IsHandleValid(pool, handle) == false {
        return nil
    }

    return &(pool.elements[handle.index])
}

FreeSlot :: proc {
    FreeSlotAtIndex,
    FreeSlotAtHandle,
}

FreeSlotAtIndex :: proc(pool: ResourcePool($T), index: int) {
    assert(index < len(pool.slots))

    pool.slots[index].inUse = false
    mem.zero_item(&pool.elements[index])
}

FreeSlotAtHandle :: proc(pool: ResourcePool($T), handle: Handle) {
    FreeSlotAtIndex(pool, cast(int) handle.index)
}

ClearPool :: proc(pool: ResourcePool($T)) {
    slice.zero(pool.slots)
    slice.zero(pool.elements)
}