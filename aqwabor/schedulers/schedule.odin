package schedulers

import "core:fmt"
import "core:mem"
import "core:sync"
import "core:thread"
import "core:time"
import "aqwabor:logx"

Resource :: distinct u32

@(private)
g_res_mu: sync.Mutex
@(private)
g_resource_names: map[Resource]string
@(private)
g_next_resource: Resource = Resource(1 << 24)

resource_of :: proc(name: string) -> Resource {
	sync.mutex_lock(&g_res_mu)
	defer sync.mutex_unlock(&g_res_mu)
	if g_resource_names == nil {
		g_resource_names = make(map[Resource]string)
	}
	for id, n in g_resource_names {
		if n == name {
			return id
		}
	}
	id := g_next_resource
	g_next_resource += 1
	g_resource_names[id] = name
	return id
}

name_resource :: proc(r: Resource, name: string) {
	sync.mutex_lock(&g_res_mu)
	defer sync.mutex_unlock(&g_res_mu)
	if g_resource_names == nil {
		g_resource_names = make(map[Resource]string)
	}
	g_resource_names[r] = name
}

@(private)
resource_name :: proc(r: Resource) -> string {
	sync.mutex_lock(&g_res_mu)
	defer sync.mutex_unlock(&g_res_mu)
	if n, ok := g_resource_names[r]; ok {
		return n
	}
	return fmt.tprintf("resource(%d)", u32(r))
}

Access :: struct {
	reads:  [dynamic]Resource,
	writes: [dynamic]Resource,
}

reads :: proc(rs: ..Resource, allocator := context.allocator) -> Access {
	a: Access
	a.reads = make([dynamic]Resource, 0, len(rs), allocator)
	for r in rs { append(&a.reads, r) }
	return a
}

writes :: proc(rs: ..Resource, allocator := context.allocator) -> Access {
	a: Access
	a.writes = make([dynamic]Resource, 0, len(rs), allocator)
	for r in rs { append(&a.writes, r) }
	return a
}

access_reads :: proc(a: Access, rs: ..Resource, allocator := context.allocator) -> Access {
	out := a
	out.reads = make([dynamic]Resource, 0, len(a.reads) + len(rs), allocator)
	append(&out.reads, ..a.reads[:])
	for r in rs { append(&out.reads, r) }
	return out
}

access_writes :: proc(a: Access, rs: ..Resource, allocator := context.allocator) -> Access {
	out := a
	out.writes = make([dynamic]Resource, 0, len(a.writes) + len(rs), allocator)
	append(&out.writes, ..a.writes[:])
	for r in rs { append(&out.writes, r) }
	return out
}

@(private)
contains_res :: proc(list: []Resource, r: Resource) -> bool {
	for x in list {
		if x == r { return true }
	}
	return false
}

@(private)
conflicts_with :: proc(a, b: Access) -> (Resource, bool) {
	for w in a.writes {
		if contains_res(b.writes[:], w) || contains_res(b.reads[:], w) {
			return w, true
		}
	}
	for w in b.writes {
		if contains_res(a.reads[:], w) {
			return w, true
		}
	}
	return 0, false
}

@(private)
Sys_Entry :: struct {
	name:     string,
	access:   Access,
	fn:       proc(Tick_State),
	estimate: time.Duration,
}

DEFAULT_PARALLEL_FLOOR :: 50 * time.Microsecond

Schedule :: struct {
	mu:        sync.Mutex,
	systems:   [dynamic]^Sys_Entry,
	stages:    [dynamic][dynamic]^Sys_Entry,
	built:     bool,
	floor:     time.Duration,
	barrier:   proc(),
	parallel:  bool,
	allocator: mem.Allocator,
	pool:      thread.Pool,
}

new_schedule :: proc(allocator := context.allocator) -> ^Schedule {
	s := new(Schedule, allocator)
	s.floor = DEFAULT_PARALLEL_FLOOR
	s.parallel = true
	s.allocator = allocator
	s.systems = make([dynamic]^Sys_Entry, 0, 8, allocator)
	s.stages = make([dynamic][dynamic]^Sys_Entry, 0, 4, allocator)
	thread.pool_init(&s.pool, allocator, 4)
	thread.pool_start(&s.pool)
	return s
}

set_parallel_floor :: proc(s: ^Schedule, d: time.Duration) {
	sync.mutex_lock(&s.mu)
	s.floor = d
	sync.mutex_unlock(&s.mu)
}

set_parallel :: proc(s: ^Schedule, on: bool) {
	sync.mutex_lock(&s.mu)
	s.parallel = on
	sync.mutex_unlock(&s.mu)
}

set_barrier :: proc(s: ^Schedule, fn: proc()) {
	sync.mutex_lock(&s.mu)
	s.barrier = fn
	sync.mutex_unlock(&s.mu)
}

add :: proc(s: ^Schedule, name: string, access: Access, fn: proc(Tick_State), allocator: mem.Allocator = {}) {
	sync.mutex_lock(&s.mu)
	defer sync.mutex_unlock(&s.mu)
	alloc := allocator
	if alloc == (mem.Allocator{}) {
		alloc = s.allocator
	}
	sys := new(Sys_Entry, alloc)
	sys.name = name
	sys.access = access
	sys.fn = fn
	append(&s.systems, sys)
	s.built = false
}

@(private)
build :: proc(s: ^Schedule, allocator := context.allocator) {
	for stage in s.stages {
		delete(stage)
	}
	delete(s.stages)
	s.stages = make([dynamic][dynamic]^Sys_Entry, 0, 4, allocator)
	for sys in s.systems {
		placed := false
		for i in 0 ..< len(s.stages) {
			ok := true
			for other in s.stages[i] {
				if _, conflict := conflicts_with(sys.access, other.access); conflict {
					ok = false
					break
				}
			}
			if ok {
				append(&s.stages[i], sys)
				placed = true
				break
			}
		}
		if !placed {
			stage := make([dynamic]^Sys_Entry, 0, 4, allocator)
			append(&stage, sys)
			s_stages := s.stages
			append(&s_stages, stage)
			s.stages = s_stages
		}
	}
	s.built = true
}

build_schedule :: proc(s: ^Schedule) {
	sync.mutex_lock(&s.mu)
	defer sync.mutex_unlock(&s.mu)
	if !s.built {
		build(s)
	}
}

@(private)
stages :: proc(s: ^Schedule, allocator := context.allocator) -> [][]string {
	sync.mutex_lock(&s.mu)
	defer sync.mutex_unlock(&s.mu)
	if !s.built {
		build(s)
	}
	out := make([][]string, len(s.stages), allocator)
	for i in 0 ..< len(s.stages) {
		out[i] = make([]string, len(s.stages[i]), allocator)
		for j in 0 ..< len(s.stages[i]) {
			out[i][j] = s.stages[i][j].name
		}
	}
	return out
}

run_schedule :: proc(s: ^Schedule, state: Tick_State) {
	sync.mutex_lock(&s.mu)
	if !s.built {
		build(s)
	}
	floor := s.floor
	barrier := s.barrier
	parallel := s.parallel
	sync.mutex_unlock(&s.mu)

	for stage in s.stages {
		run_stage(stage[:], state, floor, parallel, &s.pool, s.allocator)
		if barrier != nil {
			barrier()
		}
	}
}

@(private)
run_stage :: proc(stage: []^Sys_Entry, state: Tick_State, floor: time.Duration, parallel: bool, pool: ^thread.Pool, allocator: mem.Allocator) {
	if len(stage) == 0 {
		return
	}
	if len(stage) == 1 || !parallel {
		for sys in stage {
			run_system(sys, state)
		}
		return
	}
	estimated: time.Duration
	for sys in stage {
		estimated += sys.estimate
	}
	if estimated < floor {
		for sys in stage {
			run_system(sys, state)
		}
		return
	}
	wg: sync.Wait_Group
	sync.wait_group_add(&wg, len(stage))
	for sys in stage {
		sys := sys
		Range :: struct { sys: ^Sys_Entry, state: Tick_State, wg: ^sync.Wait_Group, alloc: mem.Allocator }
		r := new(Range, allocator)
		r.sys = sys
		r.state = state
		r.wg = &wg
		r.alloc = allocator
		thread.pool_add_task(pool, allocator, proc(task: thread.Task) {
			r := cast(^Range)task.data
			run_system(r.sys, r.state)
			sync.wait_group_done(r.wg)
			free(r, r.alloc)
		}, r)
	}
	sync.wait_group_wait(&wg)
}

@(private)
run_system :: proc(sys: ^Sys_Entry, state: Tick_State) {
	start := time.tick_now()
	sys.fn(state)
	d := time.tick_since(start)
	if sys.estimate == 0 {
		sys.estimate = d
	} else {
		sys.estimate = (sys.estimate * 3 + d) / 4
	}
}

@(private)
conflicts :: proc(s: ^Schedule, allocator := context.allocator) -> []string {
	sync.mutex_lock(&s.mu)
	defer sync.mutex_unlock(&s.mu)
	out := make([dynamic]string, 0, 8, allocator)
	for i in 0 ..< len(s.systems) {
		for j in i + 1 ..< len(s.systems) {
			if r, conflict := conflicts_with(s.systems[i].access, s.systems[j].access); conflict {
				append(&out, fmt.aprintf("%s and %s both need %s",
					s.systems[i].name, s.systems[j].name, resource_name(r), allocator))
			}
		}
	}
	return out[:]
}

destroy_schedule :: proc(s: ^Schedule) {
	if s == nil {
		return
	}
	thread.pool_join(&s.pool)
	thread.pool_destroy(&s.pool)
	for stage in s.stages {
		delete(stage)
	}
	delete(s.stages)
	for sys in s.systems {
		delete(sys.access.reads)
		delete(sys.access.writes)
		free(sys, s.allocator)
	}
	delete(s.systems)
	free(s, s.allocator)
}
