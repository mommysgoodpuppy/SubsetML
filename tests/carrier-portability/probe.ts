// Reference semantics, without editing WM's generalization rules.
import { checkFile } from "../../../wm-mini/src/compiler.ts";
const cases: Array<[string, boolean]> = [
  ["shared", true], ["procedure", true], ["partial", false], ["eta", true],
  ["parameter", false], ["copy", true], ["projection", true], ["copy_eta", true],
];
for (const [name, accepted] of cases) {
  const path = new URL(`./${name}.wm`, import.meta.url).pathname;
  let error: unknown;
  let actual = true;
  try { await checkFile(path); } catch (e) { actual = false; error = e; }
  if (actual !== accepted) throw new Error(`${name}: expected accepted=${accepted}: ${error}`);
  console.log(`${name}: WM ${actual ? "accepts" : "rejects"}`);
}
