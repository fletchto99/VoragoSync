import { createHash } from "node:crypto";
import { mkdir, readFile, readdir, writeFile } from "node:fs/promises";
import path from "node:path";
import { pathToFileURL } from "node:url";
import { zipSync } from "fflate";

export async function buildRelease(
  tag: string | undefined,
  root = process.cwd(),
  outputDirectory = path.join(root, "dist"),
) {
  if (!tag || tag !== tag.trim() || !/^v(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$/.test(tag)) {
    throw new Error("Release tag must be vX.Y.Z, without leading zeroes or prerelease suffixes.");
  }
  const version = tag.slice(1);
  const [manifest, metadata, lock] = await Promise.all(
    ["plugin.json", "package.json", "package-lock.json"].map(async (file) =>
      JSON.parse(await readFile(path.join(root, file), "utf8")),
    ),
  );
  for (const [file, declaredVersion] of [
    ["plugin.json", manifest.version],
    ["package.json", metadata.version],
    ["package-lock.json", lock.version],
    ["package-lock.json root package", lock.packages?.[""]?.version],
  ]) {
    if (declaredVersion !== version) {
      throw new Error(`${file} version must match ${tag} (${version}).`);
    }
  }

  const files = ["main.lua", "plugin.json", "LICENSE", "README.md"];
  for (const [directory, extension] of [
    ["src", ".lua"],
    ["docs", ".md"],
  ]) {
    for (const entry of await readdir(path.join(root, directory), {
      recursive: true,
      withFileTypes: true,
    })) {
      if (entry.isDirectory()) continue;
      if (!entry.isFile()) throw new Error(`Unsupported release entry: ${directory}/${entry.name}`);
      if (entry.name.endsWith(extension)) {
        files.push(path.relative(root, path.join(entry.parentPath, entry.name)));
      }
    }
  }
  const contents: Record<string, Uint8Array> = {};
  for (const file of files.sort()) {
    contents[file.split(path.sep).join("/")] = await readFile(path.join(root, file));
  }
  if (!contents["src/build.lua"]) throw new Error("Missing runtime build flag: src/build.lua");
  contents["src/build.lua"] = Buffer.from(
    "-- Release build: debug controls are disabled.\nreturn { isDevBuild = false }\n",
  );

  // ZIP timestamps are local wall-clock values; fix them for reproducible archives.
  const archive = zipSync(contents, { level: 9, mtime: new Date(1980, 0, 1) });
  const archiveName = `voragosync-${tag}.zip`;
  const digest = createHash("sha256").update(archive).digest("hex");
  await mkdir(outputDirectory, { recursive: true });
  await writeFile(path.join(outputDirectory, archiveName), archive);
  await writeFile(path.join(outputDirectory, "SHA256SUMS"), `${digest}  ${archiveName}\n`);
  return path.join(outputDirectory, archiveName);
}

if (process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href) {
  console.log(await buildRelease(process.argv[2]));
}
