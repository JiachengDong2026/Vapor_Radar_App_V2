"""Freeze build inputs and reject a build whose inputs changed while running."""
import argparse
import hashlib
import json
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TEST = ROOT.parent


def inputs():
    directories = [ROOT / "rtl", ROOT / "constraints", ROOT / "scripts"]
    paths = {p for directory in directories for p in directory.rglob("*")
             if p.is_file() and p.suffix.lower() in {".v", ".vh", ".mem", ".xdc", ".tcl", ".py"}}
    return {p.relative_to(TEST).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest()
            for p in sorted(paths)}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("mode", choices=["capture", "verify", "seal-synthesis", "verify-synthesis"])
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    output = args.output.resolve()
    if output.is_relative_to(ROOT):
        raise SystemExit("Build evidence must be outside source tree")
    output.mkdir(parents=True, exist_ok=True)
    snapshot = inputs()
    target = output / ("synth_inputs.json" if args.mode == "verify-synthesis" else "build_inputs.json")
    if args.mode == "capture":
        target.write_text(json.dumps({"utc": datetime.now(timezone.utc).isoformat(),
                                     "files": snapshot}, indent=2), encoding="utf-8")
        print(f"BUILD_INPUTS_CAPTURED count={len(snapshot)}")
        return
    before = json.loads(target.read_text(encoding="utf-8"))["files"]
    if args.mode in {"seal-synthesis", "verify-synthesis"}:
        def consumed(name):
            return Path(name).suffix in {".v", ".vh", ".mem"} or name in {
                "fpga/constraints/system/clocks.xdc", "fpga/constraints/system/board_pins.xdc",
                "fpga/scripts/full_sources.tcl"}
        before = {k: v for k, v in before.items() if consumed(k)}
        snapshot = {k: v for k, v in snapshot.items() if consumed(k)}
    differences = [name for name in sorted(before.keys() | snapshot.keys())
                   if before.get(name) != snapshot.get(name)]
    result = {"pass": not differences, "input_count": len(snapshot),
              "changed_inputs": differences, "utc": datetime.now(timezone.utc).isoformat()}
    result_name = "synthesis_input_verification.json" if args.mode.endswith("synthesis") else "build_input_verification.json"
    (output / result_name).write_text(json.dumps(result, indent=2), encoding="utf-8")
    if differences:
        raise SystemExit("BUILD_INPUTS_CHANGED: " + ", ".join(differences))
    if args.mode == "seal-synthesis":
        (output / "synth_inputs.json").write_text(json.dumps({"files": snapshot,
            "checkpoint_sha256": hashlib.sha256((output / "synth.dcp").read_bytes()).hexdigest()}, indent=2), encoding="utf-8")
    if args.mode == "verify-synthesis":
        expected = json.loads(target.read_text(encoding="utf-8"))["checkpoint_sha256"]
        if hashlib.sha256((output / "synth.dcp").read_bytes()).hexdigest() != expected:
            raise SystemExit("SYNTH_CHECKPOINT_CHANGED")
    print(f"BUILD_INPUTS_UNCHANGED count={len(snapshot)}")


if __name__ == "__main__":
    main()
