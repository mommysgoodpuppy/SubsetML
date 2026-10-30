(* WON conformance probe: the same SubsetML source runs natively and as generated Workman. *)
structure WonProbe = struct
  open SubsetOptionValue


  (* Text values are UTF-8 bytes; these fixtures spell them as byte strings. *)
  val text = fn s => SubsetWonValue.Text (SubsetResult.getOr (SubsetString.fromNative s, []))

  (* Semantic fixture is constructed independently of the parser, on both runtimes. *)
  val request = fn () =>
    SubsetWonValue.Tag (
      "Request",
      [("id", SubsetWonValue.Number "9007199254740993123456789")],
      SubsetWonValue.Record [
        ("method", text "save"),
        ("allBytes", SubsetWonValue.Blob SubsetChar.byteChars),
        (
          "asciiText",
          SubsetWonValue.Text (SubsetResult.getOr (SubsetList.take (SubsetChar.byteChars, 128), []))
        ),
        ("precise", SubsetWonValue.Number "-0.12345678901234567890123456789e400"),
        ("payload", SubsetWonValue.Blob [#"\^@", #"\255", #"\128", #"\"", #"\\", #"\n"]),
        ("unicode", text "caf\195\169 \240\159\152\128"),
        (
          "view",
          SubsetWonValue.Tag (
            "Paragraph",
            [],
            SubsetWonValue.List [
              text "Click ",
              SubsetWonValue.Tag ("Strong", [("enabled", SubsetWonValue.Boolean true)], text "Save"),
              text " to continue.",
              SubsetWonValue.Tag ("Ready", [], SubsetWonValue.Null)
            ]
          )
        ),
        (
          "empty",
          SubsetWonValue.List [SubsetWonValue.Null, SubsetWonValue.Record [], SubsetWonValue.List [], text "", SubsetWonValue.Blob []]
        ),
        ("strange key\n", text "quote: \" slash: \\ tab:\t NUL:\^@")
      ]
    )
  val response = fn () =>
    SubsetWonValue.Tag (
      "Response",
      [("id", SubsetWonValue.Number "9007199254740993123456789")],
      SubsetWonValue.List [SubsetWonValue.Boolean true, request ()]
    )
  val normalize = fn source =>
    (case SubsetWon.decode source of
        SubsetResult.Ok v =>
          (case SubsetWon.encode v of
              SubsetResult.Ok output => (true, output)
            | SubsetResult.Err e => (false, e))
      | SubsetResult.Err e => (false, #message e))
  val check = fn (source, expected) =>
    (case SubsetWon.decode source of
        SubsetResult.Ok v => v = expected
      | SubsetResult.Err _ => false)
  val output = fn v =>
    (case SubsetWon.encode v of
        SubsetResult.Ok s => (true, s)
      | SubsetResult.Err e => (false, e))
  (* Access chains: paths in problems, missing versus mismatched, and present null. *)
  val access = fn () =>
    let
      val is = fn (found, expected) =>
        SubsetResult.mapErr (found, SubsetWon.problemText) = expected
      val doc = SubsetWon.read "{server = {port = 8080} items = [1 X<id = 2>(\"y\")] none = null \"odd key\" = true}"
      val items = SubsetWon.get (doc, "items")
      val wrong = SubsetWon.text (SubsetWon.get (items, "x"))
      val unicode = SubsetResult.getOr (SubsetString.fromNative "caf\195\169 \240\159\152\128", [])
      val checks = [
        is (SubsetWon.number (SubsetWon.get (SubsetWon.get (doc, "server"), "port")), SubsetResult.Ok "8080"),
        is (
          SubsetWon.boolean (SubsetWon.get (SubsetWon.get (doc, "server"), "debug")),
          SubsetResult.Err "server.debug: missing"
        ),
        is (wrong, SubsetResult.Err "items: expected record"),
        is (SubsetWon.number (SubsetWon.attribute (SubsetWon.index (items, 1), "id")), SubsetResult.Ok "2"),
        is (SubsetWon.text (SubsetWon.payload (SubsetWon.index (items, 1))), SubsetResult.Ok [#"y"]),
        is (SubsetWon.textString (SubsetWon.payload (SubsetWon.index (items, 1))), SubsetResult.Ok "y"),
        is (
          SubsetWon.textString (SubsetWon.root (SubsetWonValue.Text [#"\255"])),
          SubsetResult.Err "document: expected UTF-8 text"
        ),
        is (SubsetWon.textString (SubsetWon.get (doc, "none")), SubsetResult.Err "none: expected text"),
        (case SubsetResult.andThen (SubsetText.fromUtf8 unicode, SubsetText.toUtf8) of
            SubsetResult.Ok bytes => bytes = unicode
          | SubsetResult.Err _ => false),
        not (SubsetResult.isOk (SubsetText.fromUtf8 [#"a", #"\255"])),
        is (SubsetWon.tagName (SubsetWon.index (items, 1)), SubsetResult.Ok "X"),
        is (SubsetWon.number (SubsetWon.index (items, 5)), SubsetResult.Err "items[5]: missing"),
        is (
          SubsetWon.value (SubsetWon.get (SubsetWon.get (doc, "odd key"), "x")),
          SubsetResult.Err "\"odd key\": expected record"
        ),
        is (
          SubsetWon.optional (SubsetWon.text (SubsetWon.get (SubsetWon.get (doc, "nope"), "deeper"))),
          SubsetResult.Ok NONE
        ),
        is (
          SubsetWon.optional (SubsetWon.value (SubsetWon.get (doc, "none"))),
          SubsetResult.Ok (SOME SubsetWonValue.Null)
        ),
        is (SubsetWon.optional wrong, SubsetResult.Err "items: expected record"),
        is (
          SubsetResult.map (SubsetWon.items items, fn xs => (SubsetList.length xs = 2)),
          SubsetResult.Ok true
        ),
        is (
          SubsetResult.map (SubsetWon.entries doc, fn xs => (SubsetList.length xs = 4)),
          SubsetResult.Ok true
        ),
        is (SubsetWon.number (SubsetWon.root SubsetWonValue.Null), SubsetResult.Err "document: expected number"),
        is (SubsetWon.value (SubsetWon.read "{"), SubsetResult.Err "byte 1: expected name")
      ]
    in
      SubsetList.all (checks, fn ok => ok)
    end
  val selftest = fn () =>
    let
      val good = [
        (
          "[Ready [1 2]]",
          SubsetWonValue.List [
            SubsetWonValue.Tag ("Ready", [], SubsetWonValue.Null),
            SubsetWonValue.List [SubsetWonValue.Number "1", SubsetWonValue.Number "2"]
          ]
        ),
        ("Title(\"Settings\")", SubsetWonValue.Tag ("Title", [], text "Settings")),
        ("X[1]", SubsetWonValue.Tag ("X", [], SubsetWonValue.List [SubsetWonValue.Number "1"])),
        ("Meta<a = true>", SubsetWonValue.Tag ("Meta", [("a", SubsetWonValue.Boolean true)], SubsetWonValue.Null)),
        (
          "[1/* outer /* inner */ end */2 // line\n 3]",
          SubsetWonValue.List [SubsetWonValue.Number "1", SubsetWonValue.Number "2", SubsetWonValue.Number "3"]
        ),
        ("x\"00ff\"", SubsetWonValue.Blob [#"\^@", #"\255"]),
        (
          "[Ready,[1, 2,]]",
          SubsetWonValue.List [
            SubsetWonValue.Tag ("Ready", [], SubsetWonValue.Null),
            SubsetWonValue.List [SubsetWonValue.Number "1", SubsetWonValue.Number "2"]
          ]
        ),
        ("[1E+5 -0.5e-3]", SubsetWonValue.List [SubsetWonValue.Number "1E+5", SubsetWonValue.Number "-0.5e-3"])
      ]
      val invalidValues = [
        SubsetWonValue.Number "true",
        SubsetWonValue.Number "1 2",
        SubsetWonValue.Text [#"\255"],
        SubsetWonValue.Tag ("null", [], SubsetWonValue.Null),
        SubsetWonValue.Tag ("bad name", [], SubsetWonValue.Null),
        SubsetWonValue.Record [("x", SubsetWonValue.Null), ("x", SubsetWonValue.Null)],
        SubsetWonValue.Tag ("X", [("x", SubsetWonValue.Null), ("x", SubsetWonValue.Null)], SubsetWonValue.Null)
      ]
      val positions = case SubsetWon.decode "[1 02]" of
          SubsetResult.Err e => (#offset e = 3)
        | _ => false
    in
      case (
        case (
          case (SubsetList.all (good, fn (s, v) => check (s, v)), positions) of
              (true, true) => true
            | _ => false,
          access ()
        ) of
            (true, true) => true
          | _ => false,
        SubsetList.all (invalidValues, fn v => not (SubsetResult.isOk (SubsetWon.encode v)))
      ) of
          (true, true) => true
        | _ => false
    end
  val run = fn (mode, source) =>
    (case mode of
        "selftest" =>
          if selftest () then (true, "ok") else (false, "semantic selftest failed")
      | "emit" => output (request ())
      | "reply" =>
          if check (source, request ()) then
            output (response ())
          else
            (false, "request differs from fixture")
      | "check" =>
          if check (source, response ()) then
            (true, "ok")
          else
            (false, "response differs from fixture")
      | "normalize" => normalize source
      | _ => (false, "unknown probe mode: " ^ mode))
end
