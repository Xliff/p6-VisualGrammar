use v6.c;

use MONKEY-SEE-NO-EVAL;

use GTK::Compat::Types;
use GTK::Raw::Types;

use GTK::Application;
use GTK::Clipboard;
use GTK::Dialog::FileChooser;
use GTK::Menu;
use GTK::MenuBar;
use GTK::Pane;
use GTK::ScrolledWindow;
use GTK::TextView;
use GTK::Box;

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
  has GTK::TextTagsTable  $!tags;

  has @!rules;
  has %!tags;

  has $!paste-text;

  method quit       { $!app.exit        }
  method close-file { $!gedit.text = '' }

  method FALLBACK ($name, |c) {
    say "NYO -- { $name } method NYI!";
  }

  method !append-buffer ($b, $v, $text) {
    $b //= $v.buffer;
    $b.insert( $b.get_end_iter, "\n{ $text }" );
  }

  method !append-m ($text) {
    self!append-buffer($!mbuffer, $!mview, $text);
  }

  method clear-msgs {
    $!mview.text = '';
  }

  method paste {
    $!tview.text = $!clip.wait_for_text;
  }

  method open-file {
    my $fc = GTK::Dialog::FileChooser.new(
      'Select Grammar file', $!app.window, GTK_FILE_CHOOSER_ACTION_OPEN
    );
    $fc.response.tap:          { $!gedit.text = $fc.filename.IO.open.slurp;
                                 $fc.hide };
    $fc.run;
  }

  method save-file {
    my $fc = GTK::Dialog::FileChooser.new(
      'Save Grammar file', $!app.window, GTK_FILE_CHOOSER_ACTION_SAVE
    );
    $fc.response.tap:          { $fc.filename.IO.open(:w).spurt($!gedit.text);
                                 $fc.hide };
    $fc.run;
  }

  method apply-tags($rule, $match) {
    sub get_range ($match) {
      (
        $!buffer.get_iter_at_offset($match.from),
        $!buffer.get_iter_at_offset($match.to)
      );
    );
    
    $!tbuffer.apply_tag( %!tags{$rule}, |get_range($match) );

    # Apply variant to positionals -- Complexifies because we DO NOT know
    # how many positionals, ahead of time. So each positional becomes another
    # tag we have to define during the loop, which means we must be as lazy as
    # possible -- Encode sub tags as "{ $rule }-{ $num }", maybe?
    # my $pos = 0;
    # for $match -> {
      # $!tbuffer.apply_tag(
    # }

    # Descend keys.
    self.apply-tags($_, $match{$_}) for $match.keys;
  }

  method refresh-grammar {
    CATCH { default { self!append-m( .message ) } }

    my ($text, $gtext) = ($!tview.text, $!gedit.text);
    my $name = ($gtext ~~ /^^ \s* 'grammar' \s+ (\w+)/ // [])[0].Str;
    die "Cannot find grammar name!\n" without $name;
    my $code = qq:to/CODE/;
{ $gtext }
\@!rules = { $name }.^methods(:local).grep( * ne 'TOP' ).map( *.name ).sort;
{ $name }.parse(\$text)
CODE

    @!rules.unshift: 'TOP';
    # Create list of rules, and colorizations
    #self.color-rules;

    my $results = EVAL $code;
    self!append-m($results.gist);
    $!tbuffer //= $!tview.buffer;
    # - Create text tags for all rules, unless already defined.
    for @!rules {
      unless %!tags{$_}:exists {
        %!tags{$_} = GTK::TextTag.new($_);
        $!tags.add($!tags{$_});
        if $_ eq 'TOP' {
          %!tags<TOP>.backgraound-rgba = GTK::Compat::RGBA.new(
            red => 0, green => 0, blue => 128
          );
          %!tags<TOP>.foreground-rgba = GTK::Compat::RGBA.new(
            red => 200, green => 200, blue => 200
          );
        } else {
          # ...
        }
      }
    }

    with $results {
      # - Go through each rule object in a TOP-DOWN mannor.
      #   - Grab start iter from Match object via:
      #       my ($siter, $eiter) = (
      #         $!tview.buffer.get_iter_at_offset(.from),
      #         $!tview.buffer.get_iter_at_offset(.to)
      #       );
      #   - Apply tag for each rule via:
      #     $!tbuffer.apply_tag($tag, $siter, $eiter);

      # Apply tag to whole rule.
      self.apply_tags('TOP', $results);
    }
  }

  submethod BUILD (:$!app, :$window) {
    # my $menubar = MenuBuilder.new(:menubar, {
    #   File => [
    #     Open  => { clicked => -> { self.open-file  } },
    #     Save  => { clicked => -> { self.save-file  } },
    #     Close => { clicked => -> { self.close-file } },
    #     Quit  => { clicked => -> { self.quit       } },
    #   ],
    #   Edit => [
    #     Cut   => { clicked => -> { self.cut-selected  } },
    #     Copy  => { clicked => -> { self.copy-selected } },
    #     Paste => { clicked => -> { self.paste         } }.
    #   ]
    #   View => [
    #     'Clear Messages' => { clicked => -> { self.clear-msgs } },
    #   ],
    #   Refresh => { clicked => -> { self.refresh-grammar } }
    # }

    my $menubar = GTK::MenuBar.new(
      GTK::MenuItem.new('File',
        :submenu(
          GTK::Menu.new(
            GTK::MenuItem.new('Open',  :clicked(-> { self.open-file  })),
            GTK::MenuItem.new('Save',  :clicked(-> { self.save-file  })),
            GTK::MenuItem.new('Close', :clicked(-> { self.close-file })),
            GTK::MenuItem.new('Quit',  :clicked(-> { self.quit       }))
          )
        ),
      ),
      GTK::MenuItem.new('Edit',
         :submenu(
           GTK::Menu.new(
             GTK::MenuItem.new('Cut',   :clicked(-> { self.cut-selected  })),
             GTK::MenuItem.new('Copy',  :clicked(-> { self.copy-selected })),
             GTK::MenuItem.new('Paste', :clicked(-> { self.paste         }))
           )
         )
      ),
      GTK::MenuItem.new('View',
        :submenu(
          GTK::Menu.new(
            GTK::MenuItem.new('Clear Messages', :clicked(-> { self.clear-msgs }))
          )
        )
      ),
      GTK::MenuItem.new('Refresh', :clicked(-> { self.refresh-grammar }))
    );

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

    $!tags = GTK::TextTagsTable.new;
    $!tview.buffer.tag-table = $!tags;
    $!clip = GTK::Clipboard.new( GDK_SELECTION_CLIPBOARD );
    $!tview.paste-clipboard.tap({ self.paste });

    $vbox.add($menubar);
    $vbox.add($!hpane);
    $window.add($vbox);
  }
}
