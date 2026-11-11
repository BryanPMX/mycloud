"""Deployment contracts; resolves public fixtures without creating containers."""
import json
import os
from pathlib import Path
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]
UUID = "00000000-0000-4000-8000-000000000039"


def resolve(*, ssd=False, uuid=None, monitoring=False):
    env = os.environ.copy()
    for name in ("MYCLOUD_MINIO_STORAGE_FILE", "MYCLOUD_STORAGE_UUID",
                 "MYCLOUD_DATA_MOUNT", "MYCLOUD_STORAGE_GUARD_PATH"):
        env.pop(name, None)
    if ssd:
        env["MYCLOUD_MINIO_STORAGE_FILE"] = "storage/minio-ssd.yml"
    if uuid:
        env["MYCLOUD_STORAGE_UUID"] = uuid
    command = ["docker", "compose", "--project-name", "mycloud", "--env-file",
               "deploy/portainer.env.example", "-f", "deploy/portainer-stack.npm.yml"]
    if monitoring:
        command += ["-f", "deploy/portainer-stack.monitoring.yml"]
    return subprocess.run(command + ["config", "--format", "json"], cwd=ROOT,
                          env=env, capture_output=True, text=True, check=False)


class PortainerConfig(unittest.TestCase):
    def config(self, **options):
        result = resolve(**options)
        self.assertEqual(result.returncode, 0, "Fixture Compose resolution failed")
        return json.loads(result.stdout)

    def private_ports(self, config):
        services = config["services"]
        for service, published in (("api", "19090"), ("worker", "19091")):
            self.assertEqual(len(services[service]["ports"]), 1)
            port = services[service]["ports"][0]
            self.assertEqual((port["host_ip"], str(port["published"]), port["target"]),
                             ("127.0.0.1", published, 9090))
        console = services["minio"]["ports"]
        self.assertEqual(len(console), 1)
        self.assertEqual((console[0]["host_ip"], console[0]["target"]), ("127.0.0.1", 9001))
        for service in ("postgres", "redis", "clamav"):
            self.assertFalse(services[service].get("ports"))

    def test_default_keeps_existing_volume_and_private_metrics(self):
        config = self.config()
        self.assertEqual(set(config["services"]),
                         {"api", "worker", "migrate", "postgres", "redis", "minio", "clamav"})
        self.assertEqual(config["volumes"]["minio_data"]["name"], "mycloud_minio_data")
        mount = config["services"]["minio"]["volumes"]
        self.assertEqual(len(mount), 1)
        self.assertEqual((mount[0]["type"], mount[0]["source"], mount[0]["target"]),
                         ("volume", "minio_data", "/data"))
        self.assertIsNone(config["services"]["minio"].get("entrypoint"))
        self.private_ports(config)

    def test_ssd_requires_identity_and_never_creates_fallback_paths(self):
        config = self.config(ssd=True, uuid=UUID)
        minio = config["services"]["minio"]
        self.assertEqual(minio["image"], "ghcr.io/bryanpmx/minio:RELEASE.2025-09-07T16-13-09Z")
        self.assertEqual(minio["entrypoint"], ["/bin/sh", "/mycloud-storage-guard.sh"])
        self.assertEqual(minio["environment"]["MYCLOUD_STORAGE_UUID"], UUID)
        mounts = {mount["target"]: mount for mount in minio["volumes"]}
        expected = {"/data": "/srv/mycloud-data/minio",
                    "/storage-identity": "/srv/mycloud-data/.mycloud-volume",
                    "/mycloud-storage-guard.sh": "/etc/mycloud/minio-entrypoint.sh"}
        self.assertEqual(set(mounts), set(expected))
        for target, source in expected.items():
            self.assertEqual((mounts[target]["type"], mounts[target]["source"]), ("bind", source))
            self.assertFalse(mounts[target]["bind"].get("create_host_path", False))
        self.assertTrue(mounts["/storage-identity"]["read_only"])
        self.assertTrue(mounts["/mycloud-storage-guard.sh"]["read_only"])
        self.private_ports(config)

    def test_ssd_without_uuid_is_rejected_before_deployment(self):
        result = resolve(ssd=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Prepared data filesystem UUID is required", result.stderr)

    def test_existing_monitoring_override_does_not_duplicate_bindings(self):
        self.private_ports(self.config(monitoring=True))


if __name__ == "__main__":
    unittest.main()
