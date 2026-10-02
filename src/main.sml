(* Command-line driver.

     subsetml check FILE...         parse and type-check the files, in order, as one program
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
    | Failed

  (* Reads and parses a file, reporting any error. *)
  val load = fn path =>
    let val src = readFile path in
      case Parser.parse src of
        Parser.ParseError (msg, pos) => (eprint (errorLine (path, src, msg, pos)); Failed)
      | Parser.Program (phrases, comments) => Parsed (path, src, phrases, comments)
    end

  val usage = fn () =>
    (eprint "usage: subsetml (check | parse | fmt | roundtrip) FILE...\n       subsetml wm OUTDIR FILE...\n       subsetml sml OUTDIR FILE.wm...\n";
     SubsetProcess.exit false)

  val finish = fn ok => SubsetProcess.exit ok

  (* Runs `f` on every file once all of them have parsed. *)
  val withParsed = fn (files, f) =>
    let
      val loaded = SmlList.map load files
      val parsed = SmlList.concat (SmlList.map (fn Parsed (path, src, prog, comments) => [(path, src, prog, comments)] | Failed => []) loaded)
    in
      if SmlList.null files then usage ()
      else (if Real.== (SubsetList.length parsed, SubsetList.length files) then finish (f parsed) else finish false)
    end

  val translate = fn (outDir, parsed) =>
    let
      val structures = SmlList.concat (SmlList.map (fn (ignored2, ignored3, prog, ignored4) => Translate.structureOf prog) parsed)
      val results =
        SmlList.map (fn (path, src, prog, comments) =>
                    Translate.toWm (structures, path, src, prog, comments)) parsed
      val errors =
        SmlList.concat (SmlList.map (fn Translate.TranslateError e => [e] | Translate.Output (ignored5Field0, ignored5Field1, ignored5Field2) => []) results)
      val warn = fn ((path, src, ignored6, ignored7), result) =>
        case result of
          Translate.Output (ignored8, ignored9, warnings) =>
            SmlList.app (fn (pos, msg) =>
                        eprint (errorLineKind (path, src, "warning", msg, pos))) warnings
        | Translate.TranslateError ignored10 => ()
    in
      case errors of
        [] =>
          (SmlList.app (fn Translate.Output (name, text, ignored11) => writeFile (outDir ^ "/" ^ name, text)
                      | Translate.TranslateError ignored12 => ()) results;
           SmlListPair.app warn (parsed, results);
           true)
      | ignored13 => (SmlList.app (fn e => eprint ("error: " ^ e ^ "\n")) errors; false)
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
          Unify.Err (msg, ignored14) => (eprint ("error translating Workman: " ^ msg ^ "\n"); NONE)
        | Unify.Ok ((path, src, prog, cs), ignored15) =>
            let val (ignored16, phrases) = Translate.module prog
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
      val structures = SmlList.concat (SmlList.map (fn (ignored17, ignored18, prog, ignored19) => Translate.structureOf prog) parsed)
      val loaded = SmlList.map (fn (path, src, prog, comments) =>
        case Translate.toWm (structures, path, src, prog, comments) of
          Translate.TranslateError msg => (eprint (msg ^ "\n"); NONE)
        | Translate.Output (name, text, ignored20) =>
            case WmParse.parseModule text of
              WmParse.ParseError (msg, pos) => (eprint (errorLine (path, text, msg, pos)); NONE)
            | WmParse.Module (ds, es, cs) => SOME (path, text,
                Syntax.TopDecs [Syntax.SStructure (0.0, [(WmParse.structureName name, ds)])] ::
                SmlList.map (fn e => Syntax.TopExp (0.0, e)) es, cs)) parsed
      val modules = SmlList.concat (SmlList.map (fn SOME m => [m] | NONE => []) loaded)
      val show = fn prog =>
        let val (ignored21, phrases) = Translate.module prog
            val (ds, es) = Translate.parts phrases
        in SmlList.map Print.dec (Normalize.decs ds) @ SmlList.map (fn e => Print.exp (Normalize.exp e)) es end
      val check = fn (path, ignored22, prog, ignored23) =>
        case SmlList.find (fn (p, ignored24, ignored25, ignored26) => p = path) modules of
          NONE => false
        | SOME m =>
            case Translate.recover (modules, m) of
              Unify.Err (msg, ignored27) => (eprint (path ^ ": round trip: " ^ msg ^ "\n"); false)
            | Unify.Ok ((ignored28, ignored29, actual, ignored30), ignored31) =>
                if show prog = show actual then true
                else (eprint (path ^ ": syntax changed in the round trip\n"); false)
    in
      SmlList.all (fn ok => ok) (SmlList.map check parsed)
    end

  (* Elaborates the files in order, each extending the environment, and reports the first
     error. *)
  val typeCheck = fn parsed =>
    case Basis.initial of
      Unify.Err (msg, ignored32) => (eprint ("internal error in the basis: " ^ msg ^ "\n"); false)
    | Unify.Ok (basis, ignored33) =>
        let
          val rec go = fn
              (ignored34, [], ignored35) => true
            | (env, (path, src, prog, ignored36) :: rest, st) =>
                case Elab.program (env, prog, st) of
                  Unify.Ok (env', st') => go (env', rest, st')
                | Unify.Err (msg, pos) => (eprint (errorLine (path, src, msg, pos)); false)
        in
          go (basis, parsed, Unify.initial)
        end

  val main = fn () =>
    let
      val args = case SubsetProcess.arguments () of
        SubsetResult.Ok values => values
      | SubsetResult.Err error => fatal (SubsetIo.errorText error)
    in case args of
      "check" :: files => withParsed (files, typeCheck)
    | "parse-only" :: files => withParsed (files, fn ignored37 => true)
    | "parse" :: files =>
        withParsed (files, fn parsed =>
          (SmlList.app (fn (ignored38, ignored39, prog, ignored40) => SmlList.app (fn p => output (Print.topdec p ^ "\n")) prog) parsed;
           true))
    | "fmt" :: files =>
        withParsed (files, fn parsed =>
          (SmlList.app (fn (ignored41, src, prog, comments) => output (Translate.toSml (src, prog, comments))) parsed;
           true))
    | "wm" :: outDir :: files => withParsed (files, fn parsed => translate (outDir, parsed))
    | "sml" :: outDir :: files => if SmlList.null files then usage () else finish (fromWm (outDir, files))
    | "roundtrip" :: files => withParsed (files, roundTrip)
    | ignored42 => usage ()
    end

end

val ignored43 = Main.main ()
