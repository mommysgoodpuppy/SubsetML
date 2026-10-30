(* Focused execution of the source-only compiler kernel, without CLI host I/O. *)
structure KernelPortable = struct
  open SubsetOptionValue

  val lists =
    (case SubsetList.at (["a", "b"], 1) of SubsetResult.Ok "b" => true | other => false)
    andalso (case SubsetList.at (["a"], 1) of SubsetResult.Err SubsetList.OutOfBounds => true | other => false)
    andalso (case SubsetList.splitAt (["a", "b"], 2) of
      SubsetResult.Ok pair => let val (prefix, rest) = pair in prefix = ["a", "b"] andalso rest = [] end
    | other => false)
    andalso (case SubsetList.take (["a", "b"], 1) of SubsetResult.Ok ["a"] => true | other => false)
    andalso (case SubsetList.drop (["a", "b"], 1) of SubsetResult.Ok ["b"] => true | other => false)
    andalso (case SubsetList.drop (["a"], 2) of SubsetResult.Err SubsetList.OutOfBounds => true | other => false)
    andalso SubsetList.all ([~1, ~2147483648], fn index =>
      (case SubsetList.at (["a"], index) of SubsetResult.Err SubsetList.InvalidIndex => true | other => false)
      andalso (case SubsetList.tabulate (index, fn i => "unexpected") of
        SubsetResult.Err SubsetList.InvalidCount => true | other => false))
  val indexed = SubsetList.tabulate (3, fn i =>
    let val text = CompilerText.natural i in print ("index " ^ text ^ "\n"); text end)
  val callbacks = case indexed of SubsetResult.Ok ["0", "1", "2"] => true | other => false
  val original = SubsetList.foldLeft (NaturalVectors.cases, IntMap.empty, fn (entry, map) =>
    let val (key, base, whole, residue, text) = entry in IntMap.insert (map, key, text) end)
  val overwritten = IntMap.insert (original, 0, "replaced")
  val maps = SubsetList.all (NaturalVectors.cases, fn entry =>
    let val (key, base, whole, residue, text) = entry in
      case IntMap.find (original, key) of SOME actual => actual = text | NONE => false
    end)
    andalso (case IntMap.find (overwritten, 0) of SOME "replaced" => true | other => false)
    andalso (case IntMap.find (original, 0) of SOME "0" => true | other => false)
    andalso (case IntMap.find (original, 1234567) of NONE => true | other => false)
  val variables = Unify.varName 26 = "'t26" andalso Unify.varName 99 = "'t99"
  val elab = fn source =>
    case (Basis.initial, Parser.parse source) of
      (Unify.Ok (env, st), Parser.Program (phrases, comments)) =>
        (case Elab.program (env, phrases, st) of Unify.Ok (result, state) => true | Unify.Err (message, pos) => false)
    | other => false
  val semantics = elab "datatype 'a box = Box of 'a val f = fn Box x => x val y = f (Box 1)"
    andalso elab "type fields = {left : bool, right : real} val pair = (true, 1) val get = fn {left = x, right = y} => (x, y)"
    andalso not (elab "val rejected = #\"a\" < #\"b\"")
  val translated =
    case Parser.parse "structure Test = struct val n = 2 val f = fn x => x + n end" of
      Parser.ParseError (message, pos) => false
    | Parser.Program (phrases, comments) =>
        (case Translate.toWm (["Test"], "test.sml", "", phrases, comments) of
          Translate.TranslateError message => false
        | Translate.Output (name, text, warnings) =>
            (case WmParse.parseModule text of WmParse.Module (decs, exps, cs) => true
             | WmParse.ParseError (message, pos) => false))
  val _ = if NaturalVectors.checked andalso lists andalso callbacks andalso maps
    andalso variables andalso semantics andalso translated
    then print "portable compiler kernel: ok\n" else print "FAILED\n"
end
