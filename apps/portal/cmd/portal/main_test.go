package main

import (
	"bytes"
	"testing"
)

func TestHomeTemplateRenders(t *testing.T) {
	var buf bytes.Buffer
	if err := homeTmpl.Execute(&buf, struct{ APIBase string }{APIBase: "https://api.example.test"}); err != nil {
		t.Fatal(err)
	}
	out := buf.Bytes()
	if !bytes.Contains(out, []byte("https://api.example.test/health")) {
		t.Fatal("expected API base in output")
	}
	if !bytes.Contains(out, []byte("m43-tokens.css")) {
		t.Fatal("expected m43 CSS")
	}
	if !bytes.Contains(out, []byte(`data-m43-app="k8s-portal-home"`)) {
		t.Fatal("expected analytics app id for home")
	}
	if !bytes.Contains(out, []byte("/v1/sample-protected")) {
		t.Fatal("expected sample-protected link")
	}
}

func TestStatusTemplateRenders(t *testing.T) {
	var buf bytes.Buffer
	err := statusTmpl.Execute(&buf, struct {
		Rows []appRow
	}{Rows: []appRow{{Name: "root", Health: "Healthy", Sync: "Synced"}}})
	if err != nil {
		t.Fatal(err)
	}
	out := buf.Bytes()
	if !bytes.Contains(out, []byte("root")) {
		t.Fatal("expected app name in output")
	}
	if !bytes.Contains(out, []byte(`data-m43-app="k8s-portal-status"`)) {
		t.Fatal("expected analytics app id for status")
	}
	if !bytes.Contains(out, []byte(`class="m43-table"`)) {
		t.Fatal("expected m43 table class")
	}
}
