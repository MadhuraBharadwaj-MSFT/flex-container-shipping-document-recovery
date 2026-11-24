#!/usr/bin/env sh
set -eu

python ./scripts/seed_schema.py
sh ./infra/scripts/deployimage.sh
