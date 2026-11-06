"""Execute the rendered email policies with only persistence stubbed."""

import json
import subprocess
import sys
from contextlib import nullcontext
from types import SimpleNamespace
from unittest.mock import Mock, patch

entries = json.loads(
    subprocess.check_output(["yq", "-o=json", ".", sys.argv[1]], text=True)
)["entries"]
programs = {}
for entry in entries:
    if entry.get("id") in {
        "policy-email-verified",
        "policy-email-gate",
        "policy-email-unverified",
    }:
        expression = entry["attrs"]["expression"]
        programs[entry["identifiers"]["name"]] = compile(
            "def evaluate(request):\n"
            + "\n".join("    " + line for line in expression.splitlines()),
            entry["id"],
            "exec",
        )


class Rows(list):
    """Minimal persistence boundary; no verification decisions live here."""

    def filter(self, **query):
        def value(row, path):
            for part in path.split("__"):
                row = getattr(row, part)
            return row

        return Rows(
            row
            for row in self
            if all(value(row, key) == expected for key, expected in query.items())
        )

    def update(self, **changes):
        for row in self:
            for key, value in changes.items():
                setattr(row, key, value)

    def exists(self):
        return bool(self)


def check(
    *,
    device_email=None,
    owner=1,
    confirmed=True,
    active=True,
    verified=None,
    current_email="new@example.com",
    pending_email="new@example.com",
    standalone=False,
):
    user = SimpleNamespace(
        pk=1, email=pending_email, is_active=active, attributes={}, save=Mock()
    )
    user.refresh_from_db = Mock(
        side_effect=lambda: setattr(user, "email", current_email)
    )
    if verified is not None:
        user.attributes["email_verified_address"] = verified
    stage = SimpleNamespace(name="personal-email")
    devices = Rows()
    if device_email is not None:
        devices.append(
            SimpleNamespace(
                user=user if owner == 1 else SimpleNamespace(pk=owner),
                email=device_email,
                confirmed=confirmed,
                stage=stage,
            )
        )
    models = SimpleNamespace(
        EmailDevice=SimpleNamespace(objects=devices),
        AuthenticatorEmailStage=SimpleNamespace(
            objects=SimpleNamespace(get=lambda **_: stage)
        ),
    )
    request = SimpleNamespace(
        context={} if standalone else {"pending_user": user},
        user=user if standalone else SimpleNamespace(pk=None),
    )

    def evaluate(name):
        scope = {"ak_call_policy": lambda name: SimpleNamespace(passing=evaluate(name))}
        exec(programs[name], scope)
        return scope["evaluate"](request)

    with patch.dict(
        sys.modules,
        {
            "django.db": SimpleNamespace(
                transaction=SimpleNamespace(atomic=nullcontext)
            ),
            "authentik.stages.authenticator_email.models": models,
        },
    ):
        first = evaluate("homelab-email-verification")
        second = evaluate("homelab-email-verification")
        assert first == second, "repeated evaluation changes the verification result"
        for name in ["homelab-email-gate", "homelab-email-unverified"]:
            assert evaluate(name) is not first, f"{name} disagrees with verification"
    assert user.is_active is active, "verification changed administrative status"
    assert len(devices) == (device_email is not None), (
        "verification removed an authenticator"
    )
    if devices:
        assert devices[0].email == device_email, (
            "verification rewrote an authenticator address"
        )
    return first, user


for standalone in [False, True]:
    result, user = check(device_email="new@example.com", standalone=standalone)
    assert result and user.attributes["email_verified_address"] == "new@example.com"
    user.save.assert_called_once()

# A different user's device, another address or an unconfirmed device proves nothing.
for parameters in [
    {"owner": 2},
    {"device_email": "old@example.com"},
    {"confirmed": False},
    {"active": False},
]:
    result, user = check(**({"device_email": "new@example.com"} | parameters))
    assert not result, parameters
    user.save.assert_not_called()

result, user = check()
assert not result
user.save.assert_not_called()

# Refresh the account address rather than trusting the plan's stale user object.
result, user = check(device_email="old@example.com", pending_email="old@example.com")
assert not result
user.save.assert_not_called()

for recorded, address, expected in [
    ("new@example.com", "new@example.com", True),
    ("old@example.com", "new@example.com", False),
    (None, "", False),
]:
    result, user = check(verified=recorded, current_email=address)
    assert result is expected
    user.save.assert_not_called()

print(
    "authentik-email-policy: PASS (address ownership, device reuse and status preservation)"
)
