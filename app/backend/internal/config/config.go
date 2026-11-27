// Package config reads the process configuration from the environment.
package config

import (
	"fmt"
	"strconv"
)

// Config is the process configuration.
type Config struct {
	Port int
}

const defaultPort = 3000

// Load reads the configuration through getenv, which is os.Getenv outside tests.
func Load(getenv func(string) string) (Config, error) {
	cfg := Config{Port: defaultPort}
	if raw := getenv("PORT"); raw != "" {
		port, err := strconv.Atoi(raw)
		if err != nil || port < 0 || port > 65535 {
			return Config{}, fmt.Errorf("PORT: %q is not a port number", raw)
		}
		cfg.Port = port
	}
	return cfg, nil
}
