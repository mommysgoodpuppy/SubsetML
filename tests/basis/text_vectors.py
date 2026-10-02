"""Generate portable SubsetML vectors using Python's independent strict UTF codecs."""
import random
import sys

rng = random.Random(82516)

def number(value):
    return str(value) + '.0'

def bytes_literal(data):
    return '[' + ', '.join('#"\\%03d"' % b for b in data) + ']'

def scalars_literal(values):
    return '[' + ', '.join(number(n) for n in values) + ']'

boundaries = [0, 1, 127, 128, 255, 256, 2047, 2048, 55295, 57344,
              65533, 65534, 65535, 65536, 128512, 1114110, 1114111]
cases = [[], boundaries] + [[n] for n in boundaries]
for _ in range(100):
    values = []
    for _ in range(rng.randrange(1, 12)):
        n = rng.randrange(1114112)
        if not 55296 <= n <= 57343:
            values.append(n)
    cases.append(values)

print('structure TextVectors = struct')
print('  val same = fn (actual, expected) =>')
print('    case SubsetListPair.zip (actual, expected) of')
print('      SubsetResult.Err error => false')
print('    | SubsetResult.Ok pairs => SubsetList.all (pairs, fn (a, b) => Real.== (a, b))')
print('  val cases = [')
rows = []
for values in cases:
    text = ''.join(chr(n) for n in values)
    rows.append('    (' + ', '.join([scalars_literal(values)] +
        [bytes_literal(text.encode(codec)) for codec in ['utf-8', 'utf-16-le', 'utf-16-be']]) + ')')
print(',\n'.join(rows) + ']')
print('''  val valid = SubsetList.all (cases, fn (scalars, utf8, little, big) =>
    (case SubsetUtf8.encode scalars of SubsetResult.Ok bytes => bytes = utf8 | SubsetResult.Err error => false)
    andalso (case SubsetUtf8.decode utf8 of SubsetResult.Ok values => same (values, scalars) | SubsetResult.Err error => false)
    andalso (case SubsetUtf16.encode (scalars, SubsetUtf16.LittleEndian) of SubsetResult.Ok bytes => bytes = little | SubsetResult.Err error => false)
    andalso (case SubsetUtf16.decode (little, SubsetUtf16.LittleEndian) of SubsetResult.Ok values => same (values, scalars) | SubsetResult.Err error => false)
    andalso (case SubsetUtf16.encode (scalars, SubsetUtf16.BigEndian) of SubsetResult.Ok bytes => bytes = big | SubsetResult.Err error => false)
    andalso (case SubsetUtf16.decode (big, SubsetUtf16.BigEndian) of SubsetResult.Ok values => same (values, scalars) | SubsetResult.Err error => false))''')

# Strict decoding agreement, including arbitrary binary data and truncated encodings.
raw = [bytes([n]) for n in range(256)]
raw += [bytes(rng.randrange(256) for _ in range(rng.randrange(0, 9))) for _ in range(140)]
for values in cases[1:20]:
    for codec in ['utf-8', 'utf-16-le', 'utf-16-be']:
        data = ''.join(chr(n) for n in values).encode(codec)
        raw += [data[:n] for n in range(len(data) + 1)]
raw = sorted(set(raw))
print('  val binaryCases = [')
rows = []
for data in raw:
    answers = []
    for codec in ['utf-8', 'utf-16-le', 'utf-16-be']:
        try:
            values = [ord(c) for c in data.decode(codec)]
            answers.append('SOME ' + scalars_literal(values))
        except UnicodeDecodeError:
            answers.append('NONE')
    rows.append('    (' + ', '.join([bytes_literal(data)] + answers) + ')')
print(',\n'.join(rows) + ']')
print('''  val bridge = fn bytes =>
    case SubsetString.toNative bytes of
      SubsetResult.Err error => false
    | SubsetResult.Ok value =>
        (case SubsetString.fromNative value of SubsetResult.Ok actual => actual = bytes | SubsetResult.Err error => false)
        andalso (case SubsetSource.fromNative value of
          SubsetResult.Err error => false
        | SubsetResult.Ok source =>
            Real.== (SubsetSource.length source, SubsetBytes.length bytes)
            andalso (case SubsetSource.slice (source, 0.0, SubsetBytes.length bytes) of
              SubsetResult.Ok actual => actual = bytes | SubsetResult.Err error => false)
            andalso (let val (checked, count) = SubsetList.foldLeft (bytes, (true, 0.0), fn (c, (checked, index)) =>
              (checked andalso (case SubsetSource.at (source, index) of SubsetResult.Ok actual => actual = c | SubsetResult.Err error => false), index + 1.0))
            in checked end))
  val matches = fn (result, expected) => case (result, expected) of
      (SubsetResult.Ok values, SOME scalars) => same (values, scalars)
    | (SubsetResult.Err error, NONE) => true
    | (SubsetResult.Ok values, NONE) => false
    | (SubsetResult.Err error, SOME scalars) => false
  val binary = SubsetList.all (binaryCases, fn (bytes, utf8, little, big) =>
    bridge bytes andalso matches (SubsetUtf8.decode bytes, utf8)
    andalso matches (SubsetUtf16.decode (bytes, SubsetUtf16.LittleEndian), little)
    andalso matches (SubsetUtf16.decode (bytes, SubsetUtf16.BigEndian), big))
  val _ = if valid andalso binary then print "text reference vectors: ok\\n" else print "FAILED\\n"
end''')
