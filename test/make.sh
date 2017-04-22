#!/bin/sh
erl -sname plists_test_$(date +%H%M%S)@localhost \
-run file set_cwd .. \
-run make all \
-run file set_cwd test \
-pa ../ebin -run make all -run plists_unittests run \
-run init stop -noshell
