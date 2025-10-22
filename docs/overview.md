# Overview

This repo hosts a collection of reusable MySQL 8.0 table packages (as submodules).
The monolithic schema in `scripts/schema-map.psd1` is the source of truth; generators
split it into per-package `schema/*.sql` and produce human-friendly docs.
