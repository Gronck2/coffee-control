#!/usr/bin/env python3
"""Writes Metadata.appintents for a bundle without Xcode.

Xcode builds this index with the closed `appintentsmetadataprocessor`, which the
Command Line Tools do not ship. Its input is the compiler's `.swiftconstvalues`
JSON, so this script builds the index from it directly.

The format copies Xcode 26 output found on macOS 26 itself, mainly
`DisplayControls.appex` (`SetDarkModeEnabledIntent`, a SetValueIntent<Bool> used by
a Control Center toggle) and the xtool packer (github.com/xtool-org/xtool PR 397).

Scope is deliberately narrow: AppIntents with static literal title/description/
openAppWhenRun/isDiscoverable, Bool or String @Parameters, the SetValueIntent
system protocol and an IntentResult perform result. Anything else fails loudly
instead of producing a wrong index.

usage: gen_appintents_metadata.py <out Resources dir> <file.swiftconstvalues>...
"""
import json
import os
import sys

TOOLS_VERSION = "17E6107"  # Xcode build that produced macOS 26.5's own indexes

SYSTEM_PROTOCOLS = {
    "AppIntents.SetValueIntent": "com.apple.link.systemProtocol.SetValue",
    "AppIntents.LiveActivityIntent": "com.apple.link.systemProtocol.SessionStarting",
    "AppIntents.AudioRecordingIntent": "com.apple.link.systemProtocol.AudioRecording",
}
PLAIN_CONFORMANCES = {
    "AppIntents.AppIntent", "AppIntents.SystemIntent", "AppIntents.PersistentlyIdentifiable",
    "AppIntents._SupportsAppDependencies", "Swift.Sendable", "Swift.SendableMetatype",
}
OUTPUT_FLAGS = {"AppIntents.IntentResult": 0, "AppIntents.ProvidesDialog": 4}
# LNValueType primitive type identifiers seen in Xcode output.
PRIMITIVE_TYPES = {"Swift.Bool": 1, "Swift.String": 0}
STATIC_KEYS = {"title", "description", "openAppWhenRun", "isDiscoverable"}
AVAILABILITY = {"LNPlatformNameWildcard": {"introducedVersion": "*"}}


class Unsupported(Exception):
    pass


def localized(key):
    return {"alternatives": [], "key": key}


def literal(prop, name):
    kind = prop.get("valueKind")
    if kind == "RawLiteral":
        return prop["value"]
    if kind == "NilLiteral":
        return None
    raise Unsupported(f"{name} is not a literal ({kind})")


def parameter(prop, intent):
    """@Parameter var x: T -> parameter entry, from the `_x` storage property."""
    value = prop.get("value") or {}
    ptype = prop.get("type", "")
    if not ptype.startswith("AppIntents.IntentParameter<") or prop.get("valueKind") != "InitCall":
        raise Unsupported(f"{intent}.{prop['label']}: unsupported parameter {ptype}")
    inner = ptype[len("AppIntents.IntentParameter<"):-1]
    optional = inner.startswith("Swift.Optional<")
    if optional:
        inner = inner[len("Swift.Optional<"):-1]
    if inner not in PRIMITIVE_TYPES:
        raise Unsupported(f"{intent}.{prop['label']}: parameter type {inner}")
    args = {a["label"]: a for a in value.get("arguments", [])}
    title = literal(args["title"], f"{intent}.{prop['label']}.title") if "title" in args else None
    if title is None:
        raise Unsupported(f"{intent}.{prop['label']}: parameter without literal title")
    for label in ("description", "default", "displayName", "requestValueDialog"):
        if label in args and args[label].get("valueKind") != "NilLiteral":
            raise Unsupported(f"{intent}.{prop['label']}: parameter {label} is not supported")
    value_type = {"primitive": {"wrapper": {"typeIdentifier": PRIMITIVE_TYPES[inner]}}}
    return {
        "capabilities": 0,
        "dynamicOptionsSupport": 0,
        "inputConnectionBehavior": 0,
        "isInput": False,
        "isOptional": optional,
        "name": prop["label"][1:],
        "resolvableInputTypes": [{"kindValue": 0, "valueType": value_type}],
        "title": localized(title),
        "typeSpecificMetadata": [],
        "valueType": value_type,
    }


def action(entry):
    name = entry["typeName"]
    identifier = name.split(".")[-1]
    conformances = entry.get("conformances", [])

    protocols = []
    for c in conformances:
        if c in SYSTEM_PROTOCOLS:
            protocols.append(SYSTEM_PROTOCOLS[c])
        elif c not in PLAIN_CONFORMANCES:
            raise Unsupported(f"{name} conforms to {c}")

    statics, params = {}, []
    for prop in entry.get("properties", []):
        label = prop["label"]
        if prop.get("isStatic") == "true":
            if label not in STATIC_KEYS:
                raise Unsupported(f"{name}.{label}: unsupported static property")
            statics[label] = literal(prop, f"{name}.{label}")
        elif label.startswith("_") and "IntentParameter<" in prop.get("type", ""):
            params.append(parameter(prop, name))
        elif label.startswith("$") or prop.get("propertyWrappers"):
            continue  # projected value / wrapped accessor of a parameter
        else:
            raise Unsupported(f"{name}.{label}: unsupported stored property")

    if statics.get("title") is None:
        raise Unsupported(f"{name} has no literal title")

    flags = 0
    for alias in entry.get("associatedTypeAliases", []):
        if alias.get("typeAliasName") != "PerformResult":
            continue
        for req in alias.get("opaqueTypeProtocolRequirements", []):
            if req not in OUTPUT_FLAGS:
                raise Unsupported(f"{name} returns {req}")
            flags |= OUTPUT_FLAGS[req]

    opens_app = statics.get("openAppWhenRun") == "true"
    discoverable = statics.get("isDiscoverable") != "false"
    protocol_metadata = [x for p in protocols for x in (p, {"empty": {}})]
    mangled = entry["mangledTypeName"]
    result = {
        "assistantDefinedSchemaTraits": [],
        "assistantDefinedSchemas": [],
        "authenticationPolicy": 0,
        "availabilityAnnotations": AVAILABILITY,
        "effectiveBundleIdentifiers": [],
        "fullyQualifiedTypeName": name,
        "identifier": identifier,
        "isAuthPolExplicit": False,
        "isDiscoverable": discoverable,
        "mangledTypeName": mangled,
        "mangledTypeNameByBundleIdentifier": {},
        "mangledTypeNameByBundleIdentifierV2": {},
        "mangledTypeNameV2": mangled,
        "openAppWhenRun": opens_app,
        "outputFlags": flags,
        "parameters": params,
        "presentationStyle": 0,
        "requiredCapabilities": [],
        # 1: runs in the background; 2: opens the app first (as Xcode writes it)
        "supportedModes": 2 if opens_app else 1,
        "systemProtocolMetadata": protocol_metadata,
        "systemProtocolMetadataV2": protocol_metadata,
        "systemProtocols": protocols,
        "title": localized(statics["title"]),
        "typeSpecificMetadata": [],
        "visibilityMetadata": {"assistantOnly": False, "isDiscoverable": discoverable},
    }
    if statics.get("description") is not None:
        result["descriptionMetadata"] = {
            "descriptionText": localized(statics["description"]),
            "searchKeywords": [],
        }
    return identifier, result


def main(argv):
    if len(argv) < 3:
        sys.exit(__doc__)
    out_dir, inputs = argv[1], argv[2:]
    actions = {}
    for path in inputs:
        with open(path) as f:
            for entry in json.load(f):
                conformances = entry.get("conformances", [])
                if "AppIntents.AppIntent" in conformances:
                    ident, act = action(entry)
                    actions[ident] = act
                elif any(c.startswith("AppIntents.") for c in conformances):
                    raise Unsupported(f"{entry['typeName']} conforms to {conformances}")
    if not actions:
        print("no App Intents, no index written")
        return
    index = {
        "actions": actions,
        "assistantEntities": [],
        "assistantIntentNegativePhrases": [],
        "assistantIntents": [],
        "autoShortcuts": [],
        "entities": {},
        "enums": [],
        "generator": {"name": "xcode-tools", "version": TOOLS_VERSION},
        "negativePhrases": [],
        "queries": {},
        "shortcutTileColor": 14,
        "version": 1,
    }
    meta_dir = os.path.join(out_dir, "Metadata.appintents")
    os.makedirs(meta_dir, exist_ok=True)
    with open(os.path.join(meta_dir, "extract.actionsdata"), "w") as f:
        json.dump(index, f, sort_keys=True, separators=(",", ":"))
    with open(os.path.join(meta_dir, "version.json"), "w") as f:
        f.write('{\n  "toolsVersion" : "%s",\n  "version" : "3.0"\n}' % TOOLS_VERSION)
    print(f"{meta_dir}: {', '.join(sorted(actions))}")


if __name__ == "__main__":
    try:
        main(sys.argv)
    except Unsupported as e:
        sys.exit(f"gen_appintents_metadata: unsupported: {e}")
