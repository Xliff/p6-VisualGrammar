use v6.c;

use GTK::Application;

use VisualGrammar;

my $a = GTK::Application.new( title => 'org.genex.visual_grammar' );
$a.activate.tap({
  my $v = VisualGrammar.new(
    window => $a.window, width => 800, height => 400, app => $a
  );

  # Remove after testing.
  $v.open-grammar-file('tg.g');
  $v.open-text-file('aaaa.txt');
  $v.refresh-grammar;

  $a.window.show_all;
});

$a.run;
