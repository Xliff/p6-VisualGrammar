use v6.c;

use MONKEY-SEE-NO-EVAL;

unit package Evals;

use Grammar::Gatherer;

# A grammar to parse grammars? -- Food for thought.

sub format-code ($code) {
  my @c;
  my $len = $code.lines.elems.Str.chars;
  for $code.lines.kv -> $k, $v {
    @c.push: "{ ($k + 1).fmt("\%{$len}d") }: { $v }";
  }
  @c.join("\n");
}

sub run-grammar($text, $gtext is copy, @rules, %counts) is export {

  # -YYY- TODO: Extract grammar statement from $gtext to limit code injection
  # possibilities.

  my token unit { 'unit' }
  my $nr = $gtext ~~ /^^ \s* [ <unit> \s+ ]? 'grammar' \s+ (<[\-\w]>+)/;
  my $name = $nr.defined ?? $nr[0] !! Nil;
  die "Cannot find grammar name!\n" without $name;

  if $nr<unit>.defined {
    # Convert from unit form to block form.
    $gtext ~~ /^^ <unit> \s 'grammar' \s+ \w+ ';' (.+) $$/;
    $gtext = qq:to/G/.chomp
      my grammar { $name } \{
      \t{ $/[0].split(/\n/).join("\t\n") }
      \}
      G

  } else {
    # Insure grammar is scope limited.
    $gtext ~~ s/^^ (.+?) 'grammar'//;
    $gtext = "my { $gtext }";
  }

  my $code = qq:to/CODE/.chomp;
use Grammar::Gatherer;
class Action \{
  has \%.counts;
  method FALLBACK (\$name, |c) \{
      \%!counts\{\$name\}++;
  \}
\}
my \$a = Action.new;
{ $gtext }
\@rules = { $name }.^methods(:local).map( *.name ).sort;
{ $name }.parse(\$text, actions => \$a);
\%counts = \$a.counts;
{ $name }.HOW.results;
CODE

  say format-code($code);

  EVAL $code;
}
