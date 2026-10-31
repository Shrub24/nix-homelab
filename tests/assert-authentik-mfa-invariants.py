"""Assert the identity plan never creates a session without a second factor.

Reads the assembled blueprint and checks the order of stage bindings per flow. The
interactive behaviour (a real passkey, a real authenticator code) is verified on a live
deployment; what this catches is the regression that matters and is invisible until
someone is locked out: a login binding moved ahead of its method requirement.
"""

import sys

from ruamel.yaml import YAML

STAGE = "authentik_flows.flowstagebinding"
METHOD_STAGES = {
    "mfa-validation": "the MFA validation stage",
    "default-authenticator-totp-setup": "authenticator-code enrolment",
    "passkey-setup": "passkey enrolment",
}
LOGIN_STAGES = {"enrollment-user-login", "recovery-user-login"}


def identifier(value):
    """The identifier an entry reference resolves to, for !KeyOf or !Find forms."""
    text = str(value)
    if str(getattr(value, "tag", "")) == "!KeyOf":
        return text
    if str(getattr(value, "tag", "")) == "!Find":
        return str(value[1][1])
    return text


def main(path):
    entries = YAML().load(open(path))["entries"]
    by_id = {e["id"]: e for e in entries if e.get("id")}
    bindings = [e for e in entries if e.get("model") == STAGE]

    failures = []
    for flow_id in ("enrollment-flow", "recovery-flow"):
        if flow_id not in by_id:
            continue
        stages = [
            (b["attrs"]["order"], identifier(b["attrs"]["stage"]), b["id"])
            for b in bindings
            if b["attrs"].get("target") is not None
            and identifier(b["attrs"]["target"]) == flow_id
        ]
        stages.sort()
        logins = [o for o, s, _ in stages if s in LOGIN_STAGES]
        methods = [o for o, s, _ in stages if s in METHOD_STAGES]
        flow = by_id[flow_id]["identifiers"]["slug"]
        if not logins:
            failures.append(f"{flow}: no login stage, so this flow cannot be checked")
        if not methods or (logins and min(methods) > min(logins)):
            failures.append(
                f"{flow}: a session is created at order {min(logins) if logins else '?'} "
                f"with no method requirement before it ({sorted(methods)})"
            )

    stage = by_id.get("mfa-validation")
    if not stage:
        failures.append("mfa-validation: the login MFA stage is not declared")
    else:
        attrs = stage["attrs"]
        classes = set(attrs.get("device_classes") or [])
        if attrs.get("not_configured_action") != "configure":
            failures.append(
                "mfa-validation: an account with no method would be let through "
                f"(not_configured_action={attrs.get('not_configured_action')!r})"
            )
        if not {"webauthn", "totp"} <= classes:
            failures.append(
                f"mfa-validation: a lost device has no alternative ({sorted(classes)})"
            )

    if failures:
        print("\n".join(f"FAIL {f}" for f in failures))
        return 1
    print("MFA plan invariant holds: every session is preceded by a method requirement")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
