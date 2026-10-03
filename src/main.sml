(* @subsetml
from "./subset_io.sml" import * as SubsetIo;
from "./compiler_text.sml" import * as CompilerText;
from "./subset_result.sml" import * as SubsetResult;
from "./subset_process.sml" import * as SubsetProcess;
from "./syntax.sml" import * as Syntax;
from "./lexer.sml" import * as Lexer;
from "./parser.sml" import * as Parser;
from "./sml_list.sml" import * as SmlList;
from "./subset_list.sml" import * as SubsetList;
from "./translate.sml" import * as Translate;
from "./sml_list_pair.sml" import * as SmlListPair;
from "./wm_parse.sml" import * as WmParse;
from "./unify.sml" import * as Unify;
from "./sml_option.sml" import * as SmlOption;
from "./print.sml" import * as Print;
from "./normalize.sml" import * as Normalize;
from "./basis.sml" import * as Basis;
from "./elab.sml" import * as Elab;
from "./module_project.sml" import * as ModuleProject;
*)

(* Command-line driver.

     subsetml check ENTRY.sml       check the entry file's explicit import graph
     subsetml check FILE1 FILE2 ... legacy sequential source-list checking
     subsetml parse FILE...         print the abstract syntax of each file
     subsetml fmt FILE...           reprint each file as SubsetML
     subsetml wm OUTDIR FILE...     translate the program's files to Workman modules in OUTDIR
     subsetml sml OUTDIR FILE.wm... translate Workman modules to SubsetML files in OUTDIR
     subsetml roundtrip FILE...     check that SML -> Workman -> SML preserves each file's syntax *)
structure Main = struct

  val eprint = fn text =>
    case SubsetIo.writeStderr (CompilerText.characters text) of
      SubsetResult.Ok result => result
    | SubsetResult.Err error => SubsetProcess.exit false
  val fatal = fn message => (eprint (message ^ "\n"); SubsetProcess.exit false)
  val readFile = fn path =>
    case SubsetIo.readFile path of
      SubsetResult.Ok bytes => CompilerText.stringOf bytes
    | SubsetResult.Err error => fatal (path ^ ": " ^ SubsetIo.errorText error)
  val writeFile = fn (path, text) =>
    case SubsetIo.writeFile (CompilerText.characters text, path) of
      SubsetResult.Ok result => result
    | SubsetResult.Err error => fatal (path ^ ": " ^ SubsetIo.errorText error)
  val output = fn text =>
    case SubsetIo.writeStdout (CompilerText.characters text) of
      SubsetResult.Ok result => result
    | SubsetResult.Err error => fatal (SubsetIo.errorText error)

  (* 1-based line and column of a byte offset. *)
  val lineCol = fn (src, offset) =>
    let
      val rec go = fn (bytes, i, line, col) =>
        if i >= offset then (line, col)
        else case bytes of [] => (line, col) | c :: rest =>
          let val newline = c = #"\n" in
            go (rest, i + 1.0, if newline then line + 1.0 else line, if newline then 1.0 else col + 1.0)
          end
    in
      go (CompilerText.characters src, 0.0, 1.0, 1.0)
    end

  val errorLineKind = fn (path, src, kind, msg, pos) =>
    let val (line, col) = lineCol (src, pos) in
      path ^ ":" ^ CompilerText.natural line ^ ":" ^ CompilerText.natural col ^ ": " ^ kind ^ ": " ^ msg ^ "\n"
    end

  val errorLine = fn (path, src, msg, pos) => errorLineKind (path, src, "error", msg, pos)

  datatype parsed =
      Parsed of string * string * Syntax.topdec list * Syntax.comment list

  (* Keep causes and source context until the CLI reporting boundary. *)
  datatype sourceError =
      ReadFailure of string * SubsetIo.error
    | LexFailure of string * string * string * Syntax.pos
    | ParseFailure of string * string * string * Syntax.pos

  val lexSource = fn (path, src) =>
    case Lexer.lex src of
      Lexer.LexError (msg, pos) => SubsetResult.Err (LexFailure (path, src, msg, pos))
    | Lexer.Tokens (tokens, comments) => SubsetResult.Ok (path, src, tokens, comments)

  val parseSource = fn (path, src, tokens, comments) =>
    case Parser.parseTokens (tokens, comments) of
      Parser.ParseError (msg, pos) => SubsetResult.Err (ParseFailure (path, src, msg, pos))
    | Parser.Program (phrases, comments) => SubsetResult.Ok (Parsed (path, src, phrases, comments))

  (* No reporting or exit inside the procedure; later transformations skip on Err. *)
  val load = fn path =>
    let
      val read = SubsetResult.viaError (fn error => ReadFailure (path, error))
        (fn file => SubsetResult.map (SubsetIo.readFile file,
          fn bytes => (file, CompilerText.stringOf bytes)))
      val lex = SubsetResult.via lexSource
      val parse = SubsetResult.via parseSource

      val loaded = read (SubsetResult.Ok path)
      val lexed = lex loaded
    in
      parse lexed
    end

  val sourceErrorText = fn
      ReadFailure (path, error) => path ^ ": " ^ SubsetIo.errorText error ^ "\n"
    | LexFailure (path, src, msg, pos) => errorLineKind (path, src, "lex error", msg, pos)
    | ParseFailure (path, src, msg, pos) => errorLineKind (path, src, "parse error", msg, pos)

  val usage = fn () =>
    (eprint "usage: subsetml (check | parse | fmt | roundtrip) FILE...\n       subsetml wm OUTDIR FILE...\n       subsetml sml OUTDIR FILE.wm...\n";
     SubsetProcess.exit false)

  val finish = fn ok => SubsetProcess.exit ok

  (* Runs `f` on every file once all of them have parsed. *)
  val withParsed = fn (files, f) =>
    let
      val loaded = SmlList.map load files
      val parsed = SmlList.concat (SmlList.map (fn
          SubsetResult.Ok value =>
            (case value of Parsed (path, src, prog, comments) => [(path, src, prog, comments)])
        | SubsetResult.Err error => (eprint (sourceErrorText error); [])) loaded)
    in
      if SmlList.null files then usage ()
      else (if Real.== (SubsetList.length parsed, SubsetList.length files) then finish (f parsed) else finish false)
    end

  val translate = fn (outDir, parsed) =>
    let
      val structures = SmlList.concat (SmlList.map (fn (_, _, prog, _) => Translate.structureOf prog) parsed)
      val results =
        SmlList.map (fn (path, src, prog, comments) =>
                    Translate.toWm (structures, path, src, prog, comments)) parsed
      val errors =
        SmlList.concat (SmlList.map (fn Translate.TranslateError e => [e] | Translate.Output (_, _, _) => []) results)
      val warn = fn ((path, src, _, _), result) =>
        case result of
          Translate.Output (_, _, warnings) =>
            SmlList.app (fn (pos, msg) =>
                        eprint (errorLineKind (path, src, "warning", msg, pos))) warnings
        | Translate.TranslateError _ => ()
    in
      case errors of
        [] =>
          (SmlList.app (fn Translate.Output (name, text, _) => writeFile (outDir ^ "/" ^ name, text)
                      | Translate.TranslateError _ => ()) results;
           SmlListPair.app warn (parsed, results);
           true)
      | _ => (SmlList.app (fn e => eprint ("error: " ^ e ^ "\n")) errors; false)
    end

  (* Workman to SubsetML: foo_bar.wm becomes foo_bar.sml holding structure FooBar. *)
  val fromWm = fn (outDir, files) =>
    let
      val loaded = SmlList.map (fn path =>
        let val src = readFile path in
          case WmParse.parseModule src of
            WmParse.ParseError (msg, pos) => (eprint (errorLine (path, src, msg, pos)); NONE)
          | WmParse.Module (ds, es, cs) => SOME (path, src,
              Syntax.TopDecs [Syntax.SStructure (0.0, [(WmParse.structureName path, ds)])] ::
              SmlList.map (fn e => Syntax.TopExp (0.0, e)) es, cs)
        end) files
      val modules = SmlList.concat (SmlList.map (fn SOME m => [m] | NONE => []) loaded)
      val recovered = SmlList.map (fn m => Translate.recover (modules, m)) modules
      val ok = Real.== (SubsetList.length modules, SubsetList.length files)
      val results = SmlList.map (fn
          Unify.Err (msg, _) => (eprint ("error translating Workman: " ^ msg ^ "\n"); NONE)
        | Unify.Ok ((path, src, prog, cs), _) =>
            let val (_, phrases) = Translate.module prog
                val (ds, es) = Translate.parts phrases
                val stem = Translate.baseName path
                val name = if CompilerText.isSuffix (stem, ".wm")
                           then CompilerText.slice (stem, 0.0, CompilerText.size stem - 3.0) else stem
            in SOME (outDir ^ "/" ^ name ^ ".sml", Translate.fromWm (path, src, ds, es, cs)) end) recovered
    in
      if ok andalso SmlList.all SmlOption.isSome results then
        (SmlList.app (fn SOME entry => let val (path, text) = entry in writeFile (path, text) end | NONE => ()) results; true)
      else false
    end

  (* SML -> Workman -> SML must give back the same declarations, up to Normalize. *)
  val roundTrip = fn parsed =>
    let
      val structures = SmlList.concat (SmlList.map (fn (_, _, prog, _) => Translate.structureOf prog) parsed)
      val loaded = SmlList.map (fn (path, src, prog, comments) =>
        case Translate.toWm (structures, path, src, prog, comments) of
          Translate.TranslateError msg => (eprint (msg ^ "\n"); NONE)
        | Translate.Output (name, text, _) =>
            case WmParse.parseModule text of
              WmParse.ParseError (msg, pos) => (eprint (errorLine (path, text, msg, pos)); NONE)
            | WmParse.Module (ds, es, cs) => SOME (path, text,
                Syntax.TopDecs [Syntax.SStructure (0.0, [(WmParse.structureName name, ds)])] ::
                SmlList.map (fn e => Syntax.TopExp (0.0, e)) es, cs)) parsed
      val modules = SmlList.concat (SmlList.map (fn SOME m => [m] | NONE => []) loaded)
      val show = fn prog =>
        let val (_, phrases) = Translate.module prog
            val (ds, es) = Translate.parts phrases
        in SmlList.map Print.dec (Normalize.decs ds) @ SmlList.map (fn e => Print.exp (Normalize.exp e)) es end
      val check = fn (path, _, prog, _) =>
        case SmlList.find (fn (p, _, _, _) => p = path) modules of
          NONE => false
        | SOME m =>
            case Translate.recover (modules, m) of
              Unify.Err (msg, _) => (eprint (path ^ ": round trip: " ^ msg ^ "\n"); false)
            | Unify.Ok ((_, _, actual, _), _) =>
                if show prog = show actual then true
                else (eprint (path ^ ": syntax changed in the round trip\n"); false)
    in
      SmlList.all (fn ok => ok) (SmlList.map check parsed)
    end

  (* Elaborates the files in order, each extending the environment, and reports the first
     error. *)
  val typeCheck = fn parsed =>
    case Basis.initial of
      Unify.Err (msg, _) => (eprint ("internal error in the basis: " ^ msg ^ "\n"); false)
    | Unify.Ok (basis, _) =>
        let
          val rec go = fn
              (_, [], _) => true
            | (env, (path, src, prog, _) :: rest, st) =>
                case Elab.program (env, prog, st) of
                  Unify.Ok (env', st') => go (env', rest, st')
                | Unify.Err (msg, pos) => (eprint (errorLine (path, src, msg, pos)); false)
        in
          go (basis, parsed, Unify.initial)
        end

  (* An entry file has only its explicit import environment; legacy source lists remain
     available for bootstrap checking and ordinary SML compilation-unit order. *)
  val checkProject = fn path =>
    let
      val source = fn file => SubsetResult.map (load file,
        fn Parsed (path, src, prog, comments) => ModuleProject.Source (path, src, prog, comments))
      val checked = SubsetResult.andThen (ModuleProject.discover (path, source), fn graph =>
        case Basis.initial of
          Unify.Err (message, _) => SubsetResult.Err
            (ModuleProject.CheckFailure (path, "", "internal error in the basis: " ^ message, 0.0))
        | Unify.Ok (basis, _) => ModuleProject.check (graph, basis))
      val report = fn
          ModuleProject.LoadFailure error => sourceErrorText error
        | ModuleProject.ResolutionFailure (path, error) => path ^ ": " ^ SubsetIo.errorText error ^ "\n"
        | ModuleProject.ImportFailure (path, src, message, pos) => errorLineKind (path, src, "import error", message, pos)
        | ModuleProject.CheckFailure (path, src, message, pos) => errorLine (path, src, message, pos)
    in
      case checked of
        SubsetResult.Ok _ => finish true
      | SubsetResult.Err error => (eprint (report error); finish false)
    end

  val main = fn () =>
    let
      val args = case SubsetProcess.arguments () of
        SubsetResult.Ok values => values
      | SubsetResult.Err error => fatal (SubsetIo.errorText error)
    in case args of
      "check" :: [file] => checkProject file
    | "check" :: files => withParsed (files, typeCheck)
    | "parse-only" :: files => withParsed (files, fn _ => true)
    | "parse" :: files =>
        withParsed (files, fn parsed =>
          (SmlList.app (fn (_, _, prog, _) => SmlList.app (fn p => output (Print.topdec p ^ "\n")) prog) parsed;
           true))
    | "fmt" :: files =>
        withParsed (files, fn parsed =>
          (SmlList.app (fn (_, src, prog, comments) => output (Translate.toSml (src, prog, comments))) parsed;
           true))
    | "wm" :: outDir :: files => withParsed (files, fn parsed => translate (outDir, parsed))
    | "sml" :: outDir :: files => if SmlList.null files then usage () else finish (fromWm (outDir, files))
    | "roundtrip" :: files => withParsed (files, roundTrip)
    | _ => usage ()
    end

end

val _ = Main.main ()
