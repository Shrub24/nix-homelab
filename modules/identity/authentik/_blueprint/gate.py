"""Run inside the pinned Authentik management environment."""

import os
import sys
import time
from hashlib import sha512
from pathlib import Path

from authentik.blueprints.models import BlueprintInstance, BlueprintInstanceStatus
from authentik.blueprints.v1.importer import Importer
from authentik.blueprints.v1.labels import LABEL_AUTHENTIK_INSTANTIATE
from authentik.blueprints.v1.tasks import (
    apply_blueprint,
    blueprints_discovery,
    blueprints_find,
)
from django.utils.timezone import now


def run():
    path = os.environ["AUTHENTIK_BLUEPRINT_PATH"]
    content = Path(path).read_text()
    expected = sha512(content.encode()).hexdigest()
    relative = Path(path).name
    deadline = time.monotonic() + int(
        os.environ.get("AUTHENTIK_BLUEPRINT_TIMEOUT", "300")
    )

    def wait_for(probe):
        while time.monotonic() < deadline:
            result = probe()
            if result:
                return result
            time.sleep(1)
        raise TimeoutError("blueprint deadline exceeded")

    defaults = [
        blueprint
        for blueprint in blueprints_find()
        if blueprint.path.startswith(("default/", "system/"))
        and not (
            blueprint.meta
            and blueprint.meta.labels.get(LABEL_AUTHENTIK_INSTANTIATE, "").lower()
            == "false"
        )
    ]
    blueprints_discovery.send()
    print("authentik-blueprint: waiting for upstream prerequisites", flush=True)

    def prerequisites():
        for blueprint in defaults:
            instance = BlueprintInstance.objects.filter(
                path=blueprint.path, enabled=True
            ).first()
            if instance is None or instance.last_applied_hash != blueprint.hash:
                return False
        return BlueprintInstance.objects.filter(path=relative, enabled=True).first()

    instance = wait_for(prerequisites)
    print("authentik-blueprint: validating shipped document", flush=True)
    valid, _logs = Importer.from_string(content, instance.context).validate()
    if not valid:
        raise ValueError("blueprint importer rejected document")

    requested_at = now()
    apply_blueprint.send_with_options(args=(instance.pk,), rel_obj=instance)
    print("authentik-blueprint: waiting for current application", flush=True)

    def applied():
        instance.refresh_from_db()
        if instance.last_applied >= requested_at:
            if (
                instance.status == BlueprintInstanceStatus.SUCCESSFUL
                and instance.last_applied_hash == expected
            ):
                return True
            if instance.status == BlueprintInstanceStatus.ERROR:
                raise ValueError("blueprint application failed")
        return False

    wait_for(applied)
    print("authentik-blueprint: current document successfully applied", flush=True)


try:
    run()
except Exception as error:
    # Serializer errors may contain resolved credentials; never print their payloads.
    print(
        f"authentik-blueprint: validation/application failed ({type(error).__name__})",
        file=sys.stderr,
    )
    sys.exit(1)
