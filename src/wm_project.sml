(* @subsetml
from "./subset_bool.sml" import * as SubsetBool;
from "./subset_option_value.sml" import * as SubsetOptionValue;
from "./module_project.sml" import * as ModuleProject;
from "./syntax.sml" import * as Syntax;
from "./wm_lexer.sml" import * as WmLexer;
from "./subset_result.sml" import * as SubsetResult;
from "./compiler_text.sml" import * as CompilerText;
from "./module_imports.sml" import * as ModuleImports;
from "./subset_list.sml" import * as SubsetList;
from "./subset_io.sml" import * as SubsetIo;
from "./wm_parse.sml" import * as WmParse;
from "./basis.sml" import * as Basis;
from "./unify.sml" import * as Unify;
from "./env.sml" import * as Env;
from "./subset_char.sml" import * as SubsetChar;
from "./subset_option.sml" import * as SubsetOption;
from "./subset_string.sml" import * as SubsetString;
from "./lexer.sml" import * as Lexer;
*)

(* Source-list reverse translation shares the source loader's canonical identities.
   Backend names are chosen separately; they are never filesystem identities. *)
structure WmProject = struct
  open SubsetOptionValue

  datatype input = Input of ModuleProject.resolved * string * string
  datatype projectUnit = Unit of input * string * string
  datatype edge = Edge of string * Syntax.pos * string * ModuleProject.moduleId
  datatype source = Source of projectUnit * edge list * WmLexer.result
  datatype error = Error of string * string * string * Syntax.pos

  val failure = fn (path, src, message, pos) => SubsetResult.Err (Error (path, src, message, pos))
  val identity = fn Unit (Input (ModuleProject.Resolved (id, _), _, _), _, _) => id
  val name = fn Unit (_, name, _) => name
  val output = fn Unit (_, _, output) => output
  val pathOf = fn Unit (Input (_, path, _), _, _) => path
  val textOf = fn Unit (Input (_, _, src), _, _) => src
  val sourceUnit = fn Source (unit, _, _) => unit
  val edgesOf = fn Source (_, edges, _) => edges

  (* "basis/won.wm" names the Basis module subset_won.wm, as in Workman. *)
  val basisModule = fn specifier =>
    let val count = CompilerText.size specifier in
      if count > 9 andalso CompilerText.slice (specifier, 0, 6) = "basis/" andalso
         CompilerText.isSuffix (specifier, ".wm") then
        let val name = CompilerText.slice (specifier, 6, count - 9) in
          if SubsetList.all (CompilerText.characters name,
               fn c => SubsetChar.isLower c orelse SubsetChar.isDigit c orelse c = #"_")
          then SOME ("subset_" ^ name ^ ".wm") else NONE
        end
      else NONE
    end

  val validSpecifier = fn specifier =>
    SubsetOption.isSome (basisModule specifier) orelse
    (CompilerText.isSuffix (specifier, ".wm") andalso
     ModuleImports.validPath (CompilerText.slice (specifier, 0, CompilerText.size specifier - 3) ^ ".sml"))

  (* basis is the directory holding the generated Basis modules, if the build supplies one. *)
  val resolve = fn (basis, referrer, specifier) =>
    case basisModule specifier of
      NONE => ModuleProject.resolve (referrer, specifier)
    | SOME file => (case basis of
        NONE => SubsetResult.Err (SubsetIo.HostError "basis/ imports need --basis DIR")
      | SOME directory => ModuleProject.identify (directory ^ "/" ^ file))

  (* Discovery reads only the supported import header. Preparation still validates aliases,
     private scope and later imports using the same canonical identities. *)
  val headerPaths = fn (path, src, tokens) =>
    let val rec scan = fn tokens => case tokens of
        (WmLexer.WKey "from", pos) :: (WmLexer.WScon (Syntax.SString specifier), _) ::
        (WmLexer.WKey "import", _) :: (WmLexer.WKey "*", _) :: rest =>
          let val remaining = case rest of
                (WmLexer.WKey "as", _) :: (WmLexer.WName [_], _) :: (WmLexer.WKey ";", _) :: tail => SOME tail
              | (WmLexer.WKey ";", _) :: tail => SOME tail | _ => NONE
          in case remaining of
            NONE => failure (path, src, "reverse discovery requires header namespace imports", pos)
          | SOME tail => if SubsetBool.not (validSpecifier specifier) then
              failure (path, src, "imports require explicit relative .wm paths or basis/ modules in the local source profile", pos)
            else SubsetResult.map (scan tail, fn paths => (specifier, pos) :: paths) end
      | (WmLexer.WKey "from", pos) :: _ =>
          failure (path, src, "reverse discovery requires header namespace imports", pos)
      | _ => SubsetResult.Ok []
    in scan tokens end

  val discover = fn (basis, roots) =>
    let
      val rec visit = fn (resolved, active, seen) =>
        let val ModuleProject.Resolved (id, path) = resolved in
          if SubsetList.exists (seen, fn (key, _, _) => ModuleProject.same (key, id)) then SubsetResult.Ok seen
          else SubsetResult.andThen (SubsetResult.mapErr (SubsetIo.readFile path,
            fn error => Error (path, "", SubsetIo.errorText error, 0)), fn bytes =>
            let val src = CompilerText.stringOf bytes in
              case WmLexer.lex src of
                WmLexer.LexError (message, pos) => failure (path, src, message, pos)
              | WmLexer.Tokens (tokens, _) =>
                  SubsetResult.andThen (headerPaths (path, src, tokens), fn paths =>
                    let val rec walk = fn (paths, seen) => case paths of
                        [] => SubsetResult.Ok seen
                      | (specifier, pos) :: rest =>
                          (case resolve (basis, resolved, specifier) of
                            SubsetResult.Err error => failure (path, src,
                              "cannot resolve import \"" ^ specifier ^ "\": " ^ SubsetIo.errorText error, pos)
                          | SubsetResult.Ok child =>
                              let val ModuleProject.Resolved (target, _) = child in
                                if SubsetList.exists (resolved :: active, fn ModuleProject.Resolved (key, _) =>
                                  ModuleProject.same (key, target)) then
                                  failure (path, src, ModuleProject.cycle (resolved :: active, child), pos)
                                else SubsetResult.andThen (visit (child, resolved :: active, seen),
                                  fn seen => walk (rest, seen)) end)
                    in walk (paths, (id, path, src) :: seen) end)
            end)
        end
      val rec loadRoots = fn (roots, seen) => case roots of
          [] => SubsetResult.Ok (SubsetList.map (SubsetList.reverse seen, fn (_, path, src) => (path, src)))
        | path :: rest => (case ModuleProject.identify path of
            SubsetResult.Err error => failure (path, "", SubsetIo.errorText error, 0)
          | SubsetResult.Ok resolved => SubsetResult.andThen (visit (resolved, [], seen),
              fn seen => loadRoots (rest, seen)))
    in loadRoots (roots, []) end

  val plan = fn sources =>
    let
      val rec identify = fn (sources, inputs) =>
        case sources of
          [] => SubsetResult.Ok (SubsetList.reverse inputs)
        | (path, src) :: rest =>
            (case ModuleProject.identify path of
               SubsetResult.Err error => failure (path, src, SubsetIo.errorText error, 0)
             | SubsetResult.Ok resolved =>
                 let val ModuleProject.Resolved (id, _) = resolved in
                   if SubsetList.exists (inputs, fn Input (ModuleProject.Resolved (key, _), _, _) => ModuleProject.same (key, id))
                   then identify (rest, inputs)
                   else identify (rest, Input (resolved, path, src) :: inputs)
                 end)
      val rec allocate = fn (inputs, used, units) =>
        case inputs of
          [] => SubsetList.reverse units
        | input :: rest =>
            let
              val Input (_, path, _) = input
              val stem = if CompilerText.isSuffix (path, ".wm") then
                CompilerText.slice (translateBase path, 0, CompilerText.size (translateBase path) - 3)
                else translateBase path
              val rec choose = fn suffix =>
                let val candidate = stem ^ suffix
                    val structureName = WmParse.structureName (candidate ^ ".wm") in
                  if SubsetList.exists (used, fn (n, f) => n = structureName orelse f = candidate)
                     orelse SubsetList.exists (rest, fn Input (_, path, _) =>
                       WmParse.structureName path = structureName) then choose (suffix ^ "Module")
                  else (structureName, candidate)
                end
              val (structureName, filename) = choose ""
            in allocate (rest, (structureName, filename) :: used, Unit (input, structureName, filename ^ ".sml") :: units) end
      and translateBase = fn path =>
        case SubsetList.reverse (CompilerText.fields (path, fn c => c = #"/")) of
          base :: _ => base | [] => path
    in
      case Basis.initial of
        Unify.Err (message, pos) => failure ("translation", "", message, pos)
      | Unify.Ok (Env.Env (structures, _, _), _) =>
          SubsetResult.map (identify (sources, []), fn inputs =>
            allocate (inputs, SubsetList.map (structures, fn (name, _) => (name, "")), []))
    end

  val prepare = fn (basis, units, unit) =>
    let
      val Unit (Input (resolved, path, src), _, _) = unit
      val dependency = fn (specifier, pos) =>
        if SubsetBool.not (validSpecifier specifier) then
          failure (path, src, "imports require explicit relative .wm paths or basis/ modules in the local source profile", pos)
        else case resolve (basis, resolved, specifier) of
          SubsetResult.Err error => failure (path, src, "cannot resolve import \"" ^ specifier ^ "\": " ^ SubsetIo.errorText error, pos)
        | SubsetResult.Ok (ModuleProject.Resolved (target, _)) =>
            case SubsetList.find (units, fn child => ModuleProject.same (identity child, target)) of
              NONE => failure (path, src, "import dependency is not in the supplied source list: " ^ specifier, pos)
            | SOME child => SubsetResult.Ok child
      val rec imports = fn (tokens, edges, aliases, opens) =>
        case tokens of
          (WmLexer.WKey "from", pos) ::
          (WmLexer.WScon (Syntax.SString specifier), _) ::
          (WmLexer.WKey "import", _) :: (WmLexer.WKey "*", _) ::
          (WmLexer.WKey "as", _) :: (WmLexer.WName [alias], _) ::
          (WmLexer.WKey ";", _) :: rest =>
            if SubsetBool.not (CompilerText.firstIs (alias, SubsetChar.isUpper)) then
              failure (path, src, "namespace aliases must start with an uppercase letter in the initial translation profile", pos)
            else (if SubsetList.exists (aliases, fn (a, _) => a = alias) then
              failure (path, src, "duplicate namespace alias " ^ alias, pos)
            else SubsetResult.andThen (dependency (specifier, pos), fn child =>
              imports (rest, Edge (specifier, pos, alias, identity child) :: edges,
                (alias, name child) :: aliases, opens)))
        | (WmLexer.WKey "from", pos) ::
          (WmLexer.WScon (Syntax.SString specifier), _) ::
          (WmLexer.WKey "import", _) :: (WmLexer.WKey "*", _) ::
          (WmLexer.WKey ";", _) :: rest =>
            SubsetResult.andThen (dependency (specifier, pos), fn child =>
              if SubsetList.exists (aliases, fn (_, target) => target = name child) then
                imports (rest, edges, aliases, (WmLexer.WOpen [[name child]], pos) :: opens)
              else failure (path, src, "open imports currently require a preceding namespace import of the same module", pos))
        | (WmLexer.WKey "from", pos) :: _ =>
            failure (path, src, "reverse translation currently requires header namespace imports: from \"./file.wm\" import * as Name;", pos)
        | _ =>
            let
              val rec rewrite = fn (tokens, acc) =>
                case tokens of
                  [] => SubsetResult.Ok (SubsetList.reverse acc)
                | (WmLexer.WKey "from", pos) :: _ =>
                    failure (path, src, "imports must precede ordinary declarations in the initial translation profile", pos)
                | (WmLexer.WName (head :: tail), pos) :: rest =>
                    (case SubsetList.find (aliases, fn (alias, _) => alias = head) of
                       NONE =>
                         if SubsetBool.not (SubsetList.isEmpty tail) andalso SubsetList.exists (units, fn u => name u = head) then
                           failure (path, src, "namespace " ^ head ^ " is not explicitly imported under that name", pos)
                         else rewrite (rest, (WmLexer.WName (head :: tail), pos) :: acc)
                     | SOME (_, target) =>
                         if SubsetList.isEmpty tail then rewrite (rest, (WmLexer.WName [head], pos) :: acc)
                         else rewrite (rest, (WmLexer.WName (target :: tail), pos) :: acc))
                | token :: rest => rewrite (rest, token :: acc)
            in SubsetResult.map (rewrite (tokens, []), fn body =>
              (SubsetList.reverse edges, SubsetList.append (SubsetList.reverse opens, body))) end
    in
      case WmLexer.lex src of
        WmLexer.LexError (message, pos) => failure (path, src, message, pos)
      | WmLexer.Tokens (tokens, comments) =>
          SubsetResult.map (imports (tokens, [], [], []), fn (edges, body) =>
            Source (unit, edges, WmLexer.Tokens (body,
              SubsetList.filter (comments, fn (_, body, _) =>
                (case ModuleImports.marked body of NONE => true | SOME _ => false) andalso
                SubsetBool.not (ModuleImports.isGeneratedHeader body)))))
    end

  val order = fn sources =>
    let
      val rec visit = fn (source, active, completed) =>
        let val unit = sourceUnit source in
          if SubsetList.exists (completed, fn s => ModuleProject.same (identity (sourceUnit s), identity unit))
          then SubsetResult.Ok completed
          else let
            val rec walk = fn (edges, completed) =>
              case edges of
                [] => SubsetResult.Ok (source :: completed)
              | Edge (specifier, pos, _, target) :: rest =>
                  if SubsetList.exists (unit :: active, fn u => ModuleProject.same (identity u, target)) then
                    failure (pathOf unit, textOf unit, "import cycle: " ^
                      SubsetString.concatWith (SubsetList.append (SubsetList.map (SubsetList.reverse (unit :: active), pathOf), [specifier]), " -> "), pos)
                  else (case SubsetList.find (sources, fn s => ModuleProject.same (identity (sourceUnit s), target)) of
                    NONE => failure (pathOf unit, textOf unit, "internal error: missing resolved dependency", pos)
                  | SOME child => SubsetResult.andThen (visit (child, unit :: active, completed), fn done => walk (rest, done)))
          in walk (edgesOf source, completed) end
        end
      val rec roots = fn (remaining, completed) =>
        case remaining of [] => SubsetResult.Ok (SubsetList.reverse completed)
        | source :: rest => SubsetResult.andThen (visit (source, [], completed), fn done => roots (rest, done))
    in roots (sources, []) end

  val imported = fn (units, unit, edges) =>
    let
      val rec loop = fn (edges, seen) =>
        case edges of
          [] => SubsetResult.Ok (SubsetList.reverse seen)
        | Edge (_, pos, _, target) :: rest =>
            case SubsetList.find (units, fn child => ModuleProject.same (identity child, target)) of
              NONE => failure (pathOf unit, textOf unit, "internal error: missing resolved dependency", pos)
            | SOME child =>
                loop (rest, if SubsetList.exists (seen, fn u => ModuleProject.same (identity u, target)) then seen else child :: seen)
    in loop (edges, []) end

  datatype adapter = Adapter of ModuleProject.moduleId * string * string

  val structureIdentifier = fn value => case Lexer.lex value of
      Lexer.Tokens ([(Lexer.TId identifier, _), (Lexer.TEOF, _)], _) =>
        identifier = value andalso SubsetChar.isAlpha (CompilerText.sub (CompilerText.source identifier, 0))
    | _ => false

  val adapters = fn (units, specifications) =>
    let val rec resolve = fn (remaining, seen) => case remaining of
        [] => SubsetResult.Ok (SubsetList.reverse seen)
      | (checker, native, exported) :: rest =>
          if SubsetBool.not (structureIdentifier exported) then
            failure (checker, "", "native adapter export must be an SML structure identifier", 0)
          else SubsetResult.andThen (case ModuleProject.identify checker of
                SubsetResult.Err error => failure (checker, "", SubsetIo.errorText error, 0)
              | SubsetResult.Ok (ModuleProject.Resolved (id, _)) =>
                  if SubsetBool.not (SubsetList.exists (units, fn unit => ModuleProject.same (identity unit, id))) then
                    failure (checker, "", "native adapter checker is not in the entry graph", 0)
                  else (if SubsetList.exists (seen, fn Adapter (key, _, _) => ModuleProject.same (id, key)) then
                    failure (checker, "", "duplicate native adapter selection", 0)
                  else (case ModuleProject.identify native of
                    SubsetResult.Err error => failure (native, "", SubsetIo.errorText error, 0)
                  | SubsetResult.Ok (ModuleProject.Resolved (_, path)) =>
                      case SubsetIo.readFile path of
                        SubsetResult.Err error => failure (native, "", SubsetIo.errorText error, 0)
                      | SubsetResult.Ok _ => SubsetResult.Ok (Adapter (id, path, exported)))),
                fn adapter => resolve (rest, adapter :: seen))
    in resolve (specifications, []) end

  (* One basis instance per canonical module. A module's body receives the standard Basis
     and only its direct dependencies; the `in` part exports only its own structure.
     Native implementations use source import aliases in separately captured basis scopes. *)
  val mlb = fn (units, sources, modules, entry, adapters) =>
    let
      val scopeName = fn name => "SubsetBuild_" ^ name
      val rec emit = fn modules => case modules of
          [] => SubsetResult.Ok ""
        | (name, dependencies, _) :: rest =>
            (case SubsetList.find (units, fn unit => nameOf unit = name) of
              NONE => failure ("translation", "", "missing build module " ^ name, 0)
            | SOME unit =>
                let
                  val selected = SubsetList.find (adapters, fn Adapter (id, _, _) => ModuleProject.same (identity unit, id))
                  val body = case selected of
                    NONE => SubsetResult.Ok (
                      "      open SubsetBuild_Standard" ^
                      SubsetString.concat (SubsetList.map (dependencies, fn name => " " ^ scopeName name)) ^
                      "\n    in\n      \"" ^ CompilerText.escapeSmlString (output unit) ^ "\"\n")
                  | SOME (Adapter (_, native, exported)) =>
                      case SubsetList.find (sources, fn source => ModuleProject.same (identity (sourceUnit source), identity unit)) of
                        NONE => failure (pathOf unit, "", "missing native adapter imports", 0)
                      | SOME source =>
                          let val rec aliases = fn edges => case edges of
                              [] => SubsetResult.Ok ("", "")
                            | Edge (_, pos, alias, target) :: rest =>
                                if SubsetBool.not (structureIdentifier alias) then
                                  failure (pathOf unit, textOf unit, "native adapter import alias must be an SML structure identifier", pos)
                                else (case SubsetList.find (units, fn child => ModuleProject.same (identity child, target)) of
                                  NONE => failure (pathOf unit, "", "missing native adapter dependency", 0)
                                | SOME child => SubsetResult.map (aliases rest, fn (declarations, opens) =>
                                    ("      basis SubsetNative_" ^ alias ^ " = bas local open " ^ scopeName (nameOf child) ^
                                     " in structure " ^ alias ^ " = " ^ nameOf child ^ " end end\n" ^ declarations,
                                     " SubsetNative_" ^ alias ^ opens)))
                          in SubsetResult.map (aliases (edgesOf source), fn (declarations, opens) =>
                            "      open SubsetBuild_Standard\n" ^ declarations ^ "      open SubsetBuild_Standard" ^ opens ^
                            "\n    in\n      local\n        \"" ^ CompilerText.escapeSmlString native ^
                            "\"\n      in\n        structure " ^ name ^ " = " ^ exported ^ "\n      end\n") end
                in SubsetResult.andThen (body, fn body => SubsetResult.map (emit rest, fn text =>
                  "  basis " ^ scopeName name ^ " = bas\n    local\n" ^ body ^ "    end\n  end\n" ^ text)) end)
      and nameOf = fn unit => name unit
    in SubsetResult.map (emit modules, fn text =>
      "local\n  basis SubsetBuild_Standard = bas $(SML_LIB)/basis/basis.mlb end\n" ^ text ^
      "in\n  open SubsetBuild_Standard " ^ scopeName (name entry) ^ "\nend\n") end

  val metadata = fn dependencies =>
    if SubsetList.isEmpty dependencies then "" else
      "(* @subsetml\n" ^ SubsetString.concat (SubsetList.map (dependencies, fn unit =>
        "from \"./" ^ output unit ^ "\" import * as " ^ name unit ^ ";\n")) ^ "*)\n\n"
end
