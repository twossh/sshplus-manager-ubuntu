SHELL := /usr/bin/env bash

.PHONY: verify lint checksums build clean version

verify:
	bash ./scripts/ci.sh

lint:
	@mapfile -t files < <(find . -type f \( -name '*.sh' -o -path './bin/*' \) -not -path './dist/*' -print | sort); \
	for file in "$${files[@]}"; do bash -n "$$file"; done; \
	shellcheck --severity=error -x -e SC1090,SC1091 "$${files[@]}"

checksums:
	bash ./scripts/checksums.sh generate

build:
	bash ./scripts/build-release.sh

version:
	bash ./scripts/version.sh show

clean:
	rm -rf dist/*
