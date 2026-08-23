#!/bin/sh

set -eu

script_dir=$(CDPATH=; export CDPATH; cd -- "$(dirname -- "$0")" && pwd)
exec bun run "$script_dir/generator.ts" refresh
