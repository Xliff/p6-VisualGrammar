use v6.c;

use Pango::Raw::Types;
use GTK::Compat::Types;
use GTK::Raw::Types;

use Color;
use Color::Names::CSS3 :colors;
use DateTime::Format::RFC2822;
use RandomColor;
use JSON::Fast;

use Evals;

#use Pango::Context;
use Pango::FontDescription;
use Pango::Layout;

use GDK::Threads;

use GTK::Compat::Signal;

use GTK::Application;
use GTK::Box;
use GTK::CSSProvider;
use GTK::Dialog::ColorChooser;
use GTK::Dialog::FileChooser;
use GTK::Dialog::FontChooser;
use GTK::Menu;
use GTK::MenuBar;
use GTK::Pane;
use GTK::ScrolledWindow;
use GTK::TextTag;
use GTK::TextView;

use GTK::Utils::MenuBuilder;

constant SEED = 314159265358979;
constant settingsFile = "{ $*HOME }/.visual-grammar";

my @method-blacklist = <TOP BUILDALL>;

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
  has GTK::TextBuffer     $!mbuffer;
  has GTK::TextBuffer     $!tbuffer;
  has GTK::Window         $!window;

  has GTK::CSSProvider    $!css;

  has @!rules;

  has %!colors;
  has %!config;
  has %!settings;

  has $!menu;
  has $!tags;
  has $!keytap;

  # See https://github.com/jnthn/grammar-debugger/blob/master/lib/Grammar/Tracer.pm6
  # as to how this can be further improved, in terms of tracking matched AND failed matches!

  method FALLBACK ($name, |c) {
    say "VisualGrammar -- { $name } method NYI!";
  }

  submethod BUILD (:$app, :$window, :$width, :$height) {
    $!app = $app;
    self!buildUI($window, $width, $height);

    # These are defaults.
    %!config = (
      auto-delay     => 2,
      TOP-color-bg   => GTK::Compat::RGBA.new-rgb(0, 0, 128),
      FAIL-color-bg  => GTK::Compat::RGBA.new-rgb(255, 0, 0),
      light-fg       => GTK::Compat::RGBA.new-rgb(230, 230, 230),
      dark-fg        => GTK::Compat::RGBA.new-rgb(10, 10, 10),
    );
    %!config<TOP-color-fg FAIL-color-fg> = %!config<light-fg> xx 2;
    %!settings<grammar-edit-fg text-view-fg> = 'black' xx 2;
    %!settings<grammar-edit-bg text-view-bg> = 'white' xx 2;
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
      %!colors{$r}<fg> = $color.rgb.list.grep( * > 160 ) >= 2 ??
        %!config<dark-fg> !! %!config<light-fg>;
      %!colors{$r}<fg> = $color.rgb.list.any >= 200 ??
        %!config<dark-fg> !! %!config<light-fg>;
      %!colors{$r}<bg> = GTK::Compat::RGBA.new-rgb( |$color.rgb );
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
      %!colors<TOP><bg> = %!config<TOP-color-bg>;
      %!colors<TOP><fg> = %!config<TOP-color-fg>;
    }
    unless %!colors<FAIL> {
      %!colors<FAIL><bg> = %!config<FAIL-color-bg>;
      %!colors<FAIL><fg> = %!config<FAIL-color-fg>;
    }

    my $count = 0;
    for @!rules.sort -> $r {
      next if $r eq @method-blacklist.any;
      self!add-rule-color($r);
    }
  }

  method !setColors {
    my $styles = q:to/CSS/;
      #grammar-edit {
      }
      #grammar-edit text {
        background-color: %s;
        color: %s;
      }
      #text-view {
      }
      #text-view text {
        background-color: %s;
        color: %s;
      }
      CSS

    # YYY - Detect if fg and bg colors are the same and if so, set an inverted
    #       color on the associated OPPOSITE color.
    my $updated-styles = $styles.&sprintf(
      |%!settings<
        grammar-edit-bg
        grammar-edit-fg
        text-view-bg
        text-view-fg
      >
    );

    $!css.load-from-data($updated-styles);
  }

  method !loadSettings {
    if settingsFile.IO.e {
      my $settings = settingsFile.IO.slurp;
      %!settings = do gather for from-json($settings).pairs {
        my $p = $_;

        # Handle colors.
        if .value.ends-with(<bg fg>.any) {
          my $m = $p ~~ / 'rgb(' (\d+)+ % ',' ')' /;
          if $m {
            $m = $m.Array.map( *.Int );
          } else {
            $m = $p ~~ / (\w+) /;
            if (my $cn = $m ?? $m[0] !! Nil) {
              $m = Color::Names::CSS3.color-data($cn.lc)<rgb>;
            } else {
              say "Unknown color name encountered for '{.key}': '{$cn}'";
            }
          }
          $p.value = GTK::Compat::RGBA( |$m ) if $m;
        }

        # Attach to %!settings
        take .key => $p.value.defined ?? $p.value !! %!settings{ .key };
      }

      self!setColors;

      self.open-grammar-file( %!settings<last-grammar> )
        if %!settings<last-grammar>;

      self.open-text-file( %!settings<last-text> )
        if %!settings<last-text>;

      $!gedit.override_font(
        Pango::FontDescription.new-from-string( %!settings<grammar-edit-font> )
      ) if %!settings<grammar-edit-font>;

      $!tview.override_font(
        Pango::FontDescription.new-from-string( %!settings<text-view-font> )
      ) if %!settings<text-view-font>;

      $!window.resize( |%!settings<win-width win-height> )
        if %!settings<win-width win-height>.all ~~ Int;

      $!hpane.position = %!settings<hpane-position>
        if %!settings<hpane-position>;

      $!vpane.position = %!settings<vpane-position>
        if %!settings<vpane-position>;
    }
  }

  multi method open-grammar-file(Str() $filename) {
    say "Cannot open '$filename'" unless $filename.IO.e;
    $!gedit.text = $filename.IO.slurp;
  }

  multi method open-text-file(Str() $filename) {
    say "Cannot open '$filename'" unless $filename.IO.e;
    $!tview.text = $filename.IO.slurp;
  }

  multi method open-grammar-file { self.slurp-file($!gedit, 'Grammar') }
  multi method open-text-file    { self.slurp-file($!tview, 'Text') }

  method close-file        { $!gedit.text = ''        }
  method save-grammar-file { self.spurt-file($!gedit) }
  method save-text-file    { self.spurt-file($!tview) }
  method clear-msgs        { $!mview.text = '';       }

  method quit {
    settingsFile.IO.spurt: to-json(%!settings);
    $!app.exit;
  }

  method !append-buffer ($b is rw, $v, $text) {
    $b //= $v.buffer;
    $b.append($text);
  }

  method !append-m ($text) {
    self!append-buffer($!mbuffer, $!mview, $text);
  }
  method !append-m-tagged ($text, $tag) {
    $!mbuffer.append-with-tag($text, $tag)
  }

  method !append-legend {
    self!append-m("Rules in grammar:\n");
    my $row = 1;
    my @r = @!rules.grep(* ne @method-blacklist.any);
    my $max = @r.map( *.chars ).max;
    my $pos = $!hpane.position - 10;
    my $col = 1;

    # Could be put into GTK::StyleContext as get-font-desc!
    # This is only useful if the text description of the
    # font is not available. We currently do not set a font
    # on the Message view. That may change.
    # my $sc = $!mview.style-context;
    # $sc.save;
    # $sc.state = 0;
    # my $v = $sc.get-property('font', GTK_STATE_FLAG_NORMAL).boxed;
    # my $fd = Pango::FontDescription.new(
    #   # This should NEVER be Nil, however it behooves the user to check.
    #   # Insure such a check is performed when moved to its new home.
    #   cast(PangoFontDescription, $v);
    # );
    # $sc.restore;

    my $pl = Pango::Layout.new($!mview.create_pango_context);
    $pl.font-desc = $!mview.style-context.get-font(GTK_STATE_FLAG_NORMAL);

    my $t;
    repeat {
        $pl.text = $t ~= "\t" ~ 'W' x $max;
    } while $pl.get-pixel-size[0] < $pos && ++$col < 9;
    $col-- unless $col == 1;

    for @r {
      self!append-m("\t");
      self!append-m-tagged(
        sprintf(
          "{ "%-{$max}s" }",
          (' ' x ($max - .chars) / 2) ~ $_
        ),
        $!tags.lookup($_)
      );
      self!append-m("\n") if !($row++ % $col);
      LAST { self!append-m("\n") unless !(($row - 1) % $col) }
    }

    .unref for $pl;
  }

  method slurp-file($tv, $name) {
    my $fc = GTK::Dialog::FileChooser.new(
      "Select $name file", $!app.window, GTK_FILE_CHOOSER_ACTION_OPEN
    );
    $fc.response.tap({
      $tv.text = $fc.filename.IO.slurp;
      $fc.hide;
      %!settings{'last-' ~ $name.lc} = $fc.filename.IO.absolute;
    });
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

  method !font-sel($v) {
    my $fd = GTK::Dialog::FontChooser.new(
      "Select a font for {$v.name}",
      $!window
    );
    if $fd.run == GTK_RESPONSE_OK {
      my $font-desc = $fd.font-desc;
      %!settings{ "{$v.name}-font" } = ~$font-desc;
      $v.override_font($font-desc);
    }
    $fd.hide;
  }

  method !color-sel($v, :$bg = False) {
    constant high-val     = 255;
    constant perfect-gray = (high-val / 2).Int;
    constant tolerance    = 20;

    my $t = $bg.not ?? 'foreground' !! 'background';
    my $ccd = GTK::Dialog::ColorChooser.new(
      "Select { $v.name } { $t } color",
      $!window
    );

    if $ccd.run == GTK_RESPONSE_OK {
      my $tt = $bg.not ?? 'fg' !! 'bg';
      my $tto = $bg    ?? 'fg' !! 'bg';

      # CStructs, and we don't have memory management in place for GtkPlus yet,
      # so we have to handle this at the application level.
      #
      # "No, sir. I didn't like it" -- said the horse.
      %!settings{"{$v.name}-{$tt}"}.free if %!settings{"{$v.name}-{$tt}"};
      %!settings{"{$v.name}-{$tt}"} = $ccd.rgba;
      if %!settings{"{$v.name}-{$tto}"} eqv $ccd.rgba {
        my $rgba = GTK::Compat::RGBA.new(
          |(high-val «-« $ccd.rgba.rgb)
        );
        my $a = $rgba.rgb.sum / $rgba.elems;
        if [&&](
          # Average Within tolerance of perfect gray
          $a ~~ perfect-gray - tolerance .. perfect-gray + tolerance,
          # 2 colors within tolerance of average.
          $rgba.rgb.grep(* ~~ $a - tolerance .. $a + tolerance) >= 2
        ) {
          # Switch to black for contrast.
          %!settings{"{$v.name}-{$tto}"}.free
            if %!settings{"{$v.name}-{$tto}"};
          %!settings{"{$v.name}-{$tto}"} = GTK::Compat::RGBA.new(0, 0, 0);
        }
        $rgba.free;
      }
      self!setColors;
    }
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
    my $tag = $!tags.lookup($rule, :raw);
    unless $rule eq 'TOP' {
      my $r = get_range($match);
      next unless $r.grep( *.defined );
      # In the case of $<name>=... inside regex.
      self!add-rule-color($rule) unless %!colors{$rule};

      if [&&]($tag, |$r) {
        $!tbuffer.apply_tag($tag, |$r)
      } else {
        say "Unknown tag data detected for rule '$rule'. Skipping...";
      }
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

  method refresh-grammar($timeout = False) {
    CATCH {
      default {
        self!append-m("{ .message }\n");
        # Starting at index 3 seems to work the best.
        my $bt = Backtrace.new.list.grep({
          $_.is-setting.not && $_.is-hidden.not
        })[2..*].Str;
        self!append-m("{ $bt }\n") unless $timeout;
        say .message;
        say $bt;
      }
    }

    # Can put this behind an option.
    #self!append-m( "Evaluating:\n{ self!format-code($code) }" );

    my @tmp-rules;
    self!append-m(
      "Auto-Refresh @ {
        DateTime::Format::RFC2822.to-string( DateTime.now )
      }:\n"
    ) if $timeout;

    my $results = run-grammar($!tview.text, $!gedit.text, @tmp-rules);

    @tmp-rules.unshift: 'FAIL'
      unless $results<occurences>.not ||
             $results<occurences>[0].key eq 'TOP';
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

    $!tview.buffer.remove_all_tags;
    my $failed = False;
    if $results<occurences> && $results<occurences>[0].key eq 'TOP' {
      self.apply-tags-from-match('TOP', $results<occurences>[0].value);
    } else {
      $failed = True;
      my $max = 0;
      for $results<occurences>.list {
        self.apply-tags-from-match(.key, .value);
        $max = max($max, .value.to)
      }
      self.apply-tag-to-end('FAIL', $max);
    }
  }

  method !buildUI ($window, $width, $height) {
    $!window = $window;
    $!css    = GTK::CSSProvider.new;

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
      View => do {
        my %l = (
          g-ft => 'Set Grammar Font',
          t-ft => 'Set Text Font',
          g-bk => 'Set Grammar Background',
          t-bk => 'Set Text Background',
          g-fg => 'Set Grammar Text Color',
          t-fg => 'Set Text Color',
          clr  => 'Clear Messages'
        );

        [
          %l<clr>        => { 'do' => -> { self.clear-msgs              } },
          '-'            => False,
          %l<g-ft>       => { 'do' => -> { self!font-sel($!gedit)       } },
          %l<t-ft>       => { 'do' => -> { self!font-sel($!tview)       } },
          '-'            => False,
          %l<g-bk>       => { 'do' => -> { self!color-sel($!gedit, :bg) } },
          %l<t-bk>       => { 'do' => -> { self!color-sel($!tview, :bg) } },
          '-'            => False,
          %l<g-fg>       => { 'do' => -> { self!color-sel($!gedit)      } },
          %l<t-fg>       => { 'do' => -> { self!color-sel($!tview)      } },
        ]
      },
      Grammar => [
        Refresh          => { 'do' => -> { self.refresh-grammar    } },
        '-'              => False,
        'Auto Refresh'   => { :check, id => 'autorefresh' },
        'Text Editable'  => $editable-item
      ]
    ]);

    my $vbox = GTK::Box.new-vbox;
    ($!hpane, $!vpane) = (GTK::Pane.new-hpane, GTK::Pane.new-vpane);
    $!gedit = GTK::TextView.new;

    # Create with shared Tag Table
    $!tags     = GTK::TextTagTable.new;
    ($!tview, $!mview) = (GTK::TextView.new( GTK::TextBuffer.new($!tags) ) xx 2);
    ($!gedit.editable, $!tview.editable, $!mview.editable) = (True, True, False);
    ($!gedit.name, $!tview.name) = <grammar-edit text-view>;
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

    sub do-auto-refresh {
      if $!menu.items<autorefresh>.active {
        $!keytap.cancel with $!keytap;
        $!keytap = $*SCHEDULER.cue({
          # If not done in a GThread, then program will crash.
          GDK::Threads.add_idle({
            my $tedit = $!tview.editable;
            $!gedit.editable = $!tview.editable = False;
            self.refresh-grammar(True);
            $!keytap = Nil;
            $!gedit.editable = True;
            $!tview.editable = $tedit;
            G_SOURCE_REMOVE;
          });
        }, in => %!config<auto-delay>);
      }
    }
    $!gedit.key-press-event.tap(-> *@a {
      do-auto-refresh();
      @a[* - 1].r = 0;
    });
    $!tview.key-press-event.tap(-> *@a {
      if $!tview.editable {
        do-auto-refresh();
        # If not done in a GThread, then program will crash.
        GDK::Threads.add_idle({
          $!tview.buffer.remove_all_tags;
          G_SOURCE_REMOVE;
        });
      }
      @a[* - 1].r = 0;
    });

    $!window.configure-event.tap(-> *@a {
      CATCH { default { .message.say } }
      my $e = cast(GdkEventConfigure, @a[1]);

      %!settings<win-width win-height win-x win-y> =
        ($e.width, $e.height, $e.x, $e.y);
      @a[* - 1].r = 0;
    });

    GTK::Compat::Signal.connect-data($!hpane, 'notify::position', -> *@a {
      %!settings<hpane-position> = $!hpane.position
    });
    GTK::Compat::Signal.connect-data($!vpane, 'notify::position', -> *@a {
      %!settings<vpane-position> = $!vpane.position
    });

    self!loadSettings;

    $vbox.add($!menu.menu);
    $vbox.pack_start($!hpane, True, True);
    $window.destroy-signal.tap({ self.quit });
    $window.add($vbox);
  }
}
