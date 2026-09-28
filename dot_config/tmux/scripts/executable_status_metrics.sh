#!/usr/bin/env bash
export LC_ALL=C
exec python3 "$(cd "$(dirname "$0")" && pwd)/status_metrics.py" "$@"
