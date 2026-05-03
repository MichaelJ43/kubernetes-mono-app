package server

import "testing"

func TestApexCredentialedCORSOK(t *testing.T) {
	t.Parallel()
	tests := []struct {
		origin string
		want   bool
	}{
		{"https://k8s.michaelj43.dev", true},
		{"https://api.k8s.michaelj43.dev", true},
		{"https://michaelj43.dev", true},
		{"http://k8s.michaelj43.dev", false},
		{"https://evil.example.com", false},
		{"https://notmichaelj43.dev", false},
	}
	for _, tt := range tests {
		ok, echo := apexCredentialedCORSOK(tt.origin)
		if ok != tt.want {
			t.Errorf("%q: got ok=%v echo=%q want ok=%v", tt.origin, ok, echo, tt.want)
		}
		if ok && echo != tt.origin {
			t.Errorf("%q: echo mismatch %q", tt.origin, echo)
		}
	}
}
