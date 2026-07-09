#!/usr/bin/env node
"use strict";

// Installs the AnimateIt Agent Skill(s) bundled in this package into a project's
// .claude/skills/ directory. Usage:
//
//   npx animate-it-skills            # install into ./.claude/skills
//   npx animate-it-skills <dir>      # install into <dir>/.claude/skills
//   npx animate-it-skills --help

const fs = require("fs");
const path = require("path");

const args = process.argv.slice(2);
if (args.includes("--help") || args.includes("-h")) {
  console.log(
    [
      "animate-it-skills — install AnimateIt Claude skills into a project",
      "",
      "Usage:",
      "  npx animate-it-skills [target-dir]",
      "",
      "Copies the bundled skill(s) into <target-dir>/.claude/skills/",
      "(defaults to the current directory). Re-running overwrites the",
      "installed copy, so it is safe to run again to update.",
    ].join("\n")
  );
  process.exit(0);
}

const targetRoot = path.resolve(process.cwd(), args[0] || ".");
const srcSkills = path.join(__dirname, "..", "skills");
const destBase = path.join(targetRoot, ".claude", "skills");

if (!fs.existsSync(srcSkills)) {
  console.error(`error: bundled skills directory not found at ${srcSkills}`);
  process.exit(1);
}

const skills = fs
  .readdirSync(srcSkills, { withFileTypes: true })
  .filter((entry) => entry.isDirectory());

if (skills.length === 0) {
  console.error("error: no skills found to install.");
  process.exit(1);
}

fs.mkdirSync(destBase, { recursive: true });

for (const skill of skills) {
  const dest = path.join(destBase, skill.name);
  fs.cpSync(path.join(srcSkills, skill.name), dest, { recursive: true });
  console.log(`✓ ${skill.name} → ${path.relative(process.cwd(), dest) || dest}`);
}

console.log(
  `\nInstalled ${skills.length} skill${skills.length === 1 ? "" : "s"}. ` +
    "Reload skills (or restart Claude Code) to pick them up."
);
