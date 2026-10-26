"""Exercise the fleet's rendered verification policy with a small persistence boundary."""

import json
import subprocess
import sys
from contextlib import nullcontext
from types import SimpleNamespace
from unittest.mock import Mock, patch

entries = json.loads(
    subprocess.check_output(["yq", "-o=json", ".", sys.argv[1]], text=True)
)["entries"]
expression = next(
    e["attrs"]["expression"] for e in entries if e.get("id") == "policy-email-verified"
)
program = compile(
    "def evaluate(request):\n"
    + "\n".join("    " + line for line in expression.splitlines()),
    "homelab-email-verification",
    "exec",
)


def check(
    *,
    proof_email=None,
    confirmed=True,
    stage="verify-email-code",
    owner=1,
    verified=None,
    current_email="new@example.com",
    pending_email="new@example.com",
    standalone=False,
):
    user = SimpleNamespace(
        pk=1, email=pending_email, attributes={}, is_active=False, save=Mock()
    )
    if verified:
        user.attributes["email_verified_address"] = verified
    user.refresh_from_db = Mock(
        side_effect=lambda: setattr(user, "email", current_email)
    )
    proof = SimpleNamespace(email=proof_email, delete=Mock()) if proof_email else None

    def filter_proof(**query):
        matches = proof and all(
            [
                query["user"].pk == owner,
                query["email"] == proof_email,
                query["stage__name"] == stage,
                query["confirmed"] == confirmed,
            ]
        )
        return SimpleNamespace(first=lambda: proof if matches else None)

    models = SimpleNamespace(
        EmailDevice=SimpleNamespace(objects=SimpleNamespace(filter=filter_proof))
    )
    with patch.dict(
        sys.modules,
        {
            "django.db": SimpleNamespace(
                transaction=SimpleNamespace(atomic=nullcontext)
            ),
            "authentik.stages.authenticator_email.models": models,
        },
    ):
        scope = {}
        exec(program, scope)
        result = scope["evaluate"](
            SimpleNamespace(
                context={} if standalone else {"pending_user": user},
                user=user if standalone else SimpleNamespace(pk=None),
            )
        )
    return result, user, proof


# A confirmed code for the current address activates once and consumes only its proof.
result, user, proof = check(proof_email="new@example.com")
assert result and user.is_active
assert user.attributes["email_verified_address"] == "new@example.com"
user.save.assert_called_once()
proof.delete.assert_called_once()

result, user, proof = check(proof_email="new@example.com", standalone=True)
assert result and user.is_active
proof.delete.assert_called_once()

# Wrong account, stale address, unconfirmed proof and unrelated MFA cannot verify it.
for parameters in [
    {"owner": 2},
    {"proof_email": "old@example.com"},
    {"confirmed": False},
    {"stage": "personal-email-mfa"},
]:
    result, user, proof = check(**({"proof_email": "new@example.com"} | parameters))
    assert not result and not user.is_active, parameters
    user.save.assert_not_called()
    proof.delete.assert_not_called()

result, user, _ = check()
assert not result and not user.is_active

# Read the current row, not the old address retained by the flow plan.
result, user, proof = check(
    proof_email="old@example.com", pending_email="old@example.com"
)
assert not result
proof.delete.assert_not_called()

result, user, _ = check(verified="new@example.com")
assert result
user.save.assert_not_called()

result, _, _ = check(verified="old@example.com")
assert not result
result, user, _ = check(current_email="", pending_email="")
assert result and "email_verified_address" not in user.attributes
user.save.assert_not_called()

print("authentik-email-policy: PASS (address-bound proof, activation and consumption)")
