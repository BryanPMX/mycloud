"""Deployment contracts; resolves public fixtures without creating containers."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from urllib.parse import urlsplit

ROOT = Path(__file__).resolve().parents[1]
UUID = "00000000-0000-4000-8000-000000000039"


# Deliberately distinct, non-secret values. Never inherit operator credentials.
ROOT_USER = "validation-root-user"
ROOT_PASSWORD = "validation-root-password-only"
APP_ACCESS = "validation-app-user"
APP_SECRET = "validation-app-password-only"
RUNTIME_DATABASE_URL = "postgres://mycloud_app:validation-runtime-only@postgres:5432/mycloud?sslmode=disable"
MIGRATION_DATABASE_URL = "postgres://mycloud:validation-admin-only@postgres:5432/mycloud?sslmode=disable"
PRODUCTION_FILES = ("deploy/portainer-stack.npm.yml", "deploy/portainer-stack.yml")
COMPOSE_FILES = (*PRODUCTION_FILES, "docker-compose.yml")


def resolve(*, ssd=False, uuid=None, monitoring=False,
            compose_file=PRODUCTION_FILES[0], missing=(), empty=()):
    fixture = (ROOT / "deploy/portainer.env.example").read_text()
    fixture_names = {line.split("=", 1)[0] for line in fixture.splitlines()
                     if line and not line.startswith("#") and "=" in line}
    env = os.environ.copy()
    for name in fixture_names | {"MYCLOUD_MINIO_STORAGE_FILE", "MYCLOUD_STORAGE_UUID",
                                 "MYCLOUD_DATA_MOUNT", "MYCLOUD_STORAGE_GUARD_PATH"}:
        env.pop(name, None)
    env.update(MINIO_ROOT_USER=ROOT_USER, MINIO_ROOT_PASSWORD=ROOT_PASSWORD,
               MINIO_ACCESS_KEY=APP_ACCESS, MINIO_SECRET_KEY=APP_SECRET,
               DATABASE_URL=RUNTIME_DATABASE_URL,
               DATABASE_MIGRATION_URL=MIGRATION_DATABASE_URL)
    for name in missing:
        env.pop(name, None)
    for name in empty:
        env[name] = ""
    if ssd:
        env["MYCLOUD_MINIO_STORAGE_FILE"] = "storage/minio-ssd.yml"
    if uuid:
        env["MYCLOUD_STORAGE_UUID"] = uuid
    # A filtered public fixture proves absence, rather than only an empty value.
    fixture = "\n".join(line for line in fixture.splitlines()
                        if line.split("=", 1)[0] not in missing) + "\n"
    with tempfile.TemporaryDirectory(prefix="mycloud-compose-config-") as work:
        env_file = Path(work) / "dummy.env"
        env_file.write_text(fixture)
        command = ["docker", "compose", "--project-name", "mycloud", "--env-file",
                   str(env_file), "-f", compose_file]
        if monitoring:
            command += ["-f", "deploy/portainer-stack.monitoring.yml"]
        # Local Compose uses env_file: .env. Never read that private file in tests.
        return subprocess.run(command + ["config", "--no-env-resolution", "--format", "json"],
                              cwd=ROOT, env=env, capture_output=True, text=True, check=False)


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

    def credentials(self, config, *, explicit_app=True):
        services = config["services"]
        minio = services["minio"]["environment"]
        self.assertEqual(minio["MINIO_ROOT_USER"], ROOT_USER)
        self.assertEqual(minio["MINIO_ROOT_PASSWORD"], ROOT_PASSWORD)
        self.assertNotIn("MINIO_ACCESS_KEY", minio)
        self.assertNotIn("MINIO_SECRET_KEY", minio)
        if explicit_app:
            for name in ("api", "worker"):
                app = services[name]["environment"]
                self.assertEqual(app["MINIO_ACCESS_KEY"], APP_ACCESS)
                self.assertEqual(app["MINIO_SECRET_KEY"], APP_SECRET)
                self.assertNotIn("MINIO_ROOT_USER", app)
                self.assertNotIn("MINIO_ROOT_PASSWORD", app)

    def test_separate_credentials_in_all_deployment_files(self):
        for file in COMPOSE_FILES:
            with self.subTest(file=file):
                self.credentials(self.config(compose_file=file),
                                 explicit_app=file in PRODUCTION_FILES)

    def test_missing_or_empty_root_credentials_are_rejected(self):
        for file in COMPOSE_FILES:
            for name in ("MINIO_ROOT_USER", "MINIO_ROOT_PASSWORD"):
                for mode in ("missing", "empty"):
                    with self.subTest(file=file, variable=name, mode=mode):
                        result = resolve(compose_file=file, **{mode: (name,)})
                        self.assertNotEqual(result.returncode, 0)
                        self.assertIn(name + " is required", result.stderr)

    def test_runtime_and_migration_database_connections_are_separate(self):
        self.assertNotEqual(urlsplit(RUNTIME_DATABASE_URL).username,
                            urlsplit(MIGRATION_DATABASE_URL).username)
        for file in COMPOSE_FILES:
            with self.subTest(file=file):
                services = self.config(compose_file=file)["services"]
                for name in ("api", "worker"):
                    self.assertEqual(services[name]["environment"]["DATABASE_URL"],
                                     RUNTIME_DATABASE_URL)
                self.assertEqual(services["migrate"]["environment"]["DATABASE_URL"],
                                 MIGRATION_DATABASE_URL)

    def test_production_migration_credentials_reach_only_the_migrator(self):
        for file in PRODUCTION_FILES:
            with self.subTest(file=file):
                services = self.config(compose_file=file)["services"]
                for name, service in services.items():
                    self.assertNotIn("DATABASE_MIGRATION_URL", service.get("environment", {}))
                    self.assertFalse(service.get("env_file"))
                    if name != "migrate":
                        self.assertNotIn(MIGRATION_DATABASE_URL, json.dumps(service))
                self.assertEqual(services["migrate"]["environment"],
                                 {"DATABASE_URL": MIGRATION_DATABASE_URL})

    def test_missing_or_empty_migration_database_url_is_rejected(self):
        for file in COMPOSE_FILES:
            for mode in ("missing", "empty"):
                with self.subTest(file=file, mode=mode):
                    result = resolve(compose_file=file, **{mode: ("DATABASE_MIGRATION_URL",)})
                    self.assertNotEqual(result.returncode, 0)
                    self.assertIn("DATABASE_MIGRATION_URL is required", result.stderr)

    def test_postgres_container_keeps_its_admin_identity(self):
        fixture = dict(line.split("=", 1) for line in
                       (ROOT / "deploy/portainer.env.example").read_text().splitlines()
                       if line and not line.startswith("#") and "=" in line)
        for file in COMPOSE_FILES:
            with self.subTest(file=file):
                postgres = self.config(compose_file=file)["services"]["postgres"]["environment"]
                self.assertEqual(postgres["POSTGRES_USER"], fixture["POSTGRES_USER"])
                self.assertEqual(postgres["POSTGRES_PASSWORD"], fixture["POSTGRES_PASSWORD"])

    def test_local_example_does_not_require_an_unprovisioned_runtime_role(self):
        fixture = dict(line.split("=", 1) for line in
                       (ROOT / ".env.example").read_text().splitlines()
                       if line and not line.startswith("#") and "=" in line)
        self.assertEqual(fixture["DATABASE_URL"], fixture["DATABASE_MIGRATION_URL"])
        self.assertEqual(urlsplit(fixture["DATABASE_URL"]).username, fixture["POSTGRES_USER"])

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
        self.credentials(config)
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

    def test_both_production_web_hosts_can_reach_the_api(self):
        origins = self.config()["services"]["api"]["environment"]["ALLOWED_ORIGINS"]
        self.assertEqual({origin.strip() for origin in origins.split(",")},
                         {"https://mynube.live", "https://www.mynube.live"})


if __name__ == "__main__":
    unittest.main()
