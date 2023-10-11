#!/bin/bash

#julia -t auto --sysimage="./ExampleTempest.so" -O3 --project=@. ./production/script_compilation.jl
julia -t auto  -O3 --project=@. ./production/script_compilation.jl

