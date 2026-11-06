import { test } from "node:test";
import assert from "node:assert/strict";
import { readFile, readdir } from "node:fs/promises";
import path from "node:path";
import { LuaFactory } from "wasmoon";

import {
  SECTIONS,
  activeSection,
  sectionPercentages,
  snapRemainingSeconds,
} from "./reference/timer.ts";

const sourceFiles = [
  "app.lua",
  "timer.lua",
  "health_probe.lua",
  "detector.lua",
  "encounter.lua",
  "build.lua",
];
const runtimeFiles = ["main.lua", ...sourceFiles.map((file) => `src/${file}`)];

async function createLua() {
  const factory = new LuaFactory();
  for (const file of runtimeFiles) {
    await factory.mountFile(file, await readFile(path.resolve(file), "utf8"));
  }
  const lua = await factory.createEngine();
  await lua.doString('assert(_VERSION == "Lua 5.4"); package.path = "./?.lua;" .. package.path');
  return lua;
}

for (const file of [
  "timer_test.lua",
  "health_probe_test.lua",
  "detector_test.lua",
  "encounter_test.lua",
  "main_test.lua",
]) {
  test(`native Lua: ${file}`, async (t) => {
    const lua = await createLua();
    t.after(() => lua.global.close());
    await lua.doString(await readFile(path.join("tests", file), "utf8"));
  });
}

test("default timer matches the frozen Alt1 reference throughout the countdown and at boundaries", async (t) => {
  const lua = await createLua();
  t.after(() => lua.global.close());
  const values = [-5, 0, 30];
  for (let i = 0; i <= 2500; i++) values.push(i / 100);
  for (let i = 0; i <= 240; i++) {
    for (const epsilon of [-1e-10, 0, 1e-10]) values.push(i / 10 + epsilon);
  }
  const rows = values.map((value) => {
    const snapped = snapRemainingSeconds(value);
    const section = SECTIONS.indexOf(activeSection(value)) + 1;
    return `{${[value, snapped, section, ...sectionPercentages(snapped)].join(",")}}`;
  });

  await lua.doString(`
    local Timer = require("src/timer")
    for _, row in ipairs({${rows.join(",")}}) do
      local snapped = Timer.snapRemainingSeconds(row[1])
      assert(math.abs(snapped - row[2]) < 1e-9, "snap mismatch at " .. row[1])
      assert(Timer.activeSection(row[1]) == Timer.sections[row[3]], "section mismatch at " .. row[1])
      for i, value in ipairs(Timer.sectionPercentages(snapped)) do
        assert(math.abs(value - row[i + 3]) < 1e-9, "fill mismatch at " .. row[1])
      end
    end
  `);
});

test("standalone runtime declares VoragoSync, PrettyUI and settings without extra permissions", async (t) => {
  const files = await readdir(".");
  assert.deepEqual(
    files.filter((file) => file.endsWith(".lua")),
    ["main.lua"],
  );
  const sources = await readdir("src", { recursive: true });
  assert.deepEqual(sources.filter((file) => file.endsWith(".lua")).sort(), [...sourceFiles].sort());
  const manifest = JSON.parse(await readFile("plugin.json", "utf8"));
  assert.deepEqual(manifest, {
    name: "VoragoSync",
    version: "0.1.0",
    hasSettingsIcon: true,
    requiredDependencies: { prettyui: 6398181 },
    optionalDependencies: {},
    requiredPermissions: [],
    optionalPermissions: [],
  });
  for (const file of runtimeFiles) {
    assert.doesNotMatch(await readFile(path.resolve(file), "utf8"), /voragotag/i);
  }
  const lua = await createLua();
  t.after(() => lua.global.close());
  assert.equal(await lua.doString("return require('src/build').isDevBuild"), true);
});
