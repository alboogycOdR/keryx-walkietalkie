#!/usr/bin/env python3
"""Execute the relay validate gate (validate.ps1 / validate.sh).

`test_relay_config.py` re-implements the static checks and therefore cannot
see caller/callee drift (validate scripts rendering into $TEMP while
`render_config.py` assumed dest lived under `relay/`). This file runs the
actual gate script and asserts exit 0.

Kept in a *separate* module so `validate.ps1` / `validate.sh` can still
invoke `test_relay_config.py` as their last step without recursing into
this test.
"""

from __future__ import annotations

import subprocess
import sys
import unittest
from pathlib import Path

RELAY = Path(__file__).resolve().parent.parent
SCRIPTS = RELAY / "scripts"


class ValidateGateTests(unittest.TestCase):
    def test_validate_script_exits_zero(self) -> None:
        if sys.platform == "win32":
            script = SCRIPTS / "validate.ps1"
            cmd = [
                "powershell",
                "-NoProfile",
                "-ExecutionPolicy",
                "Bypass",
                "-File",
                str(script),
            ]
        else:
            script = SCRIPTS / "validate.sh"
            cmd = ["bash", str(script)]

        self.assertTrue(script.is_file(), f"missing gate script: {script}")
        proc = subprocess.run(
            cmd,
            cwd=RELAY,
            check=False,
            capture_output=True,
            text=True,
            timeout=180,
        )
        blob = (proc.stdout or "") + (proc.stderr or "")
        if proc.returncode != 0:
            self.fail(
                f"{script.name} exited {proc.returncode}\n"
                f"stdout:\n{proc.stdout}\nstderr:\n{proc.stderr}"
            )
        self.assertIn("[render] wrote", blob)
        self.assertNotIn("is not in the subpath", blob)
        self.assertNotIn("ValueError", blob)


if __name__ == "__main__":
    unittest.main(verbosity=2)
