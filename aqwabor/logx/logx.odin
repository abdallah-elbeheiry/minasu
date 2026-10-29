// Package logx is a thin logging façade so the rest of the engine never
// imports a logging library of its own.
//
//	logx.info("window created", "title", cfg.title, "w", cfg.w, "h", cfg.h)
//	logx.errorf("draw failed: %v", err)
package logx

import "core:fmt"
import "core:io"
import "core:os"
import "base:runtime"
import "core:sync"
import "core:time"

Level :: enum i8 {
	Trace     = -1,
	Debug     = 0,
	Info      = 1,
	Warn      = 2,
	Error     = 3,
	Fatal     = 4,
	Panic     = 5,
	Disabled  = 7,
}

Trace_Level :: Level.Trace
Debug_Level :: Level.Debug
Info_Level  :: Level.Info
Warn_Level  :: Level.Warn
Error_Level :: Level.Error
Fatal_Level :: Level.Fatal
Panic_Level :: Level.Panic
Disabled    :: Level.Disabled

Logger :: struct {
	kvs: []any,
}

Config :: struct {
	level:          Level,
	explicit_level: bool,
	output:         ^os.File,
	color:          bool,
	json:           bool,
	has_time:       bool,
	caller:         bool,
}

@(private)
g_mu: sync.RW_Mutex
@(private)
g_cfg: Config
@(private)
g_level: Level = .Info
@(private)
g_std: Logger

@(init)
init_defaults :: proc "contextless"() {
	g_cfg = Config{
		level    = .Info,
		output   = os.stderr,
		color    = true,
		has_time = true,
	}
	g_level = g_cfg.level
}

@(private)
apply_env_level :: proc(c: ^Config) {
	if c.explicit_level {
		return
	}
	buf: [256]u8
	v, err := os.lookup_env_buf(buf[:], "AQWABOR_LOG")
	if err != nil {
		return
	}
	switch v {
	case "trace": c.level = .Trace
	case "debug": c.level = .Debug
	case "info":  c.level = .Info
	case "warn":  c.level = .Warn
	case "error": c.level = .Error
	case "fatal": c.level = .Fatal
	case "panic": c.level = .Panic
	case "disabled": c.level = .Disabled
	}
}

init :: proc(c: Config) {
	sync.guard(&g_mu)
	cfg := c
	if cfg.output == nil {
		cfg.output = os.stderr
	}
	apply_env_level(&cfg)
	g_cfg = cfg
	g_level = cfg.level
}

level :: proc() -> Level {
	sync.shared_guard(&g_mu)
	return g_level
}

set_level :: proc(l: Level) {
	sync.guard(&g_mu)
	g_level = l
	g_cfg.level = l
	g_cfg.explicit_level = true
}

discard :: proc() {
	sync.guard(&g_mu)
	g_level = .Disabled
	g_cfg.level = .Disabled
}

enabled :: proc(l: Level) -> bool {
	cur := level()
	return cur != .Disabled && l >= cur
}

with :: proc(allocator: runtime.Allocator) -> ^Logger {
	l := new(Logger, allocator)
	return l
}

with_kvs :: proc(allocator: runtime.Allocator, kvs: []any) -> ^Logger {
	l := new(Logger, allocator)
	if len(kvs) > 0 {
		l.kvs = make([]any, len(kvs), allocator)
		copy(l.kvs, kvs)
	}
	return l
}

with_more :: proc(allocator: runtime.Allocator, l: ^Logger, kvs: []any) -> ^Logger {
	out := new(Logger, allocator)
	n := 0
	if l != nil {
		n += len(l.kvs)
	}
	n += len(kvs)
	out.kvs = make([]any, n, allocator)
	i := 0
	if l != nil {
		for kv in l.kvs {
			out.kvs[i] = kv
			i += 1
		}
	}
	for kv in kvs {
		out.kvs[i] = kv
		i += 1
	}
	return out
}

@(private)
emit :: proc(l: ^Logger, lvl: Level, msg: string, kvs: []any) {
	if lvl == .Fatal {
		write_line(l, lvl, msg, kvs)
		os.exit(1)
	}
	if lvl == .Panic {
		write_line(l, lvl, msg, kvs)
		panic(msg)
	}
	if !enabled(lvl) {
		return
	}
	write_line(l, lvl, msg, kvs)
}

@(private)
write_line :: proc(l: ^Logger, lvl: Level, msg: string, kvs: []any) {
	sync.shared_guard(&g_mu)
	out := g_cfg.output
	if out == nil {
		out = os.stderr
	}
	name := level_name(lvl)
	if g_cfg.has_time {
		now := time.now()
		y, mo, d := time.date(now)
		h, mi, s := time.clock(now)
		fmt.fprintf(out, "%04d-%02d-%02d %02d:%02d:%02d %s %s", y, int(mo), d, h, mi, s, name, msg)
	} else {
		fmt.fprintf(out, "%s %s", name, msg)
	}
	if l != nil {
		write_kvs(out, l.kvs)
	}
	write_kvs(out, kvs)
	fmt.fprintln(out)
}

@(private)
write_kvs :: proc(out: ^os.File, kvs: []any) {
	i := 0
	for i + 1 < len(kvs) {
		fmt.fprintf(out, " %v=%v", kvs[i], kvs[i + 1])
		i += 2
	}
	if i < len(kvs) {
		fmt.fprintf(out, " %v", kvs[i])
	}
}

@(private)
level_name :: proc(l: Level) -> string {
	switch l {
	case .Trace: return "TRC"
	case .Debug: return "DBG"
	case .Info:  return "INF"
	case .Warn:  return "WRN"
	case .Error: return "ERR"
	case .Fatal: return "FTL"
	case .Panic: return "PNC"
	case .Disabled: return "OFF"
	}
	return "?"
}

trace :: proc(msg: string, kvs: ..any) { emit(&g_std, .Trace, msg, kvs) }
debug :: proc(msg: string, kvs: ..any) { emit(&g_std, .Debug, msg, kvs) }
info  :: proc(msg: string, kvs: ..any) { emit(&g_std, .Info,  msg, kvs) }
warn  :: proc(msg: string, kvs: ..any) { emit(&g_std, .Warn,  msg, kvs) }
error :: proc(msg: string, kvs: ..any) { emit(&g_std, .Error, msg, kvs) }
fatal :: proc(msg: string, kvs: ..any) { emit(&g_std, .Fatal, msg, kvs) }
panic_log :: proc(msg: string, kvs: ..any) { emit(&g_std, .Panic, msg, kvs) }

tracef :: proc(format: string, args: ..any) {
	if enabled(.Trace) do emit(&g_std, .Trace, fmt.tprintf(format, ..args), nil)
}
debugf :: proc(format: string, args: ..any) {
	if enabled(.Debug) do emit(&g_std, .Debug, fmt.tprintf(format, ..args), nil)
}
infof :: proc(format: string, args: ..any) {
	if enabled(.Info) do emit(&g_std, .Info, fmt.tprintf(format, ..args), nil)
}
warnf :: proc(format: string, args: ..any) {
	if enabled(.Warn) do emit(&g_std, .Warn, fmt.tprintf(format, ..args), nil)
}
errorf :: proc(format: string, args: ..any) {
	if enabled(.Error) do emit(&g_std, .Error, fmt.tprintf(format, ..args), nil)
}
fatalf :: proc(format: string, args: ..any) {
	emit(&g_std, .Fatal, fmt.tprintf(format, ..args), nil)
}

logger_trace :: proc(l: ^Logger, msg: string, kvs: ..any) { emit(l, .Trace, msg, kvs) }
logger_debug :: proc(l: ^Logger, msg: string, kvs: ..any) { emit(l, .Debug, msg, kvs) }
logger_info  :: proc(l: ^Logger, msg: string, kvs: ..any) { emit(l, .Info,  msg, kvs) }
logger_warn  :: proc(l: ^Logger, msg: string, kvs: ..any) { emit(l, .Warn,  msg, kvs) }
logger_error :: proc(l: ^Logger, msg: string, kvs: ..any) { emit(l, .Error, msg, kvs) }
logger_enabled :: proc(l: ^Logger, lvl: Level) -> bool {
	_ = l
	return enabled(lvl)
}
