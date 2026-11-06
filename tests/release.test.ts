import { test, type TestContext } from "node:test";
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { cp, mkdtemp, readFile, readdir, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { unzipSync } from "fflate";
import { buildRelease } from "../scripts/build-release.ts";

const metadata = JSON.parse(await readFile("package.json", "utf8"));
const tag = `v${metadata.version}`;

async function temporaryDirectory(t: TestContext) {
  const directory = await mkdtemp(path.join(tmpdir(), "voragosync-release-"));
  t.after(() => rm(directory, { recursive: true, force: true }));
  return directory;
}

async function fixture(t: TestContext) {
  const root = await temporaryDirectory(t);
  await Promise.all(
    [
      "main.lua",
      "plugin.json",
      "package.json",
      "package-lock.json",
      "LICENSE",
      "README.md",
      "src",
      "docs",
    ].map((file) => cp(file, path.join(root, file), { recursive: true })),
  );
  return root;
}

test("release ZIP contains runtime, documentation and notices, with debug disabled", async (t) => {
  const output = await temporaryDirectory(t);
  const archivePath = await buildRelease(tag, process.cwd(), output);
  assert.equal(path.basename(archivePath), `voragosync-${tag}.zip`);
  const archive = await readFile(archivePath);
  const files = unzipSync(archive);
  const runtimeFiles = (await readdir("src", { recursive: true }))
    .filter((file) => file.endsWith(".lua"))
    .map((file) => `src/${file.split(path.sep).join("/")}`);
  const documentationFiles = (await readdir("docs", { recursive: true }))
    .filter((file) => file.endsWith(".md"))
    .map((file) => `docs/${file.split(path.sep).join("/")}`);
  assert.deepEqual(
    Object.keys(files).sort(),
    [
      "main.lua",
      "plugin.json",
      "LICENSE",
      "README.md",
      ...runtimeFiles,
      ...documentationFiles,
    ].sort(),
  );
  for (const [file, contents] of Object.entries(files)) {
    if (file === "src/build.lua") {
      assert.match(Buffer.from(contents).toString("utf8"), /return \{ isDevBuild = false \}/);
    } else {
      assert.deepEqual(Buffer.from(contents), await readFile(file), `${file} must be unchanged`);
    }
  }
  for (const file of ["README.md", ...documentationFiles]) {
    const markdown = Buffer.from(files[file]).toString("utf8");
    for (const [, href] of markdown.matchAll(/\[[^\]]*\]\(([^)]+)\)/g)) {
      if (/^(?:https?:|mailto:|#)/i.test(href)) continue;
      const target = path.posix.normalize(
        path.posix.join(path.posix.dirname(file), href.split("#")[0]),
      );
      assert.ok(Object.hasOwn(files, target), `${file} links to missing release document: ${href}`);
    }
  }
  assert.match(await readFile(path.join("src", "build.lua"), "utf8"), /isDevBuild = true/);
  assert.equal(
    await readFile(path.join(output, "SHA256SUMS"), "utf8"),
    `${createHash("sha256").update(archive).digest("hex")}  voragosync-${tag}.zip\n`,
  );
  await buildRelease(tag, process.cwd(), output);
  assert.deepEqual(await readFile(archivePath), archive, "ZIP must be reproducible");
});

test("release tags must be stable, canonical versions", async () => {
  for (const invalid of [
    undefined,
    "",
    "0.1.0",
    "v1",
    "v1.2",
    "v01.2.3",
    "v1.02.3",
    "v1.2.03",
    "v1.2.3-beta.1",
    "v1.2.3+build",
    "v1.2.3\n",
    "v1.2.3/../../other",
  ]) {
    await assert.rejects(buildRelease(invalid), /Release tag must be vX.Y.Z/);
  }
});

for (const file of ["plugin.json", "package.json", "package-lock.json", "lock root package"]) {
  test(`rejects a version mismatch in ${file}`, async (t) => {
    const root = await fixture(t);
    const filename = path.join(root, file === "lock root package" ? "package-lock.json" : file);
    const json = JSON.parse(await readFile(filename, "utf8"));
    if (file === "lock root package") json.packages[""].version = "mismatch";
    else json.version = "mismatch";
    await writeFile(filename, JSON.stringify(json));
    await assert.rejects(buildRelease(tag, root), /version must match/);
    await assert.rejects(readdir(path.join(root, "dist")), { code: "ENOENT" });
  });
}

test("refuses to fabricate a missing runtime build flag", async (t) => {
  const root = await fixture(t);
  await rm(path.join(root, "src", "build.lua"));
  await assert.rejects(buildRelease(tag, root), /Missing runtime build flag/);
});
