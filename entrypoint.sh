#!/bin/bash

set -euo pipefail

# Load the Intel OneAPI environment
. /opt/intel/oneapi/setvars.sh

exec "$@"
