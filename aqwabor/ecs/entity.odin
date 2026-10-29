package ecs

// Entity is a generational handle. The low 32 bits are a dense index, the high
// 32 bits a generation counter that is raised each time the index is reused.
//
// Absence is not the zero value. Entity(0) is a valid entity, so a "no entity"
// is NO_ENTITY, which is every bit set.
Entity :: distinct u64

ENTITY_INDEX_MASK :: u64(0xFFFFFFFF)
ENTITY_GENERATION_SHIFT :: 32

NO_ENTITY :: Entity(max(u64))

@(private)
new_entity :: proc(index: u32, generation: u32) -> Entity {
	return Entity(u64(index) | u64(generation) << ENTITY_GENERATION_SHIFT)
}

index :: proc(e: Entity) -> u32 {
	return u32(u64(e) & ENTITY_INDEX_MASK)
}

generation :: proc(e: Entity) -> u32 {
	return u32(u64(e) >> ENTITY_GENERATION_SHIFT)
}

@(private)
Entity_Meta :: struct {
	generation: u32,
	alive:      bool,
}

@(private)
Entity_Allocator :: struct {
	metas:     [dynamic]Entity_Meta,
	free_list: [dynamic]u32,
	live:      int,
}

@(private)
entity_allocator_init :: proc(a: ^Entity_Allocator, allocator := context.allocator) {
	a.metas = make([dynamic]Entity_Meta, 0, 256, allocator)
	a.free_list = make([dynamic]u32, 0, 64, allocator)
	a.live = 0
}

@(private)
entity_allocator_destroy :: proc(a: ^Entity_Allocator) {
	delete(a.metas)
	delete(a.free_list)
	a^ = {}
}

@(private)
entity_create :: proc(a: ^Entity_Allocator) -> Entity {
	idx: u32
	if n := len(a.free_list); n > 0 {
		idx = a.free_list[n - 1]
		pop(&a.free_list)
		meta := &a.metas[idx]
		meta.generation += 1
		meta.alive = true
	} else {
		idx = u32(len(a.metas))
		append(&a.metas, Entity_Meta{generation = 0, alive = true})
	}
	a.live += 1
	return new_entity(idx, a.metas[idx].generation)
}

@(private)
entity_destroy :: proc(a: ^Entity_Allocator, e: Entity) -> bool {
	idx := int(index(e))
	if idx >= len(a.metas) {
		return false
	}
	meta := &a.metas[idx]
	if !meta.alive || meta.generation != generation(e) {
		return false
	}
	meta.alive = false
	append(&a.free_list, u32(idx))
	a.live -= 1
	return true
}

@(private)
entity_alive :: proc(a: ^Entity_Allocator, e: Entity) -> bool {
	idx := int(index(e))
	if idx >= len(a.metas) {
		return false
	}
	return a.metas[idx].alive && a.metas[idx].generation == generation(e)
}

@(private)
entity_count :: proc(a: ^Entity_Allocator) -> int {
	return a.live
}
