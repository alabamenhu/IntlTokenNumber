# Intl::Token::Number
A regex token for detecting localized numbers

To use, simply include the token `<local-number>` in anything interpreted as regex.

```raku
use Intl::Token::Number;

# (assuming English)
if '15,859,333.41' ~~ /<local-number>/ {
    say ~$<local-number>;  # 15,859,333.41   <-- stringified
    say +$<local-number>;  # 15859333.41     <-- numerical
}
```

The `<local-number>` token defaults to using the language provided by `user-language`.
This makes it quite useful for parsing CLI.  Sometimes, though, you'll want / need to specify the language directly.
Just include it after a colon:

```raku
# Korean uses commas to separate thousands
'1,234' ~~ /<local-number: 'ko'>/;
say +$<local-number>; # 1234

# Spanish uses commas to separate integers from fractionals
'1,234' ~~ /<local-number: 'es'>/;
say +$<local-number>; # 1.234
```

Formats including percents, permilles, and exponential notation are supported:

```raku
# Assuming English
'90%' ~~ /<local-number>/;
say +$<local-number>; # 0.9

'1.23E3' ~~ /<local-number>/;
say +$<local-number>; # 123
```

For those interested in details about the match, the match object is introspectable:
  * `base-number`: the number matched, ignoring percent/exponential modifiers
  * `exponent`: the exponent used (defaults to 1 for non-exponential numbers)
  * `number-type`: any of `standard`, `percent`, `permille`, `exponential`  

## To do
  * Add support for native/traditional/financial-style numbers
  * Add support for lenient parsing (e.g. accept any of `<,٫⹁︐﹐，>` for `,`).
    * This will be very important for languages like Finnish, which uses a non-breaking space, but is probably entered as a plain space by most people.
  * Enforce grouping digits? Present, *1,2,3,4* will parse as *1234*.
  * Additional formats like approximately, at least, etc.

## Version history

* **v0.6**
  * Optimized grammar
  * Now uses RakuAST for generation.
  * Match role provides more introspection
  * Now prefer `User::Language` to `Intl::UserLanguage`
* **v.0.5.0**
  * First published version as an independent module
  * Adapted to work with newest version of `Intl::CLDR`
  * Housekeeping 
     * Cleaned up code, added documentation, improved tests
* **v.0.4.2**
  * Renamed to **Intl::CLDR::Numbers**
* **v.0.4.1**
  * Published as a part of `Intl::CLDR` (as `Intl::CLDR::Numbers::NumberFinder`)
  * Support for basic number parsing using default numeric systems