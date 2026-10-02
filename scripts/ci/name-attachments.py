#!/usr/bin/env python3
"""Renomme les pièces jointes exportées d'un .xcresult (noms UUID) d'après leur nom de test.

`xcrun xcresulttool export attachments` écrit les fichiers sous un nom technique et un
manifest.json qui donne, pour chacun, `suggestedHumanReadableName` (« 01-home_0_<UUID>.png »).
On garde le nom donné dans le test (« 01-home.png »).
"""
import json
import os
import re
import sys

folder = sys.argv[1]
manifest_path = os.path.join(folder, "manifest.json")
if not os.path.exists(manifest_path):
    sys.exit(0)

with open(manifest_path, encoding="utf-8") as handle:
    manifest = json.load(handle)


def attachments(node):
    if isinstance(node, dict):
        if "exportedFileName" in node:
            yield node
        for value in node.values():
            yield from attachments(value)
    elif isinstance(node, list):
        for value in node:
            yield from attachments(value)


pattern = re.compile(r"^(.*?)_\d+_[0-9A-Fa-f-]{36}(\.\w+)$")
for item in attachments(manifest):
    exported = os.path.join(folder, item["exportedFileName"])
    suggested = item.get("suggestedHumanReadableName") or item["exportedFileName"]
    match = pattern.match(suggested)
    name = f"{match.group(1)}{match.group(2)}" if match else suggested
    target = os.path.join(folder, name)
    if os.path.exists(exported) and not os.path.exists(target):
        os.rename(exported, target)
