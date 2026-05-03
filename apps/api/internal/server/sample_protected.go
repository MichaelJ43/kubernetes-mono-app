package server

import (
	"context"
	"encoding/json"
	"io"
	"net"
	"net/http"
	"net/url"
	"strings"
	"time"
)

const defaultSharedAuthAPIBase = "https://api.michaelj43.dev"

func (s *Server) sharedAuthAPIOrigin() string {
	b := strings.TrimSpace(s.authAPIBase)
	if b == "" {
		return defaultSharedAuthAPIBase
	}
	return strings.TrimSuffix(b, "/")
}

func apexCredentialedCORSOK(origin string) (ok bool, echo string) {
	u, err := url.Parse(origin)
	if err != nil || u.Scheme != "https" || u.Host == "" {
		return false, ""
	}
	host := strings.ToLower(u.Hostname())
	if host == "" || net.ParseIP(host) != nil {
		return false, ""
	}
	if host == "michaelj43.dev" || strings.HasSuffix(host, ".michaelj43.dev") {
		return true, origin
	}
	return false, ""
}

func (s *Server) writeV1SampleCORS(w http.ResponseWriter, r *http.Request) {
	if origin := r.Header.Get("Origin"); origin != "" {
		if ok, echo := apexCredentialedCORSOK(origin); ok {
			w.Header().Set("Access-Control-Allow-Origin", echo)
			w.Header().Set("Access-Control-Allow-Credentials", "true")
			w.Header().Set("Access-Control-Allow-Methods", "GET, OPTIONS")
			w.Header().Set("Access-Control-Allow-Headers", "content-type")
			w.Header().Set("Vary", "Origin")
		}
	}
}

func (s *Server) sampleProtectedOptions(w http.ResponseWriter, r *http.Request) {
	s.writeV1SampleCORS(w, r)
	w.WriteHeader(http.StatusNoContent)
}

type authMeUser struct {
	Email string `json:"email"`
	ID    string `json:"id"`
	Role  string `json:"role"`
}

type authMeResponse struct {
	User authMeUser `json:"user"`
}

func (s *Server) sampleProtected(w http.ResponseWriter, r *http.Request) {
	s.writeV1SampleCORS(w, r)

	meURL := s.sharedAuthAPIOrigin() + "/v1/auth/me"
	ctx, cancel := context.WithTimeout(r.Context(), 10*time.Second)
	defer cancel()

	req, err := http.NewRequestWithContext(ctx, http.MethodGet, meURL, nil)
	if err != nil {
		s.log.Error("sample-protected build request", "err", err)
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "internal_error"})
		return
	}
	if c := r.Header.Get("Cookie"); c != "" {
		req.Header.Set("Cookie", c)
	}

	res, err := s.httpClient.Do(req)
	if err != nil {
		s.log.Error("sample-protected auth/me", "err", err)
		writeJSON(w, http.StatusBadGateway, map[string]string{"error": "auth_upstream_unreachable"})
		return
	}
	defer res.Body.Close()

	body, _ := io.ReadAll(io.LimitReader(res.Body, 1<<20))

	switch res.StatusCode {
	case http.StatusOK:
		var parsed authMeResponse
		if err := json.Unmarshal(body, &parsed); err != nil {
			s.log.Error("sample-protected auth/me json", "err", err)
			writeJSON(w, http.StatusBadGateway, map[string]string{"error": "auth_upstream_invalid"})
			return
		}
		writeJSON(w, http.StatusOK, map[string]any{
			"ok":      true,
			"message": "Session accepted by shared-api-platform (delegated /v1/auth/me).",
			"user":    parsed.User,
		})
	case http.StatusUnauthorized:
		writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "unauthorized", "hint": "Sign in via auth.michaelj43.dev (cookie sap_session), then retry."})
	default:
		s.log.Info("sample-protected unexpected auth/me status", "status", res.StatusCode)
		writeJSON(w, http.StatusBadGateway, map[string]string{"error": "auth_upstream_error"})
	}
}
