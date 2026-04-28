# Contract tests (stretch)

Use **OpenAPI** (`apps/api/openapi.yaml`) with one of:

- [Dredd](https://github.com/apiaryio/dredd) — black-box HTTP against a running server.
- [Schemathesis](https://schemathesis.readthedocs.io/) — property-based requests from the spec.

Example (after `docker compose` brings the API up on port 8080):

```bash
pip install schemathesis
st run ../../apps/api/openapi.yaml --base-url http://127.0.0.1:8080
```

Wire this into CI only when you want spec compliance to block merges.
