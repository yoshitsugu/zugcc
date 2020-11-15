#!/bin/bash

set -e
zig build
set +e

./test-output.sh
./test-driver.sh