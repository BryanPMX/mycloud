.PHONY: help build test run up

help:
	@echo "Available targets: build, test, run, up"

build:
	go build ./cmd/server

test:
	go test ./...

run:
	go run ./cmd/server

up:
	docker compose up --build
