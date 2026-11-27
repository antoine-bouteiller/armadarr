package config_test

import (
	"testing"

	"github.com/antoine-bouteiller/armadarr/app/backend/internal/config"
)

func env(values map[string]string) func(string) string {
	return func(key string) string { return values[key] }
}

func TestLoadDefaultsPortTo3000(t *testing.T) {
	cfg, err := config.Load(env(nil))
	if err != nil {
		t.Fatal(err)
	}
	if cfg.Port != 3000 {
		t.Fatalf("Port = %d, want 3000", cfg.Port)
	}
}

func TestLoadRejectsInvalidPort(t *testing.T) {
	for _, raw := range []string{"http", "-1", "65536"} {
		if _, err := config.Load(env(map[string]string{"PORT": raw})); err == nil {
			t.Errorf("PORT=%q: want an error", raw)
		}
	}
}
