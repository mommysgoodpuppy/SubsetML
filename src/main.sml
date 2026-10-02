(* Command-line driver.

     subsetml check FILE...         parse and type-check the files, in order, as one program
     subsetml parse FILE...         print the abstract syntax of each file
     subsetml fmt FILE...           reprint each file as SubsetML
     subsetml wm OUTDIR FILE...     translate the program's files to Workman modules in OUTDIR
     subsetml sml OUTDIR FILE.wm... translate Workman modules to SubsetML files in OUTDIR
     subsetml roundtrip FILE...     check that SML -> Workman -> SML preserves each file's syntax *)
structure Main = struct

  val readFile = fn path =>
    let
      val ins = TextIO.openIn path
      val text = TextIO.inputAll ins
      val _ = TextIO.closeIn ins
    in
      text
    end

  val writeFile = fn (path, text) =>
    let val out = TextIO.openOut path in
      TextIO.output (out, text);
      TextIO.closeOut out
    end

  (* 1-based line and column of a byte offset. *)
  val lineCol = fn (src, offset) =>
    let
      val rec go = fn (i, line, col) =>
        if i >= offset orelse i >= Num.String.size src then (line, col)
        else
          let val newline = Num.String.sub (src, i) = #"\n" in
            go (i + 1.0, if newline then line + 1.0 else line, if newline then 1.0 else col + 1.0)
          end
    in
      go (0.0, 1.0, 1.0)
    end

  val errorLineKind = fn (path, src, kind, msg, pos) =>
    let val (line, col) = lineCol (src, pos) in
      path ^ ":" ^ Num.toString line ^ ":" ^ Num.toString col ^ ": " ^ kind ^ ": " ^ msg ^ "\n"
    end

  val errorLine = fn (path, src, msg, pos) => errorLineKind (path, src, "error", msg, pos)

  val eprint = fn s => TextIO.output (TextIO.stdErr, s)

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
     OS.Process.exit OS.Process.failure)

  val finish = fn ok => OS.Process.exit (if ok then OS.Process.success else OS.Process.failure)

  (* Runs `f` on every file once all of them have parsed. *)
  val withParsed = fn (files, f) =>
    let
      val loaded = SmlList.map load files
      val parsed = SmlList.concat (SmlList.map (fn Parsed p => [p] | Failed => []) loaded)
    in
      if SmlList.null files then usage ()
      else (if Real.== (Num.List.length parsed, Num.List.length files) then finish (f parsed) else finish false)
    end

  val translate = fn (outDir, parsed) =>
    let
      val structures = SmlList.concat (SmlList.map (fn (_, _, prog, _) => Translate.structureOf prog) parsed)
      val results =
        SmlList.map (fn (path, src, prog, comments) =>
                    Translate.toWm (structures, path, src, prog, comments)) parsed
      val errors =
        SmlList.concat (SmlList.map (fn Translate.TranslateError e => [e] | Translate.Output _ => []) results)
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
      val ok = Real.== (Num.List.length modules, Num.List.length files)
      val results = SmlList.map (fn
          Unify.Err (msg, _) => (eprint ("error translating Workman: " ^ msg ^ "\n"); NONE)
        | Unify.Ok ((path, src, prog, cs), _) =>
            let val (_, phrases) = Translate.module prog
                val (ds, es) = Translate.parts phrases
                val stem = Translate.baseName path
                val name = if String.isSuffix ".wm" stem
                           then Num.String.substring (stem, 0.0, Num.String.size stem - 3.0) else stem
            in SOME (outDir ^ "/" ^ name ^ ".sml", Translate.fromWm (path, src, ds, es, cs)) end) recovered
    in
      if ok andalso SmlList.all SmlOption.isSome results then
        (SmlList.app (fn SOME (path, text) => writeFile (path, text) | NONE => ()) results; true)
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

  val main = fn () =>
    case CommandLine.arguments () of
      "check" :: files => withParsed (files, typeCheck)
    | "parse-only" :: files => withParsed (files, fn _ => true)
    | "parse" :: files =>
        withParsed (files, fn parsed =>
          (SmlList.app (fn (_, _, prog, _) => SmlList.app (fn p => print (Print.topdec p ^ "\n")) prog) parsed;
           true))
    | "fmt" :: files =>
        withParsed (files, fn parsed =>
          (SmlList.app (fn (_, src, prog, comments) => print (Translate.toSml (src, prog, comments))) parsed;
           true))
    | "wm" :: outDir :: files => withParsed (files, fn parsed => translate (outDir, parsed))
    | "sml" :: outDir :: files => if SmlList.null files then usage () else finish (fromWm (outDir, files))
    | "roundtrip" :: files => withParsed (files, roundTrip)
    | _ => usage ()

end

val _ = Main.main ()
