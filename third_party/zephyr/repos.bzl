# Copyright lowRISC contributors (OpenTitan project).
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0

load("@python3//:defs.bzl", "interpreter")
load("//rules:repo.bzl", "http_archive_or_local")
load("@rules_python//python:pip.bzl", "pip_parse")

def zephyr_pip_deps():
    pip_parse(
        name = "py_deps",
        python_interpreter_target = interpreter,
        requirements_lock = "@@zephyr//:scripts/requirements-base.txt",
    )

# TODO: choose between this rule and `local_patched_repository`.
def zephyr_repos(zephyr = None):
    http_archive_or_local(
        name = "zephyr",
        local = zephyr,
        url = "https://github.com/zephyrproject-rtos/zephyr/archive/refs/tags/v3.7.0.tar.gz",
        sha256 = "3b27e54752af40ff9854626aca609ef52e5cb4eee7de836065547681437e1f80",
        patches = [
            "@zephyr-patch//:patch.diff",
        ],
    )
