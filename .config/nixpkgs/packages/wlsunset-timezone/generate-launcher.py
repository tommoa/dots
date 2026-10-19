"""Bake timezone coordinates into a wlsunset launcher during its build."""

import argparse
import math
from pathlib import Path
import re
import shlex


def decimal_coordinate(encoded, degree_digits):
    if not re.fullmatch(r"[+-]\d{%d}(?:\d{2})?" % (degree_digits + 2), encoded):
        raise ValueError(f"Invalid zone.tab coordinate: {encoded}")
    degrees = int(encoded[1 : 1 + degree_digits])
    minutes = int(encoded[1 + degree_digits : 3 + degree_digits])
    seconds = int(encoded[3 + degree_digits :] or "0")
    if minutes >= 60 or seconds >= 60:
        raise ValueError(f"Invalid zone.tab coordinate: {encoded}")
    magnitude = degrees + minutes / 60 + seconds / 3600
    rounded = math.floor(magnitude * 10 + 0.5) / 10
    return -rounded if encoded[0] == "-" else rounded


def location_args(zone_tab, timezone):
    if timezone is None:
        return ["-S", "06:00", "-s", "19:00"]
    for line in zone_tab.read_text().splitlines():
        if not line or line.startswith("#"):
            continue
        fields = line.split("\t")
        if len(fields) < 3 or fields[2] != timezone:
            continue
        coordinates = re.fullmatch(r"([+-]\d+)([+-]\d+)", fields[1])
        if coordinates is None:
            raise ValueError(f"Invalid zone.tab coordinates for timezone {timezone}")
        latitude = decimal_coordinate(coordinates[1], 2)
        longitude = decimal_coordinate(coordinates[2], 3)
        if abs(latitude) > 90 or abs(longitude) > 180:
            raise ValueError(f"Out-of-range zone.tab coordinates for timezone {timezone}")
        return ["-l", f"{latitude:.1f}", "-L", f"{longitude:.1f}"]
    raise ValueError(f"No representative coordinates found in tzdata for timezone {timezone}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--zone-tab", type=Path)
    parser.add_argument("--timezone")
    parser.add_argument("--shell", required=True)
    parser.add_argument("--wlsunset", required=True)
    args = parser.parse_args()
    if args.timezone is not None and args.zone_tab is None:
        parser.error("--timezone requires --zone-tab")
    try:
        command = [args.wlsunset, *location_args(args.zone_tab, args.timezone)]
    except ValueError as error:
        parser.error(str(error))
    print(f"#!{args.shell}")
    print(f'exec {shlex.join(command)} "$@"')


if __name__ == "__main__":
    main()
