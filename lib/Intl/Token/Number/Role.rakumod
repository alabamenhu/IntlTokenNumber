unit role LocalNumber;

has $.base-number;
has $.exponent;
has $.number-type;
has $!value;

method SETUP-NUMBER($number,$type, $!exponent) {
    $!base-number = $number;
    $!number-type = $type;

    given $type {
        when 'standard'    { $!value = $number                    }
        when 'percent'     { $!value = $number / 100              }
        when 'permille'    { $!value = $number / 1000             }
        when 'exponential' { $!value = $number * 10 ** $!exponent }
    }
}

method Numeric { $!value }
method Int     { $!value.Int     }
method Num     { $!value.Num     }
method Complex { $!value.Complex }
method Rat     { $!value.Rat     }
method FatRat  { $!value.FatRat  }
