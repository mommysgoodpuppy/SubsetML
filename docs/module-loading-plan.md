# Source module loading

Status: entry-file checking is implemented in both the native and generated Workman compiler.
`check ENTRY.sml` loads explicit comment imports, resolves canonical file identities, and checks
modules in private dependency environments. The compiler and source Basis have these directives.
WM-to-SML source-list translation now reuses this resolver, preserves namespace aliases and
canonical module identity, checks private import environments, and emits SML metadata. Entry-driven
translation discovery and private MLton build artifacts are now implemented for the initial
header namespace WM profile, including explicit canonical native adapter selection. Other
commands, and `check` with multiple files, still use the supplied source list. This work does not
change the SubsetML expression/declaration grammar or imply SML Basis Library support.

```sh
make wm
bin/subsetml check errordemo.sml
wm run src/main.wm -- check src/main.sml
sh tests/module-loading.sh
```

## Workman references and ownership

Use Workman's compilation-unit protocol as the resolution contract, rather than inventing a
smaller resolver with different identity or ordering rules:

- [Module overview](../../wm-mini/docs/modules.md): ownership, import environments, identity,
  graph construction and initialization.
- [Normative module semantics](../../wm-mini/markdown/module-update26.7/proposed-semantics.md):
  resolution, graph, public environments and nominal declaration identity.
- [Settled decisions](../../wm-mini/markdown/module-update26.7/decisions.md): especially D4
  (cycles), D7 (declaration identity), D11–D13 (module environments and identity), D15
  (initialization), and D25 (deferred package/non-local resolution).
- [Current graph/resolver implementation](../../wm-mini/src/module_graph.ts) and
  [ModuleId implementation](../../wm-mini/src/module_id.ts): implementation references, not
  independent definitions of the contract.
- [Module tests](../../wm-mini/tests/module_test.ts),
  [compiler module tests](../../wm-mini/tests/compiler_module_test.ts), and
  [module regression tests](../../wm-mini/tests/module_update_regression_test.ts): existing
  behavior and useful inputs for shared conformance fixtures.

SML owns the meanings of declarations, environments, types and long identifiers. The loading
protocol owns source-file resolution, identity, dependencies and initialization order. Backend
adapters own filesystem representation and generated build artifacts. These responsibilities
must stay separate, as in Workman's design.

## Source syntax and first supported profile

Use Workman's import spelling inside a dedicated top-level SML comment:

```sml
(* @subsetml
from "./subset_io.sml" import * as SubsetIo;
from "./parser.sml" import * as Parser;
*)

structure Main = struct
  (* ordinary SubsetML declarations *)
end
```

The first profile accepts a header metadata block before ordinary declarations, with explicit
relative `.sml` paths and namespace imports only. The imported name must match the dependency's
declared structure. Arbitrary aliases, named imports, open imports, import declarations between
ordinary declarations, and JavaScript/host import syntax are outside this first profile.
Unsupported forms receive a diagnostic rather than being silently ignored or approximated.
An imported dependency must contain one declared structure and no named top-level values or
types outside that structure. Top-level wildcard effects are allowed. This conservative interface
restriction avoids disagreement with the current Workman translator, which flattens outside
bindings into its module. General interface mapping belongs to the backend generation phase.

The marker distinguishes metadata from prose comments and quoted examples. Parse metadata from
actual comment tokens, retaining source spans for diagnostics; do not search arbitrary source
text with a regular expression. Missing dependencies are diagnosed at their import directive.
Dependency discovery follows directives, not guesses from qualified identifier uses.

Ordinary SML tools ignore the comment. They still need the dependency environment, supplied by
generated loading/build artifacts. The comment alone does not make MLton load another file.

The restriction to header namespace imports is a syntax/profile restriction. Resolution,
identity and graph behavior adopt the Workman contract from the beginning. Later import forms
must extend that same model, including Workman's declaration-order scope rules.

## Resolution and module identity

The conceptual interface is:

```text
resolve(referrerModuleId, specifier, configuration) -> Result resolvedModule
```

A resolved module has separate identity, source location and display information. Keep the
original specifier and its source span on the import edge. Do not use a structure name, basename,
display path or generated filename as module identity.

For local files:

1. Resolve the explicit path relative to the importing file, not the process working directory.
2. Remove lexical dot segments before obtaining the canonical filesystem path, including
   symlink resolution. This matches Workman URL resolution even for directory symlinks.
3. Associate it with a project-local ModuleId and load/elaborate the module once.
4. Preserve the original spelling for diagnostics and choose backend output names separately.

Different spellings of one canonical file identify one module and its original datatype
declarations. Distinct files remain distinct even when their contents or basenames match.
ModuleIds are opaque to semantic consumers; they are not persistent or cross-machine identifiers.
Virtual providers must supply stable identities within a project snapshot rather than pretend
their paths have been canonicalized by the filesystem.

The implemented physical provider supports POSIX paths and printable ASCII relative import
specifiers beginning with `./` or `../` and ending with `.sml`. It rejects backslashes, percent
escapes, URL query/fragment characters and non-ASCII specifiers. These are explicit limits of
this first shared profile, not universal restrictions in Workman's contract. Entry paths and
canonical host paths still use validated native byte strings. Unicode specifiers, escaping,
Windows paths and virtual providers need further conformance work. Identity and physical path
are separate fields; semantic consumers compare ModuleIds and do not derive paths from them.
Keep this separation when adding Workman's virtual-source model.
Package names, import maps, vendoring and other non-local resolution remain future protocol work,
as in Workman D25. There is no implicit filename guessing or library search fallback.

The intentional source distinction is `.sml` versus `.wm`. Translation maps source module edges
to emitted Workman module paths using an explicit module-to-output mapping; it must not blindly
replace suffixes when files are relocated or flattened.

## Graph, environments and initialization

- Discover all reachable imports before elaborating modules. Reject cycles with the complete
  ordered import-edge path and the location of the closing edge.
- Traverse outgoing edges in source order, depth-first. Complete dependencies before importers
  and initialize each resolved module once. Preserve effects already performed if initialization
  fails; importers must not begin after a dependency fails.
- Give each module the initial environment plus its explicit imports. Compilation order must
  not grant access to unrelated or merely transitive modules.
- Export the module's own declarations, not its imported bindings. Namespace imports project
  the already elaborated dependency environment and preserve its original schemes, constructor
  status and nominal identities; do not re-elaborate a dependency for each importer.
- Keep entrypoint invocation separate from initialization. Adding loading must preserve current
  SML top-level execution, including the compiler's `val _ = Main.main ()`, without adding a second
  implicit invocation.

These rules rule out implementing the loader as just a topological list of files elaborated
into one ambient environment. The existing dependency analysis in `Translate.recover` is useful
scaffolding, but its project-wide environment is not the complete new module protocol.

## Portable implementation and host boundary

Metadata parsing, graph traversal, cycle detection, caching, error construction, environment
assembly and output planning should be ordinary SubsetML. They need no package manager or
directory enumeration for explicit file imports.

Canonical filesystem identity requires host access. Whole-file reads cannot determine whether
two paths are symlink aliases; equal file contents cannot establish identity either. The additional Result-based operation is implemented as `SubsetIo.canonicalPath`, backed by
`SubsetHost.canonicalPath`. The native adapter uses `OS.FileSys.fullPath`; the Workman adapter
uses Node's `realpathSync` with Buffer input/output to preserve native path bytes. Failures stay
in Result and reuse the existing I/O error representation. The compiler now needs eight explicit
host entry points: one text extraction operation, six CLI operations and this filesystem operation.

The first path ABI deliberately supports the common POSIX profile above. Extend it against
Workman conformance fixtures before accepting Unicode specifiers, escaping or Windows volumes.
Preserve SubsetML's byte-text model; JavaScript URL/path utilities are implementation details,
not a new language requirement. Lexical `.`/`..` cleanup complements filesystem canonicalization
and cannot replace it.

## MLton and other backends

Resolve and elaborate one source graph, then give each backend that graph and its original
module identities. For MLton, generate an `.mlb` with the selected native adapters and suitable
per-module scopes. Emit each module instance once and hide dependency-only working bindings;
verify that generated scopes preserve nominal identities and initialization order.

Users should not maintain that `.mlb` themselves. Source remains valid SML, supplied with the
generated environment. Other SML implementations may require their own generated driver format.
There is no assumption that one build-file syntax is portable between implementations.

The Workman backend emits real import declarations and an output-path mapping from the same
graph. Ordinary directives must not survive as duplicate comments as well as emitted imports.
Reverse source-list translation now reconstructs metadata so dependency information is not lost. Extending
the current syntax round-trip checks to cover import metadata is part of this work.

## Implementation sequence and validation

Steps 1–4 are implemented for the first profile; steps 5–6 remain planned.

1. Extract shared conformance fixtures from the Workman contract and existing tests. Record
   discrepancies between the contract and current implementation before selecting behavior.
2. Define metadata/import-edge data and a resolver/provider interface. Specify filesystem path
   representation and the canonicalization adapter using those fixtures.
3. Implement the graph loader and typed import diagnostics in SubsetML. Add explicit-import
   environments and dependency export caching rather than ambient project visibility.
4. Add directives to a small example, then the compiler and source Basis. Make entry-file
   checking work in both the native and generated Workman compiler.
5. Generate Workman imports and MLton build artifacts from the graph, with backend adapter
   selection, output mapping and metadata round trips.
6. Replace handwritten compiler source ordering where the new graph supplies it. Existing
   explicit-file workflows remain available during migration.

Shared fixtures should cover importer-relative paths independently of working directory,
`./` and `../` spellings, symlink aliases, missing files, same-basename distinct modules, diamond
dependencies, complete cycle diagnostics, hidden transitive imports, nominal type identity, and
once-only source-ordered initialization. Add byte/Unicode, escaping and platform cases when
settling the path ABI. Run matching fixtures against both implementations; `.sml`/`.wm` syntax
differences must be explicit fixture parameters, not different expected resolution behavior.

The current loader suite checks 19 cases plus the compiler entry on both backends, and compares
12 shared cases against Workman's compiler. It covers private scope, nominal identity, source
order, cycles, symlinks, dot-segment ordering, diagnostics and metadata restrictions. Checking
does not execute the loaded program: once-only initialization and generated artifact execution
still need backend-phase tests.

This plan does not commit to implementing package resolution, all Workman import forms, an LSP
project-discovery model, or a new asynchronous/process-spawning kernel as part of the first loader.
