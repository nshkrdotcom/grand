"""Offline failure/recovery checks for bootstrap; execute with uv."""
import contextlib
import io
import json
import os
from pathlib import Path
import tarfile
import tempfile
import unittest
from unittest.mock import patch
from types import SimpleNamespace

import provision


class BootstrapTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.local = Path(self.temp.name)
        self.local_patch = patch.object(provision, "LOCAL", self.local)
        self.local_patch.start()
        self.addCleanup(self.local_patch.stop)

    def artifact(self, malicious=False):
        (self.local / "downloads").mkdir()
        archive = self.local / "downloads/tool.tar.gz"
        with tarfile.open(archive, "w:gz") as tar:
            content = b"fixture source"
            entry = tarfile.TarInfo("../escaped" if malicious else "root/tool")
            entry.size = len(content)
            tar.addfile(entry, io.BytesIO(content))
        return {"url": "https://invalid.example/tool.tar.gz", "sha256": provision.digest(archive)}

    def test_checked_cache_avoids_network_and_corruption_fails_closed(self):
        pin = self.artifact()
        with patch("urllib.request.urlopen", side_effect=AssertionError("network accessed")):
            path = provision.download(pin)
            path.write_bytes(b"corrupt")
            with self.assertRaisesRegex(RuntimeError, "Corrupt cached"):
                provision.download(pin)

    def test_install_repeats_and_incomplete_extraction_recovers(self):
        pin = self.artifact()
        dest = self.local / "installed"
        pending = self.local / "installed.partial"
        pending.mkdir()
        (pending / "interrupted").write_text("old")
        provision.extract(pin, dest, strip_root=True)
        self.assertEqual(b"fixture source", (dest / "tool").read_bytes())
        mtime = (dest / "tool").stat().st_mtime_ns
        provision.extract(pin, dest, strip_root=True)
        self.assertEqual(mtime, (dest / "tool").stat().st_mtime_ns)
        changed = dict(pin, sha256="0" * 64)
        with self.assertRaisesRegex(RuntimeError, "Tool pin changed"):
            provision.extract(changed, dest, strip_root=True)

    def test_archive_traversal_is_rejected(self):
        pin = self.artifact(malicious=True)
        with self.assertRaises(tarfile.FilterError):
            provision.extract(pin, self.local / "installed", strip_root=True)
        self.assertFalse((self.local / "escaped").exists())
        self.assertFalse((self.local / "installed").exists())

    def test_local_environment_does_not_modify_parent(self):
        before = dict(os.environ)
        env = provision.local_env()
        self.assertEqual(before, dict(os.environ))
        self.assertEqual(str(self.local / "elan"), env["ELAN_HOME"])
        self.assertTrue(env["GRAND_TLC_JAR"].startswith(str(self.local)))

    def test_missing_java_has_friendly_diagnostic_without_installation(self):
        real = provision.shutil.which
        with patch.object(provision.shutil, "which", side_effect=lambda name: None if name == "java" else real(name)):
            with self.assertRaisesRegex(RuntimeError, "Missing prerequisite java.*Install a compatible JDK"):
                provision.prerequisites()

    def test_incompatible_java_has_install_guidance(self):
        bad_java = SimpleNamespace(returncode=1, stdout="", stderr="Unrecognized option: --version")
        with patch.object(provision, "run", side_effect=["Elixir 1.20.5 (compiled with Erlang/OTP 29)", "29.1.2"]):
            with patch.object(provision.subprocess, "run", return_value=bad_java):
                with self.assertRaisesRegex(RuntimeError, "Expose Java 21"):
                    provision.prerequisites()


if __name__ == "__main__":
    unittest.main()
