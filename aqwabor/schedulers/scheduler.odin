package schedulers

import "core:math"
import "base:runtime"
import "core:sync"
import "core:time"
import "aqwabor:logx"

Tick_State :: struct {
	tick: u64,
	hz:   f64,
}

delta :: proc(t: Tick_State) -> f64 {
	if t.hz == 0 {
		return 0
	}
	return 1 / t.hz
}

DEFAULT_MAX_CATCH_UP :: 8

Advance_Result :: struct {
	fired:   int,
	dropped: u64,
}

@(private)
Job_Inner :: struct {
	fn:        proc(Tick_State),
	every:     uint,
	tick:      u64,
	next:      u64,
	paused:    bool,
	removed:   bool,
	drop:      u64,
	reg_order: u64,
}

Job :: struct {
	j: ^Job_Inner,
	s: ^Scheduler,
}

@(private)
Job_Run :: struct {
	j:  ^Job_Inner,
	fn: proc(Tick_State),
}

Scheduler :: struct {
	jobs:         [dynamic]^Job_Inner,
	job_order:    []Job_Run,
	reg_seq:      u64,
	sim_ticks:    u64,
	sim_time_ns:  i64,
	master_hz:    u32,
	max_catch_up: i32,
	speed:        f64,
	paused:       bool,
	mu:           sync.Mutex,
	log:          ^logx.Logger,
}

new_scheduler :: proc(allocator: runtime.Allocator) -> ^Scheduler {
	s := new(Scheduler, allocator)
	s.speed = 1
	s.max_catch_up = DEFAULT_MAX_CATCH_UP
	s.jobs = make([dynamic]^Job_Inner, 0, 8, allocator)
	s.log = logx.with(allocator)
	logx.logger_debug(s.log, "scheduler created")
	return s
}

destroy_scheduler :: proc(s: ^Scheduler) {
	if s == nil {
		return
	}
	for j in s.jobs {
		free(j)
	}
	delete(s.jobs)
	delete(s.job_order)
	free(s)
}

set_master_hz :: proc(s: ^Scheduler, hz: uint) {
	if hz == 0 || hz > 1000 {
		logx.logger_warn(s.log, "SetMasterHz ignored: must be 1..1000", "hz", hz)
		return
	}
	s.master_hz = u32(hz)
	logx.logger_debug(s.log, "master Hz set", "hz", hz)
}

master_hz :: proc(s: ^Scheduler) -> uint {
	return uint(s.master_hz)
}

quantum :: proc(s: ^Scheduler) -> time.Duration {
	if s.master_hz == 0 || s.speed <= 0 {
		return 0
	}
	return time.Duration(f64(time.Second) / (f64(s.master_hz) * s.speed))
}

set_speed :: proc(s: ^Scheduler, speed: f64) {
	s.speed = max(speed, 0)
	logx.logger_debug(s.log, "scheduler speed changed", "speed", s.speed)
}

speed :: proc(s: ^Scheduler) -> f64 {
	return s.speed
}

set_max_catch_up :: proc(s: ^Scheduler, n: int) {
	if n < 1 {
		logx.logger_warn(s.log, "SetMaxCatchUp ignored", "n", n)
		return
	}
	s.max_catch_up = i32(n)
}

run :: proc(s: ^Scheduler, fn: proc(Tick_State), every: uint) -> Job {
	if every == 0 {
		logx.logger_warn(s.log, "Run ignored: every must be ≥ 1", "every", every)
		return {}
	}
	if s.master_hz == 0 {
		panic("schedulers: Run called before SetMasterHz")
	}
	sync.mutex_lock(&s.mu)
	defer sync.mutex_unlock(&s.mu)
	j := new(Job_Inner)
	j.fn = fn
	j.every = every
	j.reg_order = s.reg_seq
	s.reg_seq += 1
	append(&s.jobs, j)
	rebuild_order(s)
	logx.logger_debug(s.log, "registered job", "every", every, "total_jobs", len(s.jobs))
	return Job{j = j, s = s}
}

@(private)
rebuild_order :: proc(s: ^Scheduler) {
	delete(s.job_order)
	runs := make([dynamic]Job_Run, 0, len(s.jobs))
	for j in s.jobs {
		if j.removed {
			continue
		}
		append(&runs, Job_Run{j = j, fn = j.fn})
	}
	// Ascending every, then registration order.
	for i in 1 ..< len(runs) {
		key := runs[i]
		j := i - 1
		for j >= 0 && (runs[j].j.every > key.j.every ||
			(runs[j].j.every == key.j.every && runs[j].j.reg_order > key.j.reg_order)) {
			runs[j + 1] = runs[j]
			j -= 1
		}
		runs[j + 1] = key
	}
	s.job_order = runs[:]
}

advance :: proc(s: ^Scheduler, sim_dt: time.Duration) -> Advance_Result {
	if sim_dt <= 0 || s.paused {
		return {}
	}
	if s.master_hz == 0 {
		panic("schedulers: Advance called before SetMasterHz")
	}
	ticks := u64(f64(sim_dt) * f64(s.master_hz) / f64(time.Second))
	if ticks == 0 {
		return {}
	}
	s.sim_ticks += ticks
	s.sim_time_ns += i64(sim_dt)
	result: Advance_Result
	for jr in s.job_order {
		fired, dropped := advance_job(s, jr, s.sim_ticks)
		result.fired += fired
		result.dropped += dropped
	}
	return result
}

advance_ticks :: proc(s: ^Scheduler, n: int) -> Advance_Result {
	if n <= 0 || s.paused || s.speed <= 0 {
		return {}
	}
	if s.master_hz == 0 {
		panic("schedulers: AdvanceTicks called before SetMasterHz")
	}
	scaled := u64(f64(n) * s.speed)
	if scaled == 0 {
		return {}
	}
	s.sim_ticks += scaled
	q := time.Duration(f64(time.Second) / f64(s.master_hz))
	s.sim_time_ns += i64(q) * i64(scaled)
	result: Advance_Result
	for jr in s.job_order {
		fired, dropped := advance_job(s, jr, s.sim_ticks)
		result.fired += fired
		result.dropped += dropped
	}
	return result
}

@(private)
advance_job :: proc(s: ^Scheduler, jr: Job_Run, sim_ticks: u64) -> (fired: int, dropped: u64) {
	g := jr.j
	if g.removed || g.paused {
		return 0, 0
	}
	max_catch := int(s.max_catch_up)
	ran := 0
	for g.next < sim_ticks && ran < max_catch {
		state := Tick_State{tick = g.tick, hz = f64(s.master_hz) / f64(g.every)}
		jr.fn(state)
		g.tick += 1
		g.next += u64(g.every)
		ran += 1
	}
	if g.next < sim_ticks {
		skip := (sim_ticks - g.next) / u64(g.every)
		if skip > 0 {
			dropped = skip
			g.drop += dropped
			g.next += skip * u64(g.every)
		}
	}
	return ran, dropped
}

sim_time :: proc(s: ^Scheduler) -> time.Duration {
	return time.Duration(s.sim_time_ns)
}

sim_ticks :: proc(s: ^Scheduler) -> u64 {
	return s.sim_ticks
}

dropped :: proc(s: ^Scheduler) -> u64 {
	n: u64
	for jr in s.job_order {
		n += jr.j.drop
	}
	return n
}

ticks :: proc(s: ^Scheduler, every: uint) -> u64 {
	for jr in s.job_order {
		if jr.j.every == every {
			return jr.j.tick
		}
	}
	return 0
}

pause :: proc(s: ^Scheduler) { s.paused = true }
resume :: proc(s: ^Scheduler) { s.paused = false }

reset :: proc(s: ^Scheduler) {
	s.sim_ticks = 0
	s.sim_time_ns = 0
	sync.mutex_lock(&s.mu)
	defer sync.mutex_unlock(&s.mu)
	for j in s.jobs {
		j.tick = 0
		j.next = 0
		j.drop = 0
	}
}

dispose :: proc(s: ^Scheduler) {
	sync.mutex_lock(&s.mu)
	defer sync.mutex_unlock(&s.mu)
	for j in s.jobs {
		free(j)
	}
	delete(s.jobs)
	delete(s.job_order)
	s.job_order = nil
}

@(private)
job_pause :: proc(h: Job) {
	if h.j != nil { h.j.paused = true }
}
@(private)
job_resume :: proc(h: Job) {
	if h.j != nil { h.j.paused = false }
}
@(private)
job_stop :: proc(h: Job) {
	if h.j == nil || h.s == nil {
		return
	}
	h.j.removed = true
	h.j.paused = true
	sync.mutex_lock(&h.s.mu)
	defer sync.mutex_unlock(&h.s.mu)
	for i := 0; i < len(h.s.jobs); i += 1 {
		if h.s.jobs[i] == h.j {
			ordered_remove(&h.s.jobs, i)
			break
		}
	}
	rebuild_order(h.s)
	free(h.j)
}
@(private)
job_tick :: proc(h: Job) -> u64 {
	if h.j == nil { return 0 }
	return h.j.tick
}
