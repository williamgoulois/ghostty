#!/usr/bin/env python3
"""Run all GhosttyIDE test suites via pytest.

Usage:
    ide/Tests/run_all.py              # run all tests
    ide/Tests/run_all.py -k workflow  # run only workflow tests
    ide/Tests/run_all.py -x           # stop on first failure
"""

import os
import subprocess
import sys

test_dir = os.path.dirname(os.path.abspath(__file__))
venv_pytest = os.path.join(test_dir, ".venv", "bin", "pytest")

if not os.path.isfile(venv_pytest):
    print(f"pytest not found. Run: cd {test_dir} && python3 -m venv .venv && .venv/bin/pip install pytest")
    sys.exit(1)

# Pass through all args to pytest
sys.exit(subprocess.run([venv_pytest] + sys.argv[1:], cwd=test_dir).returncode)
