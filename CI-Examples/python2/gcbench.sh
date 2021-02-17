#!/bin/bash

for i in {1..3}
do
    sleep 30
    PERF=1 numactl -C 1 --membind=0 gramine-sgx python benchmarks/performance/gcbench.py 2>&1 | tee run${i}_${1}
done
