#!/bin/sh
# Builds JernOrac with the opam switch that holds its libraries, on 3 cores (rule 11).
cd "$(dirname "$0")" && exec opam exec --switch=jernal-oracle -- dune build -j 3 "$@"
