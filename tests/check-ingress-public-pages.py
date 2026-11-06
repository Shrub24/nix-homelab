#!/usr/bin/env python3
"""Exercise the rendered apex handlers with Caddy, without production TLS or upstreams."""

import http.client
import json
import os
from pathlib import Path
import socket
import subprocess
import tempfile
import threading
import unittest


ROOT = Path(__file__).resolve().parents[1]


class PublicPages(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        edge = subprocess.check_output(
            [
                "nix",
                "eval",
                "--impure",
                "--raw",
                "--expr",
                "(import ./lib/deploy/hosts.nix).edgeHost",
            ],
            cwd=ROOT,
            text=True,
        ).strip()
        report = json.loads(
            subprocess.check_output(
                [
                    "nix",
                    "eval",
                    "--json",
                    f".#nixosConfigurations.{edge}.config",
                    "--apply",
                    """c: {
                      caddyfile = c.services.caddy.configFile.text;
                      domain = c.services.ingress.primaryDomain;
                      redirect = c.services.ingress.routes.apex.redirectTo;
                      page = builtins.readFile c.services.ingress.staticPages.apex."/privacy";
                    }""",
                ],
                cwd=ROOT,
                text=True,
            )
        )
        cls.domain = report["domain"]
        cls.redirect = report["redirect"]
        cls.page = report["page"].encode()
        caddy = os.environ.get("CADDY_BIN")
        if not caddy:
            package = subprocess.check_output(
                [
                    "nix",
                    "build",
                    "--no-link",
                    "--print-out-paths",
                    "--inputs-from",
                    ".#",
                    "nixpkgs#caddy",
                ],
                cwd=ROOT,
                text=True,
            ).strip()
            caddy = str(Path(package) / "bin/caddy")

        tmp = tempfile.TemporaryDirectory()
        cls.addClassCleanup(tmp.cleanup)
        directory = Path(tmp.name)
        caddyfile = directory / "Caddyfile"
        caddyfile.write_text(report["caddyfile"])
        adapted_result = subprocess.run(
            [caddy, "adapt", "--adapter", "caddyfile", "--config", str(caddyfile)],
            text=True,
            capture_output=True,
        )
        if adapted_result.returncode:
            raise AssertionError(adapted_result.stderr)
        adapted = json.loads(adapted_result.stdout)
        # Keep the real apex handlers, but isolate them from certificate files,
        # privileged ports and unrelated applications in the production configuration.
        apex = [
            route
            for server in adapted["apps"]["http"]["servers"].values()
            for route in server["routes"]
            if any(
                cls.domain in matcher.get("host", [])
                for matcher in route.get("match", [])
            )
        ]
        if len(apex) != 1:
            raise AssertionError(f"Expected one rendered apex site, found {len(apex)}")
        with socket.socket() as listener:
            listener.bind(("127.0.0.1", 0))
            cls.port = listener.getsockname()[1]
        config = {
            "admin": {"disabled": True},
            "apps": {
                "http": {
                    "servers": {
                        "test": {
                            "listen": [f"127.0.0.1:{cls.port}"],
                            "automatic_https": {"disable": True},
                            "routes": apex,
                        }
                    }
                }
            },
        }
        config_file = directory / "caddy.json"
        config_file.write_text(json.dumps(config))
        process = subprocess.Popen(
            [caddy, "run", "--config", str(config_file)],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE,
            text=True,
        )

        def stop():
            if process.poll() is None:
                process.terminate()
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()
            thread.join(timeout=5)
            process.stderr.close()

        cls.addClassCleanup(stop)
        ready = threading.Event()
        logs = []

        def read_logs():
            for line in process.stderr:
                logs.append(line)
                if '"msg":"serving initial configuration"' in line:
                    ready.set()
            ready.set()

        thread = threading.Thread(target=read_logs, daemon=True)
        thread.start()
        if not ready.wait(15) or process.poll() is not None:
            raise AssertionError("Caddy did not start:\n" + "".join(logs))

    def request(self, path, method="GET"):
        connection = http.client.HTTPConnection("127.0.0.1", self.port, timeout=5)
        try:
            connection.request(method, path, headers={"Host": self.domain})
            response = connection.getresponse()
            return response.status, dict(response.getheaders()), response.read()
        finally:
            connection.close()

    def test_policy_is_public_html_at_both_paths(self):
        for path in ["/privacy", "/privacy/", "/privacy?from=google"]:
            with self.subTest(path=path):
                status, headers, body = self.request(path)
                self.assertEqual(status, 200)
                self.assertTrue(headers["Content-Type"].startswith("text/html"))
                self.assertEqual(body, self.page)

    def test_head_is_public_without_a_response_body(self):
        status, _, body = self.request("/privacy", "HEAD")
        self.assertEqual(status, 200)
        self.assertEqual(body, b"")

    def test_other_paths_keep_the_redirect_and_query(self):
        for path in [
            "/",
            "/privacy-extra",
            "/privacy/child?keep=yes",
            "/somewhere?keep=yes",
        ]:
            with self.subTest(path=path):
                status, headers, _ = self.request(path)
                self.assertEqual(status, 301)
                self.assertEqual(headers["Location"], self.redirect + path)


if __name__ == "__main__":
    unittest.main()
