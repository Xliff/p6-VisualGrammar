use v6.c;

use GTK::Compat::Types;
use GTK::Raw::Types;

use Color;
use RandomColor;

use Evals;

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

constant SEED = 31459265;

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

  has %!colors;
  has $!menu;

  has $!dark-fg;
  has $!light-fg;
  has $!tags;

  # See https://github.com/jnthn/grammar-debugger/blob/master/lib/Grammar/Tracer.pm6
  # as to how this can be further improved, in terms of tracking matched AND failed matches!

  method FALLBACK ($name, |c) {
    say "VisualGrammar -- { $name } method NYI!";
  }

  submethod BUILD (:$app, :$window, :$width, :$height) {
    $!app = $app;
    self!buildUI($window, $width, $height);
  }

  method !get-new-color {
    state $count = 0;
    my ($color, $collided) = (0);
    repeat {
      $color = RandomColor.new(
        seed => SEED + $count++, format => 'color', count => 1
      ).list[0];

      # Check for color collision.
      $collided = %!colors.values.map( *<bg> ).grep({
        my $r = False;
        if .defined {
          my ($r, $g, $b) = $color.rgb;
          my ($rp, $gp, $bp) =
            (($_.red, $_.green, $_.blue) »*« (255 xx 3))».Int;
          $r = [&&](
            $rp -  5 <= $r <= $rp +  5,
            $gp -  5 <= $g <= $gp +  5,
            $bp -  5 <= $b <= $bp +  5
          )
        }
        $r;
      }).elems;
    } until $collided.not;
    $color;
  }

  method !add-rule-color($r) {
    without %!colors{$r} {
      my $color = self!get-new-color;
      %!colors{$r}<fg> = $color.rgb.list.any > 220 ??
        $!dark-fg !! $!light-fg;
      %!colors{$r}<bg> = GTK::Compat::RGBA.new-rgb(|$color.rgb);
    }

    without $!tags.lookup($r) {
      say "---» Creating tag \"{ $r }\"";
      my $tag = GTK::TextTag.new($r);
      $tag.background-set = True;
      $tag.foreground-set = True;
      $tag.background-rgba = %!colors{$r}<bg>;
      $tag.foreground-rgba = %!colors{$r}<fg>;
      $!tags.add($tag);
    }
  }

  method !update-colors {
    unless %!colors<TOP> {
      %!colors<TOP><bg> = GTK::Compat::RGBA.new-rgb(0, 0, 128);
      %!colors<TOP><fg> = $!light-fg;
    }
    unless %!colors<FAIL> {
      %!colors<FAIL><bg> = GTK::Compat::RGBA.new-rgb(255, 0, 0);
      %!colors<FAIL><fg> = $!light-fg;
    }

    my $count = 0;
    for @!rules.sort -> $r {
      next if $r eq 'TOP';
      self!add-rule-color($r);
    }
  }

  multi method open-grammar-file($filename) {
    say "Cannot open '$filename'" unless $filename.IO.e;
    $!gedit.text = $filename.IO.slurp;
  }

  multi method open-text-file($filename) {
    say "Cannot open '$filename'" unless $filename.IO.e;
    $!tview.text = $filename.IO.slurp;
  }

  multi method open-grammar-file { self.slurp-file($!gedit) }
  multi method open-text-file    { self.slurp-file($!tview) }

  method quit              { $!app.exit               }
  method close-file        { $!gedit.text = ''        }
  method save-grammar-file { self.spurt-file($!gedit) }
  method save-text-file    { self.spurt-file($!tview) }
  method clear-msgs        { $!mview.text = '';       }

  #method paste             { $!tview.text = $!clip.wait_for_text; }

  method !append-buffer ($b is rw, $v, $text) {
    $b //= $v.buffer;
    $b.insert( $b.get_end_iter, "\n{ $text }" );
    #$v.scroll_to_bottom;
  }

  method !append-m ($text) {
    self!append-buffer($!mbuffer, $!mview, $text);
  }

  method !append-legend {
    # Color legend replaces this list.
    self!append-m("Rules in grammar:\n");
    # Why Slip when I omit the use of the intermediary $tags?
    my $row = 1;
    for @!rules {
      next if $_ eq 'TOP';
      $!mbuffer.append("\t");
      $!mbuffer.append_with_tag("\t{ $_ }", $!tags.lookup($_));
      #$!mbuffer.append("\n") if $row++ % 5;
    }
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

  method apply-tag-to-end($rule, Int $offset) {
    my $tag;
    return False unless $tag = $!tags.lookup($rule);
    my $r = (
      $!tbuffer.get_iter_at_offset($offset),
      $!tbuffer.get_end_iter
    );
    $!tbuffer.apply_tag( $tag, |$r );
    True;
  }

  method apply-tags-from-match($rule, $match) {
    sub get_range ($match) {
      my $r;
      # The with blocks shouldn't be needed!
      with $match.from {
        with $match.to {
          $r = (
            $!tbuffer.get_iter_at_offset($match.from),
            $!tbuffer.get_iter_at_offset($match.to)
          );
        }
      }
      $r;
    }

    #my $tags = $!tview.buffer.tag-table;
    my $tag = $!tags.lookup($rule);
    unless $rule eq 'TOP' {
      my $r = |get_range($match);
      next unless $r.grep( *.defined );
      # In the case of $<name>=... inside regex.
      self!add-rule-color($rule) unless %!colors{$rule};
      $!tbuffer.apply_tag( $tag, |$r );
    }


    # Apply fg variant to positionals -- Complexifies because we DO NOT know
    # how many positionals, ahead of time. So each positional becomes another
    # tag we have to define during the loop, which means we must be as lazy as
    # possible -- Encode sub tags as "{ $rule }-{ $num }", maybe?

    # Descend match object.
    given $match {
      when Array {
        for $match.List -> $m {
          self.apply-tags-from-match($_, $m{$_}) for $m.keys;
        }
      }
      when Match {
        self.apply-tags-from-match($_, $match{$_}) for $match.keys
      }
      default {
        say "Don't know how to handle '{ .^name }'";
      }
    }
  }

  method refresh-grammar {
    CATCH {
      default {
        self!append-m( .message );
        # Starting at index 3 seems to work the best.
        my $bt = Backtrace.new.list.grep({
          $_.is-setting.not && $_.is-hidden.not
        })[2..*].Str;
        self!append-m( $bt );
        say .message;
        say $bt;
      }
    }

    # Can put this behind an option.
    #self!append-m( "Evaluating:\n{ self!format-code($code) }" );

    my @tmp-rules;
    my $results = run-grammar($!tview.text, $!gedit.text, @tmp-rules);
    @tmp-rules.push: 'FAIL' unless $results[0].key eq 'TOP';
    @!rules = @tmp-rules;

    self!update-colors;
    self!append-legend;
    #self!append-m($results.gist);
    $!tbuffer //= $!tview.buffer;

    # Set edit area read-only until user rechecks the menu.
    $!menu.items<editable-text>.active = $!tview.editable = False;
    $!tview.editable = False;

    # Instead of waiting, could always prebuild for $/0 .. $/9
    # self.update-positional-colors($results{$_}) with $results;

    my $failed = False;
    if $results[0].key eq 'TOP' {
      self.apply-tags-from-match('TOP', $results[0].value);
    } else {
      $failed = True;
      my $max = 0;
      for $results.list {
        self.apply-tags-from-match(.key, .value);
        $max = max($max, .value.to)
      }
      self.apply-tag-to-end('FAIL', $max);
    }
  }

  method !buildUI ($window, $width, $height) {
    my $editable-item = {
      :check,
      id      => 'editable-text',
      toggled => -> {
        # Yes, the assignment is correct!
        $!tview.buffer.remove_all_tags
          if $!tview.editable = $!menu.items<editable-text>.active;
      }
    };

    $!menu = GTK::Utils::MenuBuilder.new(:bar, TOP => [
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
        'Clear Messages' => { 'do' => -> { self.clear-msgs         } },
      ],
      Grammar => [
        Refresh          => { 'do' => -> { self.refresh-grammar    } },
        '-'              => False,
        'Auto Refresh'   => { :check },
        'Text Editable'  => $editable-item
      ]
    ]);

    my $vbox = GTK::Box.new-vbox;
    ($!hpane, $!vpane) = (GTK::Pane.new-hpane, GTK::Pane.new-vpane);
    $!gedit = GTK::TextView.new;

    # Should be constants, but currently not possible with Rakudo
    $!dark-fg  = GTK::Compat::RGBA.new-rgb(10, 10, 10);
    $!light-fg = GTK::Compat::RGBA.new-rgb(230, 230, 230);

    # Create with shared Tag Table
    $!tags     = GTK::TextTagTable.new;
    ($!tview, $!mview) = (GTK::TextView.new( GTK::TextBuffer.new($!tags) ) xx 2);
    ($!gedit.editable, $!tview.editable, $!mview.editable) = (True, True, False);
    $!menu.items<editable-text>.active = True;
    ($!hpane.wide-handle, $!vpane.wide-handle) = (True, True);
    ($!gscroll, $!tscroll, $!mscroll) = (GTK::ScrolledWindow.new xx 3);
    .set_policy(GTK_POLICY_AUTOMATIC, GTK_POLICY_AUTOMATIC)
      for $!gscroll, $!tscroll, $!mscroll;
    $!gscroll.set_size_request(($width / 2).floor, 3 * $height / 4);
    $!tscroll.set_size_request($width / 2, $height);
    $!mscroll.set_size_request($width / 2, $height / 4);
    $vbox.set_size_request($width, $height);
    ($!hpane.position, $!vpane.position) = ($width / 2, 3 * $height / 4);
    $!gscroll.add($!gedit);
    $!mscroll.add($!mview);
    $!tscroll.add($!tview);
    $!vpane.add1($!gscroll);
    $!vpane.add2($!mscroll);
    $!hpane.add1($!vpane);
    $!hpane.add2($!tscroll);
    $!mview.autoscroll = True;

    # $!clip = GTK::Clipboard.new( GDK_SELECTION_CLIPBOARD );
    # $!tview.paste-clipboard.tap({ self.paste });

    $vbox.add($!menu.menu);
    $vbox.pack_start($!hpane, True, True);
    $window.add($vbox);
  }
}
