-- +goose Up
CREATE TABLE IF NOT EXISTS items (
    id   SERIAL PRIMARY KEY,
    name TEXT NOT NULL
);

INSERT INTO items (name) VALUES ('demo-a'), ('demo-b');

-- +goose Down
DROP TABLE IF EXISTS items;
