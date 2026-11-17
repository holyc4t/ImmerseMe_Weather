#!/usr/bin/env python3
"""Release helper used by the GitHub Actions workflows. Plain Python 3, no dependencies.

  release.py check-title "<title>"
      Exit 1 unless the pull request title starts with an allowed type, e.g. "feat: ...".

  release.py plan --title "<title>" [--number N] [--body-file F]
      Work out the next version from the latest vX.Y.Z tag and the title's type, and write the
      release notes to notes.md. Prints version=... and release=true|false (also to $GITHUB_OUTPUT).
      With no tag yet the version is 1.0.0 and the notes are CHANGELOG.md's "## 1.0.0" section.

  release.py package --version X.Y.Z [--notes notes.md]
      Build dist/<Addon>-vX.Y.Z.zip from the committed files (HEAD), minus everything marked
      export-ignore in .gitattributes. The zip holds one <Addon>/ folder, ready to extract into
      Interface/AddOns. The TOC's "## Version:" is stamped and CHANGELOG.md is rebuilt from the
      notes plus every earlier GitHub release.
"""
import argparse
import datetime
import io
import json
import os
import re
import subprocess
import sys
import tarfile
import zipfile

# Pull request title type -> version bump. Any other allowed type releases nothing.
BUMPS = {"refactor": "major", "feat": "minor", "fix": "patch", "perf": "patch"}
NO_RELEASE = ["docs", "chore", "ci", "test", "build", "style"]
TITLE = re.compile(r"^(?P<type>[a-z]+)(\((?P<scope>[^)]+)\))?: (?P<subject>\S.*)$")
TAG = re.compile(r"^v(\d+)\.(\d+)\.(\d+)$")
INITIAL = "1.0.0"


def git(*args):
	return subprocess.run(["git", *args], check=True, capture_output=True).stdout


def parse_title(title):
	m = TITLE.match(title.strip())
	if not m or m.group("type") not in list(BUMPS) + NO_RELEASE:
		return None
	return m


def latest_tag():
	best = None
	for line in git("tag", "--list", "v*").decode().split():
		m = TAG.match(line)
		if m:
			v = tuple(int(x) for x in m.groups())
			best = v if best is None or v > best else best
	return best


def bump(version, kind):
	major, minor, patch = version
	if kind == "major":
		return (major + 1, 0, 0)
	if kind == "minor":
		return (major, minor + 1, 0)
	return (major, minor, patch + 1)


def changelog_section(version):
	"""The body of '## <version>' in CHANGELOG.md, or ''."""
	try:
		text = open("CHANGELOG.md", encoding="utf-8").read()
	except FileNotFoundError:
		return ""
	m = re.search(r"^## " + re.escape(version) + r"\b.*?\n(.*?)(?=^## |\Z)", text, re.M | re.S)
	return m.group(1).strip() if m else ""


def clean_body(body):
	body = re.sub(r"<!--.*?-->", "", body or "", flags=re.S)
	return body.strip()


def output(**values):
	lines = [f"{k}={v}" for k, v in values.items()]
	print("\n".join(lines))
	if os.environ.get("GITHUB_OUTPUT"):
		with open(os.environ["GITHUB_OUTPUT"], "a", encoding="utf-8") as f:
			f.write("\n".join(lines) + "\n")


def cmd_check_title(args):
	if parse_title(args.title):
		print(f"OK: {args.title}")
		return 0
	print(f"Pull request title not allowed: {args.title!r}")
	print("Start it with one of these types, then a colon and a space:")
	print("  refactor: ...  -> major version (2.0.0)")
	print("  feat: ...      -> minor version (1.1.0)")
	print("  fix: ...       -> patch version (1.0.1)   (perf: too)")
	print("  " + ", ".join(NO_RELEASE) + ": ...  -> no release")
	print("An optional scope is fine: 'fix(tooltip): ...'.")
	return 1


def cmd_plan(args):
	current = latest_tag()
	if current is None:
		version, kind = INITIAL, "initial"
		notes = changelog_section(INITIAL) or "First release."
	else:
		m = parse_title(args.title or "")
		kind = BUMPS.get(m.group("type")) if m else None
		if not kind:
			output(release="false", version="")
			return 0
		version = ".".join(map(str, bump(current, kind)))
		subject = m.group("subject").strip()
		ref = f" (#{args.number})" if args.number else ""
		notes = f"- {subject[0].upper()}{subject[1:]}{ref}"
		body = clean_body(open(args.body_file, encoding="utf-8").read()) if args.body_file else ""
		if body:
			notes += "\n\n" + body
	with open("notes.md", "w", encoding="utf-8", newline="\n") as f:
		f.write(notes + "\n")
	output(release="true", version=version, bump=kind)
	return 0


def previous_releases(skip_tag):
	"""Earlier GitHub releases as changelog sections, newest first. Empty without gh."""
	try:
		listed = json.loads(subprocess.run(
			["gh", "release", "list", "--limit", "200", "--exclude-drafts", "--json", "tagName"],
			check=True, capture_output=True).stdout)
	except (OSError, subprocess.CalledProcessError, ValueError):
		return []
	tags = [r["tagName"] for r in listed if TAG.match(r["tagName"]) and r["tagName"] != skip_tag]
	tags.sort(key=lambda t: tuple(int(x) for x in TAG.match(t).groups()), reverse=True)
	sections = []
	for tag in tags:
		info = json.loads(subprocess.run(
			["gh", "release", "view", tag, "--json", "body,publishedAt"],
			check=True, capture_output=True).stdout)
		date = (info.get("publishedAt") or "")[:10]
		sections.append(f"## {tag[1:]} - {date}\n\n{info.get('body', '').strip()}\n")
	return sections


def cmd_package(args):
	tocs = [n for n in os.listdir(".") if n.endswith(".toc")]
	if len(tocs) != 1:
		sys.exit(f"expected one .toc in the repository root, found {tocs}")
	addon = tocs[0][:-4]
	version = args.version
	notes = open(args.notes, encoding="utf-8").read().strip() if args.notes else ""
	today = datetime.date.today().isoformat()
	changelog = "# Changelog\n\n"
	if notes:
		changelog += f"## {version} - {today}\n\n{notes}\n\n"
	changelog += "\n".join(previous_releases(f"v{version}"))

	tar = tarfile.open(fileobj=io.BytesIO(git("archive", "--format=tar", "HEAD")))
	os.makedirs("dist", exist_ok=True)
	path = os.path.join("dist", f"{addon}-v{version}.zip")
	with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as z:
		for member in tar.getmembers():
			if not member.isfile() or member.name == "CHANGELOG.md":
				continue
			data = tar.extractfile(member).read()
			if member.name == tocs[0]:
				data, n = re.subn(rb"(?m)^## Version:.*$", f"## Version: {version}".encode(), data)
				if n != 1:
					sys.exit("the .toc needs exactly one '## Version:' line")
			z.writestr(f"{addon}/{member.name}", data)
		z.writestr(f"{addon}/CHANGELOG.md", changelog.rstrip() + "\n")
		names = z.namelist()
	print(f"{path}: {len(names)} files")
	output(zip=path)
	return 0


def main():
	p = argparse.ArgumentParser()
	sub = p.add_subparsers(dest="cmd", required=True)
	s = sub.add_parser("check-title")
	s.add_argument("title")
	s = sub.add_parser("plan")
	s.add_argument("--title", default="")
	s.add_argument("--number", default="")
	s.add_argument("--body-file")
	s = sub.add_parser("package")
	s.add_argument("--version", required=True)
	s.add_argument("--notes")
	args = p.parse_args()
	return {"check-title": cmd_check_title, "plan": cmd_plan, "package": cmd_package}[args.cmd](args)


if __name__ == "__main__":
	sys.exit(main())
