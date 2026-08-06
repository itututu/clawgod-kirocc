package main

import (
	"context"
	"testing"
	"time"

	"github.com/d-kuro/kirocc/internal/config"
)

func TestRun_HelpFlagReturnsNoError(t *testing.T) {
	if err := run(context.Background(), []string{"-h"}); err != nil {
		t.Errorf("run with -h: got err %v; want nil", err)
	}
}

func TestParseFlags_KiroAPIRegion(t *testing.T) {
	cfg, err := parseFlags([]string{"-kiro-api-region", "us-east-1"})
	if err != nil {
		t.Fatal(err)
	}
	if cfg.KiroAPIRegion != "us-east-1" {
		t.Fatalf("KiroAPIRegion = %q", cfg.KiroAPIRegion)
	}
	if err := cfg.Validate(); err != nil {
		t.Fatalf("Validate: %v", err)
	}
}

func TestParseFlags_KeepAliveInterval(t *testing.T) {
	t.Run("default", func(t *testing.T) {
		cfg, err := parseFlags(nil)
		if err != nil {
			t.Fatalf("parseFlags: %v", err)
		}
		if cfg.KeepAliveInterval != config.DefaultKeepAliveInterval {
			t.Fatalf("KeepAliveInterval = %v, want %v", cfg.KeepAliveInterval, config.DefaultKeepAliveInterval)
		}
	})

	t.Run("flag", func(t *testing.T) {
		cfg, err := parseFlags([]string{"-keepalive-interval", "30s"})
		if err != nil {
			t.Fatalf("parseFlags: %v", err)
		}
		if cfg.KeepAliveInterval != 30*time.Second {
			t.Fatalf("KeepAliveInterval = %v, want 30s", cfg.KeepAliveInterval)
		}
	})
}
