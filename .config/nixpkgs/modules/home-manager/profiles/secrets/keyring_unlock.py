"""Unlock the existing GNOME login keyring without starting another daemon."""

from pathlib import Path
import sys

import dbus


SERVICE_PATH = "/org/freedesktop/secrets"
COLLECTION_PATH = SERVICE_PATH + "/collection/login"
INTERNAL_INTERFACE = "org.gnome.keyring.InternalUnsupportedGuiltRiddenInterface"


def unlock(password_file):
    password = Path(password_file).read_bytes()
    if not password:
        raise ValueError("The keyring password file is empty")

    bus = dbus.SessionBus(private=True)
    session = None
    try:
        # Bind every call to the same daemon, including when D-Bus activates it.
        owner = bus.activate_name_owner("org.freedesktop.secrets")
        service = bus.get_object(owner, SERVICE_PATH, introspect=False)
        _, session = dbus.Interface(service, "org.freedesktop.Secret.Service").OpenSession(
            "plain", dbus.String("", variant_level=1), timeout=10
        )
        collection = bus.get_object(owner, COLLECTION_PATH, introspect=False)
        properties = dbus.Interface(collection, dbus.PROPERTIES_IFACE)

        def locked():
            return bool(properties.Get("org.freedesktop.Secret.Collection", "Locked", timeout=10))

        if not locked():
            return

        internal = dbus.Interface(service, INTERNAL_INTERFACE)
        # Older keyrings were encrypted with the secret file's trailing newline.
        # Support both those keyrings and passwords entered normally at login.
        candidates = dict.fromkeys((password.rstrip(b"\r\n"), password))
        for candidate in candidates:
            if not candidate:
                continue
            secret = dbus.Struct(
                (session, dbus.ByteArray(b""), dbus.ByteArray(candidate), "text/plain"),
                signature="oayays",
            )
            try:
                internal.UnlockWithMasterPassword(dbus.ObjectPath(COLLECTION_PATH), secret, timeout=10)
            except dbus.DBusException as error:
                if error.get_dbus_name() != "org.gnome.keyring.Error.Denied":
                    raise
                continue
            if not locked():
                return

        raise RuntimeError("The configured password did not unlock the login keyring")
    finally:
        try:
            if session is not None:
                dbus.Interface(
                    bus.get_object(owner, session, introspect=False),
                    "org.freedesktop.Secret.Session",
                ).Close(timeout=10)
        finally:
            bus.close()


if __name__ == "__main__":
    try:
        unlock(sys.argv[1])
    except dbus.DBusException as error:
        sys.exit(f"Keyring unlock failed: {error.get_dbus_name()}")
    except (OSError, ValueError, RuntimeError) as error:
        sys.exit(f"Keyring unlock failed: {error}")
    print("Login keyring verified unlocked")
