"""Merge desktop preferences and prepare model/client settings for Home Manager."""

import json
import os
from pathlib import Path
import sys
import tempfile


def merge_model_selection(current, managed):
    # Options belong to a provider. Keep unrelated options only when retaining it.
    if not isinstance(current, dict) or current.get("instanceId") != managed["instanceId"]:
        return managed
    managed_ids = {option["id"] for option in managed["options"]}
    options = [
        option for option in current.get("options", [])
        if option["id"] not in managed_ids
    ]
    return {**current, **managed, "options": options + managed["options"]}


def read_document(path):
    document = json.loads(path.read_text(encoding="utf-8")) if path.exists() else {}
    if not isinstance(document, dict):
        raise ValueError(f"{path}: expected a settings object; file left unchanged")
    return document


def merge_model_settings(current, managed):
    updated = {
        **current,
        "defaultModelSelection": merge_model_selection(
            current.get("defaultModelSelection"), managed["defaultModelSelection"]
        ),
    }
    if "customModels" in managed:
        instance_id = managed["defaultModelSelection"]["instanceId"]
        instances = dict(current.get("providerInstances", {}))
        instance = instances.get(instance_id, {})
        existing_config = instance.get("config", {})
        managed_slugs = {model["slug"] for model in managed["customModels"]}
        custom_models = [
            model for model in existing_config.get("customModels", [])
            if (model if isinstance(model, str) else model.get("slug")) not in managed_slugs
        ] + managed["customModels"]
        instances[instance_id] = {
            **instance,
            "config": {**existing_config, "customModels": custom_models},
        }
        updated["providerInstances"] = instances
    return updated


def write_document(path, document):
    # mkstemp creates a private, writable file even when replacing a store link.
    descriptor, temporary = tempfile.mkstemp(dir=path.parent, prefix=f".{path.name}.")
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as stream:
            json.dump(document, stream, indent=2, ensure_ascii=False)
            stream.write("\n")
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def apply_settings(directory, managed):
    settings_path = directory / "settings.json"
    current = read_document(settings_path)
    updates = [(settings_path, current, merge_model_settings(current, managed))]
    if desktop_settings := managed.get("desktopSettings"):
        desktop_path = directory / "desktop-settings.json"
        desktop = read_document(desktop_path)
        updates.append((desktop_path, desktop, {**desktop, **desktop_settings}))
    client_path = directory / "client-settings.json"
    if client_path.exists():
        client = read_document(client_path)
        normalized = client
        # Older clients read only the wrapped settings. Flatten them before
        # Home Manager merges its preferences into the top-level object.
        if "settings" in client:
            if not isinstance(client["settings"], dict):
                raise ValueError(f"{client_path}: expected a settings object; file left unchanged")
            normalized = {**client, **client["settings"]}
            del normalized["settings"]
        updates.append((client_path, client, normalized))
    # Decode every input before writing, so a malformed file prevents all changes.
    directory.mkdir(parents=True, exist_ok=True, mode=0o700)
    for path, current, document in updates:
        if document != current or path.is_symlink() or not path.exists():
            write_document(path, document)


if __name__ == "__main__":
    directory, managed_path = sys.argv[1:]
    try:
        apply_settings(Path(directory), json.loads(Path(managed_path).read_text(encoding="utf-8")))
    except (OSError, ValueError) as error:
        sys.exit(f"t3code settings: {error}")
