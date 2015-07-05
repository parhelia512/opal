opal_filter "Integer" do
  fails "Integer#chr with an encoding argument converts a String to an Encoding as Encoding.find does"
  fails "Integer#chr with an encoding argument raises RangeError if self is invalid as a codepoint in the specified encoding"
  fails "Integer#chr with an encoding argument raises a RangeError is self is less than 0"
  fails "Integer#chr with an encoding argument returns a String encoding self interpreted as a codepoint in the specified encoding"
  fails "Integer#chr with an encoding argument returns a String with the specified encoding"
  fails "Integer#chr with an encoding argument returns a new String for each call"
  fails "Integer#chr without argument raises a RangeError is self is less than 0"
  fails "Integer#chr without argument returns a new String for each call"
  fails "Integer#chr without argument when Encoding.default_internal is nil and self is between 0 and 127 (inclusive) returns a String encoding self interpreted as a US-ASCII codepoint"
  fails "Integer#chr without argument when Encoding.default_internal is nil and self is between 0 and 127 (inclusive) returns a US-ASCII String"
  fails "Integer#chr without argument when Encoding.default_internal is nil and self is between 128 and 255 (inclusive) returns a String containing self interpreted as a byte"
  fails "Integer#chr without argument when Encoding.default_internal is nil and self is between 128 and 255 (inclusive) returns an ASCII-8BIT String"
  fails "Integer#chr without argument when Encoding.default_internal is nil raises a RangeError is self is greater than 255"
  fails "Integer#chr without argument when Encoding.default_internal is not nil and self is between 0 and 127 (inclusive) returns a String encoding self interpreted as a US-ASCII codepoint"
  fails "Integer#chr without argument when Encoding.default_internal is not nil and self is between 0 and 127 (inclusive) returns a String encoding self interpreted as a US-ASCII codepoint"
  fails "Integer#chr without argument when Encoding.default_internal is not nil and self is between 0 and 127 (inclusive) returns a US-ASCII String"
  fails "Integer#chr without argument when Encoding.default_internal is not nil and self is between 0 and 127 (inclusive) returns a US-ASCII String"
  fails "Integer#chr without argument when Encoding.default_internal is not nil and self is between 128 and 255 (inclusive) returns a String containing self interpreted as a byte"
  fails "Integer#chr without argument when Encoding.default_internal is not nil and self is between 128 and 255 (inclusive) returns a String containing self interpreted as a byte"
  fails "Integer#chr without argument when Encoding.default_internal is not nil and self is between 128 and 255 (inclusive) returns an ASCII-8BIT String"
  fails "Integer#chr without argument when Encoding.default_internal is not nil and self is between 128 and 255 (inclusive) returns an ASCII-8BIT String"
  fails "Integer#chr without argument when Encoding.default_internal is not nil and self is greater than 255 raises RangeError if self is invalid as a codepoint in the default internal encoding"
  fails "Integer#chr without argument when Encoding.default_internal is not nil and self is greater than 255 raises RangeError if self is invalid as a codepoint in the default internal encoding"
  fails "Integer#chr without argument when Encoding.default_internal is not nil and self is greater than 255 returns a String encoding self interpreted as a codepoint in the default internal encoding"
  fails "Integer#chr without argument when Encoding.default_internal is not nil and self is greater than 255 returns a String encoding self interpreted as a codepoint in the default internal encoding"
  fails "Integer#chr without argument when Encoding.default_internal is not nil and self is greater than 255 returns a String with the default internal encoding"
  fails "Integer#chr without argument when Encoding.default_internal is not nil and self is greater than 255 returns a String with the default internal encoding"
  fails "Integer#denominator returns 1"
  fails "Integer#gcd accepts a Bignum argument"
  fails "Integer#gcd works if self is a Bignum"
  fails "Integer#gcdlcm accepts a Bignum argument"
  fails "Integer#gcdlcm raises a TypeError unless the argument is an Integer"
  fails "Integer#gcdlcm returns [self, self] if self is equal to the argument"
  fails "Integer#gcdlcm returns a two-element Array"
  fails "Integer#gcdlcm returns an Array"
  fails "Integer#gcdlcm returns the greatest common divisor of self and argument as the first element"
  fails "Integer#gcdlcm returns the least common multiple of self and argument as the last element"
  fails "Integer#gcdlcm works if self is a Bignum"
  fails "Integer#lcm accepts a Bignum argument"
  fails "Integer#lcm works if self is a Bignum"
  fails "Integer#numerator returns self"
  fails "Integer#odd? returns true when self is an odd number"
  fails "Integer#rationalize ignores a single argument"
  fails "Integer#rationalize raises ArgumentError when passed more than one argument"
  fails "Integer#rationalize returns a Rational object"
  fails "Integer#rationalize uses 1 as the denominator"
  fails "Integer#rationalize uses self as the numerator"
  fails "Integer#round calls #to_int on the argument to convert it to an Integer"
  fails "Integer#round raises a RangeError when passed Float::INFINITY"
  fails "Integer#round raises a RangeError when passed a beyond signed int"
  fails "Integer#round raises a TypeError when #to_int does not return an Integer"
  fails "Integer#round raises a TypeError when its argument cannot be converted to an Integer"
  fails "Integer#round raises a TypeError when passed a String"
  fails "Integer#round returns itself rounded if passed a negative value"
  fails "Integer#round rounds itself as a float if passed a positive precision"
  fails "Integer#to_r constructs a rational number with 1 as the denominator"
  fails "Integer#to_r constructs a rational number with self as the numerator"
  fails "Integer#to_r raises an ArgumentError if given any arguments"
  fails "Integer#to_r returns a Rational object"
  fails "Integer#to_r works even if self is a Bignum"
  fails "Integer#truncate returns self"
end