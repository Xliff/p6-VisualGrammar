use v6.c;

use MONKEY-SEE-NO-EVAL;

use GTK::Compat::Types;
use GTK::Raw::Types;

use GTK::Application;
use GTK::Box;
use GTK::Clipboard;
use GTK::Dialog::FileChooser;
use GTK::Menu;
use GTK::MenuBar;
use GTK::Pane;
use GTK::ScrolledWindow;
use GTK::TextTag;
use GTK::TextView;

use GTK::Utils::MenuBuilder;

class VisualGrammar {
  has GTK::Application    $!app;
  has GTK::Pane           $!hpane;
  has GTK::Pane           $!vpane;
  has GTK::TextView       $!gedit;
  has GTK::TextView       $!tview;
  has GTK::TextView       $!mview;
  has GTK::ScrolledWindow $!gscroll;
  has GTK::ScrolledWindow $!tscroll;
  has GTK::ScrolledWindow $!mscroll;
  has GTK::Clipboard      $!clip;
  has GTK::TextBuffer     $!mbuffer;
  has GTK::TextBuffer     $!tbuffer;

  has @!rules;
  has %!tags;

  has $!paste-text;

  method FALLBACK ($name, |c) {
    say "NYO -- { $name } method NYI!";
  }

  method quit              { $!app.exit               }
  method close-file        { $!gedit.text = ''        }
  method open-grammar-file { self.slurp-file($!gedit) }
  method open-text-file    { self.slurp-file($!tview) }
  method save-grammar-file { self.spurt-file($!gedit) }
  method save-text-file    { self.spurt-file($!tview) }
  method clear-msgs        { $!mview.text = '';       }

  method paste             { $!tview.text = $!clip.wait_for_text; }

  method !append-buffer ($b is rw, $v, $text) {
    $b //= $v.buffer;
    $b.insert( $b.get_end_iter, "\n{ $text }" );
  }

  method !append-m ($text) {
    self!append-buffer($!mbuffer, $!mview, $text);
  }

  method !format-code ($code) {
    my @c;
    my $len = $code.lines.elems.Str.chars;
    for $code.lines.kv -> $k, $v {
      @c.push: "{ $k.fmt("\%{$len}d") }: { $v }";
    }
    @c.join("\n");
  }

  method slurp-file($tv) {
    my $fc = GTK::Dialog::FileChooser.new(
      'Select Grammar file', $!app.window, GTK_FILE_CHOOSER_ACTION_OPEN
    );
    $fc.response.tap:          { $tv.text = $fc.filename.IO.slurp;
                                 $fc.hide };
    $fc.run;
  }

  method spurt-file($tv) {
    my $fc = GTK::Dialog::FileChooser.new(
      'Save Grammar file', $!app.window, GTK_FILE_CHOOSER_ACTION_SAVE
    );
    $fc.response.tap:          { $fc.filename.IO.spurt($tv.text);
                                 $fc.hide };
    $fc.run;
  }

  method apply-tags($rule, $match) {
    sub get_range ($match) {
      (
        $!tbuffer.get_iter_at_offset($match.from),
        $!tbuffer.get_iter_at_offset($match.to)
      );
    }

    %!tags.gist.say;

    $!tbuffer.apply_tag( %!tags{$rule}, |get_range($match) );

    # Apply variant to positionals -- Complexifies because we DO NOT know
    # how many positionals, ahead of time. So each positional becomes another
    # tag we have to define during the loop, which means we must be as lazy as
    # possible -- Encode sub tags as "{ $rule }-{ $num }", maybe?
    # my $pos = 0;
    # for $match sub {
      # $!tbuffer.apply_tag(
    # }

    # Descend keys.
    #self.apply-tags($_, $match{$_}) for $match.keys;
  }

  method refresh-grammar {
    CATCH {
      default {
        self!append-m( .message );
        self!append-m( Backtrace.new.Str );
        say .message;
        say Backtrace.new.Str;
      }
    }

    my ($text, $gtext) = ($!tview.text, $!gedit.text);
    my $name = ($gtext ~~ /^^ \s* 'grammar' \s+ (\w+)/ // [])[0].Str;
    die "Cannot find grammar name!\n" without $name;
    my $code = qq:to/CODE/.chomp;
my { $gtext }
say \$text;
\@!rules = { $name }.^methods(:local).map( *.name ).sort;
{ $name }.parse(\$text)
CODE

    @!rules.unshift('TOP');
    # Create list of rules, and colorizations
    #self.color-rules;

    self!append-m( "Evaluating:\n{ self!format-code($code) }" );

    my $results = EVAL $code;
    self!append-m("Rules in grammar: { @!rules.join(', ') }");
    self!append-m($results.gist);
    $!tbuffer //= $!tview.buffer;
    # - Create text tags for all rules, unless already defined.
    for @!rules {
      unless %!tags{$_}:exists {
        %!tags{$_} = GTK::TextTag.new($_);
        if $_ eq 'TOP' {
          %!tags<TOP>.background-set = True;
          %!tags<TOP>.foreground-set = True;
          %!tags<TOP>.background-rgba = GTK::Compat::RGBA.new-rgb(0, 0, 128);
          %!tags<TOP>.foreground-rgba = GTK::Compat::RGBA.new-rgb(200, 200, 200);
        } else {
          # ...
        }
        $!tbuffer.tag-table.add(%!tags{$_});
      }
    }

    self.apply-tags('TOP', $results) with $results;
  }

  submethod BUILD (:$!app, :$window) {
    my $mb = GTK::Utils::MenuBuilder.new(:bar, TOP => [
      File => [
        'Open Grammar'   => { 'do' => -> { self.open-grammar-file  } },
        'Save Grammar'   => { 'do' => -> { self.save-grammar-file  } },
        '-'              => False,
        'Open Text'      => { 'do' => -> { self.open-text-file     } },
        'Save Text'      => { 'do' => -> { self.save-text-file     } },
        '-'              => False,
        Close            => { 'do' => -> { self.close-file         } },
        Quit             => { 'do' => -> { self.quit               } },
      ],
      Edit => [
        Cut              => { 'do' => -> { self.cut-selected       } },
        Copy             => { 'do' => -> { self.copy-selected      } },
        Paste            => { 'do' => -> { self.paste              } },
      ],
      View => [
        'Clear Messages' => { do => -> { self.clear-msgs         } },
      ],
      Grammar => [
        Refresh          => { do => -> { self.refresh-grammar    } },
        '-'              => False,
        'Auto Refresh'   => { :check }
      ]
    ]);

    my $vbox = GTK::Box.new-vbox;
    ($!hpane, $!vpane) = (GTK::Pane.new-hpane, GTK::Pane.new-vpane);
    ($!gedit, $!tview, $!mview) = (GTK::TextView.new xx 3);
    ($!gedit.editable, $!tview.editable, $!mview.editable) = (True, False, False);
    ($!hpane.wide-handle, $!vpane.wide-handle) = (True, True);
    ($!gscroll, $!tscroll, $!mscroll) = (GTK::ScrolledWindow.new xx 3);
    .set_policy(GTK_POLICY_AUTOMATIC, GTK_POLICY_AUTOMATIC)
      for $!gscroll, $!tscroll, $!mscroll;
    $!gscroll.set_size_request(400, 300);
    $!tscroll.set_size_request(400, 400);
    $!mscroll.set_size_request(400, 100);
    $vbox.set_size_request(800, 400);
    ($!hpane.position, $!vpane.position) = (400, 300);
    $!gscroll.add($!gedit);
    $!mscroll.add($!mview);
    $!tscroll.add($!tview);
    $!vpane.add1($!gscroll);
    $!vpane.add2($!mscroll);
    $!hpane.add1($!vpane);
    $!hpane.add2($!tscroll);

    $!clip = GTK::Clipboard.new( GDK_SELECTION_CLIPBOARD );
    $!tview.paste-clipboard.tap({ self.paste });

    $vbox.add($mb.menu);
    $vbox.pack_start($!hpane, True, True);
    $window.add($vbox);
  }
}
