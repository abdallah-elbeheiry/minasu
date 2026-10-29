package logx

import "core:os"
import "core:sync"

// Convenience constructors used at startup:
//
//	logx.init({level = .Debug, color = true, has_time = true})
//
// AQWABOR_LOG still supplies a default when explicit_level is false.
apply :: proc(c: Config) {
	sync.guard(&g_mu)
	cfg := c
	if cfg.output == nil {
		cfg.output = os.stderr
	}
	apply_env_level(&cfg)
	g_cfg = cfg
	g_level = cfg.level
}
