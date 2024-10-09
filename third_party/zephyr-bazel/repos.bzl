# Copyright lowRISC contributors (OpenTitan project).
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0

load("//rules:repo.bzl", "http_archive_or_local")

def zephyr_bazel_repos(zephyr_bazel = None):
    if not zephyr_bazel:
        fail("Only local zephyr-bazel archives are currently supported.")

    http_archive_or_local(
        name = "zephyr-bazel",
        local = zephyr_bazel,
    )
