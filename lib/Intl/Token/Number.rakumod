unit module Number;

    use Intl::CLDR;
    use User::Language;
    use experimental :rakuast;

# This represents the Unicode character ID of the zero in these decimal systems
constant DIGITS = %(
    adlm     => 125264, ahom     => 71472,  arab     => 1632,   arabext  => 1776,
    bali     => 6992,   beng     => 2534,   bhks     => 72784,  brah     => 69734,
    cakm     => 69942,  cham     => 43600,  deva     => 2406,   diak     => 72016,
    fullwide => 65296,  gong     => 73120,  gonm     => 73040,  gujr     => 2790,
    guru     => 2662,   hanidec  => 12295,  hmng     => 93008,  hmnp     => 123200,
    java     => 43472,  kali     => 43264,  kawi     => 73552,  khmr     => 6112,
    knda     => 3302,   lana     => 6784,   lanatham => 6800,   laoo     => 3792,
    latn     => 48,     lepc     => 7232,   limb     => 6470,   mathbold => 120782,
    mathdbl  => 120792, mathmono => 120822, mathsanb => 120812, mathsans => 120802,
    mlym     => 3430,   modi     => 71248,  mong     => 6160,   mroo     => 92768,
    mtei     => 44016,  mymr     => 4160,   mymrshan => 4240,   mymrtlng => 43504,
    nagm     => 124144, newa     => 70736,  nkoo     => 1984,   olck     => 7248,
    orya     => 2918,   osma     => 66720,  rohg     => 68912,  saur     => 43216,
    segment  => 130032, shrd     => 70096,  sind     => 70384,  sinh     => 3558,
    sora     => 69872,  sund     => 7088,   takr     => 71360,  talu     => 6608,
    tamldec  => 3046,   telu     => 3174,   thai     => 3664,   tibt     => 3872,
    tirh     => 70864,  tnsa     => 92864,  vaii     => 42528,  wara     => 71904,
    wcho     => 123632);
sub regex-block(*@statements) {
    RakuAST::Regex::Block.new(
        RakuAST::Block.new(
            body => RakuAST::Blockoid.new(
                RakuAST::StatementList.new(|@statements)
    )   )   )
}


my %cache;
my sub generate-local-number-regex { ... }
my sub local-number-regex (\tag) {
    .return with %cache{tag};
    %cache{tag} = generate-local-number-regex tag;
}
our token local-number (\tag = INIT user-language) is export {
    :my $*number = 0;
    :my $*type = 'standard';
    :my $*exponent = 1;
    :my $*sign = 1;
    <{local-number-regex tag}>
    {
        use Intl::Token::Number::Role;
        $/ does LocalNumber;
        $/.SETUP-NUMBER: $*number, $*type, $*exponent
    }
}

sub generate-local-number-regex(\tag) {
    # Per CLDR's norms, the effective regex for decimal system is
    # / [<negative> | <positive>]?   <integer>    [ <decimal><fraction>? ]?
    #
    #   [ <.ws>?
    #        [
    #        |   <percent>
    #        |   <permille>
    #        | [ <&e-symbol> <.ws>? <exponent> ]
    #        ]
    #   ]?
    # /
    # Each is a hard symbol, except for integer/fraction/exponent, which is the set of digits
    # (maybe with added grouping digit, e.g., a comma in English.
    # Thus we go ahead and grab these
    my \numbers = cldr{tag}.numbers;
    my \system  = numbers.numbering-systems.default;
    my \symbols = numbers.symbols{system};

    my \PERCENT-SYMBOL  = symbols.percent;
    my \PERMILLE-SYMBOL = symbols.permille;
    my \PLUS-SYMBOL     = symbols.plus;
    my \MINUS-SYMBOL    = symbols.minus;
    my \EXPONENT-SYMBOL = symbols.exponential;
    my \GROUPING-SYMBOL = symbols.group;
    my \DECIMAL-SYMBOL  = symbols.decimal;
    my \ZERO-START      = DIGITS{system};  # we only need the .ord of 0 for decimal systems

    # First we define the sign.  Deparsed:
    #     | '-' {$sign = -1}
    #     | '+'
    # We will set $sign by default to be 1, so no need to modify it here unless negative
    my $sign = RakuAST::Regex::QuantifiedAtom.new(
        quantifier => RakuAST::Regex::Quantifier::ZeroOrOne.new,
        atom => RakuAST::Regex::Group.new(
            RakuAST::Regex::Alternation.new(
                RakuAST::Regex::Sequence.new(
                    RakuAST::Regex::Literal.new(MINUS-SYMBOL),
                    regex-block(
                        RakuAST::Statement::Expression.new(
                            expression => RakuAST::ApplyInfix.new(
                                left => RakuAST::Var::Dynamic.new('$*sign'),
                                infix => RakuAST::Infix.new('='),
                                right => RakuAST::IntLiteral.new(-1)
                            )
                        )
                    )
                ),
                RakuAST::Regex::Literal.new(PLUS-SYMBOL)
            )
        ),
    );

    # Next we define digits.  This is a simple quantified atom, deparsed as
    #     <[0..9]>+
    # where the 0..9 may be something else (e.g. ๐..๙ if detecting thai digits).
    # this will be reused several times.
    my $digits = RakuAST::Regex::QuantifiedAtom.new(
        quantifier => RakuAST::Regex::Quantifier::OneOrMore.new,
        atom => RakuAST::Regex::Assertion::CharClass.new(
            RakuAST::Regex::CharClassElement::Enumeration.new(
                elements => (
                    RakuAST::Regex::CharClassEnumerationElement::Range.new(
                        from => ZERO-START,
                        to   => ZERO-START+9
                    ),
                )
            )
        )
    );

    # Define a function that counts the digits.  Deparses as
    #    { $<group>.tail.chars }
    # Basically, grab the last group of digits.  Only used with integer digits
    my $digit-count = RakuAST::ApplyPostfix.new(
        postfix => RakuAST::Call::Method.new(
            name => RakuAST::Name.from-identifier('chars')
        ),
        operand => RakuAST::ApplyPostfix.new(
            postfix => RakuAST::Call::Method.new(
                name => RakuAST::Name.from-identifier('tail')
            ),
            operand => RakuAST::Var::NamedCapture.new(
                RakuAST::QuotedString.new(
                    processors => <words val>,
                    segments => (
                        RakuAST::StrLiteral.new("group"),
                    )
                )
            )
        )
    );

    # Gets the Int value of a group of digits.  Deparse as
    #    { $<group>.Str.Int }
    # Used only in integer digit calculations.  The Int is probably unnecessary
    my $digit-value = RakuAST::ApplyPostfix.new(
        postfix => RakuAST::Call::Method.new(
            name => RakuAST::Name.from-identifier('Int')
        ),
        operand => RakuAST::ApplyPostfix.new(
            postfix => RakuAST::Call::Method.new(
                name => RakuAST::Name.from-identifier('Str')
            ),
            operand => RakuAST::ApplyPostfix.new(
                postfix => RakuAST::Call::Method.new(
                    name => RakuAST::Name.from-identifier('tail'),
                ),
                operand => RakuAST::Var::NamedCapture.new(
                    RakuAST::QuotedString.new(
                        processors => <words val>,
                        segments => (
                            RakuAST::StrLiteral.new("group"),
                        )
                    )
                )
            )
        )
    );

    # Gets the integer value of the number. Deparse as
    #     [
    #         $<group>=<[0..9]>+
    #         {
    #             $number *= 10 ** $group.Str.chars;
    #             $number += $group.Str.Int;
    #         }
    #     ]+
    my $integer = RakuAST::Regex::QuantifiedAtom.new(
        quantifier => RakuAST::Regex::Quantifier::OneOrMore.new,
        separator => RakuAST::Regex::Literal.new(GROUPING-SYMBOL),
        atom => RakuAST::Regex::Group.new(
            RakuAST::Regex::Sequence.new(
                RakuAST::Regex::NamedCapture.new(
                    name => 'group',
                    regex => $digits
                ),
                regex-block(
                    RakuAST::Statement::Expression.new(
                        expression => RakuAST::ApplyInfix.new(
                            left => RakuAST::Var::Dynamic.new('$*number'),
                            infix => RakuAST::MetaInfix::Assign.new(
                                RakuAST::Infix.new('*')
                            ),
                            right => RakuAST::ApplyInfix.new(
                                left => RakuAST::IntLiteral.new(10),
                                infix => RakuAST::Infix.new('**'),
                                right => $digit-count
                            )
                        )
                    ),
                    RakuAST::Statement::Expression.new(
                        expression => RakuAST::ApplyInfix.new(
                            left => RakuAST::Var::Dynamic.new('$*number'),
                            infix => RakuAST::MetaInfix::Assign.new(
                                RakuAST::Infix.new('+')
                            ),
                            right => $digit-value
                        )
                    )
                )
            )
        )
    );


    # Gets the fractional digits, if any.  Defined as
    #     [
    #         '.'
    #         $fraction=<[0..9]>+
    #         { $number += $<fraction>.Str.Int / 10 ** $<fraction>.Str.char }
    #     ]?
    my $fraction = RakuAST::Regex::QuantifiedAtom.new(
        quantifier => RakuAST::Regex::Quantifier::ZeroOrOne.new,
        atom => RakuAST::Regex::Group.new(
            RakuAST::Regex::Sequence.new(
                RakuAST::Regex::NamedCapture.new(
                    name => 'fraction',
                    regex => $digits
                ),
                regex-block(
                    RakuAST::Statement::Expression.new(
                        expression => RakuAST::ApplyInfix.new(
                            left  => RakuAST::Var::Dynamic.new('$*number'),
                            infix => RakuAST::MetaInfix::Assign.new(
                                RakuAST::Infix.new('+')
                            ),
                            right => RakuAST::ApplyInfix.new(
                                left  => RakuAST::ApplyPostfix.new(
                                    operand => RakuAST::Var::NamedCapture.new(
                                        RakuAST::QuotedString.new(
                                            processors => <words val>,
                                            segments   => (
                                                RakuAST::StrLiteral.new('fraction'),
                                            )
                                        )
                                    ),
                                    postfix => RakuAST::Call::Method.new(
                                        name => RakuAST::Name.from-identifier('Str')
                                    )
                                ),
                                infix => RakuAST::Infix.new('/'),
                                right => RakuAST::ApplyInfix.new(
                                    left  => RakuAST::IntLiteral.new(10),
                                    infix => RakuAST::Infix.new('**'),
                                    right => RakuAST::ApplyPostfix.new(
                                        operand => RakuAST::Var::NamedCapture.new(
                                            RakuAST::QuotedString.new(
                                                processors => <words val>,
                                                segments   => (
                                                    RakuAST::StrLiteral.new('fraction'),
                                                )
                                            )
                                        ),
                                        postfix => RakuAST::Call::Method.new(
                                            name => RakuAST::Name.from-identifier('chars')
                                        )
                                    )
                                )
                            )
                        )
                    )
                )
            )
        )
    );
    my $decimal = RakuAST::Regex::QuantifiedAtom.new(
        quantifier => RakuAST::Regex::Quantifier::ZeroOrOne.new,
        atom => RakuAST::Regex::Group.new(
            RakuAST::Regex::Sequence.new(
                RakuAST::Regex::Literal.new(DECIMAL-SYMBOL),
                $fraction
            )
        )
    );

    my $percent = RakuAST::Regex::Sequence.new(
        RakuAST::Regex::Literal.new(PERCENT-SYMBOL),
        regex-block(
            RakuAST::Statement::Expression.new(
                expression => RakuAST::ApplyInfix.new(
                    left => RakuAST::Var::Dynamic.new('$*type'),
                    infix => RakuAST::Infix.new('='),
                    right => RakuAST::StrLiteral.new('percent')
                )
            )
        )
    );
    my $permille = RakuAST::Regex::Sequence.new(
        RakuAST::Regex::Literal.new(PERMILLE-SYMBOL),
        regex-block(
            RakuAST::Statement::Expression.new(
                expression => RakuAST::ApplyInfix.new(
                    left => RakuAST::Var::Dynamic.new('$*type'),
                    infix => RakuAST::Infix.new('='),
                    right => RakuAST::StrLiteral.new('permille')
                )
            )
        )
    );
    my $exponent = RakuAST::Regex::Sequence.new(
        RakuAST::Regex::Literal.new(EXPONENT-SYMBOL),
        RakuAST::Regex::QuantifiedAtom.new(
            atom => RakuAST::Regex::CharClass::HorizontalSpace.new,
            quantifier => RakuAST::Regex::Quantifier::ZeroOrMore.new
        ),
        RakuAST::Regex::QuantifiedAtom.new(
            atom => RakuAST::Regex::Group.new(
                RakuAST::Regex::Alternation.new(
                    RakuAST::Regex::Literal.new(PLUS-SYMBOL),
                    RakuAST::Regex::Sequence.new(
                        RakuAST::Regex::Literal.new(MINUS-SYMBOL),
                        regex-block(
                            RakuAST::Statement::Expression.new(
                                expression => RakuAST::ApplyInfix.new(
                                    left => RakuAST::Var::Dynamic.new('$*exponent'),
                                    infix => RakuAST::Infix.new('='),
                                    right => RakuAST::IntLiteral.new(-1)
                                )
                            )
                        )
                    )
                )
            ),
            quantifier => RakuAST::Regex::Quantifier::ZeroOrOne.new
        ),
        RakuAST::Regex::NamedCapture.new(
            name => 'exp-val',
            regex => $digits
        ),
        regex-block(
            RakuAST::Statement::Expression.new(
                expression => RakuAST::ApplyInfix.new(
                    left => RakuAST::Var::Dynamic.new('$*type'),
                    infix => RakuAST::Infix.new('='),
                    right => RakuAST::StrLiteral.new('exponential')
                )
            ),
            RakuAST::Statement::Expression.new(
                expression => RakuAST::ApplyInfix.new(
                    left => RakuAST::Var::Dynamic.new('$*exponent'),
                    infix => RakuAST::MetaInfix::Assign.new(
                        RakuAST::Infix.new('*')
                    ),
                    right => RakuAST::ApplyPostfix.new(
                        postfix => RakuAST::Call::Method.new(
                            name => RakuAST::Name.from-identifier('Int'),
                        ),
                        operand => RakuAST::ApplyPostfix.new(
                            postfix => RakuAST::Call::Method.new(
                                name => RakuAST::Name.from-identifier('Str'),
                            ),
                            operand => RakuAST::Var::NamedCapture.new(
                                RakuAST::QuotedString.new(
                                    processors => <words val>,
                                    segments   => (
                                        RakuAST::StrLiteral.new('exp-val'),
                                    )
                                )
                            )
                        )
                    )
                )
            ),
        )
    );

    # This simply combines the three extra types as one
    my $types = RakuAST::Regex::QuantifiedAtom.new(
        atom => RakuAST::Regex::Group.new(
            RakuAST::Regex::Sequence.new(
                RakuAST::Regex::QuantifiedAtom.new(
                    atom => RakuAST::Regex::CharClass::HorizontalSpace.new,
                    quantifier => RakuAST::Regex::Quantifier::ZeroOrMore.new
                ),
                RakuAST::Regex::Group.new(
                    RakuAST::Regex::Alternation.new(
                        $percent,
                        $permille,
                        $exponent,
                    ),
                )
            )
        ),
        quantifier => RakuAST::Regex::Quantifier::ZeroOrOne.new
    );


    use MONKEY-SEE-NO-EVAL;
    EVAL RakuAST::QuotedRegex.new(
        body => RakuAST::Regex::Group.new(
            RakuAST::Regex::Sequence.new(
                $sign,
                $integer,
                $decimal,
                $types,
            ),
        )
    )
}

