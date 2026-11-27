#!/usr/bin/env python3
"""Run Xcode's App Intents metadata and phrase tooling for the SwiftPM app."""

import argparse
import json
from pathlib import Path
import plistlib
import shlex
import subprocess
import tempfile


def run(*arguments):
    subprocess.run([str(argument) for argument in arguments], check=True)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--build-products", type=Path, required=True)
    parser.add_argument("--resources", type=Path, required=True)
    parser.add_argument("--info-plist", type=Path, required=True)
    parser.add_argument("--sdk", type=Path, required=True)
    arguments = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    products = arguments.build_products.resolve()
    toolchain = Path(subprocess.check_output(["xcrun", "--find", "swiftc"], text=True).strip()).parents[2]
    toolchain_protocols = toolchain / "usr/share/swift/SwiftConstantValues/AppIntents.json"
    metadata = arguments.resources / "Metadata.appintents"
    info = plistlib.loads(arguments.info_plist.read_bytes())
    deployment = info["LSMinimumSystemVersion"]
    xcode_version = subprocess.check_output(["xcodebuild", "-version"], text=True).split("Build version ", 1)[1].strip()

    with tempfile.TemporaryDirectory(prefix="nexora-intents-") as temporary_path:
        temporary = Path(temporary_path)
        source_list = temporary / "sources.txt"
        constant_list = temporary / "constants.txt"
        description = products / "description.json"
        if description.exists():
            # Native SwiftPM does not run Xcode's constant-value extraction.
            # Reuse its exact source list and dependency/compiler arguments in a
            # typecheck-only pass; this never builds or launches another app.
            commands = json.loads(description.read_text())["swiftCommands"].values()
            command = next(item for item in commands if item.get("moduleName") == "ClashGlass")
            sources = command["sources"]
            protocols = json.loads(toolchain_protocols.read_text())
            if isinstance(protocols, dict):
                protocols = protocols["constValueProtocols"]
            protocol_file = temporary / "protocols.json"
            protocol_file.write_text(json.dumps(protocols))
            constant_file = temporary / "ClashGlass.swiftconstvalues"
            # Keep semantic/import flags and paired Clang/frontend arguments;
            # object compilation and diagnostics outputs are irrelevant here.
            compiler_arguments = []
            options = iter(command["otherArguments"])
            for option in options:
                if option in ("-Xcc", "-Xfrontend"):
                    compiler_arguments.extend((option, next(options)))
                elif option in ("-num-threads", "-j"):
                    next(options)
                elif option not in ("-parseable-output", "-whole-module-optimization",
                                    "-serialize-diagnostics", "-O", "-Onone", "-Osize", "-g") and not option.startswith("-j"):
                    compiler_arguments.append(option)
            # Ask the driver for a single whole-module frontend invocation so
            # SDK macro/plugin paths stay correct. Calling the driver directly
            # either overwrites the same sidecar for each primary file or
            # discards it with its temporary supplementary-output map.
            plan = subprocess.check_output([
                command["executable"], "-###", "-typecheck", "-whole-module-optimization",
                "-parse-as-library", "-module-name", "ClashGlass", "-I", command["importPath"],
                *compiler_arguments, *sources,
            ], text=True)
            frontend_commands = [shlex.split(line) for line in plan.splitlines() if line.strip()]
            if len(frontend_commands) != 1 or "-frontend" not in frontend_commands[0]:
                raise RuntimeError("Unexpected Swift frontend plan for App Intents extraction")
            frontend_arguments = []
            options = iter(frontend_commands[0])
            for option in options:
                if option == "-supplementary-output-file-map":
                    next(options)
                else:
                    frontend_arguments.append(option)
            run(*frontend_arguments, "-emit-const-values-path", constant_file,
                "-const-gather-protocols-file", protocol_file)
            if not constant_file.is_file():
                raise RuntimeError("The Swift compiler did not emit App Intents constants")
            source_list.write_text("\n".join(sources) + "\n")
            constant_list.write_text(str(constant_file) + "\n")
            target = compiler_arguments[compiler_arguments.index("-target") + 1]
        else:
            # Xcode's SwiftPM backend already emits a sidecar per source file.
            configuration = products.name
            intermediates = root / ".build/out/Intermediates.noindex"
            candidates = list(intermediates.glob(f"*/{configuration}/Nexora-p.build/Objects-normal/*/Nexora.SwiftFileList"))
            if len(candidates) != 1:
                raise RuntimeError("Cannot locate the app's SwiftPM App Intents compiler outputs")
            source_file = candidates[0]
            source_list.write_bytes(source_file.read_bytes())
            constants = sorted(source_file.parent.glob("*.swiftconstvalues"))
            if not constants:
                raise RuntimeError("The SwiftPM app has no App Intents constant-value outputs")
            constant_list.write_text("\n".join(str(path) for path in constants) + "\n")
            target = f"{source_file.parent.name}-apple-macosx{deployment}"

        run("xcrun", "appintentsmetadataprocessor", "--output", arguments.resources,
            "--toolchain-dir", toolchain, "--module-name", "ClashGlass",
            "--sdk-root", arguments.sdk, "--xcode-version", xcode_version,
            "--platform-family", "macOS", "--deployment-target", deployment,
            "--target-triple", target, "--source-file-list", source_list,
            "--swift-const-vals-list", constant_list)
        actions = json.loads((metadata / "extract.actionsdata").read_text())
        if not actions.get("actions") or not actions.get("autoShortcuts"):
            raise RuntimeError("App Intents extraction produced no actions or App Shortcuts")
        run("xcrun", "appintentsnltrainingprocessor", "--infoplist-path", arguments.info_plist,
            "--temp-dir-path", temporary / "phrases", "--bundle-id", info["CFBundleIdentifier"],
            "--product-path", arguments.resources, "--extracted-metadata-path", metadata,
            "--archive-ssu-assets",
            *(item for path in sorted(arguments.resources.glob("*.lproj/AppShortcuts.strings"))
              for item in ("--source-file", path)))
        localized_phrases = sorted(arguments.resources.glob("*.lproj/AppShortcuts.strings"))
        archives = [path.parent / "nlu.appintents/nlu.lzfse" for path in localized_phrases]
        if not archives:
            archives = [metadata / "nlu/nlu.lzfse"]
        if not (metadata / "root.ssu.yaml").is_file() or not all(path.is_file() for path in archives):
            raise RuntimeError("App Shortcuts phrase training did not produce its required assets")


if __name__ == "__main__":
    main()
