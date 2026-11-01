"""Merge Nix-managed preferences into T3 Code's mutable settings files."""

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


def merge_document(path, managed):
    document = json.loads(path.read_text(encoding="utf-8")) if path.exists() else {}
    if not isinstance(document, dict):
        raise ValueError(f"{path}: expected a settings object; file left unchanged")
    # Older desktop clients wrapped their preferences in a settings property.
    wrapped = path.name == "client-settings.json" and "settings" in document
    current = document["settings"] if wrapped else document
    if not isinstance(current, dict):
        raise ValueError(f"{path}: expected a settings object; file left unchanged")
    updated = {**current, **managed}
    if "defaultModelSelection" in managed:
        updated["defaultModelSelection"] = merge_model_selection(
            current.get("defaultModelSelection"), managed["defaultModelSelection"]
        )
    if "providerInstances" in managed:
        instances = dict(current.get("providerInstances", {}))
        for instance_id, preferences in managed["providerInstances"].items():
            instance = instances.get(instance_id, {})
            existing_config = instance.get("config", {})
            provider_config = {**existing_config, **preferences["config"]}
            managed_models = preferences["config"]["customModels"]
            managed_slugs = {model["slug"] for model in managed_models}
            provider_config["customModels"] = [
                model for model in existing_config.get("customModels", [])
                if (model if isinstance(model, str) else model.get("slug")) not in managed_slugs
            ] + managed_models
            instances[instance_id] = {**instance, **preferences, "config": provider_config}
        updated["providerInstances"] = instances
    result = {**document, "settings": updated} if wrapped else updated
    return result, result != document or path.is_symlink() or not path.exists()


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
    # Decode every input before writing, so a malformed file prevents all changes.
    updates = [
        (directory / name, *merge_document(directory / name, preferences))
        for name, preferences in managed.items()
    ]
    directory.mkdir(parents=True, exist_ok=True, mode=0o700)
    for path, document, changed in updates:
        if changed:
            write_document(path, document)


if __name__ == "__main__":
    directory, managed_path = sys.argv[1:]
    try:
        apply_settings(Path(directory), json.loads(Path(managed_path).read_text(encoding="utf-8")))
    except (OSError, ValueError) as error:
        sys.exit(f"t3code settings: {error}")
