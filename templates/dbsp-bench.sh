#!/bin/sh
set -e
set -u
set -x

cd /home/ubuntu/database-stream-processor || exit

# Run with 8 CPU cores for similar parallelism to Nexmark Flink.
cargo bench --bench nexmark --features with-nexmark -- \
    --first-event-rate=10000000 \
    --max-events=100000000 \
    --cpu-cores 8 \
    --num-event-generators 8 \
    --source-buffer-size 10000 \
    --input-batch-size 40000
