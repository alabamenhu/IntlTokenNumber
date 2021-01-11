# Need to manually export to properly wrap the token
sub EXPORT {
    use Intl::CLDR;
    use Intl::Token::Util::Digits;
    use Intl::UserLanguage;

    my token negative { $( $*symbols.minus        ) }
    my token positive { $( $*symbols.plus         ) }
    my token decimal  { $( $*symbols.decimal      ) }
    my token group    { $( $*symbols.group        ) }
    my token digit    { @( @*digits )               }
    my token integer  { [$<groupings>=[<&digit>+]]+
                         % <&group>                 }
    my token fraction {    <&digit>+                }
    my token percent  { $( $*symbols.percent      ) }
    my token permille { $( $*symbols.permille     ) }
    my token e-symbol { $( $*symbols.exponential  ) }
    my token exponent { [
                        | $<negative> = <&negative>
                        | $<positive> = <&positive>
                        ]?
                        $<integer>=<&integer>       }

    #| Provides override for the standard numeric classes
    role LocalNumeric[$number] {
        method Numeric { $number         }
        method Int     { $number.Int     }
        method Num     { $number.Num     }
        method Complex { $number.Complex }
        method Rat     { $number.Rat     }
        method FatRat  { $number.FatRat  }
    }

    # This is the only method we export to avoid contaminating the namespace
    my token local-number ($*locale = INIT user-language) {

        :my \numbers   = cldr{$*locale}.numbers;
        :my $system    = numbers.numbering-systems.default;
        :my $*symbols := numbers.symbols{$system};
        :my @*digits  := %digits{$system};

        [<negative> | <positive>]?
        <integer>
        [ <decimal><fraction>? ]?

        # After the base number, we can also grab a percent/permille
        # or an exponent.  These maybe should be specified individually
        # with a flag later on, but for now we grab everything
        [
            <.ws>?
            [
            |   <percent>
            |   <permille>
            | [ <&e-symbol> <.ws>? <exponent> ]
            ]
        ]?

        # When wrapping the token, we don't get access to sub-matches for some reason
        # This gives us that access.
        { $*match := $¢ }
    }

    &local-number.wrap(
        sub (|) {
            # When wrapping, we don't get access to sub-matches for some reason.
            # This gives us access
            my $*match;

            my \match := callsame;      # must use sigil-less because Grammars do not like containerized Matches
            return match unless match;  # immediate toss back if failed
            $/ := $*match;              # QOL

            my $number;
            $number  = +$<integer><groupings>.join;
            $number += +~$_ / (10 ** .chars) with $<fraction>;

            # Mutually exclusive conditions
            with   $<percent>  {    $number *= 0.01               }
            orwith $<permille> {    $number *= 0.001              }
            orwith $<exponent> { my $power   = +~.<integer>;
                                    $power  *= -1 with .<negative>;
                                    $number *= 10 ** $power;
                               }

            match does LocalNumeric[$number]
        }
    );

    # Export the token in its wrapped form
    Map.new: '&local-number' => &local-number
}
