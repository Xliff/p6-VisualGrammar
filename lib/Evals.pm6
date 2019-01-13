use v6.c;

use MONKEY-SEE-NO-EVAL;

unit package Evals;

use Grammar::Gatherer;

# A grammar to parse grammars? -- Food for thought.

sub format-code ($code) {
  my @c;
  my $len = $code.lines.elems.Str.chars;
  for $code.lines.kv -> $k, $v {
    @c.push: "{ $k.fmt("\%{$len}d") }: { $v }";
  }
  @c.join("\n");
}

sub run-grammar($text, $gtext, @rules) is export {

  # -YYY- TODO: Extract grammar statement from $gtext to limit code injection
  # possibilities.

  my $name = ($gtext ~~ /^^ \s* 'grammar' \s+ (\w+)/ // [])[0].Str;
  die "Cannot find grammar name!\n" without $name;
  my $code = qq:to/CODE/.chomp;
use Grammar::Gatherer;
my { $gtext }
\@rules = { $name }.^methods(:local).map( *.name ).sort;
{ $name }.parse(\$text);
{ $name }.HOW.results;
CODE

  say format-code($code);

  EVAL $code;
}
