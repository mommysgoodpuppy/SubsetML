(* Portable SML Char algorithms, adapted to SubsetML.

   Classification and case conversion adapted from MLton basis-library/text/char.sml:
   Copyright (C) 2026 Matthew Fluet.
   Copyright (C) 1999-2007 Henry Cejtin, Matthew Fluet, Suresh Jagannathan, and Stephen Weeks.
   Copyright (C) 1997-2000 NEC Research Institute.
   MLton is released under a HPND-style license; see LICENSES/MLton.txt.

   The linear contains search is adapted from MLWorks src/basis/__pre_char.sml:
   Copyright 2013 Ravenbrook Limited. All rights reserved.
   BSD 2-Clause license; see LICENSES/MLWorks.txt.

   Host primitives are limited to string size/subscript and character code conversion,
   through Num. No arrays, functors, exceptions, integer values or unsafe access are used. *)
structure SmlChar = struct

  val compare = fn (c : char, d : char) =>
    if c < d then LESS else (if c > d then GREATER else EQUAL)

  val contains = fn s =>
    let val size = Num.String.size s in
      fn c =>
        let
          val rec search = fn i =>
            i < size andalso (Num.String.sub (s, i) = c orelse search (i + 1.0))
        in search 0.0 end
    end

  val notContains = fn s =>
    let val member = contains s in fn c => not (member c) end

  val isLower = fn c => #"a" <= c andalso c <= #"z"
  val isUpper = fn c => c <= #"Z" andalso #"A" <= c
  val isDigit = fn c => c <= #"9" andalso #"0" <= c
  val isGraph = fn c => #"!" <= c andalso c <= #"~"
  val isPrint = fn c => #" " <= c andalso c <= #"~"
  val isCntrl = fn c => c < #" " orelse c = #"\127"
  val isAscii = fn c => c <= #"\127"

  val isAlpha = fn c => if #"a" <= c then c <= #"z" else #"A" <= c andalso c <= #"Z"
  val isAlphaNum = fn c =>
    if #"A" <= c then (if #"a" <= c then c <= #"z" else c <= #"Z")
    else #"0" <= c andalso c <= #"9"
  val isHexDigit = fn c =>
    if #"A" <= c then (if #"a" <= c then c <= #"f" else c <= #"F")
    else #"0" <= c andalso c <= #"9"
  val isSpace = fn c => if #"\r" < c then c = #" " else #"\t" <= c
  val isPunct = fn c => isGraph c andalso not (isAlphaNum c)

  val toLower = fn c =>
    if isUpper c then Num.Char.chr (Num.Char.ord c - Num.Char.ord #"A" + Num.Char.ord #"a") else c
  val toUpper = fn c =>
    if isLower c then Num.Char.chr (Num.Char.ord c - Num.Char.ord #"a" + Num.Char.ord #"A") else c

end
