"""Exercise shipped flows in a disposable pinned Authentik instance.

Run through manage.py shell after importing native defaults and the rendered fleet
blueprint. Only mail delivery and the physical authenticator are replaced.
"""

import base64
import hashlib
import json
import os
import struct
from uuid import uuid4
from datetime import timedelta
from unittest.mock import PropertyMock, patch

import cbor2
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.asymmetric import ec
from django.core.mail.backends.locmem import EmailBackend
from django.urls import reverse
from django.utils.timezone import now
from authentik.stages.authenticator.oath import totp
from rest_framework.test import APIClient

from authentik.core.models import User
from authentik.flows.models import Flow, FlowToken
from authentik.flows.views.executor import SESSION_KEY_PLAN
from authentik.stages.authenticator_email.models import EmailDevice
from authentik.stages.authenticator_email.stage import PLAN_CONTEXT_EMAIL_DEVICE
from authentik.stages.authenticator_totp.models import TOTPDevice
from authentik.stages.email.models import EmailStage
from authentik.stages.invitation.models import Invitation

assert os.environ.get("AUTHENTIK_ENROLLMENT_TEST") == "1", "isolated instance only"
PASSWORD = "Orchard!Velvet-58-traveller"
RECOVERY_PASSWORD = "Forest!Harbour-74-galaxy"


def encoded(value):
    return base64.urlsafe_b64encode(value).rstrip(b"=").decode()


class Passkey:
    """A virtual user-verifying authenticator producing valid WebAuthn responses."""

    def __init__(self):
        self.key = ec.generate_private_key(ec.SECP256R1())
        self.id = os.urandom(32)
        self.counter = 0

    def client_data(self, kind, challenge):
        return json.dumps(
            {
                "type": kind,
                "challenge": challenge,
                "origin": "http://testserver",
                "crossOrigin": False,
            }
        ).encode()

    def registration(self, options):
        self.handle = options["user"]["id"]
        numbers = self.key.public_key().public_numbers()
        public_key = cbor2.dumps(
            {
                1: 2,
                3: -7,
                -1: 1,
                -2: numbers.x.to_bytes(32, "big"),
                -3: numbers.y.to_bytes(32, "big"),
            }
        )
        auth_data = (
            hashlib.sha256(options["rp"]["id"].encode()).digest()
            + b"\x45"
            + struct.pack(">I", 0)
            + bytes(16)
            + struct.pack(">H", len(self.id))
            + self.id
            + public_key
        )
        return {
            "id": encoded(self.id),
            "rawId": encoded(self.id),
            "type": "public-key",
            "response": {
                "clientDataJSON": encoded(
                    self.client_data("webauthn.create", options["challenge"])
                ),
                "attestationObject": encoded(
                    cbor2.dumps({"fmt": "none", "attStmt": {}, "authData": auth_data})
                ),
                "transports": ["internal"],
            },
            "clientExtensionResults": {"credProps": {"rk": True}},
        }

    def assertion(self, options):
        self.counter += 1
        client_data = self.client_data("webauthn.get", options["challenge"])
        auth_data = (
            hashlib.sha256(options["rpId"].encode()).digest()
            + b"\x05"
            + struct.pack(">I", self.counter)
        )
        signature = self.key.sign(
            auth_data + hashlib.sha256(client_data).digest(), ec.ECDSA(hashes.SHA256())
        )
        return {
            "id": encoded(self.id),
            "rawId": encoded(self.id),
            "type": "public-key",
            "response": {
                "clientDataJSON": encoded(client_data),
                "authenticatorData": encoded(auth_data),
                "signature": encoded(signature),
                "userHandle": self.handle,
            },
        }


class Browser:
    def __init__(self, flow):
        self.client = APIClient()
        self.url = reverse("authentik_api:flow-executor", kwargs={"flow_slug": flow})

    def request(self, data=None, query="", allow_errors=False):
        url = self.url
        if query:
            from urllib.parse import urlencode

            url += "?" + urlencode({"query": query})
        response = (
            self.client.get(url)
            if data is None
            else self.client.post(url, data, format="json")
        )
        # Automatic stages legitimately redirect to the same executor URL.
        for _ in range(20):
            if response.status_code not in {301, 302, 303}:
                break
            response = self.client.get(response["Location"])
        else:
            raise AssertionError("flow exceeded the browser redirect limit")
        assert response.status_code == 200, (response.status_code, response.content)
        self.response = response
        self.session = response.wsgi_request.session
        self.challenge = response.json()
        if not allow_errors:
            assert not self.challenge.get("response_errors"), self.challenge.get(
                "response_errors"
            )
        return self.challenge

    def expect(self, component):
        assert self.challenge["component"] == component, self.challenge

    def no_session(self):
        assert not self.response.wsgi_request.user.is_authenticated, (
            "session issued before completion"
        )

    def signed_in(self, user):
        assert self.response.wsgi_request.user.pk == user.pk, self.challenge

    def code(self):
        device = self.session[SESSION_KEY_PLAN].context[PLAN_CONTEXT_EMAIL_DEVICE]
        self.request(
            {"component": "ak-stage-authenticator-email", "code": device.token}
        )


def enroll(method, stop=None):
    name = "enroll-" + uuid4().hex[:10]
    flow = Flow.objects.get(slug="enrollment")
    issuer, _ = User.objects.get_or_create(username="isolated-invitation-issuer")
    invite = Invitation.objects.create(
        name=name, flow=flow, single_use=True, created_by=issuer
    )
    browser = Browser(flow.slug)
    browser.request(query="itoken=" + str(invite.pk))
    replay = Browser(flow.slug)
    replay.request(query="itoken=" + str(invite.pk))
    replay.expect("ak-stage-access-denied")
    replay.no_session()
    browser.expect("ak-stage-prompt")
    assert {f["field_key"] for f in browser.challenge["fields"]} == {
        "welcome_copy",
        "welcome_marker",
    }, "invitation did not land on the welcome stage"
    welcome = next(
        f for f in browser.challenge["fields"] if f["field_key"] == "welcome_copy"
    )
    assert welcome["initial_value"], "welcome copy would render empty"
    browser.request({"component": "ak-stage-prompt"})
    browser.expect("ak-stage-prompt")
    browser.request(
        {
            "component": "ak-stage-prompt",
            "username": name,
            "email": name + "@example.test",
        }
    )
    user = User.objects.get(username=name)
    assert user.is_active
    browser.no_session()
    browser.expect("ak-stage-authenticator-validate")
    # TOTP is enrolled from settings, not here.
    offered = [s["name"] for s in browser.challenge["configuration_stages"]]
    assert offered == ["Passkey", "Password"], (
        f"enrolment offered {offered}, not the passkey/password pair"
    )
    if stop == "reservation":
        return user, None
    target_model = (
        "authentik_stages_authenticator_webauthn.authenticatorwebauthnstage"
        if method == "passkey"
        else "authentik_stages_authenticator_email.authenticatoremailstage"
    )
    selection = next(
        s
        for s in browser.challenge["configuration_stages"]
        if s["meta_model_name"] == target_model
    )
    browser.request(
        {
            "component": "ak-stage-authenticator-validate",
            "selected_stage": selection["pk"],
        }
    )
    if method == "passkey":
        browser.expect("ak-stage-authenticator-webauthn")
        key = Passkey()
        browser.request(
            {
                "component": "ak-stage-authenticator-webauthn",
                "response": key.registration(browser.challenge["registration"]),
            }
        )
        browser.no_session()
        browser.expect("ak-stage-authenticator-email")
        if stop == "passkey":
            return user, key
        browser.code()
    else:
        key = None
        browser.expect("ak-stage-authenticator-email")
        if stop in {"wrong-code", "expired-code"}:
            device = browser.session[SESSION_KEY_PLAN].context[
                PLAN_CONTEXT_EMAIL_DEVICE
            ]
            code = device.token
            if stop == "wrong-code":
                code = "0" * len(code) if set(code) != {"0"} else "1" * len(code)
            else:
                device.valid_until = now() - timedelta(seconds=1)
                browser.session.modified = True
                browser.session.save()
            browser.request(
                {"component": "ak-stage-authenticator-email", "code": code},
                allow_errors=True,
            )
            browser.expect("ak-stage-authenticator-email")
            browser.no_session()
            assert browser.challenge.get("response_errors"), (
                "invalid code advanced the flow"
            )
            user.refresh_from_db()
            assert user.attributes.get("email_verified_address") != user.email
            print("VERIFICATION_REJECTED", stop)
            return user, None
        browser.code()
        browser.no_session()
        browser.expect("ak-stage-prompt")
        browser.request(
            {"component": "ak-stage-authenticator-email", "code": "replayed"},
            allow_errors=True,
        )
        browser.expect("ak-stage-prompt")
        browser.no_session()
        if stop == "email":
            return user, None
        browser.request({"component": "ak-stage-prompt", "password": PASSWORD})
    browser.signed_in(user)
    user.refresh_from_db()
    assert user.attributes["email_verified_address"] == user.email
    assert (
        EmailDevice.objects.filter(user=user, confirmed=True, email=user.email).count()
        == 1
    )
    assert user.check_password(PASSWORD) is (method == "email")
    print("ENROLLMENT_OK", method)
    return user, key


def login(user, key=None, password=PASSWORD, verify_address=False):
    browser = Browser("default-authentication-flow")
    browser.request()
    browser.expect("ak-stage-identification")
    if key:
        browser.request(
            {
                "component": "ak-stage-identification",
                "passkey": key.assertion(browser.challenge["passkey_challenge"]),
            }
        )
    else:
        browser.request(
            {
                "component": "ak-stage-identification",
                "uid_field": user.username,
                "password": password,
            }
        )
        browser.no_session()
        browser.expect("ak-stage-authenticator-validate")
        device = EmailDevice.objects.filter(user=user, confirmed=True).first()
        if device:
            challenge = next(
                c
                for c in browser.challenge["device_challenges"]
                if c["device_class"] == "email"
                and str(c["device_uid"]) == str(device.pk)
            )
            browser.request(
                {
                    "component": "ak-stage-authenticator-validate",
                    "selected_challenge": challenge,
                },
                allow_errors=True,
            )
            browser.expect("ak-stage-authenticator-validate")
            browser.no_session()
            device.refresh_from_db()
            assert device.token, "selecting the email factor did not issue a code"
        code = (
            device.token
            if device
            else str(totp(TOTPDevice.objects.get(user=user).bin_key)).zfill(6)
        )
        browser.request({"component": "ak-stage-authenticator-validate", "code": code})
    if verify_address:
        browser.expect("ak-stage-authenticator-email")
        browser.no_session()
        browser.code()
    browser.signed_in(user)
    print("LOGIN_OK", "passkey" if key else "password+code")


def enrol_taken(owner):
    """A taken name and a taken address are refused on the credentials form, and no second
    account is created for either."""
    flow = Flow.objects.get(slug="enrollment")
    issuer = User.objects.get(username="isolated-invitation-issuer")
    browser = Browser(flow.slug)
    invite = Invitation.objects.create(
        name="taken-" + uuid4().hex[:10],
        flow=flow,
        single_use=False,
        created_by=issuer,
    )
    browser.request(query="itoken=" + str(invite.pk))
    browser.request({"component": "ak-stage-prompt"})
    browser.expect("ak-stage-prompt")
    fresh = "taken-" + uuid4().hex[:10]
    before = User.objects.count()
    for username, email, expected in [
        (owner.username.upper(), fresh + "@example.test", "Username is already taken."),
        (fresh, owner.email.upper(), "already uses that email address"),
    ]:
        browser.request(
            {"component": "ak-stage-prompt", "username": username, "email": email},
            allow_errors=True,
        )
        browser.expect("ak-stage-prompt")
        browser.no_session()
        errors = [
            detail["string"]
            for details in (browser.challenge.get("response_errors") or {}).values()
            for detail in details
        ]
        assert any(expected in error for error in errors), (expected, errors)
        assert User.objects.count() == before, f"{username} created an account"
    # The stage is not wedged by the refusal: a free pair carries on through setup.
    browser.request(
        {
            "component": "ak-stage-prompt",
            "username": fresh,
            "email": fresh + "@example.test",
        }
    )
    browser.expect("ak-stage-authenticator-validate")
    print("TAKEN_REFUSED_VERBOSELY_OK")


def recover(user, interrupt=None):
    browser = Browser("recovery")
    browser.request()
    browser.request(
        {"component": "ak-stage-identification", "uid_field": user.username}
    )
    browser.expect("ak-stage-email")
    browser.no_session()
    token = FlowToken.objects.filter(user=user, flow__slug="recovery").latest("expires")
    if interrupt == "disabled":
        user.is_active = False
        user.save(update_fields=["is_active"])
    elif interrupt == "address-changed":
        user.email = "changed-" + user.email
        user.save(update_fields=["email"])
    browser.request(query="flow_token=" + token.key)
    browser.expect("ak-stage-consent")
    browser.no_session()
    browser.request(
        {"component": "ak-stage-consent", "token": browser.challenge["token"]}
    )
    if interrupt:
        browser.no_session()
        user.refresh_from_db()
        assert not user.check_password(RECOVERY_PASSWORD)
        assert user.is_active is (interrupt != "disabled")
        print("RECOVERY_DENIED", interrupt)
        return
    browser.expect("ak-stage-prompt")
    browser.no_session()
    browser.request(
        {
            "component": "ak-stage-prompt",
            "password": "short",
            "password_repeat": "short",
        },
        allow_errors=True,
    )
    browser.expect("ak-stage-prompt")
    browser.no_session()
    assert browser.challenge.get("response_errors"), "weak recovery password accepted"
    browser.request(
        {
            "component": "ak-stage-prompt",
            "password": RECOVERY_PASSWORD,
            "password_repeat": RECOVERY_PASSWORD,
        }
    )
    browser.signed_in(user)
    login(user, password=RECOVERY_PASSWORD)
    print("RECOVERY_AND_SUBSEQUENT_LOGIN_OK")


with patch.object(
    EmailStage, "backend_class", new_callable=PropertyMock, return_value=EmailBackend
):
    email_user, _ = enroll("email")
    login(email_user)
    passkey_user, key = enroll("passkey")
    login(passkey_user, key)
    enrol_taken(passkey_user)
    name = "totp-" + uuid4().hex[:10]
    user = User.objects.create(
        username=name,
        email=name + "@example.test",
        attributes={"email_verified_address": name + "@example.test"},
    )
    user.set_password(PASSWORD)
    user.save()
    TOTPDevice.objects.create(user=user, confirmed=True)
    login(user)
    print("EXISTING_TOTP_OK")
    original_email = email_user.email
    original_device = EmailDevice.objects.get(user=email_user)
    email_user.email = "independent-" + original_email
    EmailDevice.objects.create(
        user=email_user,
        email=email_user.email,
        stage=original_device.stage,
        confirmed=True,
    )
    email_user.save(update_fields=["email"])
    login(email_user)
    email_user.email = "unproved-" + original_email
    email_user.save(update_fields=["email"])
    login(email_user, verify_address=True)
    before = EmailDevice.objects.filter(user=email_user).count()
    email_user.email = original_email
    email_user.save(update_fields=["email"])
    login(email_user)
    assert EmailDevice.objects.filter(user=email_user).count() == before
    print("ADDRESS_CHANGE_REUSES_AND_RETAINS_FACTORS_OK")
    recover(passkey_user)
    login(passkey_user, key)
    print("ESTABLISHED_PASSKEY_PRESERVED_OK")
    for rejected in ["wrong-code", "expired-code"]:
        enroll("email", stop=rejected)
    for stop in ["reservation", "email", "passkey"]:
        user, key = enroll("passkey" if stop == "passkey" else "email", stop=stop)
        recover(user)
        if key:
            browser = Browser("default-authentication-flow")
            browser.request()
            browser.request(
                {
                    "component": "ak-stage-identification",
                    "passkey": key.assertion(browser.challenge["passkey_challenge"]),
                },
                allow_errors=True,
            )
            browser.no_session()
            assert browser.challenge.get("response_errors"), (
                "pre-verification passkey survived mailbox recovery"
            )
        print("INTERRUPTED_ENROLLMENT_RECOVERED", stop)
    for interrupt in ["disabled", "address-changed"]:
        user, _ = enroll("email", stop="reservation")
        recover(user, interrupt=interrupt)
