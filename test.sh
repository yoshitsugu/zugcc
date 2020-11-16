#!/bin/bash

set -e
zig build

./test-output.sh
./test-driver.sh