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
	if !bytes.Contains(buf.Bytes(), []byte("https://api.example.test/health")) {
		t.Fatal("expected API base in output")
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
	if !bytes.Contains(buf.Bytes(), []byte("root")) {
		t.Fatal("expected app name in output")
	}
}
