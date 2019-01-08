use v6.c;

use MONKEY-SEE-NO-EVAL;

use GTK::Application;

use VisualGrammar;

my $a = GTK::Application.new( title => 'org.genex.visual_grammar' );
$a.activate.tap({
  my $v = VisualGrammar.new(
    window => $a.window, width => 800, height => 400, app => $a
  );
  $a.window.show_all;
});

$a.run;
