(* The sized numeric types: word constants, Int64 and Real32, and Appendix E overloading over them. *)
structure SizedNumbers = struct
  val byte : Word8.word = 0w250
  val wrapped = byte + 0w10
  val masked = Word8.andb (byte, 0wx0F)
  val big : Int64.int = 9000000000
  val product = big * 3
  val half : Real32.real = 1.5
  val third = half / 3.0
  val divided = (0w17 : Word16.word) div 0w5
  val count = 1 + 2
  val ratio = 7.0 / 2.0
  val classify = fn (0w0 : Word32.word) => "zero" | _ => "other"
  val negated = ~ big
end
